import 'package:flutter/material.dart';

/// 全站图标的唯一出口 —— 页面只认语义名，来源（iconfont / Material）在这里决定。
///
/// iconfont 字库在 `assets/fonts/iconfont.ttf`，码点抄自同目录 `iconfont.json`
/// （阿里图标项目「Outlooks」，id `5228387`）。要加图标就走这条路：
/// 在 iconfont 项目里挑好 → 重新下载覆盖 `iconfont.ttf` + `iconfont.json`
/// → 按 `font_class` 在本文件加常量 → 把用到的地方指过来。
///
/// 还没挑到的图标暂时回退 Material（见下方「待补」区），补齐时只改这一处，
/// 页面代码不用动。
///
/// 两条硬约束：
/// - 常量必须是 `const IconData`，release 的 `--tree-shake-icons` 才能把字库
///   裁到只剩用到的字形（写成方法返回就裁不掉了）。
/// - `uses-material-design: true` 不能关：Material 组件内部自己画的图标
///   （DropdownButton 箭头、TextField 清除等）仍取 MaterialIcons 字体。
class AppIcons {
  const AppIcons._();

  /// 与 pubspec `fonts:` 里声明的家族名一致。
  static const String _font = 'IconFont';

  // ---- iconfont ----

  /// 返回（细尖角 `<`）—— 各页顶栏通用。
  static const IconData back = IconData(0xe617, fontFamily: _font);

  /// 搜索（放大镜）。
  static const IconData search = IconData(0xe791, fontFamily: _font);

  /// 新增 / 新建（加号）。
  static const IconData add = IconData(0xe6a7, fontFamily: _font);

  /// 更多（竖三点）。
  static const IconData more = IconData(0xe62f, fontFamily: _font);

  /// 附件（回形针）。
  static const IconData attach = IconData(0xe776, fontFamily: _font);

  /// 图片。
  static const IconData image = IconData(0xe654, fontFamily: _font);

  /// 发送（线性纸飞机）—— `send-line`。
  static const IconData send = IconData(0xe6dd, fontFamily: _font);

  /// 下拉选择（小三角）—— 跟在文字后面的那种。
  static const IconData dropDown = IconData(0xe602, fontFamily: _font);

  /// 展开 / 收起（`v`）—— 收起态直接用，展开态转 180°。
  static const IconData chevronDown = IconData(0xe622, fontFamily: _font);

  /// 撤销 —— `revoke`。
  static const IconData undo = IconData(0xe606, fontFamily: _font);

  /// 已标星（实心星）。
  static const IconData starFilled = IconData(0xe601, fontFamily: _font);

  /// 未标星（空心星）。
  static const IconData starEmpty = IconData(0xe605, fontFamily: _font);

  /// 未读（信封 + 圆点）—— 抽屉「未读」与列表左滑「标未读」共用。
  static const IconData unread = IconData(0xe62d, fontFamily: _font);

  /// 收件箱。
  static const IconData inbox = IconData(0xe7b0, fontFamily: _font);

  /// 已标星文件夹（信封 + 星）—— `starred-email`。
  /// 另一款造型见 [starredMailAlt]。
  static const IconData starredFolder = IconData(0xe821, fontFamily: _font);

  /// 已发送文件夹（信封 + 箭头）。
  static const IconData sentFolder = IconData(0xe62e, fontFamily: _font);

  /// 关闭（叉）。
  static const IconData close = IconData(0xe608, fontFamily: _font);

  // 新建邮件的排版工具栏 —— 字形已核对过（对齐三态按短横的贴边方向确认）。

  /// 加粗（B）。
  static const IconData bold = IconData(0xe6fe, fontFamily: _font);

  /// 斜体（I）。
  static const IconData italic = IconData(0xe7a6, fontFamily: _font);

  /// 下划线（U）。
  static const IconData underline = IconData(0xe61d, fontFamily: _font);

  /// 文字颜色（A + 色条）—— `icon-font-color`。
  static const IconData textColor = IconData(0xe61a, fontFamily: _font);

  /// 无序列表。
  static const IconData listBulleted = IconData(0xe6ec, fontFamily: _font);

  /// 有序列表。
  static const IconData listNumbered = IconData(0xe60e, fontFamily: _font);

  /// 增加缩进（箭头向右）。
  static const IconData indentIncrease = IconData(0xe6f0, fontFamily: _font);

  /// 减少缩进（箭头向左）。
  static const IconData indentDecrease = IconData(0xe6f1, fontFamily: _font);

  /// 左对齐。
  static const IconData alignLeft = IconData(0xe6e7, fontFamily: _font);

  /// 居中对齐。
  static const IconData alignCenter = IconData(0xe6e8, fontFamily: _font);

  /// 右对齐。
  static const IconData alignRight = IconData(0xe6e6, fontFamily: _font);

  // 列表 / 账号操作 —— 字形已逐个看图核对过（名字字段不可信，只认字形）。

  /// 回复（信封 + 单条左箭头）—— `reply-email`。
  static const IconData reply = IconData(0xe82e, fontFamily: _font);

  /// 全部回复（信封 + 双左箭头）—— `reply-all-email`。
  /// 与 [reply] 并排放，靠「单箭头 / 双箭头」区分。
  static const IconData replyAll = IconData(0xe82f, fontFamily: _font);

  /// 转发（信封 + 右箭头）—— `forward-email`。
  static const IconData forward = IconData(0xe612, fontFamily: _font);

  /// 重做 —— 与 [undo] 成镜像的一对。
  static const IconData redo = IconData(0xe679, fontFamily: _font);

  /// 删除（线性垃圾桶）。实心版见 [deleteFill]。
  static const IconData delete = IconData(0xe60a, fontFamily: _font);

  /// 归档 / 移动到（文件夹 + 右箭头）。
  static const IconData archive = IconData(0xe692, fontFamily: _font);

  /// 导入账号（向下箭头入线）。
  static const IconData importFile = IconData(0xe609, fontFamily: _font);

  /// 已选中（实心圆 + 勾）—— 导入页选好文件后的状态。
  static const IconData checkCircle = IconData(0xe64c, fontFamily: _font);

  /// 健康检测（盾 + 脉搏）。
  static const IconData healthCheck = IconData(0xe6e9, fontFamily: _font);

  /// 提权（盾 + 钥匙）。
  static const IconData elevate = IconData(0xe61f, fontFamily: _font);

  /// 设置。
  static const IconData settings = IconData(0xe69d, fontFamily: _font);

  /// 全选（勾 + 实心圆点，「都选上了」）。
  ///
  /// 这两个的造型**必须看图确认**，不能照 `iconfont.json` 的名字接：不同批次下载里
  /// 名字变过好几轮（`checked-all` / `check-all` / 与 `deselect-all` 互换），而两个
  /// 码点上的字形一直没变（0xe6c3 实心 = 全选，0xe6c2 空心 = 取消全选）。
  static const IconData selectAll = IconData(0xe6c3, fontFamily: _font);

  /// 取消全选（勾 + 空心圆点，「都没选」）。见 [selectAll] 的说明。
  static const IconData deselect = IconData(0xe6c2, fontFamily: _font);

  // ---- iconfont 备用：字库里有、当前没用上 ----

  /// 字体样式（`Aa`）。
  static const IconData fontStyle = IconData(0xe640, fontFamily: _font);

  /// 发送（实心纸飞机）—— [send] 的实心版。
  static const IconData sendSolid = IconData(0xe6be, fontFamily: _font);

  /// 导出（箭头出托盘）—— 导入的对偶操作，功能还没做。
  static const IconData export = IconData(0xe60b, fontFamily: _font);

  /// 删除（实心垃圾桶）—— [delete] 的实心版。
  static const IconData deleteFill = IconData(0xe664, fontFamily: _font);

  /// 未选中（空心圆）—— 配 [checkCircle] 做勾选列表。
  static const IconData uncheckCircle = IconData(0xe621, fontFamily: _font);

  /// 多选（虚线框 + 勾）。
  static const IconData multiSelect = IconData(0xe8b3, fontFamily: _font);

  /// 已读邮件（信封 + 勾）。
  static const IconData readMail = IconData(0xe6cc, fontFamily: _font);

  /// 已读邮件（另一款，方形信封）—— [readMail] 的备选造型。
  static const IconData readMailAlt = IconData(0xe658, fontFamily: _font);

  /// 未读邮件（信封 + 圆点，另一款）—— [unread] 的备选造型。
  static const IconData unreadMailAlt = IconData(0xe8b2, fontFamily: _font);

  /// 未读邮件（实心信封 + 圆点）。
  static const IconData unreadMailFill = IconData(0xe64a, fontFamily: _font);

  /// 已展开的邮件（拆开的信封）—— `open-email`。
  static const IconData mailOpen = IconData(0xe64f, fontFamily: _font);

  /// 邮件（普通信封）。
  static const IconData mail = IconData(0xe6ce, fontFamily: _font);

  /// 写邮件（信封 + 铅笔）—— `edit-email`。
  static const IconData mailEdit = IconData(0xe611, fontFamily: _font);

  /// 邮件搜索（信封 + 放大镜）—— `search-email`。
  static const IconData mailSearch = IconData(0xe613, fontFamily: _font);

  /// 已标星邮件（另一款，信箱 + 星）—— [starredFolder] 的备选造型。
  static const IconData starredMailAlt = IconData(0xe63a, fontFamily: _font);

  // ---- 待补：字库里还没有对应造型，仍用 Material ----

  /// 勾（裸的对勾）—— 字库里只有「圆圈 + 勾」，没有裸勾。
  static const IconData check = Icons.check;

  /// 断网 / 加载失败。
  static const IconData cloudOff = Icons.cloud_off_outlined;

  /// 非图片附件（通用文件）。
  static const IconData file = Icons.insert_drive_file_outlined;
}
