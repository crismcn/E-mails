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
    // ★ 关键：明确指定 scope
    scope: 'https://graph.microsoft.com/User.Read offline_access',
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

// ====== 调用 Graph API ======
async function checkMailboxHealth(accessToken) {
  console.log('📤 准备调用 Graph API，Token 前20字符:', accessToken.substring(0, 20))
  const response = await fetch(GRAPH_API_ENDPOINT, {
    headers: { Authorization: `Bearer ${accessToken}` },
  })

  const raw = await response.text()
  console.log('📥 Graph API 响应状态:', response.status)
  console.log('📄 响应内容:', raw.substring())

  if (!response.ok) {
    let errMsg = raw
    try {
      const json = JSON.parse(raw)
      errMsg = json?.error?.message || raw
    } catch (_) {}
    throw new Error(`HTTP ${response.status}: ${errMsg}`)
  }

  const data = JSON.parse(raw)
  console.log('✅ 邮箱健康检查通过！')
  console.log(`📧 邮箱地址: ${data.userPrincipalName || data.mail || EMAIL}`)
  console.log(`👤 显示名称: ${data.displayName || '未设置'}`)
  console.log(`🆔 用户 ID: ${data.id}`)
  console.log(`📁 邮箱状态: 可正常访问`)
}

// ====== 主流程 ======
;(async () => {
  console.log('🔍 开始检测 Outlook 邮箱健康状态...')
  try {
    const token = await getAccessToken()
    await checkMailboxHealth(token)
  } catch (error) {
    console.error('❌ 健康检查失败：')
    console.error(error.message)
    // 额外提示
    if (error.message.includes('invalid_grant')) {
      console.log('\n💡 Refresh Token 无效或已过期，请重新授权获取。')
    } else if (error.message.includes('401')) {
      console.log('\n💡 可能原因：')
      console.log('  1. 授权时未包含 User.Read 或 Mail.Read 权限')
      console.log('  2. Refresh Token 对应的用户已禁用或密码过期')
      console.log('  3. Client Secret 不正确（请重新生成）')
    }
  }
})()
