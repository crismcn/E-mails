import 'package:flutter_test/flutter_test.dart';

import 'package:email_manager/data/mail_mapper.dart';

import 'fake_mail_api.dart';

void main() {
  group('formatMailTime', () {
    final now = DateTime(2026, 8, 28, 20, 0);

    test('当天显示 HH:mm（补零）', () {
      expect(formatMailTime(DateTime(2026, 8, 28, 9, 5), now), '09:05');
      expect(formatMailTime(DateTime(2026, 8, 28, 23, 59), now), '23:59');
    });

    test('同年不同天显示 M/D', () {
      expect(formatMailTime(DateTime(2026, 8, 25, 9, 38), now), '8/25');
      expect(formatMailTime(DateTime(2026, 1, 3, 0, 0), now), '1/3');
    });

    test('跨年显示 YYYY/M/D', () {
      expect(formatMailTime(DateTime(2025, 12, 31, 23, 0), now), '2025/12/31');
    });

    test('UTC 入参按本地时区判定「今天」', () {
      // 构造一个「本地今天」的 UTC 时刻：本地时间不变，标签必须是时刻而非日期。
      final localToday = DateTime(2026, 8, 28, 14, 30);
      final asUtc = localToday.toUtc();
      expect(formatMailTime(asUtc, now), '14:30');
    });
  });

  group('mailPreviewFromGraph', () {
    final now = DateTime(2026, 8, 28, 20, 0);

    test('取显示名、主题、未读标记', () {
      final preview = mailPreviewFromGraph(
        fakeGraphMessage(
          id: 'm1',
          fromName: '蓝湖官方',
          from: 'notice@lanhuapp.com',
          subject: '权益调整通知',
          isRead: false,
          receivedDateTime: '2026-08-25T09:38:00Z',
        ),
        now: now,
      );

      expect(preview.id, 'm1');
      expect(preview.sender, '蓝湖官方');
      expect(preview.subject, '权益调整通知');
      expect(preview.unread, 1);
      // 单封消息不是会话，不显示会话数角标。
      expect(preview.count, 0);
    });

    test('已读 → unread 为 0', () {
      final preview = mailPreviewFromGraph(
        fakeGraphMessage(id: 'm', isRead: true),
        now: now,
      );
      expect(preview.unread, 0);
    });

    test('缺显示名回退到邮箱地址，都缺则用占位符', () {
      expect(
        mailPreviewFromGraph(
          fakeGraphMessage(id: 'm', from: 'a@b.com'),
          now: now,
        ).sender,
        'a@b.com',
      );
      expect(
        mailPreviewFromGraph(fakeGraphMessage(id: 'm'), now: now).sender,
        kUnknownSender,
      );
    });

    test('主题为空时回退到正文摘要', () {
      final preview = mailPreviewFromGraph(
        fakeGraphMessage(id: 'm', bodyPreview: '正文开头几句'),
        now: now,
      );
      expect(preview.subject, '正文开头几句');
    });

    test('时间无法解析时标签为空，不抛异常', () {
      final preview = mailPreviewFromGraph(
        fakeGraphMessage(id: 'm', receivedDateTime: ''),
        now: now,
      );
      expect(preview.time, '');
    });

    test('批量映射保持顺序并逐条转换', () {
      final previews = mailPreviewsFromGraph(kFakeGraphMessages, now: now);
      expect(previews.length, kFakeGraphMessages.length);
      expect(previews.map((p) => p.id), ['m1', 'm2', 'c3-3']);
      // 具体标签依赖运行机器的时区，只断言都成功解析出了时间。
      expect(previews.every((p) => p.time.isNotEmpty), isTrue);
    });

    test('携带 conversationId', () {
      final preview = mailPreviewFromGraph(
        fakeGraphMessage(id: 'm', conversationId: 'conv-1'),
        now: now,
      );
      expect(preview.conversationId, 'conv-1');
    });
  });

  group('formatFullDate', () {
    test('输出 年月日 时:分（补零）', () {
      expect(formatFullDate(DateTime(2026, 8, 24, 9, 5)), '2026年8月24日 09:05');
      expect(formatFullDate(DateTime(2026, 12, 3, 14, 30)), '2026年12月3日 14:30');
    });
  });

  group('mailMessageFromGraph', () {
    final now = DateTime(2026, 8, 28, 20, 0);

    test('映射会话消息：发件人/未读/收件人/主题/id', () {
      final msg = mailMessageFromGraph(
        fakeGraphMessage(
          id: 'x1',
          fromName: '蓝湖官方',
          subject: '权益通知',
          bodyPreview: '预览文字',
          isRead: false,
          toRecipients: const ['a@qq.com', 'b@qq.com'],
          receivedDateTime: '2026-08-24T14:58:00Z',
        ),
        now: now,
      );
      expect(msg.id, 'x1');
      expect(msg.sender, '蓝湖官方');
      expect(msg.subject, '权益通知');
      expect(msg.body, '预览文字');
      expect(msg.unread, isTrue);
      expect(msg.recipient, 'a@qq.com; b@qq.com');
      expect(msg.fullDate, contains('2026年8月24日'));
    });

    test('已读消息 unread 为 false', () {
      final msg = mailMessageFromGraph(
        fakeGraphMessage(id: 'x', isRead: true),
        now: now,
      );
      expect(msg.unread, isFalse);
    });
  });

  group('applyBody', () {
    test('HTML 正文并入 htmlBody、保留预览 body', () {
      final base = mailMessageFromGraph(
        fakeGraphMessage(id: 'x', bodyPreview: '预览'),
      );
      final full = fakeGraphMessage(
        id: 'x',
        bodyContent: '<p>你好</p>',
        bodyIsHtml: true,
      );
      final merged = applyBody(base, full);
      expect(merged.htmlBody, '<p>你好</p>');
      expect(merged.body, '预览'); // HTML 时不覆盖预览 body
    });

    test('纯文本正文并入 body、htmlBody 仍为空', () {
      final base = mailMessageFromGraph(
        fakeGraphMessage(id: 'x', bodyPreview: '预览'),
      );
      final full = fakeGraphMessage(
        id: 'x',
        bodyContent: '完整纯文本',
        bodyIsHtml: false,
      );
      final merged = applyBody(base, full);
      expect(merged.htmlBody, isNull);
      expect(merged.body, '完整纯文本');
    });

    test('无正文时原样返回', () {
      final base = mailMessageFromGraph(fakeGraphMessage(id: 'x'));
      final merged = applyBody(base, fakeGraphMessage(id: 'x'));
      expect(identical(merged, base), isTrue);
    });
  });
}
