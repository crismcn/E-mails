# 邮件详情正文改「正文自滚」+ 全屏化（根治展示不全）[OK]

- 量高模型真机不可靠：用户多轮反馈「展示不全 / 滑不到底」，冷启动第一封邮件必现、干等不长全、
  返回重进才全。修了三版量高补丁（catch→continue、轮询拉长、跟图片 complete）都没根治 → 结论：
  「整页一条滚动条 + JS 量高给 WebView 撑内容高的盒子」这条链路在平台视图上不可靠（尺寸动态
  变化时纹理/合成跟不上）。
- 改：正文 WebView **有界视口自滚 + 双指缩放**（`EagerGestureRecognizer` 独占手势），不再量高。
  - `Column` 布局：顶（返回栏 + 元信息 + 附件）/ 中 `Expanded` 正文 / 底操作栏，顶底两条
    `SizeTransition` 收起，由正文内部滚动位置驱动（HTML 用 `setOnScrollPositionChange`，
    纯文本用 `ScrollController`）。
  - 文档去掉量高脚本 / JS 通道 / nonce，CSP `script-src 'none'`（整份文档无脚本，更安全）。
  - 收放回弹抖动用「累计位移 + ±16px 死区」吞掉（拖拽结束的物理回弹会误判成下滑把栏弹回来）。
  - **全屏化**：去外层 `SafeArea`，顶/底栏背景延伸到状态栏 / 底部安全区，任何时刻不露背景带。
- 待真机确认：① 冷启动第一封邮件不再截断、能一路滑到底；② 收起动画期间 WebView 视口变化
  是否偶发抖动（有 `isAnimating` 闸；若仍抖，收放改回 SlideTransition 浮层 / 动画调短）；
  ③ 状态栏/底部安全区无遮挡；④ 附件展开多图时顶区自己滚不挤爆正文。iOS 首次跑需 `pod install`。

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

# 消息详情页面展示不全 [OK]

- 用量高脚本测量的正文盒子高度，首次进入偶发「展示不全，返回再进又全了」，根因：
  - 宿主侧 `_measureFromHost` 单次 `runJavaScriptReturningResult` 失败就 `return` 掐死整条链路，
    冷启动（首次进 App）图片慢 + Android 加载窗口偶发抛异常 → 后面的量高轮次都不跑，
    高度停在低值。
  - JS 侧轮询只跑 10 拍 3 秒，冷启动到不了。
  - 宿主侧补救只在 `onPageFinished` 里跑，`onPageFinished` 被慢资源吊着没来就没人量。
- 修法（又一轮，用户实测仍缺）：症状「带图的邮件、正文底部直接没有、干等不会长全、
  只有返回重进才好」→ 确认是「图片加载后的完整高度从未报回」。前一轮的 catch→continue
  + 固定轮次（8s/7.2s）没用，因为固定圈数在图片到齐前就跑完了。改：JS 轮询**一直跑到
  `document.images` 全部 `complete` 才停**（60 拍 × 300ms = 18s 死兜底），宿主侧兜底同步
  拉 20 秒。详见 CLAUDE.MD §5.5 量高段。待真机重验；若仍缺，说明量高模型在真机不可靠，
  需转「正文 WebView 有界视口自滚 + 元信息并进同一文档」架构（结构性免疫）。

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
  - `ClipRect` + 高度测量那一整套删掉。
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

# 新建邮件页面调整 [OK]

- 收件人编辑框输入提示：
  样式：参照 UI文件夹下的 “收件人-输入提示.jpg” 1:1实现
  交互：输入收件人时 在收件列表模糊匹配，点击提示项填入到输入框；填入后的样式参照 “收件人-多收件人.jpg” 实现。
  - 候选池 = **当前账号收件箱已加载的发件人**（已与用户确认）。为此给 `MailPreview` 加了
    `senderAddress`（Graph 早就返回 `from`，之前映射时丢掉了），邮件列表页按地址去重后传给
    `ComposePage`。不读系统通讯录（要 `READ_CONTACTS` 全量读）、不额外打接口。
  - 提示卡走 `Overlay` + `LayerLink`：排进 `Column` 会把下面几行往下顶，每敲一个字表单跳一次。
    按最后一段输入匹配名称 / 地址，已填过的人不再提示，最多 4 条；滚动时主动收掉（浮层不受
    视口裁剪，否则会飘到顶栏上）。
  - 填入后是灰色胶囊（`ComposeContact` 按地址大小写不敏感判等，三栏间唯一）。

- 点击收件人编辑框选项
  样式：参照 UI文件夹下的 ”收件人-收件人编辑.jpg“ 1:1实现
  交互：点击输入框联系人选项 弹出操作菜单：删除｜编辑｜移至抄送｜移至密送
  - `showMenu` 贴着被点的那一枚胶囊弹。「移至」只列另外两栏（在抄送里的人不会看到「移至抄送」）；
    「编辑」= 删胶囊 + 把地址放回输入框并聚焦。

- 发件人编辑框点击输入框后
  样式：参照 UI文件夹下的 ”发件人-点击发件人输入框.jpg“ 1:1实现
  交互：点击收件人输入框，展开抄送和密送输入框，样式参照“发件人-点击发件人输入框.jpg”；如果没有输入 抄送人&密送人，则隐藏输入框，参照：“发件人-无抄送&密送.jpg” 1:1 实现
  - 展开条件 = 有收件栏聚焦 || 抄送密送非空；都空且失焦才折叠回「抄送/密送, 发件人：<账号>」。
    已填过的抄送**绝不折叠** —— 那等于把收件人藏起来。
  - `+` 只在「聚焦或该栏为空」时出现 —— 五张设计稿同时满足这一条（折叠成一行文字时稿里没有它）。
  - **发件人行做成只读**：设计稿那个 ▾ 没接账号切换。本页从某账号的邮件列表进来、`sendMail`
    也用这个账号鉴权，换发件人等于换 token，还可能撞上目标账号没授权 `Mail.Send`。
  - 抄送 / 密送随发信一起下发（`sendMail` 加 `cc` / `bcc` → Graph `ccRecipients` /
    `bccRecipients`，空列表不下发），三栏地址都过一遍格式校验。

- 页面需要可以上滑
  在输入内容时，输入区域太小
  - 表单 / 附件 / 正文改成同一条 `CustomScrollView`：正文走
    `SliverFillRemaining(hasScrollBody: false)` —— 内容装得下时正好占满剩余高度（点下方空白
    也能落焦点、一格滚不动），长了就把页面撑长。键盘弹起后上滑即可把收件人那几行滚走。

- **两个 element 复用的坑**（都表现成「焦点被抢」，都靠 key 治，已写进 CLAUDE.md §5.6）
  - 输入框必须在三种形态里都待在**同一个 `Wrap` 的最后一格**且带 key，折叠态用 `Offstage`
    藏而不是移出树。让它在「直接子级」与「Wrap 内」之间搬家，`EditableText` 会被重建 ——
    **点一下输入框，键盘刚起来又立刻收回**。
  - `_FieldRow` 每行都要带 key。抄送 / 密送整行会增删，行数一变、无 key 的兄弟按下标重新
    配对：主题那行的 `EditableText` 被重建、焦点被踢掉，焦点作用域又把焦点还给上一个聚焦过
    的节点 —— 表现为**在主题里打字，字进了收件人**（先被 `mail_list_page_test` 的发信用例抓到）。

- 待真机确认：点收件人输入框键盘不再一闪即收；提示卡位置与圆角观感；胶囊菜单贴合度；
  折叠 / 展开切换时表单不跳；键盘弹起后上滑手感。

# 两处修改：搜索框等高 + 详情页 loading 居中 [OK]

- 所有的搜索框高度保持一致
  - 首页与邮件列表**各写了一份**搜索框：首页被外层 `SizedBox` 夹到 34、邮件列表按内容
    自然撑到 35。差一线不明显，但**系统字号放大后差距会跟着变大**（一个被夹住不动、
    一个跟着长）。
  - 抽成 `lib/widgets/search_field.dart` 的 `AppSearchField`，高度写死
    `kHeight = 36`（≥ 自然高度，不再压扁）；首页吸顶头部的搜索条改成
    `AppSearchField.kHeight + 8`（42 → 44），左右 20 边距仍由调用方给。
  - 新增回归用例：首页量一次、进邮件列表再量一次，两处必须相等且等于 `kHeight`。

- 邮件详情页内容加载的 loading 动画 icon 没有置于内容区域垂直中间
  - 两处都在偏上：① 懒取全文的转圈**排在元信息后面**（紧贴收件人那几行，看着像挂在
    页面上三分之一）；② 正文 WebView 的加载遮罩把转圈 `Center` 在**盒子**里，而盒子
    量到高度前只有 160、量到后又可能比屏幕高好几倍 —— 长邮件时转圈直接跑到屏幕外。
  - ① 改成 `Stack(fit: StackFit.expand)` + `Positioned.fill` + `Center` 浮在内容区
    （返回栏与底部操作栏之间）正中，`_BodyLoading` 只留预览文字。
    `StackFit.expand` 是必需的 —— 默认 loose 会让滚动视图按内容缩，短邮件时下半截
    点不着、滑不动。
  - ② 遮罩期间盒子**至少占满内容区可见高度**（详情页新传的 `viewportHeight`）；转圈的落点
    每次载入 post-frame 量一次「盒子顶端在滚动视口里的位置」（`_coverAnchor`），据此对齐
    **内容区垂直正中** —— 与 ① 那个转圈同一个落点，两个阶段之间不会上下跳。
    `_kInitialHeight = 160` 一并删掉（顺带少一次「短占位 → 实测高度」的版式跳动）。
  - 已有的 `find.byType(SingleChildScrollView).last` 上滑用例不受影响（结构没换成 sliver）。
  - **测试里不能对着转圈 `pumpAndSettle`**（永不收敛）：新用例只 `pump()` 走完路由转场。
- 待真机确认：暗色下点进邮件，转圈在正中、不再先冒一下再跳；长邮件（量高后盒子远高于
  一屏）加载期间转圈仍在屏幕内；两页搜索框在系统字号放大时仍等高。

## 追加：转圈会上下抖动一次

抖的是**正文遮罩里那个转圈**（懒取阶段那个浮在内容区正中的没动过）。三处，都在
`mail_html_view.dart`：

- **落点还没量到就先画了一帧**：`_coverAnchor` 为 null 时退回按 `viewportHeight` 居中
  （偏下约「元信息高度的一半」），量到后再挪上去。Android 上平台视图首帧要几十毫秒，
  这一下不是一帧的事，看着就是明显抖一下。→ **量到才画转圈**，没量到只画底色。
- **只量了一次**：附件条是正文之后才拉回来的，元信息一变高，盒子顶端就往下走，转圈跟着
  盒子一起挪。→ 遮罩期**每帧末补量**（量到同一个值不 `setState`，不成环）。
- **淡出期间收盒子**：原来一开始淡出就把盒子交回实测高度，实测比一屏矮的短邮件会把还
  看得见的转圈往上带一段。→ 改成**淡完**才交回（`_coverGone`，`_cover` 的状态监听）。

顺带：中线还在盒子上方（元信息比半屏还高）时，落点退回「盒子可见段」的正中，别摆到屏幕外。

# 三处修改：详情页闪烁 + 列表 loading 偏下 + 搜索框清除按钮 [OK]

- 邮件详情：loading 不抖了，但闪烁一下
  - 病根是**两段等待各画一个转圈**：懒取全文那个由页面画，正文渲染那个由 `MailHtmlView`
    在遮罩里画。上一轮为治抖动加了「落点没量到就先不画转圈」，于是交接处有一两帧谁都
    没画 —— Android 上平台视图首帧还要几十毫秒，那就是**闪一下**。
  - 改成**整段等待只有一个转圈**：页面那个从进页面亮到正文可见，位置一次都不变；
    正文遮罩退化成纯底色，起落用新的 `onCoverChanged(bool)` 通知页面，两者按同一时长
    （`MailHtmlView.kRevealDuration = 240ms`）一起淡出。
  - 顺带删掉一整套「量落点」的机器：`_coverAnchor` / `_measureCoverAnchor` /
    `_viewportCenterInBox` / 每帧末补量 / `spinnerTop` 夹逼 —— 转圈不在盒子里了，
    这些就都不需要，抖动与错位在结构上不再可能。
  - **通知必须排到帧末**：`_load()` 的调用点之一是 `didChangeDependencies`（换主题重载），
    此刻页面正在构建，直接回调就是「setState() called during build」。
  - 测试环境没有平台视图 → 那条降级分支要立刻回报 `false`，否则页面转圈永远挂着，
    既有的 `pumpAndSettle` 用例全超时。

- 邮件列表：loading 位置偏下
  - 原来在**搜索框下面那块列表区**里居中：上面压着标题栏 + 搜索框近 120，下面没有对称的
    底栏来抵消 —— 实测落在 452，而屏幕正中是 390。
  - 改成整页级浮层（`SafeArea` 下的 `Stack` + `Positioned.fill` + `Center`），列表区那支
    只留 `SizedBox.shrink()`。`SafeArea(bottom: false)` 是为了让列表滚到屏幕最底，故浮层
    自己减掉 `viewPadding.bottom`，否则中线被系统手势条压低半个 inset。
  - 新增用例（`listMessagesHangs` 假替身停在首屏加载态）：转圈中心 == 页面中心。

- 搜索框：输入后右侧加清除按钮
  - `AppSearchField` 改成有状态、自持 `TextEditingController`；非空才把叉入树，
    点一下清空**并回调 `onChanged('')`**（`TextField.onChanged` 不为程序性修改触发，
    不手动回调页面的过滤条件就不复位）。
  - 叉只有 15，靠 `HitTestBehavior.opaque` + 内边距把可点区域撑到 33×33；
    `suffixIconConstraints` 必须放开最小尺寸 —— `IconButton` 那套 48×48 会把胶囊顶破
    `kHeight = 36`（用例里连高度一起断言了）。
  - 新增 l10n `searchClear`（清除 / Clear）只用于 `Semantics` 标签 —— 纯图标按钮读屏没得读。

- 待真机确认：① 暗色下点进 HTML 邮件，从头到尾只有一个转圈、不闪不跳、淡出即见正文；
  ② 换主题重载时转圈重新亮起再淡出；③ 慢网 / 大图邮件最多 1.5s 露出；④ 邮件列表首屏
  转圈在屏幕正中（有手势条的机型也不偏）；⑤ 两页搜索框的叉位置与点击手感一致。

# 邮件详情：顶 / 底栏的收起切回接回来 [OK]

上一轮为治「全屏状态来回跳动」把收放**整个取消**了（当时是你拍的板），现在按你的要求接回来。
这次能接回来的前提是**架构已经不一样了**：正文那会儿是独立滚动的 WebView、收放由它的滚动
回报驱动；现在是整页一条 Flutter 滚动条、正文按量到的高度占位。

- 做法：滚动视图 `Positioned.fill` **恒定**铺满内容区，返回栏 / 底部操作栏是浮在它上面的两条
  浮层（`Positioned` + `ClipRect` + `SlideTransition`），靠滚动视图**恒定**的上下内边距让位。
  **收放只是绘制期平移** —— 不改视口尺寸、不改那份内边距。
  - 病根一直是「收放改了正文区尺寸或滚动几何 → 正文是 WebView，一改尺寸就重排 → 重排又吐
    新偏移去驱动收放」的正反馈。收放不碰布局，这条回路就不存在：用例里断言了
    `maxScrollExtent` 收起前后**一格不差**。
  - 驱动改回**页面这条 Flutter 滚动条**（`ScrollController` + `userScrollDirection`），不是
    WebView 的滚动回报。回调里只驱动 `AnimationController`、**绝不 `setState`**（重建会把
    WebView 一起重排）。
  - 阈值：贴顶 60px 内恒展开、上滑越过 80px 才收、可滚距离 < 200px 不收；**下滑立刻切回**
    （`appRoute` 没有 iOS 侧滑返回，返回箭头藏着就退不出这一页）。
  - `ClipRect` 必须有：`SlideTransition` 是绘制期变换，浮层的布局矩形始终在 `Stack` 内 →
    `RenderStack` 认为没溢出 → 不装裁剪层 → 挪出去的部分照画。这就是当年真机上「顶栏没隐藏、
    赖在状态栏里」那个坑，测试的 view padding 为 0 时抓不到 —— 新用例用 `FakeViewPadding`
    模拟刘海机型，按各自的裁剪窗断言「浮层已整体移出窗外」。裁剪顺带管住命中测试。
  - 内边距用两条浮层的实测高度（`GlobalKey` + 帧后量一次，值没变不 `setState`）；写死会因
    平台字体 / 文字缩放差几像素，内容正好露在浮层边缘。
- 用例：原来那条「返回栏与底部操作栏不收起」换成两条 —— 长邮件上滑收起 + 滚动几何不变 +
  下滑切回原位；短邮件（一屏装得下）上滑也不收。
- 已知取舍：正文放大后单指归 WebView 内部滚动，那会儿外层滚动条不动 → 两条栏不收放。
- 待真机确认：① 上滑收起 / 下滑切回跟不跟手；② 收放期间正文**不跳位**（这是历史上反复栽的
  那一条）；③ 顶栏在刘海机型上是真的藏干净了；④ 双指缩放正文时不受收放干扰。

# 新建邮件：收件人 / 抄送 / 密送的光标紧跟胶囊后面 [OK]

原来落一个收件人之后，光标跑到了下一行（「收件人在这一行、光标在下一行」）。原因不是间距
设错，而是**排版容器选错了**：`Wrap` 给每个孩子的 maxWidth 都是整行宽，而 `TextField` 会
铺满拿到的宽度 —— 只要前面有一枚胶囊就挤不下，输入框（连光标）被整体推到下一行。

- 改用自写的 `_ChipsInput`（`MultiChildRenderObjectWidget` + `RenderBox`）：胶囊按行流下去，
  **最后一格（输入框）拿当前行的余量**；余量不足 `_kMinInputWidth = 72` 才另起一行、占满整行。
  间距沿用原来的 8 / 行距 6，行内垂直居中。
- 顺带的好处：输入框铺满行尾余量，**点胶囊右边那片空白也能落焦点**（同系统邮件客户端）。
- 折叠态（未聚焦且已填）输入框仍留在树上保住 `EditableText` 的 element（否则点一下键盘
  刚起来又收回），只是零尺寸摆在原点、不参与排版。
- 提示卡的 `LayerLink` 从输入框挪到**整块内容区**：输入框现在只占行尾余量，贴着它弹会得到
  一张又窄又从行中间起头的卡片。
- 用例：新增「收件人光标紧跟胶囊：行尾余量够就同一行，不够才另起一行」—— 断言输入框左边缘
  紧跟胶囊右边缘（隔一个间距）、同一行居中、右边缘一直铺到「+」按钮；再填一个人后余量不足，
  输入框整行独占。测试字体每字都是 fontSize 见方（比真机宽近一倍），故该用例把屏幕放宽到
  480 逻辑像素，让余量与真机观感一致。
- 代价：地址长过行尾余量时在框内横向滚动（余量至少 72，够看清正在敲的几个字符）。
- 待真机确认：① 落一个收件人后光标确实贴在它后面；② 点胶囊右边空白能落焦点；③ 敲长地址时
  框内横向滚动可接受；④ 提示卡宽度与位置仍与设计稿一致。

# 新建邮件：正文排版改成选区级（选中哪段变哪段）[OK]

原来选中一段文字再设字号 / 加粗 / 斜体 / 下划线 / 颜色，**整篇文字一起变** —— 因为这五项
都只是 `TextField.style` 上的整篇属性，压根没有「哪几个字」的概念。用户要的是只改所选那段。

- 新增 `lib/data/compose_rich_text.dart`（纯函数 + 值类型，可单测）：`ComposeTextFormat`
  = 一个字符的完整格式；`composeTextRuns` 合并成段；`composeTextEdit` / `composeSpliceFormats`
  让格式表跟着编辑挪；`composeBodyHtml` 序列化成 Graph 正文。
- 正文控制器 `_RichBodyController extends TextEditingController`：**每个字记一份格式**，
  覆写 `buildTextSpan` 逐段渲染。刻意不引富文本引擎（flutter_quill 那类）—— 工具栏与整页
  布局都是按设计稿 1:1 写的，换引擎等于连编辑器一起换掉；`TextField` 的光标 / 选择菜单 /
  输入法 / 撤销全部照旧。
- 为什么「每个字都记完整格式」而不是「只记与基准不同的项」：基础样式要跟着光标处的字号走
  （光标高度、空正文的提示文字都看它），谁靠继承取值，改一次字号就会串到旧文字上 —— 那正是
  原来的病根。颜色是例外（null = 跟随主题，靠继承），故基础样式的颜色只能是主题正文色。
- `strutStyle: StrutStyle.disabled` 是必需的：`EditableText` 默认按基础字号
  `forceStrutHeight: true`，会把每行行高焊死 —— 混排大字号那几段会被压扁 / 叠在一起。
- 没有选区时，工具栏设的是「接下来要打的字」（Word / Gmail 同款），光标挪去别处即作废；
  **首次落焦点不算挪**，否则「先选好颜色再点进正文」一进去就把颜色丢了。
- 排版栏改为显示**光标处**的格式（光标停在粗体里 B 就亮着），缓存在 State 里、派生值没变
  就不 `setState`，免得每敲一个字整页重建。
- 对齐 / 列表 / 缩进仍是段落级：对齐走 `textAlign`（整篇），列表与缩进靠行首插字符近似。
- 发信：没排版过且左对齐 → 纯文本直发；否则外层 `<div>` 带 pre-wrap / 基准字号 / 对齐，
  **只给非默认格式的段各包一个 `<span>`**。
- 用例 +10（143 → 153）：`test/compose_rich_text_test.dart` 7 条单测（改动定位、格式表挪动、
  越界夹住、合并成段、HTML 三种形态）；widget 3 条 —— 选中一段改字号 / 加粗后屏幕上只有那段变、
  只有那段带 `<span>` 发出去、没选区时只有接着打的字变粗。
- 已知取舍：格式不进撤销栈（`UndoHistoryController` 只管文字），撤销回来的那段取邻居的格式。
- 待真机确认：① 选中一段设格式，别处确实不变；② 混排大字号时行距正常、不叠字；③ 中文输入法
  拼字期间下划线与格式都对；④ 选好颜色再点进正文打字，颜色还在；⑤ 收信方（Outlook / Gmail）
  看到的样式与编辑时一致。

# 新建邮件：抄送 / 密送改由「发件人行」展开 [OK]

原来聚焦收件人（点收件人输入框）就顺带把抄送 / 密送 / 发件人三行撑开；用户期望**点发件人那一
行**才展开，点收件人只为编辑收件人。

- `_ccBccOpen` 由 `有收件栏聚焦 || 抄送密送非空` 改为 `_ccBccExpanded || 抄送密送非空`：
  新增布尔态 `_ccBccExpanded`，点折叠行「抄送/密送, 发件人：<账号>」时置 true。
- 折叠行整行包一层 `GestureDetector(behavior: opaque, onTap: 展开)`；`Key('compose-row-ccfrom')`
  从 `_FieldRow` 挪到 `GestureDetector` 上 —— 它才是 Column 的直接子级，反配对靠它这一层认。
- **展开后没填内容、焦点离开收件栏 → 自动收回**（用户二轮反馈）。点发件人行展开不带任何焦点
  事件，收回只能靠「焦点后来挪去别处」察觉：监听 `FocusManager.instance`（`ChangeNotifier`，
  primary focus 一变化就通知），帧末判定「无收件栏聚焦 && 抄送密送（胶囊 + 未提交文字）全空」
  才 `_ccBccExpanded = false`。判据放帧末：cc / bcc 的未提交文字刚在 `_onFocusChanged` 里被
  `_commitPending` 落成胶囊，帧末才拿得到最新状态。已填过的抄送 / 密送仍绝不折叠。
- 用例：改写「点收件人才展开」那条为「点发件人行才展开、聚焦收件人不展开、**空着失焦自动收回**」；
  「填了抄送不折叠」与「抄送密送随发信下发」两条改成先点发件人行展开再输入 cc / bcc（否则 cc /
  bcc 输入框仍 Offstage 找不到）。
- 待真机确认：① 点发件人行确实展开三行、点收件人不再展开；② 展开后没填东西、点正文/主题就收回；
  ③ 往 cc / bcc 填了人后失焦不收回、随发信正常下发。

# 新建邮件：胶囊菜单对齐首页菜单样式 + 表单字重/字号/胶囊边距收细 [OK]

两处视觉调整（用户反馈）。

- **收件人胶囊菜单样式 = 首页右上角「导入 / 设置」菜单**：把首页私有的 `_MenuRow` /
  `_MenuDivider` 提成共享组件 `lib/widgets/app_menu.dart`（`AppMenuRow` / `AppMenuDivider`，
  带 key 参数），两页共用同一份、防样式漂移。胶囊菜单改为：底色 `palette.background` +
  `surfaceTintColor` 同底 + `elevation: 20` + `shadowColor: 0x4B000000` 四周发散阴影 +
  圆角 12；选项改「图标 + 文案」（删除 `AppIcons.delete`、编辑 `AppIcons.mailEdit`、
  移至 `AppIcons.forward`），高 52 / 左右 20 边距 / 15 号字 / 字距 1.5；分隔线用
  `AppMenuDivider`（`palette.divider`、缩进 20）。原为圆角 16 / 居中 16 号字 / 高 48 /
  `PopupMenuDivider`。
- **表单收细**：`_FieldRow` 左侧标签 16 → 14（对齐次要文本尺度）；收件人 / 抄送 / 密送 /
  发件人 / 重要性 / 主题的值与输入（`valueStyle`）16 / w600 → 15 / w500，折叠成一行时的
  主色文字同步 15 / w500；收件人胶囊内边距 `14/7` → `10/5`（文字保持 16 —— 用户只说胶囊
  边距；改小文字会让「两枚胶囊 + 输入框」在测试方形字形下不再换行、要连带改几何测试）。
- 测试：几何用例（光标紧跟胶囊）在胶囊收细后仍成立 —— 标签变小腾出的宽度 + 胶囊变窄，
  两枚胶囊 + 输入框仍 58 < 72 最小宽、照旧换行；`_MenuRow` 提走后 home 菜单测试只按文字 /
  图标定位，不受影响。
- 待真机确认：① 胶囊菜单视觉与首页菜单一致（底色 / 阴影 / 圆角 / 行距）；② 表单整体更轻、
  收件人胶囊更紧凑不贴字。

# 新建邮件：浮层样式统一 + 表单行去边框 [OK]

又一轮视觉调整（用户反馈）。

- **输入提示卡 / 重要性下拉 → 胶囊菜单同一套样式**：收件人 / 抄送 / 密送输入时弹出的
  `_SuggestionCard`（背景 `palette.card` + `elevation: 8` + 圆角 20 + 主行 17 号）与
  重要性下拉 `PopupMenuButton`（背景 `palette.card`）统一为胶囊菜单那套：底色
  `palette.background` + `surfaceTintColor` 同底 + `elevation: 20` + `shadowColor:
0x4B000000` + 圆角 12；提示卡主行字号 17 → 15（仍靠 w600 区分主次，次行本就是 15）。
  三个浮层（胶囊菜单 / 提示卡 / 重要性）观感统一。
- **表单行去边框**：`_FieldRow` 移除底部 1px 分隔线（`Border(bottom: divider)`），各行间
  留白分隔。附件条 `_buildAttachments` 与正文之间那条线**保留**（它分隔附件区与正文，不是
  表单项边框；用户要再去掉说一声）。
- 验证：`flutter analyze` 零问题；`flutter test` 全量 153 例通过。测试不断言浮层样式 /
  行边框，无需改动。
- 待真机确认：① 提示卡 / 重要性下拉与胶囊菜单背景阴影圆角一致；② 表单去线后整页观感。

# 新建邮件：重要性下拉选中态去方形深底 [OK]

用户反馈「选中选项后是方形的底色」——根因在 SDK：[popup_menu.dart](file) 的
`_PopupMenu.build` 对 `initialValue` 代表的那一项整项包 `ColoredBox(color: Theme.highlightColor)`
（默认近 40% 黑），菜单 Material 默认 `clipBehavior: Clip.none` 不裁剪 → 选中项一块方形深底，
圆角失效。我们恰好在重要性下拉传了 `initialValue: _importance`，每次打开都能看到。

- 修法：**去掉 `initialValue`**（不再触发 SDK 的方形 ColoredBox），选中态在 `itemBuilder`
  里自己画——选中的值包 `Container(decoration: primary@10% + 圆角 8, padding: 12/6)`，淡色圆角块。
- 影响面：只有重要性下拉有选中态残留（胶囊菜单 / 提示卡点选即关闭、无 `initialValue`），
  故只改这一处。按压反馈（InkWell 方形高亮）用户没提，未动。
- 验证：`flutter analyze` 零问题；`flutter test` 153 例全绿（无测试触碰重要性下拉）。
- 待真机确认：选中项为淡蓝圆角块、不再方形深底。

# 新建邮件：菜单项点按去方形按压底色 [OK]

用户反馈「手指点击的时候依旧还有一个底色」——`PopupMenuItem` 内部 InkWell 的按压高亮
取 `Theme.of(context).highlightColor`（默认近 40% 黑），SDK 不暴露参数、菜单又在独立
route 里包不住 Theme 覆盖，点按选项就浮一块方形深底。

- 修法：自绘 `_FlatMenuEntry<T>`（`PopupMenuEntry` 子类）——复刻 `PopupMenuItem` 布局
  （`ConstrainedBox(minHeight) + Padding + Align(centerStart)`），迭代两轮：第一轮
  InkWell 反馈色全透明；用户实测重要性下拉「点击仍有底色」，第二轮干脆用
  `GestureDetector`（彻底脱离 Material Ink 机制，`focusColor` / `hoverColor` 等其它
  Material 态也碰不到），`onTap` 里 `Navigator.pop` 返回 value。
  胶囊菜单（`_chipMenuItem`，高 52 / 边距 20）与重要性下拉（高 48 / 边距 20）都换用它。
  代价：失去 PopupMenuItem 的键盘焦点导航（移动端菜单短、可接受，已记录）。
- 提示卡 `_SuggestionCard` 的 InkWell 被外层 Material（圆角 12 + `Clip.antiAlias`）裁剪成
  圆角淡色反馈，非方形，用户未提，未动。
- 验证：`flutter analyze` 零问题；`flutter test` 153 例全绿。
- 待真机确认：点按胶囊菜单 / 重要性下拉选项不再浮方形底色，选中态仍是淡蓝圆角块。

# 新建邮件：收件人输入一个联系人后「后方还有空间光标却换行」+ 重要性下拉点按底色 [OK]

用户两项反馈一起处理：

**① 收件人行尾余量阈值 72 → 40**（`_ChipsInput` 的 `_kMinInputWidth`）：真机上地址稍长
（行尾还剩 40~70px）就被 `free < 72` 判「余量不足」而把输入框整行推到下一行 —— 用户眼里
「还有空间光标却换行了」。降到 40（≈5 字符，仍够看清正在敲的字）。配套测试
「收件人光标紧跟胶囊」从 1440 物理宽改 1260（÷dpr3 = 逻辑 420）：1440 下两枚胶囊后余量
仍上百，阈值 40 不再触发换行、断言失准；1260 正好落在「单枚同排、两枚换行」的区间
（测试字体是 fontSize 见方，screenWidth 是物理像素 ÷3 才是逻辑宽，踩过坑）。

- 代价：行尾余量 40~72px 时输入框更窄、框内横向滚动稍多，换来「有空间就紧跟胶囊」。

**② 重要性下拉点按底色 → `_FlatMenuEntry` 改用 `GestureDetector`**：上一轮 `_FlatMenuEntry`
用「InkWell + 三反馈色透明」，用户实测重要性下拉点按仍浮底色 —— InkWell 的反馈还受
`focusColor` / `hoverColor` 等其它 Material 态影响，且必须落在 Material Ink 层上。
干脆弃用 InkWell，`GestureDetector` 只管手势、什么都不画，任何点按 / 水波 / 悬停都不可能
再出现。胶囊菜单同用此组件，一并生效。

- 验证：`flutter analyze` 零问题；`flutter test` 153 例全绿。
- 待真机确认：① 输完一个联系人，只要行尾还有约 5 个字符以上的余量，光标就跟在胶囊后面
  同一行；② 重要性下拉点按任意选项全程无底色。

# 详情页：滑动「时不时」只有 HTML 滚、整体页面不移动 [OK]

用户反馈「有时进详情页滑邮件内容，只有 html 往上滑动，整体页面没有上移」「时不时会失灵」。

- 根因：单指归谁听的是页内脚本那句 `内容高度 > visualViewport.height + 2px` 的布尔量。
  但图片陆续加载、宿主盒子高度还没跟上的窗口里（以及测量舍入差），它会**偶尔误判为
  「能内滚」** → 单指被 WebView 抢走，外层滚动视图收不到手势 → 整页滑不动，
  表现为「只有 html 滚、页面不滚」，且时不时。
- 修法：页内脚本**只报高度**（删掉 visualViewport 监听与 canScroll 计算）；
  「能否内滚」改由宿主 `MailHtmlView._applyMetrics` 按**「量到高度 > 纹理上限」**判
  （`_canScrollInside = scaled > cap + 1`）—— 普通邮件恒不内滚、单指恒归外层整页滚；
  只有内容真被纹理上限截断（超长邮件，下半截靠 WebView 内滚读全）才认领单指。
  - 取舍：放大后的单指平移让给双指（识别器对第二根手指无条件认领）；被截断的
    超长邮件仍是「正文内滚、元信息不动」，但那是硬约束下的必要分支。
- 改动：`lib/data/mail_html_document.dart`（\_heightProbe 只报高度）、
  `lib/widgets/mail_html_view.dart`（\_applyMetrics 宿主判定）、
  `test/mail_html_document_test.dart`（断言页内不再含 visualViewport）、CLAUDE.MD §5.5。
- 验证：`flutter analyze` 零问题；`flutter test` 153 例全绿。
- 待真机确认：① 进详情页、正文图片加载过程中去滑，页面也应整页一起滚（不再时不时
  卡住）；② 超长邮件（内容超约 2700 逻辑 px）仍能读到被夹住的下半截。

# 邮件详情页面 【NO】

邮件详情页面全屏效果 修改为 包括状态栏 和 底部 安全区域。现在滑动内容时 状态栏和底部安全区域还是有边框遮挡
