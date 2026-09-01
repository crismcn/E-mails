# 首页交互调整 [OK]

- 页面上滑的时候 汇总、搜索框、列表同时上滑；汇总 上滑覆盖掉标题 右侧操作ICON保留不动；覆盖掉标题后 汇总、搜索框 固定 不在滑动 列表继续上滑加载

# 新增消息详情页面 [OK]

- 入口：在邮件消息页面 点击邮件消息 进入消息详情
- 风格：参照 "邮件详情.jpg" UI图 1:1 代码还原
- 功能：消息内容需要支持渲染 html 内容，非html内容文字渲染即可

# 邮件列表 [OK]

- 邮件列表 点击邮件进入详情后 需标记为已读

# 导入调整 [OK]

- 导入邮箱帐号 状态设为：未知

# 首页调整 [OK]

- 列表状态新增 “未知” 状态
- 现在列表下拉刷新 状态会变回 “有效” 状态 这个问题要修复
- 状态统计卡片 按安全存储的数据进行统计

# 检测调整 [OK]

- 检测接口需要获取用户的信息并与帐号一起落盘安全存储

# 兑换clientId写权限 [NO]

# 首页调整 [OK]

- 长按列表项 弹出的底部菜单中 在“健康检测”右侧 新增 “提权” 按钮
  - 按钮已落地（健康检测 / 提权 / 删除 / 全选 四格等宽），点击暂弹“提权功能尚未实现”；
    提权方案待定：scope 初始授权即锁死、个人 Outlook 禁 ROPC，无人值守只有“换 clientId 兑换”可试。

# 新建邮件页面 [OK]

- 实现附件&选图功能
- 内容编辑区域下方的工具栏 需要新增对其方式：参照”新建邮件-工具栏.jpg“ 1:1 实现 由于选项过多 需要左右滑动 关闭按钮固定在最右侧

# 邮件详情页面 实现邮件收件-附件功能 [OK]

- 风格：附件信息展示参照 “邮件详情-附件信息.jpg” 展开参照 “邮件详情-附件预览.jpg” 请1:1实现
- 功能：一些常规文件 如 图片 txt mp3 mp4 都直接调用手机API 如果调用不了 则直接下载文件

# 邮件详情页面调整 [OK]

- 现在有些邮件内容是html的宽度超出手机了 要滑动才能看到，能否固定宽度只有手机屏幕宽度，内容如果超出的话需缩放
  - 图片统一夹 `max-width:100%`；整封写死设计宽度（如 `<table width="600">`）时按该宽度渲染再用
    `FittedBox` 整体等比缩小，永不横向滑动。宽度推断在 `htmlDeclaredWidth`（纯函数，忽略 img 宽度、
    忽略百分比、上限 1600）。
- 内容过多 上滑邮件的时候 顶部标题 和 底部菜单都向外收缩隐藏 全屏空间用来展示内容，当用户下滑高度快到顶部时 标题栏和底部菜单又切入出现
  - 两条都用 `SizeTransition` 压高度（200ms），正文区随之占满全屏；贴顶 60px 内恒展开，
    上滑越过 80px 且可滚动距离 ≥200px 才收起。**下滑即刻切回**（不是只在快到顶部才回来）——
    `appRoute` 没有 iOS 侧滑返回，标题栏藏着就没法退出，需要严格按顶部阈值请说。

# 邮件详情正文改 WebView 独立滚动 + 双指缩放 [OK]

- 顶部标题栏 / 底部菜单改绝对定位（治收起标题时正文「偏差距离」跳位）
  - 已落地又回退：新架构下正文是**独立滚动**的 WebView，收起顶栏只让正文区变高、不改其滚动偏移，
    跳位在结构上不可能发生 —— 故绝对定位那套（Stack/Positioned/SlideTransition/ClipRect/高度测量）
    删掉，收放回到更简单的 `SizeTransition` Column。
- 邮件内容过多没显示全 + 不能双指缩放
  - 根因是同一个：旧「WebView 不滚 + 页内量高占位 + 整页一条滚动条」与「正文内缩放」天生冲突
    （缩放需要正文自己有可平移的视口）。改成正文 WebView **自己滚动 + 双指缩放**
    （`WebViewWidget` 挂 `EagerGestureRecognizer` 独占 pan + pinch）：长邮件内部滚动不再截断、
    双指可缩放；连带删掉量高脚本 / JS 通道，CSP `script-src` 收紧到 `'none'`。
  - 取舍（已与用户确认）：正文与上方「收件人/主题/附件」成两个滚动区；顶 / 底栏收放改由正文滚动
    位置驱动（HTML 用 `WebViewController.setOnScrollPositionChange`，纯文本用 `ScrollController`）。
  - 待真机验证：收起动画期间 WebView 被 resize 若有跳动，把 `_chrome` 时长调短或改瞬时；
    iOS 首次跑需 `pod install`。

# release 打包失败 + 图标补齐 [OK]

- `Codepoint 59198 not found in font, aborting`
  - 覆盖 `iconfont.ttf` 后码点重排，`starredFolder`(0xe73e) 与 `undoAlt`(0xe600) 在新字库里已不存在。
    debug/profile 不裁字库所以照跑，只有 release 的 `--tree-shake-icons` 会逐个找字形。
    报的是**十进制**码点（59198 = 0xE73E），换算后才好在 `app_icons.dart` 里定位。
  - 分别改到 `starred-email`(0xed88) 与 `revoke`(0xe606)；CLAUDE.md §4.2 补了「覆盖字库后先用
    fontTools 比对一遍」的一行命令，免得下次再等 release 才发现。
- 新增字形接上（字库 31 → 57 个）
  - 回复 / 转发 / 重做 / 删除 / 归档 / 导入 / 已选中 / 健康检测 / 提权 / 设置 / 全选 / 取消全选
    12 项从 Material 换成 iconfont；另存了 10 个备用常量（实心删除、多选、已读/未读信封等）。
  - **重做**之前因「字库两款撤销都朝左、没有镜像版」只能留 Material，这次补上了 `redo`(0xe679)。
  - `delete-line` 码点在 BMP 之外（`0x100CF`），`Icon` 与 tree-shaker 都能正常处理（已 release 验证）。
  - 仍留 Material 四项：裸对勾 / 断网 / 回复全部 / 通用文件 —— 字库里没有对应造型。

# 邮件详情正文：缩放抖动 + 隐藏滚动条 [OK]

- 双指缩放时页面抖动
  - 根因是**正反馈**：WebView 的滚动回报驱动顶 / 底栏收放 → 收放 resize 正文区 →
    WebView 重排又吐新偏移 → 再收放。缩放时偏移双向连续变化，抖得最明显。
  - 两道闸：① `MailHtmlView` 外套 `Listener` 数手指，≥2 根即视为缩放、期间不回报滚动
    （抬手后再缓 400ms 等回弹 / 边界修正的尾巴）；② `_onBodyScroll` 在 `_chrome.isAnimating`
    期间只更新基准值、不判方向 —— 收放动画自己引起的偏移不是用户意图。
  - 没走「用 JS 监听 visualViewport 拿缩放比」那条：会把刚删掉的 JS 通道和
    `script-src 'none'` 又放开，代价不值。数手指不需要 JS，也不分平台。
- 滚动时隐藏滚动条
  - 主视口那条是**原生绘制**的，CSS 管不到 → `setVerticalScrollBarEnabled(false)` +
    横向同理（Android / iOS 都支持，调用前问 `supportsSetScrollBarsEnabled()`）。
  - 邮件自带的内层滚动容器另加 `::-webkit-scrollbar{width:0;height:0}`。
- 待真机确认：缩放手感与抖动是否彻底消失（widget 测试没有平台视图、碰不到多指手势）。

# 字库又换了一版：重新梳理图标映射 [OK]

- 按 `font_class` 把 54 个常量逐个对了一遍当前字库，实际要改的 4 个：
  `send`(送 0xe7aa→0xe6dd)、`starredFolder`(0xed88→0xe821)、`delete`(0x100cf→0xe60a)、
  `textColor`(0xe61e→0xe61a)。`starred-email-1` 没了、新增 `send-line-1`(存为 `sendAlt`)。
- **`font_class` 也不可信了**：这版里 `checked-all` / `deselect-all` 两个名字互换，
  但两个码点上的字形一直没变（0xe6c3 实心=全选、0xe6c2 空心=取消全选）。照名字接会正好接反，
  已按字形定死并在 `selectAll` 上写了注释。对齐 / 缩进五个字形也重新量了几何,没动。
- 新增 `test/app_icons_test.dart`：比对 `app_icons.dart` 的码点与 `iconfont.json`，
  把「码点消失」从 release 打包失败前移到 `flutter test`。
  管不到「码点还在但换了图形」——那种只能看图，CLAUDE.md §4.2 存了出图脚本。

# 邮件详情：元信息并入正文滚动区（治上滑抖动）[OK]

- 上滑时收件人 / 标题也要跟着往上滚，否则抖动
  - 根因：收起顶栏 = `SizeTransition` 压高度 = 正文区被 resize = WebView 重排，
    重排又吐新偏移驱动收放，正反馈。**只要收放会改正文尺寸，抖动就治不干净。**
  - 收件人 / 主题 / 日期改由 `buildMailHtmlDocument` 写进文档头部 `#mail-meta`，
    与正文同一个滚动区、上滑一起滚走（纯文本正文则与正文同一个 `SingleChildScrollView`）。
  - 顶 / 底栏改回 `Stack` + `Positioned` + `SlideTransition` 浮层：正文 `Positioned.fill`
    恒定铺满，靠**恒定**留白给浮层让位，收放只做绘制期平移。正文尺寸与 `maxScrollExtent`
    全程不变（已加断言），WebView 不再重排。
  - 附件条拆成「摘要行（恒定高度，参与留白）」+「展开列表（盖在正文上，不参与留白）」，
    展开 / 收起不会改留白 —— 改了就要重载文档、正文跳回顶部。
- 顺带
  - 主题 / 收件人来自远端，拼进文档前一律 `escapeMailHtml` 转义；元信息样式全部 `!important`
    压住邮件的全局规则。
  - 超宽邮件下元信息字号与留白按缩放比倒数放大回去，正文自己的尺寸不动。
- 待真机确认：上滑 / 下滑的连续感与缩放手感。

# 字库第三版：接上 reply-all / export，撤销换 revoke [OK]

- 字库 57 → 56 个，`chexiao` / `reply` / `forward` / `send-line-1` 等被删，换成
  `revoke`(撤销)、`reply-email`、`reply-all-email`、`forward-email`。
  `undo` 改指 `revoke`(0xe606)、`reply`→0xe82e、`forward`→0xe612。
- **`replyAll` 终于能离开 Material**：新字库有 `reply-all-email`(0xe82f，双左箭头)，
  与 `reply`(单箭头) 并排能分清。仍留 Material 的只剩三个：裸对勾 / 断网 / 通用文件。
- 新增 `export`(0xe60b) 备用（导入的对偶，功能还没做）。
- 56 个常量与 56 个字形现在**一一对应、无未引用字形**。`test/app_icons_test.dart`
  这次就是它先报出 4 个失效码点的。

# 邮件详情页最终形态：整页一条滚动条 + 正文可缩放 [OK]

- 收件人 / 标题 / 日期回到原生组件；html 用 webview；整体一起上滑；webview 可缩放移动、无滚动条
  - 元信息 / 附件全部改回原生 Flutter 组件，与正文同在一个 `SingleChildScrollView`
    里，整页只有一条滚动条 —— 上滑时收件人、标题、日期、正文一起走。
  - 正文 WebView **按页内量到的高度占位、自己不滚**（量高脚本与 nonce CSP 一并回来了：
    `script-src 'nonce-…'`，邮件自带脚本照旧全挡）。
  - **手势分工是这次的关键**：`WebViewWidget` 挂自写的 `_MultiTouchGestureRecognizer`，
    只在**第二根手指落下**时认领。于是单指拖动归外层滚动视图（整页滚）、双指归 WebView
    （缩放 + 平移）、单指点击靠竞技场清算落到平台视图（链接能点）。
    之前用 `EagerGestureRecognizer`（落手即赢）会把单指拖动也吃掉，外层就滚不动了。
  - **放大后要够得着**：双指放大只改视觉缩放、CSS 高度不变，故脚本连
    `visualViewport.scale` 一起回报，宿主按 `CSS 高度 × 排版缩放比 × 视觉缩放比` 重新定高
    —— 放大后的下半截靠页面滚动就能看完，不必在 WebView 里纵向平移。
  - 滚动条：WebView 原生那条关掉（两个平台都支持），邮件内层容器靠 `::-webkit-scrollbar` 关。
  - 顶 / 底栏保持绝对定位浮层 + 恒定内边距：`maxScrollExtent` 恒定，内容不跳位（已加断言）。
- 待真机确认：单指滑 / 双指缩放的分工手感；缩放后页面变长是否顺；长邮件是否完整。

# 新建邮件页面调整 [OK]

- 底部工具栏图标没有均分宽度
  - `spaceAround` 均分的是间隙不是格子，各项内容宽度不同（图标 24 vs「Aa」文字）导致中心不等距；
    改成四个 `Expanded` 各占 1/4、格内居中。
- 字体大小选择 和 文字颜色选择 改为横向布局可以左右滑动选择
  - 去掉下拉浮层：点字号 / 颜色时**排版栏整行原地换成横向选项条**（可左右滑），
    选中即生效并切回排版栏；高度恒 48，不遮正文。字号档位扩到 12–36 共 10 档。
- 收件人右侧图标点击后选择系统联系人
  - `flutter_contacts ^2.3.1` 的系统选择器（`FlutterContacts.native.showPicker`）。
    多邮箱联系人会二次选择，不默认取第一个；没邮箱 / 没权限就地提示。
  - **Android 需 `READ_CONTACTS`**（要拿邮箱就必须带 properties，插件无权限会抛异常），
    已加进 manifest 并在调用前运行时申请；iOS 系统选择器免权限，但仍补了
    `NSContactsUsageDescription` 以防审核问询。

# 邮件详情页面调整 · 浮层化 [OK]

- 顶部标题栏 和 底部菜单栏修改成绝对定位 现在滑动邮件内容时 在隐藏标题的时候 页面有个偏差距离
  - 根因：原来用 `SizeTransition` 压高度，两条栏在 `Column` 里占位，收起时视口变高
    → 滚动视图重新布局、`maxScrollExtent` 变短，正文当场跳一段。
  - 改成 `Stack` + `Positioned`：滚动视图 `Positioned.fill` 恒定铺满整屏，靠**恒定**的上下
    内边距给两条浮层让位；收放只用 `SlideTransition` 把浮层移出屏幕外沿（Stack 自带裁剪）。
    内边距与视口都不变 → `maxScrollExtent` 恒定，正文一格都不跳（已加断言）。
  - 内边距用两条浮层的**实测高度**（`GlobalKey` + 帧后量一次校正），写死会因平台字体 /
    文字缩放差几像素、正好露在浮层边缘。标题栏补了不透明底色（现在压在正文上）。
  - 浮层各自套 `ClipRect`。`SlideTransition` 是**绘制期**变换，浮层的布局矩形始终在
    `Stack` 范围内 → `RenderStack._hasVisualOverflow == false` → 不装裁剪层 → 挪出去的
    部分照画。真机上表现为「顶部菜单没隐藏」：标题栏滑进状态栏那条安全区里赖着不走
    （测试的 view padding 为 0，越界即出屏被裁，所以第一版测试没抓到 —— 现在断言里
    补了 `FakeViewPadding` 模拟刘海机型）。

# 邮件详情正文换 WebView [OK]

- 渲染 html 的区域改成 webview（原来的 `flutter_widget_from_html_core` 还原度不够）
  - `webview_flutter ^4.14.1`（Flutter 官方）。包装文档抽成纯函数
    `buildMailHtmlDocument`（视口 + CSP + 样式 + 量高脚本），组件 `MailHtmlView` 只管生命周期。
  - **宽度**：声明宽度超屏 → 视口写 `width=<声明宽度>` 由引擎整体缩放（不再 `FittedBox` 压扁，
    文字不发虚）；双指缩放开着；`overflow-wrap:anywhere` 顺手修掉「长 URL 撑出横条」。
  - **高度**：页内 `ResizeObserver` 回报 `body.scrollHeight`，组件按此占位 → 整页仍一条滚动条，
    收件人 / 附件 / 正文一起滚，标题栏收放逻辑不动。`onPageFinished` 宿主侧再量一次兜底。
  - **正文全宽**：滚动视图不再留左右 20 边距，改由元信息自己带 —— 邮件按整屏宽设计，
    挤在边距里会被多缩一截。
  - **配色（按你选的「跟随主题注入暗色」）**：暗色下整份文档反色 + 图片反回来。这样不猜发件人
    配色也能保证文字可读、版式与对比关系都留着。已知取舍：白底 logo 仍是白块、
    元素 `background-image` 会被反色、深底设计的邮件会被反成亮底。
  - **安全**（正文是发件人可控的敌意输入）：CSP `default-src 'none'`，脚本只认每份随机 nonce
    的那一段；邮件自带 script / onclick / iframe / 表单 / base 全挡，`<script>` 另外物理删一遍；
    链接不在 WebView 内导航，只把 http/https/mailto/tel 抛给外部浏览器。
    **远程图片仍会加载**（与换之前一致），跟踪像素照旧能打点。
- 内容过多的时候没有显示全
  - 真凶：**`webview_flutter_android` 默认 `useWideViewPort = false`**，Android WebView 于是
    **忽略 `viewport` meta** —— 写死 680px 的邮件按屏宽排版、不做缩放，而 Flutter 侧仍按
    「声明宽度 → 屏宽」算了 0.53 的缩放比去定高，于是盒子只有实际显示高度的一半，
    下半截被裁掉。显式 `AndroidWebViewController.setUseWideViewPort(true)` 修掉
    （iOS 的 WKWebView 原生就认 viewport meta，只有 Android 有这个坑）。
  - 顺带加固量高：取 `#mail-root` / `body` / `documentElement` 三种量法的最大值，
    `ResizeObserver` + 轮询持续跟进，宿主侧也隔几拍补量；并用 `!important` 压掉邮件写给
    `html/body` 的 `height:100%` / `overflow:hidden`（照办会把正文压成一屏高）。
  - 真机验证（Android 模拟器 API 36，实账号）：680px 宽的转发邮件、Microsoft 通知邮件
    都能滚到底、内容完整；纯文本邮件（GitHub 通知）仍走 Flutter 文本，长 URL 正常折行。

# 邮件详情：放大正文直接闪退 [OK]

- 真凶是我们自己的定高逻辑：上一版按 `CSS 高度 × 排版缩放比 × visualViewport.scale`
  给 WebView 重新定高，想让放大后的下半截靠整页滚动看完。缩放比可到 10，盒子被撑成
  几万逻辑像素，**Android 平台视图按自身尺寸开纹理**（受 `GL_MAX_TEXTURE_SIZE` 约束，
  通常 4096–16384）当场炸；缩放过程中 `visualViewport` 的 resize/scroll 事件还连成一串
  setState，每帧都在重设平台视图尺寸。
- 改法：**盒子高度只由「内容高度 × 排版缩放比」决定，与视觉缩放彻底解耦**。
  量高脚本不再回报缩放比、不再监听 `visualViewport`，宿主侧删掉 `_visualScale`。
- 代价（明说）：放大后要看溢出部分改用**双指平移**（`_MultiTouchGestureRecognizer` 本来就
  把双指判给 WebView），不再是「页面自己变长、单指滚下去」。单指仍是整页滚动。
- 待真机确认：放大不再闪退；放大后双指平移能够着内容。

# 邮件详情：双指缩放变形 + 整机卡死 → 正文改独立滚动 [OK]

- 上一版只去掉了「按缩放比重新定高」，仍留着「WebView 按**内容高度**占位」——
  真机上双指缩放依然**画面变形 + 整机卡死**。
- 根因（读插件源码确认）：`webview_flutter_android` 默认
  `displayWithHybridComposition = false` → `PlatformViewsService.initSurfaceAndroidView`
  → **纹理合成**，纹理按控件尺寸开、受 `GL_MAX_TEXTURE_SIZE` 约束（常见 4096–16384
  **物理**像素）。长邮件的内容高度 × devicePixelRatio(3) 轻易越界 → 纹理被 clamp 成小尺寸
  再拉伸铺满 = **变形**；缩放时每帧重绘这块巨型表面 = **主线程打满、整机卡死**。
  也就是说「按内容高度占位」这个模型本身就踩在红线上，跟缩放放一起必炸。
- **「整页一条滚动条」与「正文内缩放」在这个渲染模型下互斥**，已让用户拍板 →
  选「正文独立滚动（业界做法，Gmail / Outlook 就这样）」。
- 落地：页面改 `Column` 三层 —— 可收起顶部区（返回栏 + 收件人 / 主题 / 日期 / 附件，
  原生组件，自带 `maxHeight = 屏高×0.45` 与自己的滚动）、`Expanded` 正文区
  （WebView 视口 = 一屏、自己滚、`EagerGestureRecognizer` 独占手势、原生双指缩放）、
  可收起底部操作栏。顶 / 底两块回到 `SizeTransition` 压高度 —— 正文独立滚动，
  压顶栏只让视口变高、不改滚动偏移，跳位在结构上不可能发生，`Stack` + `SlideTransition`
  + `ClipRect` + 高度测量那一整套删掉。
- 顺带清掉一大片：量高脚本 / `MailMetrics` JS 通道 / `mailHtmlNonce` / `layoutScale`
  / `_MultiTouchGestureRecognizer` 全删，**CSP `script-src` 从 `'nonce-…'` 收紧回 `'none'`**
  （宿主不必知道内容多高，就不需要在敌意文档里跑任何脚本了）。
- 收放改由正文滚动驱动：HTML 走 `setOnScrollPositionChange`，纯文本走 `ScrollController`。
  **坑**：`ScrollPositionChange` 两个平台单位不同（Android 设备像素 / iOS 点），
  `MailHtmlView` 里按 `devicePixelRatio` 归一化后再回调。
- 待真机确认：双指缩放不再变形 / 不卡死；单指滑正文顺不顺；顶 / 底栏收放跟手；
  长邮件能滚到底；iOS 上同样正常（这次改动只在 Dart 侧，无需重跑 `pod install`）。

# 邮件详情：元信息要跟着滚 + 全屏来回跳动 → 回到整页一条滚动条 [OK]

- 上一版（正文独立滚动）有两个毛病：顶部收件人 / 标题 / 日期不跟着正文滑；顶 / 底栏收起后
  「全屏状态来回跳动」。
  - 跳动的病根一直是同一条：**收放会改正文区尺寸或滚动几何 → WebView 重排 → 吐出新偏移 →
    又去驱动收放**，正反馈。压高度、浮层平移、滚动位置驱动三种做法都绕不开。
    按用户要求**直接取消收放**，回路就不存在了。
- 结构按用户给的方案回到「整页一条滚动条」：`Column`[固定返回栏 / `Expanded` 里一条
  `SingleChildScrollView`（收件人 / 主题 / 日期 / 附件 / 正文都在里面）/ 固定底部操作栏]。
  正文 WebView **按页内量到的渲染高度占位、自己不滚**；**双指缩放只在这个高度内做**
  （缩放不改盒子高度 —— 那正是「一放大就闪退」的旧账）。
- **变形 / 卡死这次靠 Hybrid Composition 治**：`AndroidWebViewWidgetCreationParams(
  displayWithHybridComposition: true)`，经 `WebViewWidget.fromPlatformCreationParams` 传。
  默认的纹理合成（`initSurfaceAndroidView`）按控件尺寸开纹理、受 `GL_MAX_TEXTURE_SIZE`
  约束，长邮件必越界 → clamp 后拉伸 = 变形、每帧重绘巨型表面 = 卡死。插件注释自己写着
  HC「有性能代价，但没有渲染到 SurfaceTexture 的尺寸限制」。
  **代价**：HC 下叠在平台视图上的 Flutter 内容走 `FlutterImageView` 覆盖层，快速滚动时平台视图
  可能跟不上。若真机上有拖影，退路是给盒子高度设上限、超出让 WebView 自己滚。
- 手势回到 `_MultiTouchGestureRecognizer`（**第二根手指落下**才认领）：单指滑 = 整页滚，
  双指 = WebView 缩放 + 平移，单指点 = 链接。`EagerGestureRecognizer` 会吃掉单指拖动。
- 量高脚本 / `MailHeight` 通道 / nonce / `layoutScale` 一并回来（宿主必须知道内容多高），
  CSP `script-src` 从 `'none'` 放回 `'nonce-…'`；`setOnScrollPositionChange` / `SizeTransition`
  / `_chrome` / `_onBodyScroll` / `_MetaSection` 的高度上限全删。
- 待真机确认：① 双指缩放不变形 / 不卡死（HC 是否真的解掉纹理上限）；② 元信息跟着正文一起上滑、
  不再跳动；③ 长邮件量高准不准、能不能滚到底；④ HC 下快速滚动有没有拖影；
  ⑤ iOS 照旧（改动只在 Dart 侧，无需 `pod install`）。

# 邮件详情：滚动卡顿 + 放大后够不着内容 [OK]

- 上一版靠 Hybrid Composition 绕开纹理尺寸限制，代价如实兑现了：**滚动卡顿**。
  已改回默认的纹理合成，改用 **`min(内容高度 × layoutScale, 8192 物理像素 ÷ dpr)`** 夹住盒子高度
  来防变形 / 卡死。上限值运行时拿不到真实的 `GL_MAX_TEXTURE_SIZE`，取了个几乎所有机型都满足的值。
- 放大后被遮住的内容够不着：根因是单指拖动一律判给外层页面，WebView 内部那段可滚距离没人用。
  改成**按「WebView 内部现在还能不能纵向滚」决定单指归谁**（页内脚本比
  `内容高度 > visualViewport.height` 得出一个布尔量）：
  - 放大后可视视口变小 → 能内滚 → 单指在 WebView 里滚，够得着遮住的部分；缩回 1 倍自动交还外层。
  - 邮件超过高度上限被夹 → 同样走内滚，不会截断。
  - 双指永远归 WebView；单指点击照旧靠竞技场清算落到平台视图，链接能点。
  - 那个布尔量**不进 `setState`**（只被手势识别器读）——所以这次监听 `visualViewport` 是安全的，
    历史上炸的是「按缩放比重新定高」。
- 也**评估过不用 WebView**：`flutter_html` 系画成原生 widget 最流畅、天然一条滚动条，但表格嵌套 /
  绝对定位 / 媒体查询 / 背景图 / webfont 都会走形 —— 项目当初就是因为还原度换走的，未采用。
- 待真机确认：① 滚动是否恢复顺滑；② 放大后单指能不能在正文里滑到被遮住的内容、缩回后整页滚动
  是否自动接回；③ 超长邮件（触到高度上限那种）读得完不；④ 双指缩放仍不变形 / 不卡死。

# 邮件详情：暗色下加载 html 白闪一下 [OK]

- WebView 在文档 CSS 生效前画的是**自己的默认白底**，`setBackgroundColor(palette.background)`
  挡不干净；再叠上「首帧 160 占位 → 量到高度跳一次版式」，暗色下就是一下白闪加一跳。
- 改法：WebView 上面盖一层 `palette.background` 的遮罩（带转圈），**「文档加载完 + 已量到
  高度」才淡出**（240ms）—— 露出来的就是最终版式。
  - 淡的是这层 **Flutter 覆盖层**，不是 WebView 的 `opacity`：平台视图的透明度在 iOS 上
    不保证生效（embedder 只稳定支持裁剪与变换）。
  - 淡完把整层**移出树**：转圈留在 `opacity:0` 下面会一直空转、每帧重绘（CLAUDE.md §4.6
    那条老坑）。用 `AnimationController` + `AnimatedBuilder`，`isDismissed` 时返回
    `SizedBox.shrink()`。
  - 兜底 `_kRevealDeadline = 1500ms` 无条件淡出：量高三条路全失败 / 远程图片把
    `onPageFinished` 吊住时，不能把正文永远盖着。换主题重载文档时遮罩重新盖上。
- 待真机确认：暗色下点进邮件不再白闪、内容一次到位地淡入；慢网 / 大图邮件不会久等黑屏
  （最多 1.5s 就露出来）。

# 邮件详情：白闪的真凶是「靠反色凑底色」 [OK]

- 蒙层已经在了（上一条），仍残留闪动 —— 因为**我们自己在文档里写了一层近白色**：暗色下
  整份文档 `filter:invert(1)`，页面底色于是得先写成 App 底色的反色 `#f5f2ed`（近白）才能
  反回 `#0a0d12`。而浏览器**先画背景、后合成滤镜**，中间几帧照着近白画 = 白闪。
  蒙层挡的是首帧，挡不住蒙层淡出后滤镜尚未稳定的那几帧。
- 改法：**滤镜从 `html` 挪到 `#mail-root`**，`html{background:<App 底色>!important}` 直接写
  真实暗色、不参与反色。任何时刻页面底色都是暗的。
  - 配套 `body{background:transparent!important}`（仅暗色）：邮件常带
    `<body style="background:#fff">`，嵌套 body 标签被解析器丢弃、属性并到文档 body 上，
    而 body 在反色层**外面** —— 不压掉就是暗页面上一大块白。
  - `_invertHex` 随之删掉（没有消费者了）。
- 蒙层顺带加严：条件满足后再压 `_kRevealSettle = 140ms` 才淡出（`onPageFinished` 只说明
  文档加载完，首帧上纹理还要一两帧）；淡出只排一次，免得图片陆续到把它一路推到兜底时间。
- 待真机确认：暗色下点进邮件、以及暗↔亮切主题时都不再有白闪。

# 新建邮件页面调整 [NO]

- 收件人编辑框输入提示：
  样式：参照 UI文件夹下的 “收件人-输入提示.jpg” 1:1实现
  交互：输入收件人时 在收件列表模糊匹配，点击提示项填入到输入框；填入后的样式参照 “收件人-多收件人.jpg” 实现。

- 点击收件人编辑框选项
  样式：参照 UI文件夹下的 ”收件人-收件人编辑.jpg“ 1:1实现
  交互：点击输入框联系人选项 弹出操作菜单：删除｜编辑｜移至抄送｜移至密送

- 发件人编辑框点击输入框后
  样式：参照 UI文件夹下的 ”发件人-点击发件人输入框.jpg“ 1:1实现
  交互：点击收件人输入框，展开抄送和密送输入框，样式参照“发件人-点击发件人输入框.jpg”；如果没有输入 抄送人&密送人，则隐藏输入框，参照：“发件人-无抄送&密送.jpg” 1:1 实现

- 页面需要可以上滑
  在输入内容时，输入区域太小
