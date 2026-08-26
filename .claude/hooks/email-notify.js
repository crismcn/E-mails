#!/usr/bin/env node
/**
 * Claude Code Stop Hook — 任务执行完成后发送结果邮件。
 *
 * 每次 Claude 完成一次响应（一次“任务”）后触发，从 stdin 的会话转录中提取：
 *   - 提问内容（最近一次用户文本输入）      → 邮件「提问内容」栏
 *   - 执行反馈（最后一条带有文本的回复）    → 邮件「执行反馈」栏
 *   - 状态（任一工具结果 is_error=true → 异常，否则成功）
 *
 * SMTP 配置读取自同目录 email.config.json（不提交到 git）：
 *   { "host": "smtp.qq.com", "port": 465, "user": "…", "pass": "…", "to": "…" }
 *
 * 注册方式（.claude/settings.json）：
 *   "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "node .claude/hooks/email-notify.js" } ] } ] }
 */

'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const nodemailer = require('nodemailer');

const CONFIG_PATH = path.join(__dirname, 'email.config.json');
const LOG_PATH = process.env.EMAIL_NOTIFY_LOG || path.join(os.homedir(), '.claude', 'email-notify.log');
const SEND_TIMEOUT_MS = 10_000;
const MAX_QUESTION_CHARS = 2000;
const MAX_ANSWER_CHARS = 6000;
const MAX_SUBJECT_CHARS = 40;

/* ----- 调用留痕 -----
 * 每次 hook 被触发都向 ~/.claude/email-notify.log 追加一行（含来源/结果），
 * 用于排查「任务结束却没收到邮件」：分清是没触发、payload 缺 transcript、还是发送失败。
 * 日志写失败不影响主流程。
 */
function logRun(message) {
  try {
    fs.appendFileSync(LOG_PATH, `[${new Date().toISOString()}] ${message}\n`);
  } catch {
    // 忽略：日志盘失败不阻断邮件通知本身
  }
}

/* ----- 配置 ----- */

function readConfig() {
  try {
    return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
  } catch {
    return null;
  }
}

/* ----- 转录解析 -----
 * Stop 事件 stdin JSON：
 *   { "session_id", "transcript_path", "transcript": Message[] | string }
 * transcript 可能是数组或 JSON 字符串；两者都不行时退回读取 transcript_path 的 JSONL。
 */

function rowsFromInput(input) {
  const parsed = typeof input === 'string' ? JSON.parse(input) : input;
  let rows = Array.isArray(parsed.transcript) ? parsed.transcript : null;
  let source = rows !== null ? 'inline-array' : null;

  if (rows === null && typeof parsed.transcript === 'string') {
    try {
      const array = JSON.parse(parsed.transcript);
      if (Array.isArray(array)) {
        rows = array;
        source = 'inline-string';
      }
    } catch {
      source = 'inline-string-unparseable';
    }
  }

  if (rows === null && parsed.transcript_path && fs.existsSync(parsed.transcript_path)) {
    rows = readJsonl(parsed.transcript_path);
    source = 'path';
  }

  // 兜底：payload 只带了 session_id（IDE/部分会话不发 transcript），
  // 按 session_id 到 ~/.claude/projects/<项目> 下自找会话 JSONL。
  if (rows === null && typeof parsed.session_id === 'string') {
    try {
      const projectsRoot = path.join(os.homedir(), '.claude', 'projects');
      for (const dir of fs.readdirSync(projectsRoot, { withFileTypes: true })) {
        if (!dir.isDirectory()) {
          continue;
        }
        const candidate = path.join(projectsRoot, dir.name, `${parsed.session_id}.jsonl`);
        if (fs.existsSync(candidate)) {
          rows = readJsonl(candidate);
          source = 'session-file';
          break;
        }
      }
    } catch {
      // 目录不可读时保持 rows=null，走 rows-empty 分支并记录原因
    }
  }

  if (rows === null) {
    source = source ?? 'none';
  }

  return { meta: parsed, rows: rows ?? [], source };
}

function readJsonl(filePath) {
  return fs
    .readFileSync(filePath, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

function textOf(content) {
  if (typeof content === 'string') {
    return content;
  }
  if (Array.isArray(content)) {
    return content
      .filter((block) => block && block.type === 'text' && typeof block.text === 'string')
      .map((block) => block.text)
      .join('\n');
  }
  return '';
}

function contentBlocks(messageContent) {
  return Array.isArray(messageContent) ? messageContent : [];
}

function extractQuestion(rows) {
  // 工具结果也以 type:'user' 记录，需跳过；取最近一条“真提问”
  for (let index = rows.length - 1; index >= 0; index -= 1) {
    const row = rows[index];
    if (row?.type !== 'user') {
      continue;
    }
    const blocks = contentBlocks(row.message?.content);
    if (blocks.some((block) => block.type === 'tool_result')) {
      continue;
    }
    const text = textOf(row.message?.content).trim();
    if (text) {
      return text;
    }
  }
  return '';
}

function extractAnswer(rows) {
  for (let index = rows.length - 1; index >= 0; index -= 1) {
    const row = rows[index];
    if (row?.type !== 'assistant') {
      continue;
    }
    const text = textOf(row.message?.content).trim();
    if (text) {
      return text;
    }
  }
  return '';
}

function countToolCalls(rows) {
  return rows.reduce((total, row) => {
    if (row?.type !== 'assistant') {
      return total;
    }
    const calls = contentBlocks(row.message?.content).filter(
      (block) => block.type === 'tool_use',
    ).length;
    return total + calls;
  }, 0);
}

function lastToolResultBlocks(rows) {
  // 返回“最后一批工具结果”：从后往前找最近一条携带 tool_result 的消息。
  // 它代表本次任务收尾前的工具执行批次（后续往往紧跟最终文本回复）。
  for (let index = rows.length - 1; index >= 0; index -= 1) {
    const row = rows[index];
    if (row?.type !== 'user') {
      continue;
    }
    const blocks = contentBlocks(row.message?.content);
    if (blocks.some((block) => block.type === 'tool_result')) {
      return blocks.filter((block) => block.type === 'tool_result');
    }
  }
  return [];
}

// 只依据“最后一批工具结果”判定成败：
// 会话中早期曾失败但已修复/重试成功的调用不把整封邮件标记为异常。
function hasAnyError(rows) {
  return lastToolResultBlocks(rows).some((block) => block.is_error === true);
}

/* ----- 格式化 ----- */

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}

function truncate(text, max) {
  if (text.length <= max) {
    return text;
  }
  return `${text.slice(0, max)}…（内容过长已截断）`;
}

function renderHtml({ answer, isError, question, sessionId, timeText, toolCalls }) {
  const accent = isError ? '#b3261e' : '#1e7e45';
  const statusLabel = isError ? '⚠️ 执行异常' : '✅ 任务完成';
  const metaRows = [
    ['执行状态', statusLabel],
    ['时间', timeText],
    ['会话', sessionId],
    ['工具调用', `${toolCalls} 次`],
  ];
  const metaHtml = metaRows
    .map(
      ([label, value]) =>
        `<tr><td style="color:#667085;width:96px;white-space:nowrap;">${label}</td><td style="color:#1f2328;">${escapeHtml(value)}</td></tr>`,
    )
    .join('');
  return `<!doctype html>
<html lang="zh-CN">
  <head><meta charset="utf-8"></head>
  <body style="margin:0;background:#f2f3f5;font-family:-apple-system,'Segoe UI','PingFang SC','Microsoft YaHei',sans-serif;color:#1f2328;">
    <div style="max-width:680px;margin:24px auto;background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,.08);">
      <div style="background:${accent};color:#fff;padding:20px 28px;">
        <div style="font-size:18px;font-weight:600;">Claude 任务执行通知 · ${statusLabel}</div>
        <div style="font-size:13px;opacity:.9;margin-top:6px;">由 Claude Code Stop Hook 自动发送</div>
      </div>
      <div style="padding:24px 28px;">
        <table style="width:100%;border-collapse:collapse;font-size:13px;line-height:1.9;margin-bottom:20px;">${metaHtml}</table>
        <div style="font-size:14px;font-weight:600;color:${accent};margin-bottom:8px;">📋 提问内容</div>
        <div style="white-space:pre-wrap;line-height:1.7;font-size:14px;background:#f8f9fb;border:1px solid #e6e8ec;border-radius:8px;padding:14px 16px;">${escapeHtml(question)}</div>
        <div style="font-size:14px;font-weight:600;color:#1e7e45;margin:20px 0 8px;">🧾 执行反馈</div>
        <div style="white-space:pre-wrap;line-height:1.7;font-size:14px;background:#f8f9fb;border:1px solid #e6e8ec;border-radius:8px;padding:14px 16px;">${escapeHtml(answer)}</div>
      </div>
    </div>
  </body>
</html>`;
}

/* ----- 发送 ----- */

async function sendMail(config, mail) {
  const transport = nodemailer.createTransport({
    auth: { pass: config.pass, user: config.user },
    host: config.host,
    port: Number(config.port),
    secure: Number(config.port) === 465,
  });
  let timer;
  try {
    // 超时保护：SMTP 卡死时不拖住 Claude 会话
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('SMTP 发送超时（10s）')), SEND_TIMEOUT_MS);
      timer.unref?.();
    });
    return await Promise.race([transport.sendMail(mail), timeout]);
  } finally {
    transport.close();
  }
}

function main() {
  const config = readConfig();
  if (config === null) {
    logRun('invoked; cause=config-missing');
    console.error(`[email-notify] 缺少配置文件 ${CONFIG_PATH}，跳过邮件通知。`);
    return;
  }

  let raw;
  try {
    raw = fs.readFileSync(0, 'utf8');
  } catch (error) {
    logRun(`invoked; cause=stdin-read-fail (${error.message})`);
    console.error(`[email-notify] 读取 stdin 失败：${error.message}`);
    return;
  }
  logRun(`invoked; stdin-bytes=${Buffer.byteLength(raw)}`);
  if (raw.trim() === '') {
    logRun('invoked; cause=stdin-empty');
    console.error('[email-notify] stdin 为空，跳过邮件通知。');
    return;
  }

  let meta;
  let rows;
  let source;
  try {
    ({ meta, rows, source } = rowsFromInput(raw));
  } catch (error) {
    logRun(`invoked; cause=transcript-parse-fail (${error.message})`);
    console.error(`[email-notify] 解析会话转录失败：${error.message}`);
    return;
  }
  logRun(
    `parsed; source=${source} session_id=${String(meta.session_id ?? 'unknown').slice(0, 32)} rows=${rows.length}`,
  );
  if (rows.length === 0) {
    logRun('invoked; cause=rows-empty');
    console.error('[email-notify] 会话转录为空，跳过邮件通知。');
    return;
  }

  const question = truncate(extractQuestion(rows), MAX_QUESTION_CHARS) || '（未能识别到提问内容）';
  const answer = truncate(extractAnswer(rows), MAX_ANSWER_CHARS) || '（本次执行没有文本反馈）';
  const isError = hasAnyError(rows);
  const toolCalls = countToolCalls(rows);

  const now = new Date();
  const timeText = now.toLocaleString('zh-CN', { hour12: false });
  const preview = question.replace(/\s+/g, ' ').slice(0, MAX_SUBJECT_CHARS);
  const subject = `[Claude] 任务${isError ? '失败' : '成功'} · ${preview}`;
  const to = config.to || config.user;

  sendMail(config, {
    from: `"Claude" <${config.user}>`,
    html: renderHtml({
      answer,
      isError,
      question,
      sessionId: meta.session_id ?? 'unknown',
      timeText,
      toolCalls,
    }),
    subject,
    to,
  })
    .then(() => {
      console.log(`[email-notify] 邮件已发送 → ${to}`);
      logRun(`sent; question="${question.slice(0, 60)}"`);
    })
    .catch((error) => {
      console.error(`[email-notify] 发送失败：${error.message}`);
      logRun(`fail; ${error.message}`);
    });
}

main();