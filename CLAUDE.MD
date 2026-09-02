# Email Manager · 产品规范文档

> 本文件是项目的单一事实来源（产品 / 设计 / 开发约定）。给协作者与 AI 助手阅读。
> 约定：**本项目后续所有对话一律使用中文回复。**

---

## 1. 产品定位

**Email Manager（工程名 `email_manager`）** 是一款面向「**批量管理大量 Outlook / Microsoft 邮箱账号**」的 Flutter 移动端 App（iOS + Android）。

它不是给普通用户收发个人邮件用的客户端，而是给需要**同时持有并运维成百上千个微软邮箱**的场景使用：批量导入账号凭据、批量体检账号可用性、快速查看每个账号的收件箱与邮件详情。

**一句话**：把一堆微软邮箱的「能不能用 + 里面有什么信」集中管起来。

### 核心价值
- **批量**：一次导入 N 个账号，一次勾选 N 个账号做健康检测 / 删除。
- **可信**：直连微软官方 OAuth + Microsoft Graph，账号可用性是「此刻真打接口」得出的真实结论，而非本地猜测。
- **安全**：长期敏感凭据（refresh_token / client_id / password）走系统安全存储（Keychain / Keystore），短期 access_token 只留内存。

---

## 2. 目标用户与典型场景

| 用户 | 场景 |
|---|---|
| 邮箱资源运维 / 采购者 | 手上有大批采购来的微软邮箱，需要定期确认哪些还活着、哪些 token 过期 |
| 需要按账号查信的人 | 点开某个账号 → 看它的收件箱列表 → 读某封邮件详情（含 HTML 富文本） |

典型动线：
1. **导入**：粘贴 / 选 CSV，把 `邮箱----密码----client_id----refresh_token----创建时间` 批量导入 → 落安全存储。
2. **总览**：首页看总数 / 有效 / 异常统计，滚动浏览账号列表与状态点。
3. **体检**：长按进多选 → 勾选若干 → 「健康检测」→ 汇总「正常 X / 异常 Y」，异常账号状态点变色。
4. **查信**：点账号 → 邮件列表（Graph 真实收件箱）→ 点邮件 → 详情页（HTML 渲染，自动标已读）。
5. **清理**：多选 → 删除（二次确认）→ 从安全存储移除。

---

## 3. 信息架构与页面

| 页面 | 文件 | 说明 |
|---|---|---|
| 首页 / 账号总览 | `lib/pages/home_page.dart` | 三统计卡 + 账号列表；吸顶头部（标题上滑被汇总覆盖后固定）；长按进多选，底部操作栏（健康检测 / 删除 / 全选）；右上角「…」菜单 → 导入 / 设置 |
| 导入邮箱 | `lib/pages/import_page.dart` | CSV 文件导入 + 文本粘贴导入；格式说明卡；底部「确认导入」落安全存储 |
| 邮件列表 | `lib/pages/mail_list_page.dart` | 某账号的 Graph 真实收件箱；下拉刷新 / 上滑翻页（`$skip`）；左滑归档 / 已读 / 删除；点击进详情并自动标已读；首屏转圈浮在整页正中（见 §4.7） |
| 邮件详情 | `lib/pages/message_detail_page.dart` | 单封邮件；懒取全文与正文渲染**共用一个**转圈，浮在内容区正中（见 §4.7）；**整页一条滚动条**——滚动视图恒定铺满内容区（收件人 / 主题 / 日期 / 附件 / 正文一起上滑，HTML 交给按内容高度占位的 WebView，见 §5.5），返回栏与底部操作栏是浮在它上面的两条**绝对定位浮层**，上滑收起 / 下滑立刻切回（只做绘制期平移，滚动几何恒定，见 §5.5）；附件条（收起显示「N 个附件 + 总大小」，展开出图片预览与文件行，点击交给系统应用打开、打不开转下载） |
| 新建邮件 | `lib/pages/compose_page.dart` | 顶栏（返回 / 附件 / 发送）+ 表单（收件人 / 抄送 / 密送 / 发件人 / 重要性 / 主题）+ 附件条 + 正文 + 底部两条工具栏（排版栏 / 撤销·重做·Aa·图片）；**表单与正文同在一条滚动条里**（`CustomScrollView`，正文走 `SliverFillRemaining(hasScrollBody:false)`）；收件人交互见 §5.6，正文的选区级排版见 §5.7 |
| 设置 | `lib/pages/settings_page.dart` | 主题（跟随系统 / 暗黑 / 亮白）+ 语言（中文 / English），分段控件切换，即时持久化 |

> 设计稿（仓库根）：`邮件列表.jpg`、`邮件列表消息.jpg`、`邮件详情.jpg`、`长按操作.jpg`。新页面要求 **1:1 还原设计稿**。
> 会话/对话视图（`mail_thread_page`）已按用户要求移除——列表点击**直达详情页**；但 `MailApi.listConversation` 接口保留，日后可复用。

---

## 4. 设计规范

### 4.1 主题与配色
- 颜色**不硬编码**。全部走 `lib/theme/app_palette.dart` 的 `AppPalette extends ThemeExtension`，含 `AppPalette.dark` / `AppPalette.light` 两套，取色用 `context.palette.xxx`。
- `lib/theme/app_theme.dart` 的 `AppTheme.light/dark` 把 palette 挂到 `ThemeData.extensions`。
- 暗色基调：背景 `#0A0D12`、卡片 `#141A24`、主蓝 `#2F80FF`。亮色为白底。
- 状态色：有效（绿）/ 警告·token 过期（黄）/ 错误·密码错误（红）/ 未知（中性灰）。
- **新增组件一律用 `context.palette`，不要引入固定颜色常量类。**

### 4.2 图标
- **页面不直接写 `Icons.xxx`**，统一走 `lib/theme/app_icons.dart` 的语义常量（`AppIcons.back` / `AppIcons.starFilled` …）。换整套图标只动这一个文件。
- 主来源是 **iconfont**（阿里图标库，项目「Outlooks」id `5228387`）：字库 `assets/fonts/iconfont.ttf`，码点抄自同目录 `iconfont.json`，pubspec 里声明为家族 `IconFont`。加图标的流程：iconfont 项目里挑好 → 重新下载覆盖 ttf + json → 按 `font_class` 在 `app_icons.dart` 补常量。
- **`iconfont.json` 的名字字段都不可信**——`name` 出过错（`right-align` 与 `left-align` 两条都叫「left-align」），`font_class` 也出过错（不同批次里 `checked-all` / `deselect-all` 互换，而两个码点上的字形一直没变）。**只认字形**：拿不准就渲染出来看图 / 量几何。
- **覆盖字库后码点会重排**，老码点可能消失或换成别的图形。两类后果差别很大：
  - **码点消失** → debug/profile 照跑（缺的字形只是画不出来），只有 release 的 `--tree-shake-icons` 会整个打包失败：`Codepoint 59198 not found in font, aborting`（**十进制**，换成 hex 才好定位）。这条已被 `test/app_icons_test.dart` 前移到 `flutter test`，覆盖字库后跑一遍就知道要改哪几个常量。
  - **码点还在但换了图形（或两个图形互换）** → 编译、打包、测试全过，只是界面上图标不对。**没有自动化能兜住，只能看图**：
    ```bash
    python3 - <<'PY'
    import json
    from PIL import Image, ImageDraw, ImageFont
    gs=json.load(open('assets/fonts/iconfont.json'))['glyphs']
    fo=ImageFont.truetype('assets/fonts/iconfont.ttf',46); lb=ImageFont.load_default()
    CW,CH,C=96,96,7; R=(len(gs)+C-1)//C
    im=Image.new('RGB',(C*CW,R*CH),(255,)*3); d=ImageDraw.Draw(im)
    for i,g in enumerate(gs):
        cp=int(g['unicode'],16); x,y=(i%C)*CW,(i//C)*CH
        d.text((x+CW//2,y+33),chr(cp),font=fo,fill=(15,20,28),anchor='mm')
        d.text((x+3,y+64),g['font_class'][:16],font=lb,fill=(170,0,0))
        d.text((x+3,y+76),'0x%04X'%cp,font=lb,fill=(0,0,190))
    im.save('/tmp/iconfont.png')
    PY
    ```
- 少数造型字库里还没有（裸对勾 / 断网 / 回复全部 / 通用文件），仍回退 Material（`app_icons.dart` 末尾「待补」区），补齐时页面代码不用动。
- 常量必须是 **`const IconData`**，release 的 `--tree-shake-icons` 才能把字库裁到只剩用到的字形。码点可以在 BMP 之外（曾出现 `0x100CF`），`Icon` 与 tree-shaker 都能处理。
- `uses-material-design: true` **不能关**：Material 组件内部自己画的图标（DropdownButton 箭头、TextField 清除、Slidable 等）仍取 MaterialIcons 字体。
- iconfont 字形的字面尺寸不统一（有的填满 1.0em，有的只有 0.56em），跟 Material 的 0.83em 混排时同一个 `size:` 观感会不一致，必要时按调用点微调 `size`。

### 4.3 字号与间距（2026-08-27 收紧后的尺度）
- 首页标题 22、统计卡数字 24 / 标签 12、列表主文本 16、次要文本 14、小字 12、搜索框 14。
- 首页吸顶头部三段高度 62 / 66 / 44（第三段 = `AppSearchField.kHeight` 36 + 下间距 8）；
  多选顶栏高度常量 `_kSelTopBarHeight` 必须 == 标题条 `_titleBand`（62），二者靠此抵消保证进出多选净高不跳。
- **搜索框只有一份**：`lib/widgets/search_field.dart` 的 `AppSearchField`（胶囊形、放大镜 19、
  文字 14），首页与邮件列表共用，高度写死 `kHeight = 36`。两页曾各写一份 —— 首页被外层
  `SizedBox` 夹到 34、邮件列表按内容自然撑到 35，**系统字号放大后差距还会跟着变大**
  （一个被夹住不动、一个跟着长）。左右边距（都是 20）由调用方给。
  - **输入非空时右侧出清除按钮**（叉 15）：点一下清空并回调 `onChanged('')`，
    调用方的过滤条件跟着复位（`TextField.onChanged` 不为程序性修改触发，得手动回调）。
    文本控制器由组件自己持有；`suffixIconConstraints` 必须放开最小尺寸 —— 用
    `IconButton` 那套 48×48 会把胶囊顶破 `kHeight`。

### 4.4 滚动手感（约定：轻微且迅速的回弹）
- 全局 `lib/theme/app_scroll_behavior.dart` 的 `SmallBounceScrollBehavior`（挂 `MaterialApp.scrollBehavior`），物理 `_SnappyBouncePhysics`：小幅过冲 + 干脆收口（比 iOS 默认更硬）。
- 两个可复用常量：`snappyFrictionFactor(f)=0.4*(1-f)^2`（越小越硬）、`kSnappySpring`（临界阻尼、不来回晃）。
- **坑**：`MaterialApp.scrollBehavior` 管不到 `EasyRefresh` 内部。用 `EasyRefresh` 的页面（首页 / 邮件列表）必须显式传 `spring: kSnappySpring, frictionFactor: snappyFrictionFactor`。
- 不要 Android 边缘发光 / 拉伸，只要位移回弹。回归测试 `test/scroll_bounce_test.dart`。

### 4.5 多语言（i18n）
- 官方 gen-l10n。配置 `l10n.yaml`（arb-dir/output-dir 均 `lib/l10n`，template = `app_zh.arb`，`nullable-getter: false`）。
- 文案写在 `lib/l10n/app_zh.arb` / `app_en.arb`，**改文案后跑 `flutter gen-l10n` 重新生成** `AppLocalizations`。
- 取文案：`AppLocalizations.of(context).xxx`。语言标签「中文」「English」按惯例各显本名、不本地化。

### 4.6 EasyRefresh 指示器约定
- 共用指示器在 `lib/widgets/app_refresh.dart`。两条硬约束：
  1. **收起时整体不入树**：`build` 开头 `if (state.offset <= 0) return const SizedBox.shrink();`，否则 `CupertinoActivityIndicator` 常驻空转 → 所有 `pumpAndSettle` 超时。
  2. **`processedDuration` 是一次性 Timer**：测试触发刷新 / 加载后需额外 `await tester.pump(const Duration(milliseconds: 400))`，否则报「Timer still pending」。
- 子 `ListView` **不要显式设 `physics`**（会盖掉全局回弹）。

### 4.7 加载转圈的位置
- 一屏之内的等待，转圈**落在可见区域垂直正中**，不要排在已有内容后面、也不要只按
  「剩下那块」居中。两处都踩过：
  - 邮件详情页的懒取转圈原来跟在元信息下面，看着像挂在页面上三分之一处；现在用
    `Stack(fit: StackFit.expand)` + `Positioned.fill` + `Center` 浮在整块内容区正中。
    `StackFit.expand` 是必需的 —— 默认 loose 会让里面的滚动视图按内容缩，短邮件时
    下半截点不着、滑不动。返回栏与底部操作栏是浮层且高度相当，故「整块内容区正中」
    与「两条栏之间那块的正中」相差两三像素，看不出来。
  - 邮件列表的首屏转圈原来在**搜索框下面那块列表区**里居中 —— 上面压着标题栏 + 搜索框
    近 120、下面没有对称的底栏抵消，实测落在 452 而屏幕正中是 390，看着明显偏下。
    改成整页级浮层（`SafeArea` 下的 `Stack` + `Positioned.fill` + `Center`），列表区那支
    只留 `SizedBox.shrink()`。`SafeArea(bottom: false)` 是为了让列表滚到屏幕最底，故浮层
    自己减掉 `MediaQuery.viewPaddingOf(context).bottom`，否则中线被手势条压低半个 inset。
- **一次等待只能有一个转圈，中间不许落幕**：详情页「懒取全文 → 正文 WebView 渲染」是
  两段，曾各画一个（页面画懒取那个、`MailHtmlView` 在遮罩里画渲染那个），交接处有一两帧
  谁都没画 —— Android 上平台视图首帧还要几十毫秒，看着就是**闪一下**。现在整个等待只有
  页面那一个转圈，正文遮罩只负责底色，起落靠 `MailHtmlView.onCoverChanged` 通知（详见 §5.5）。
- **测试里不能对着转圈 `pumpAndSettle`**（永不收敛，同 §4.6）：`pump()` 走完路由转场即断言。
  同理，转圈淡出后必须整层**移出树**（`isDismissed → SizedBox.shrink()`），留在 `opacity:0`
  下面会一直空转、每帧重绘，`pumpAndSettle` 也永不收敛。

---

## 5. 技术架构

### 5.1 分层
```
UI 页面 (pages / widgets)
  └─ ApiScope (InheritedWidget 组合根注入) / SettingsScope
       └─ ApiService（组合根，装配下列部件）
            ├─ AuthApi        直连微软 OAuth 换 token
            ├─ MailApi        Microsoft Graph 收件箱 / 邮件
            ├─ UserApi        Graph GET /me（健康检测用）
            ├─ TokenService   access_token 缓存 + 并发刷新合流
            ├─ HealthService  两步体检（刷 token + GET /me）
            └─ CredentialsStore  安全存储的长期凭据
```

### 5.2 网络层（`lib/core/network/`）
- **dio 5.11**，直连微软，无自建后端。
- 内部统一契约 `ApiResponse<T>{code,message,data}`（`api_response.dart`）——微软本身**不是**这个格式（OAuth form-urlencoded、Graph 资源 JSON / `{error:{code,message}}`），由 `error_mapper.mapError()` + `ApiClient` 归一化。
- 业务码 `api_code.dart`（ok=0 / unauthorized=401 / network=-1 / timeout=-2 / parse=-4 …，含 `isSuccess` / `isAuthFailure`）。
- `dio_client.dart` 造三种 Dio：`buildAuthDio()`（form 编码、无 Bearer）、`buildGraphDio(authInterceptor)`、`buildPlainGraphDio()`（无鉴权，健康检测显式传 Bearer 用，避免污染邮件 token 缓存）。
- 拦截器：`app_log_interceptor`（仅 debug，脱敏 Authorization/password/token）、`auth_interceptor`（`QueuedInterceptorsWrapper`，靠 `options.extra['account']` 取 token 注入 Bearer，401 强制刷新重试一次防递归）。

### 5.3 认证与存储（`lib/core/auth/` + `lib/core/storage/`）
- **flutter_secure_storage 11**（默认 AES-GCM）。自建抽象 `SecureStorage` + `FlutterSecureStorageAdapter`，测试用内存假实现免平台通道。
- `SecureCredentialsStore`：每账号凭据 JSON 存于键 `cred.<email>`，`listEmails` 靠 `readAll` 过滤前缀。
- **安全决策**：只有长期敏感凭据（refresh_token / client_id / password）落安全存储；**access_token 只在内存**（1h 寿命、冷启动重刷），减少落盘短期令牌攻击面。
- `TokenService`：同账号并发刷新用 `Map<String,Future>` 合流去重；轮换的 refresh_token 回写凭据。

### 5.4 数据映射（纯函数，`lib/data/`）
- `account_import.dart` `parseImportText`：逐行按 `----` 拆分（回退逗号 / CSV），字段 `邮箱----密码----client_id----refresh_token----创建时间`，≥5 字段且首字段合法邮箱才有效。
- `mail_mapper.dart`：`mailPreviewFromGraph` / `mailMessageFromGraph` / `formatMailTime`（今天 `HH:mm`、今年 `M/D`、更早 `YYYY/M/D`，**UTC→本地再比日期**）等。

### 5.5 邮件正文渲染（WebView）

HTML 正文交给**系统 WebView**（`webview_flutter`，iOS WKWebView / Android WebView）。曾用
`flutter_widget_from_html_core` 画成原生 widget，排版还原度不够（表格、定位、webfont），已换掉。

- **包装文档是纯函数**：`lib/data/mail_html_document.dart` 的 `buildMailHtmlDocument`
  把正文包成一整份 HTML（视口 + CSP + 注入样式），可单测；
  `lib/widgets/mail_html_view.dart` 只管 WebView 生命周期。
- **正文是发件人可控的敌意输入**，安全姿态写死在那份文档里：CSP `default-src 'none'`，只放开
  图片 / 内联样式 / 字体，**脚本只放行带随机 nonce 的那一段**（量高用，`Random.secure` 每份文档
  重生成）；邮件自带 `<script>`、内联 `onclick`、`<iframe>`、表单提交、`<base>` 全被挡；
  `<script>` 整块另外物理删一遍。链接一律不在 WebView 内导航，只把 `http/https/mailto/tel`
  交给外部浏览器（`isSafeMailLink`）。
  **远程图片照旧加载**（跟踪像素照旧能打点），要拦得做成「点按钮才显示图片」。
- **整页一条滚动条**：`Stack` —— 一条 `SingleChildScrollView` 以 `Positioned.fill` **恒定**
  铺满内容区（收件人 / 主题 / 日期 / 附件 / 正文都在里面，一起上滑），返回栏与底部操作栏是
  浮在它上面的两条绝对定位浮层，靠滚动视图**恒定**的上下内边距让位（内容滑到浮层背后，
  浮层不透明）。正文 WebView **按页内量到的渲染高度占位、自己不滚**。
- **盒子高度 = `min(页内量到的 CSS 高度 × layoutScale, 纹理安全边 ÷ dpr)`**，与双指缩放彻底解耦。
  - `layoutScale` 是排版缩放比，只跟这封邮件的声明宽度有关。曾按 `× visualViewport.scale`
    重新定高想让放大后的下半截靠页面滚动看完，缩放比能到 10、盒子被撑成几万逻辑像素 →
    **一放大就闪退**。
  - **纹理安全边（`_kMaxTexturePhysical = 8192` 物理像素）是硬约束**：Android 平台视图走纹理合成
    （`initSurfaceAndroidView`），WebView 被画进一张**按控件尺寸开的纹理**，受
    `GL_MAX_TEXTURE_SIZE` 约束（常见 4096–16384）。越界 → 纹理被 clamp 再拉伸铺满 = **画面变形**；
    缩放时每帧重绘巨型表面 = **整机卡死**。运行时拿不到真实上限，只能取个几乎所有机型都满足的值。
  - **开 Hybrid Composition 是试过又退回的路**：`displayWithHybridComposition: true` 确实绕开了
    纹理尺寸限制（插件注释写着「有性能代价，但没有 SurfaceTexture 的尺寸限制」），但真机上
    **滚动明显卡顿** —— 它让叠在平台视图上的内容走 `FlutterImageView` 覆盖层。故改回默认合成 +
    上面那道高度上限。
- **单指拖动归谁，看「WebView 内部现在还能不能纵向滚」**（页内脚本回报的布尔量，
  判据是 `内容高度 > visualViewport.height`）：
  - 能内滚（**双指放大后**可视视口变小 / 邮件超过高度上限被夹）→ 单指归 WebView，在里面滚，
    够得着被放大遮住的内容；
  - 不能内滚（常态：盒子正好装下全文）→ 单指归外层滚动视图，整页一起上滑。
  - 双指**永远**归 WebView（缩放 + 平移）；单指点击靠竞技场清算落到平台视图，链接照样点得动。
  - 实现是自写的 `_MultiTouchGestureRecognizer`（手指落下时现问一次那个布尔量）。`Set<Factory>`
    在 State 里只建一份 —— 每帧换新的会让平台视图反复重挂。
  - **那个布尔量刻意不进 `setState`**：双指平移时它频繁翻转，只被识别器读、不参与绘制；
    重建界面会把 WebView 一起重排。这也是「监听 `visualViewport` 是安全的」的前提 ——
    历史上炸的是「按缩放比重新定高」，不是监听本身。
  - **已知取舍**：超过高度上限的长邮件，单指滑正文时滚的是 WebView 内部（元信息不跟着走），
    要滑走元信息得在元信息那块拖。绝大多数邮件在上限内，不会走到这条分支。
- **顶 / 底栏上滑收起、下滑切回**，两条都是浮层：`Positioned` + `ClipRect` + `SlideTransition`。
  **收放只做绘制期平移** —— 不改滚动视图的尺寸、不改它那份上下内边距，`maxScrollExtent`
  全程恒定（用例里有断言）。**这条约束就是全部的关键**：历史上收起做坏过三轮（压高度
  `SizeTransition`、浮层平移但由正文滚动位置驱动、正文独立滚动时压高度），病根都是同一条 ——
  **收放改了正文区尺寸或滚动几何 → 正文是 WebView，一改尺寸就重排 → 重排又吐出新的滚动偏移
  去驱动收放**，正反馈表现为「全屏状态来回跳动」，曾按用户要求把收放整个取消掉。现在收放
  一格布局都不碰，那条回路在结构上不存在。
  - 驱动是**页面这条 Flutter 滚动条**（`ScrollController` + `userScrollDirection`），不是
    WebView 的滚动回报。滚动回调里**只驱动 `AnimationController`、绝不 `setState`** ——
    重建会把正文那块 WebView 一起重排。
  - 阈值：贴顶 60px 内恒展开；上滑越过 80px 才收；可滚距离 < 200px 不收（内容本来就快装得下）。
    **下滑立刻切回**（不是等快到顶部才回来）—— `appRoute` 没有 iOS 侧滑返回，返回箭头藏着
    就退不出这一页。
  - **`ClipRect` 是必需的**：`SlideTransition` 是绘制期变换，浮层的**布局**矩形始终在 `Stack`
    范围内 → `RenderStack._hasVisualOverflow == false` → 不装裁剪层 → 挪出去的部分照画。
    真机上表现为「顶栏没隐藏」（滑进状态栏那条安全区里赖着不走）；而测试的 view padding 为 0
    时越界即出屏被裁、抓不到，故用例用 `FakeViewPadding` 模拟刘海机型，并按各自的裁剪窗断言
    「浮层已整体移出窗外」。裁剪同时管住命中测试：藏起来的浮层点不到。
  - 内边距用两条浮层的**实测高度**（`GlobalKey` + 帧后量一次校正，值没变就不 `setState`，
    免得量→重建→再量成环）：写死会因平台字体 / 系统文字缩放差几像素，内容正好露在浮层
    边缘那一线。两条浮层各自自带不透明底色（它们压在正文上）。
  - **已知取舍**：正文放大后（或超高被夹时）单指归 WebView 内部滚动，那会儿外层滚动条不动
    → 两条栏不收放。绝大多数邮件不会走到这条分支。
- **量高**：页内脚本取 `#mail-root` / `body` / `documentElement` 三种量法的**最大值**
  （邮件可能写死 body 高度、可能整封浮动、可能被 `overflow` 裁掉，少量一种就截断），
  `ResizeObserver` + `visualViewport` 事件 + 10 拍轮询跟进；同一条消息里带上「能否内部滚动」。
  宿主侧 `onPageFinished` 后再隔几拍调页内的 `window.mailMetrics()` 兜底（两条路径同一套量法）。
  高度**只涨不缩**，免得来回抖。
  仍用 `!important` 压掉邮件写给 `html/body` 的 `height:100%` / `overflow:hidden`
  （那是给桌面客户端整页布局用的，照办会把正文压成一屏高）。
- **滚动条**：WebView 的原生滚动条一律关掉（`setVerticalScrollBarEnabled(false)` / 横向同理，
  两个平台都支持，调用前问一下 `supportsSetScrollBarsEnabled()`）—— 盒子等于内容高度时本不该
  出现，但**放大之后 WebView 内部就有可滚距离了**，那两条会冒出来。邮件自带的内层滚动容器另由
  文档里的 `::-webkit-scrollbar{width:0;height:0}` 关（主视口那条是原生绘制，CSS 管不到）。
- **宽度**：`htmlDeclaredWidth` 推断出的声明宽度超过屏宽时，视口写成 `width=<声明宽度>`，
  由浏览器整体缩到屏宽作为**初始适配**（引擎重绘、清晰；之后可双指放大）。
  **坑：`webview_flutter_android` 默认 `useWideViewPort = false`，会忽略 `viewport` meta** ——
  于是按屏宽排版、无视声明宽度，写死 600px 的邮件会横向溢出。必须显式
  `AndroidWebViewController.setUseWideViewPort(true)`（故直接依赖了 `webview_flutter_android`）。
  iOS 的 WKWebView 原生就认 viewport meta。
- **暗色**：邮件都按白底黑字写，故暗色主题下给**正文容器** `#mail-root` 加
  `filter: invert(1) hue-rotate(180deg)`，图片再反一次抵消。
  - **滤镜刻意不加在 `html` 上**：那样页面底色得先写成 App 底色的**反色**（近白的
    `#f5f2ed`）才能反回来，而浏览器**先画背景、后合成滤镜** —— 中间几帧照着近白画，
    暗色下就是加载时**白闪一下**。现在 `html{background:<App 底色>!important}` 直接写真实
    底色、不参与反色，任何时刻都是暗的。
  - 配套 `body{background:transparent!important}`（仅暗色）：邮件常带
    `<body style="background:#fff">`（嵌套 body 标签被解析器丢弃、属性并到文档 body 上），
    而 body 在反色层**外面**，照办就是暗页面上一大块白。
  - 已知取舍：白底 logo 仍是白块、元素的 `background-image` 会被反色、深底设计的邮件会被
    反成亮底。要改姿态只动 `_kDarkFilter` 一处。
- **加载遮罩（治暗色下的白闪）**：WebView 在文档 CSS 生效前会画自己的默认白底 ——
  `setBackgroundColor(palette.background)` 挡不干净，暗色主题下就是一下白闪。故 WebView
  上面盖一层 `palette.background` 的遮罩（`Stack` + `Positioned.fill`），**「文档加载完 +
  已量到高度」再压 `_kRevealSettle = 140ms` 才淡出**（`kRevealDuration = 240ms`），
  露出来就是最终版式。
  - **遮罩只画底色，转圈由详情页画**：整段等待（懒取全文 → 正文渲染）只能有一个转圈，
    见 §4.7。遮罩起落用 `onCoverChanged(bool)` 通知宿主，宿主的转圈按同一时长
    （`MailHtmlView.kRevealDuration`）一起淡出。**通知要排到帧末** —— 一个调用点是
    `didChangeDependencies`（换主题重载），此刻宿主正在构建，直接回调会撞上
    「setState() called during build」。测试环境没有平台视图、根本没有遮罩，
    那条分支要立刻回报 `false`，否则宿主的转圈永远挂着（`pumpAndSettle` 直接超时）。
  - **遮罩期间盒子至少占满 `viewportHeight`**（详情页传进来的内容区可见高度）：免掉
    「先给一段短占位、量到高度再跳一次版式」（那是 `_kInitialHeight = 160` 的旧账，已删）。
    **淡完**（`_coverGone`，靠 `_cover` 的状态监听）才把盒子交回实测高度 —— 用「开始淡出」
    的话，实测高度比一屏矮的短邮件会在淡出**期间**收盒子，WebView 视口跟着变小、文档重排，
    那一下正好透过半透明的遮罩被看见。量不到高度就退回一屏高。
  - 那 140ms 是留给合成的：`onPageFinished` 只说明文档加载完，WebView 把带样式（暗色下还带
    反色滤镜）的首帧真正画到纹理上还要一两帧，早淡出就露出中间态。
  - 淡出**只排一次**（`_revealScheduled`）—— 图片是陆续到的，每次高度增长都重排定时器会把
    淡出一路推到兜底时间。
  - **淡的是这层 Flutter 覆盖层，不是 WebView 的 `opacity`**：平台视图的透明度在 iOS 上
    不保证生效（embedder 只稳定支持裁剪与变换）。
  - **有兜底**：`_kRevealDeadline = 1500ms` 一到无条件淡出 —— 量高三条路全失败、或远程图片
    把 `onPageFinished` 吊住时，绝不能把正文永远盖着。换主题重载文档时遮罩重新盖上。
- **测试**：widget 测试环境没有平台视图，`MailHtmlView` 检测到 `WebViewPlatform.instance == null`
  就降级成 `MailHtmlUnavailable`（挂着生成好的文档供断言）。所以**HTML 正文在测试里不渲染、高度为 0**，
  要撑出滚动距离的用例必须用纯文本长邮件；多指手势、纹理尺寸、Hybrid Composition、原生滚动条
  都碰不到，**缩放与变形 / 卡死只能真机验**。

### 5.6 新建邮件页的收件人三栏

设计稿在 `UI/` 下（`收件人-输入提示.jpg`、`收件人-多收件人.jpg`、`收件人-收件人编辑.jpg`、
`发件人-点击发件人输入框.jpg`、`发件人-无抄送&密送.jpg`），要求 1:1。

- **三种形态**（每栏独立判定）：聚焦 → 灰色胶囊 + 行尾输入框；未聚焦且已填 → 折叠成一行
  主色文字（点一下回到聚焦）；未聚焦且为空 → 留着输入框。右侧 `+`（选系统联系人）
  只在**聚焦或该栏为空**时出现 —— 五张设计稿同时满足这一条。
- **胶囊 + 输入框的排版是自写的 `_ChipsInput`（`MultiChildRenderObjectWidget`），不是
  `Wrap`**：`Wrap` 给每个孩子的 maxWidth 都是**整行宽**，而 `TextField` 会铺满拿到的宽度
  —— 于是只要前面有一枚胶囊就挤不下，输入框（连光标）被整体推到下一行，表现为
  **收件人在这一行、光标在下一行**。`_ChipsInput` 让胶囊按行流下去，**最后一格（输入框）
  拿当前行的余量**（不足 `_kMinInputWidth = 72` 才另起一行、占满整行），光标便紧跟在最后
  一枚胶囊后面；输入框铺满行尾余量，顺带让胶囊右边那片空白也能点出光标。
  代价：地址长过余量时在框内横向滚动，不再独占一整行。折叠态输入框留在树上但不参与排版
  （零尺寸摆原点，`Offstage` 本来也不画它）。
- **抄送 / 密送整行的显隐**：`_ccBccOpen = 用户点过折叠行(_ccBccExpanded) || 抄送密送非空`。
  抄送密送都空且没点开时，三行折叠成一行「抄送/密送, 发件人：<账号>」；**点这一行**（整行
  是个 `GestureDetector`，= 设计稿的「发件人」列）才展开抄送 / 密送 / 发件人三行。
  **刻意不看收件人有没有聚焦** —— 点收件人只为编辑收件人，历史上「聚焦收件人就顺带展开」
  被用户反馈掉了。展开后若**没填任何内容、焦点又离开收件栏**则自动收回折叠行：监听
  `FocusManager` 的 primary focus 变化（它是个 `ChangeNotifier`，focus 一挪就通知），帧末判定
  —— 此刻 cc / bcc 的「未提交文字」可能刚被落成胶囊，帧末才能拿到最新状态；判定条件是
  「无收件栏聚焦 && 抄送密送（胶囊 + 未提交文字）全空」。已填过的抄送 / 密送**绝不折叠**
  —— 那等于把收件人藏起来。
  折叠行的 `Key('compose-row-ccfrom')` 挪到 `GestureDetector` 上（它才是 Column 的直接子级，
  反配对靠它这一层认）。
- **两个 element 复用的坑**（都表现为「输入焦点被抢」，都靠 key 治）：
  - 输入框在三种形态里必须待在**同一个 `_ChipsInput` 的最后一格**且带 key，折叠态用
    `Offstage` 藏而不是移出树。让它在「直接子级」与容器内部之间搬家，`EditableText` 会被
    重建 —— **点一下输入框，键盘刚起来又立刻收回**。
  - `_FieldRow` 每行都要带 key。抄送 / 密送整行会增删，行数一变，无 key 的兄弟就按下标
    重新配对：主题那行的 `EditableText` 被当成另一个 widget 重建、焦点被踢掉，焦点作用域
    又把焦点还给上一个聚焦过的节点（收件人）—— 表现为**在主题里打字，字进了收件人**。
- **输入提示**：候选池是**当前账号收件箱已加载的发件人**（`MailPreview.senderAddress` +
  `sender`，由邮件列表页按地址去重后传进来）。刻意不读系统通讯录（要 `READ_CONTACTS` 全量
  读）、不额外打接口。按最后一段输入模糊匹配名称或地址，已填过的人不再提示，最多 4 条。
  提示卡走 **`Overlay` + `LayerLink`**：排进 `Column` 会把下面几行往下顶，每敲一个字表单
  都跳一次。它不受视口裁剪，故滚动时（`ScrollUpdateNotification`）主动收掉。
  `LayerLink` 贴的是**整块收件人内容区**（`_ChipsInput`）而不是输入框 —— 输入框只占行尾
  余量，贴它会得到一张又窄又从行中间起头的卡片。
- **点胶囊**弹「删除 / 编辑 / 移至抄送 / 移至密送」（`showMenu` 贴着被点的那一枚）。
  **样式与首页右上角「导入 / 设置」菜单一致**（同一份 `AppMenuRow` / `AppMenuDivider`，
  见 `lib/widgets/app_menu.dart`）：底色 `palette.background` + 圆角 12 + 四周发散阴影，
  选项「图标 + 文案」高 52 / 左右 20 边距 / 15 号字 / 字距 1.5，细线分隔缩进 20。
  「移至」只列另外两栏；「编辑」= 删胶囊 + 把地址放回输入框。同一地址在三栏间唯一
  （`ComposeContact` 按地址大小写不敏感判等）。
- **发件人行只读**：本页从某账号的邮件列表进来，`sendMail` 也用这个账号鉴权，故设计稿上
  那个 ▾ 没做成账号切换（换发件人要换 token / 可能撞上未授权 `Mail.Send`）。
- 抄送 / 密送随发信一起下发（`MailApi.sendMail` 的 `cc` / `bcc` → Graph
  `ccRecipients` / `bccRecipients`，空列表不下发该字段），三栏地址都过一遍格式校验。

### 5.7 新建邮件正文的选区级排版

字号 / 加粗 / 斜体 / 下划线 / 颜色是**选区级**的：选中一段再点，只有那一段变。曾经这五项
都整篇套用（`TextField.style` 一改，全篇文字跟着变），用户反馈「我期望只针对所选文案」。

- **模型是一份与正文等长的逐字格式表**（`lib/data/compose_rich_text.dart` 的
  `ComposeTextFormat`，纯函数 + 值相等，可单测）。刻意**不引富文本引擎**
  （flutter_quill 那类）：底部两条工具栏、收件人三栏与整页滚动都是按设计稿 1:1 写的，
  换引擎等于连编辑器一起换掉；而这里只要五种字符级属性，一份格式表就够，`TextField`
  自带的光标 / 选择菜单 / 输入法 / 撤销全部照旧。
- **每个字都记一份完整格式**，不是「只记与基准不同的那几项」：正文 `TextField` 的基础样式
  要跟着光标处的字号走（光标高度、空正文时的提示文字都看它），若某些字靠继承基础样式取值，
  改一次字号就会串到本该保持原样的旧文字上 —— 那正是原来的病根。
  例外只有颜色：`null` 就是「跟随主题」，靠继承基础样式实现，故**基础样式的颜色只能是
  `palette.textPrimary`**（若按光标处的颜色给，光标停在红字里时别处没上色的字会一起变红）。
- **渲染**：`_RichBodyController extends TextEditingController` 覆写 `buildTextSpan`，
  把格式表合并成尽量少的段（`composeTextRuns`）再各自 `TextSpan`；输入法正在拼的那一段
  照惯例加下划线（与基类默认行为一致）。
- **`strutStyle: StrutStyle.disabled` 是必需的**：`EditableText` 默认
  `StrutStyle.fromTextStyle(style, forceStrutHeight: true)`，会按基础字号把每行行高**焊死**
  —— 混排大字号那几段会被压扁 / 叠在一起。关掉 strut 后每行按自己那几段的实际字号排；
  正文统一字号时观感与原来一致（行高由 `TextStyle.height = 1.5` 决定，与 strut 无关）。
- **格式跟着文字挪**：编辑框只交出「改完之后的整段文字」（输入法、粘贴、撤销都一样），
  故每次 `value` 变更先按 `composeTextEdit`（公共前后缀之差）求出改了哪一段，再
  `composeSpliceFormats` 挪格式表；新插入的字继承左边那个字（行首取右边），同系统编辑器。
- **没有选区时，工具栏设的是「接下来要打的字」**（`_pending`，Word / Gmail 同款），
  光标被挪去别处即作废 —— 但**首次落焦点不算挪**（此前压根没有有效选区），否则
  「先在工具栏选好颜色、再点进正文打字」一进去就把颜色丢了。
- **排版栏显示光标处的格式**（`_shownFormat` ← `formatAtCursor`）：光标停在粗体里 B 就亮着。
  它缓存在页面 State 里，只在派生值真的变了时 `setState` —— 否则每敲一个字整页都重建一次。
  选区里粗细不一时按**选区头一个字**取反，与系统编辑器一致。
- **对齐 / 列表 / 缩进仍是段落级的**：对齐走 `TextField.textAlign`（整篇），列表与缩进靠在
  行首插字符近似。字符级格式表管不着这些。
- **发信**：`composeBodyHtml` 一个字都没排版过且左对齐 → 纯文本直发；否则包一层
  `<div style="white-space:pre-wrap;font-size:16px[;text-align:…]">`，**只给非默认格式的段各包
  一个 `<span>`**，文字一律转义。
- **已知取舍**：格式**不进撤销栈**（`UndoHistoryController` 只管文字），撤销回来的那段文字取
  邻居的格式，重新选一次即可，不至于丢内容。

---

## 6. 微软集成关键约束（务必牢记）

- **OAuth 端点用 `common` 租户**（`/common/oauth2/v2.0/token`）：个人 Outlook + 组织账号都收（用 `consumers` 会挡掉组织账号）。
- **`defaultScope = 'https://graph.microsoft.com/.default'`**：换取该账号**已授权的全部**权限，不写死具体 scope。原因：OAuth 规则「请求的任一 scope 未授权 → 整个请求 AADSTS70000 失败」；导入的批量账号往往只授权了 `Mail.Read`（无 `Mail.ReadWrite`/`Mail.Send`），写死会连读都拉不到 token。`.default` 只取已同意权限：只有 `Mail.Read` → 能读；额外授权 `Mail.ReadWrite`/`Send` → 写也能用。
- **健康检测 = 两步**：刷 token（scope 显式带 `User.Read offline_access`）**+ 真打 `GET /me`**，两步都过才算 ok。刻意不复用 `TokenService`（那里缓存邮件 scope token）。
- **scope 在初始授权时锁死**，无法给已有 token 补授权；要新增权限（如标已读 `Mail.ReadWrite`、发信 `Mail.Send`）必须**重新走 OAuth 换新 token**。个人 outlook 被微软禁 ROPC，纯账号密码无人值守换 token 不可行，需浏览器登录 + 同意。
- 换 token 工具：`api-test/get-token.mjs`（Node，授权码流 + PKCE，起 localhost:3000 回调）。已注册 Azure 应用 **clientId `2955bdca-22de-4829-80e8-1908618c7f49`**（见 `MAIL-TOOLS.MD`），重定向 `http://localhost:3000`，公共客户端 + PKCE 无 secret。换到的 token 追加到 `api-test/tokens.txt`（`api-test/` 已 gitignore）。**换到新 token 导入后 App 无需改代码**（`.default` 自动带新权限）。
- 常见错误码：`AADSTS70000`（请求了未授权 scope）、`AADSTS700016 / unauthorized_client`（client_id 无效）。`error_mapper._isOAuthAuthError` 已把 `invalid_grant/invalid_client/unauthorized_client/invalid_scope/interaction_required/consent_required` 归到 `unauthorized`，健康检测据此标红。

---

## 7. 目录结构

```
lib/
  main.dart                 组合根：ApiScope + SettingsScope + MaterialApp
  api/                      对外接口 + 注入
    api_scope.dart          ApiService 的 InheritedWidget 注入
    api_service.dart        组合根工厂 create() + saveImported/knownAccounts
    auth_api.dart / mail_api.dart / user_api.dart
  core/
    network/                dio 封装、统一契约、错误映射、拦截器
    auth/                   token_store / token_service / credentials_store / health_service
    storage/                secure_storage 抽象
  data/                     account_import / mail_mapper（纯函数）/ mail_html_document / compose_rich_text / mock_mails
  models/                   account.dart / mail.dart
  pages/                    home / import / mail_list / message_detail / compose / settings
  widgets/                  stat_card / account_tile / mail_tile / app_refresh / segmented_selector / search_field / mail_html_view / app_menu
  theme/                    app_palette / app_icons / app_theme / app_scroll_behavior / app_page_route
  settings/                 settings_controller（ChangeNotifier + shared_preferences）
  l10n/                     app_zh.arb / app_en.arb + 生成的 AppLocalizations
test/                       单元 + widget 测试（详见 §9）
api-test/                   Node 换 token 脚本（gitignore，不入库）
```

---

## 8. 技术栈与依赖

- **Flutter 3.47 / Dart SDK ^3.13**，目标平台 iOS + Android。
- 状态：轻量自建（`ChangeNotifier` + `InheritedWidget`/`InheritedNotifier`），**未引入 Riverpod / Bloc**（历史上评估过 Riverpod 3，当前工程未用）。
- 关键依赖：`dio ^5.11`、`flutter_secure_storage ^11`、`shared_preferences ^2.3`、`file_picker ^12`（v12 用**静态方法** `FilePicker.pickFile` / `pickFiles` / `saveFile`）、`flutter_slidable ^4`、`easy_refresh ^3.5`、`webview_flutter ^4.14`（邮件正文渲染，见 §5.5）、`url_launcher ^6.3`、`path_provider ^2.1` + `open_filex ^4.7`（附件写临时文件后交系统应用打开）、`intl`、`flutter_localizations`。
- **iOS**：`Info.plist` 已补 `NSPhotoLibraryUsageDescription`（新建邮件选图要用相册，缺了会崩）、`NSContactsUsageDescription`（选联系人；系统选择器本身免权限，补上防审核问询）。
- 通讯录：`flutter_contacts ^2.3.1`，只用系统选择器 `FlutterContacts.native.showPicker(properties: {email})`。**要拿到邮箱地址 Android 必须有 `READ_CONTACTS`**（无权限插件抛 `PlatformException`），故 manifest 里声明 + 调用前运行时申请；iOS 免权限。选人这一步抽成 `ContactEmailPicker`（`lib/core/contacts/contact_picker.dart`）便于测试注入。
- 图标：`flutter_launcher_icons`（`dart run flutter_launcher_icons` 从 logo 生成）。
- **Android**：`compileSdk` 显式 37（flutter_secure_storage 11 要求）；main manifest 已补 `INTERNET` 权限。

---

## 9. 开发与测试约定

### 9.1 提交前必做
1. `flutter analyze` —— 必须**零问题**。
2. `flutter test` —— 全量通过（当前 153 个用例，随功能增减）。
3. 改了 arb 文案 → `flutter gen-l10n`。
4. 尽快 commit（历史上曾整套 MVP 文件丢失、无 commit，务必防再次丢失）。

### 9.2 测试约定
- 网络相关用**依赖注入假实现**，不打真网：`ApiService.create(mailApi:, healthService:, credentialsStore:)` 全部可注入。
- `test/fake_mail_api.dart` 的 `FakeMailApi`（继承真 `MailApi` 覆盖方法，`super(ApiClient(Dio()))`）；健康检测走真网的路径测试里用 `_FakeHealthService` 替换。
- 假数据主题需含「蓝湖 / 蓝湖官方」等原文，既有断言按该文本定位。
- EasyRefresh 触发后补 `pump(400ms)`（见 §4.6）。
- 断言「不可见」注意：`find.text` 会命中 `Opacity(0)`/`ClipRect` 里仍在树中的文本；要么 `f==0` 时 `SizedBox.shrink()` 移出树，要么换断言方式。push 后上一路由 offstage，`find.text` 默认 `skipOffstage:true`。

### 9.3 环境坑
- node 在 `/usr/local/bin/node`（v22）、flutter SDK 在 `/Volumes/WD2T/ENV/Flutter/flutter/bin`，**都不在默认 PATH**，跑命令要显式加 PATH。

### 9.4 运行命令
```bash
export PATH="/Volumes/WD2T/ENV/Flutter/flutter/bin:$PATH"
flutter pub get
flutter analyze
flutter test
flutter run                 # 需已 booted 的模拟器 / 真机
flutter gen-l10n            # 改 arb 后
node api-test/get-token.mjs <邮箱> [密码]   # 换新 token（需 /usr/local/bin/node 在 PATH）
```

---

## 10. 现状与路线图

### 已完成
- 首页总览（统计卡实时计算 total/valid/error、账号列表、吸顶头部、长按多选 + 底部操作栏、健康检测 / 删除 / 全选）。
- 导入（粘贴 + CSV）→ 落安全存储 → 启动载入。
- 邮件列表接 Graph 真实收件箱（下拉刷新 / 上滑翻页 / 去重 / 错误页原样展示 AADSTS）。
- 邮件详情懒取全文 + HTML 渲染；点击列表项**直达详情并自动标已读**（乐观更新 + 失败回滚）。
- 健康检测两步验证（刷 token + `GET /me`），模拟器双账号实测通过。
- 设置：主题 / 语言运行时切换 + 持久化。安全存储、错误映射、并发刷新合流。

### 待办（来自 `TODO.MD`，按用户优先级）
1. **导入调整**：导入的账号状态设为「未知」（不再默认「有效」）。
2. **首页调整**：列表状态新增「未知」；修复「下拉刷新把状态重置回有效」；统计卡按安全存储数据统计。
3. **检测调整**：健康检测接口获取用户信息，与账号**一起落盘安全存储**。
4. 归档 / 删除邮件回写 Graph（当前仅本地态）。
5. 发信能力（需 `Mail.Send`，依赖重新授权换 token）。

---

## 11. 待你决策的补充建议（我补充、供你选择）

以下是当前没列进 TODO、但对这类「批量账号运维」产品通常重要的点。**按优先级排，均待你拍板**，未确认前我不擅自实现：

**A. 数据与可靠性**
- A1. **账号状态与用户信息落盘 + 冷启动展示**：现在 access_token 只在内存、状态每次现算，冷启动列表全是「未知」。建议把「上次检测状态 + 检测时间 + 显示名 / 头像」随凭据落盘，启动即展示（配合 TODO 2/3）。
- A2. **全量 / 定时健康检测**：现仅手动勾选检测。可加「一键全体检」与「后台定时体检」，异常账号置顶。
- A3. **导出**：导入的对偶——把账号（可选是否含敏感字段）导出为 CSV / 文本备份（曾有 `邮箱账户导出_*.txt` 痕迹，说明有此需求）。

**B. 规模与性能**
- B1. **列表虚拟化 / 分页持久化**：账号量大（数百上千）时，首页与统计需分页 / 懒加载，避免一次性读全量安全存储。
- B2. **搜索升级**：当前是「已加载内过滤」，账号多时需服务端 / 全量索引搜索。
- B3. **并发限流**：批量体检对同一 IP 大量打微软接口可能触发限流（429），建议加并发上限 + 退避重试。

**C. 安全与合规**
- C1. **应用锁**：进入 App 需生物识别 / PIN（管理大量凭据，泄露风险高）。
- C2. **敏感信息展示策略**：列表 / 导出默认打码 refresh_token / 密码，按需揭示。
- C3. **审计日志**：记录「谁在何时删了 / 检测了哪些账号」，误删可追溯。

**D. 体验**
- D1. **状态筛选 / 分组**：按状态（有效 / 过期 / 未知）筛选与分组，运维更聚焦。
- D2. **批量重新授权向导**：把 `get-token.mjs` 的换 token 流程做进 App（WebView + 授权码流），避免命令行。
- D3. **未读数真实填充**：`Account.unread` 目前占位，可用 Graph 拉真实未读。
- D4. **空 / 错误态文案与重试**：统一各页错误态，网络抖动可重试。

**E. 工程**
- E1. **CI**：GitHub Actions 跑 `analyze + test`（`.github/` 已存在，可补 workflow）。
- E2. **崩溃 / 日志上报**：release 版接入错误收集。
- E3. **README 填充**：目前为空，可从本文件裁剪对外说明。

> 想推进哪些，告诉我编号即可；我会先就选中项确认细节再动手。

