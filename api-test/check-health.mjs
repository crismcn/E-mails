// 读取环境变量（假设你使用 --env-file）
const { EMAIL, CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN } = process.env
if (!EMAIL || !CLIENT_ID || !REFRESH_TOKEN) {
  console.error('❌ 缺少环境变量：请设置 EMAIL, CLIENT_ID, REFRESH_TOKEN')
  process.exit(1)
}

// ====== 配置 ======
const TOKEN_ENDPOINT = 'https://login.microsoftonline.com/common/oauth2/v2.0/token'
const GRAPH_API_ENDPOINT = 'https://graph.microsoft.com/v1.0/me'

// ====== 换取 Access Token ======
async function getAccessToken() {
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    refresh_token: REFRESH_TOKEN,
    grant_type: 'refresh_token',
    // ★ 关键：用 `.default` 换取账号「已授权的全部」权限，而不是硬申请 User.Read。
    //   这批账号普遍没授权 User.Read（采购号常只有 Mail.Read，自助脚本申请的是
    //   Mail.ReadWrite/Send），硬申请 User.Read 会整体 AADSTS70000 失败。
    //   `.default` 只取已同意的权限，能换到 token 就说明 refresh_token 有效、账号可用。
    scope: 'https://graph.microsoft.com/.default',
  })

  if (CLIENT_SECRET) {
    params.append('client_secret', CLIENT_SECRET)
  }

  const response = await fetch(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  })

  const rawBody = await response.text()
  console.log('📦 换取Token响应状态:', response.status)
  console.log('📄 响应内容（前200字符）:', rawBody.substring())

  if (!response.ok) {
    throw new Error(`换取 Token 失败 (HTTP ${response.status}): ${rawBody}`)
  }

  const data = JSON.parse(rawBody)
  // 检查是否包含 access_token
  if (!data.access_token) {
    throw new Error('响应中没有 access_token，请检查响应内容：' + JSON.stringify(data, null, 2))
  }

  // 打印 token 的前20个字符，检查是否有点
  const token = data.access_token
  console.log('🔑 获取到的 Access Token 前20字符:', token.substring(0, 20))
  console.log('🔍 是否包含点 (.)?', token.includes('.') ? '✅ 是' : '❌ 否（这可能是问题所在）')

  return token
}

// ====== 尽力读 /me 补全账号信息（读不到不代表账号不可用）======
async function fetchProfile(accessToken) {
  console.log('📤 尝试读取 /me，Token 前20字符:', accessToken.substring(0, 20))
  const response = await fetch(GRAPH_API_ENDPOINT, {
    headers: { Authorization: `Bearer ${accessToken}` },
  })

  const raw = await response.text()
  console.log('📥 Graph /me 响应状态:', response.status)

  if (!response.ok) {
    // 账号未授权 User.Read 时这里会 401/403，但账号本身可用（能换到 token）。
    console.log('ℹ️  读取 /me 失败（多因未授权 User.Read），跳过账号信息展示。')
    return
  }

  const data = JSON.parse(raw)
  console.log(`📧 邮箱地址: ${data.userPrincipalName || data.mail || EMAIL}`)
  console.log(`👤 显示名称: ${data.displayName || '未设置'}`)
  console.log(`🆔 用户 ID: ${data.id}`)
}

// ====== 主流程 ======
;(async () => {
  console.log('🔍 开始检测 Outlook 邮箱健康状态...')
  try {
    // 能换到 token（refresh_token 有效）即判定账号健康。
    const token = await getAccessToken()
    console.log('✅ 邮箱健康检查通过！refresh_token 有效，账号可用。')
    // /me 仅用于补全展示信息，读不到不影响健康结论。
    await fetchProfile(token)
  } catch (error) {
    console.error('❌ 健康检查失败：')
    console.error(error.message)
    if (error.message.includes('invalid_grant')) {
      console.log('\n💡 Refresh Token 无效或已过期，请重新授权获取。')
    } else if (error.message.includes('unauthorized_client') || error.message.includes('invalid_client')) {
      console.log('\n💡 client_id 无效或应用未在该账号所属目录注册。')
    }
  }
})()
