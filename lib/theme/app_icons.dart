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

  /// 发送（线性纸飞机）。
  static const IconData send = IconData(0xe7aa, fontFamily: _font);

  /// 下拉选择（小三角）—— 跟在文字后面的那种。
  static const IconData dropDown = IconData(0xe602, fontFamily: _font);

  /// 展开 / 收起（`v`）—— 收起态直接用，展开态转 180°。
  static const IconData chevronDown = IconData(0xe622, fontFamily: _font);

  /// 撤销。
  static const IconData undo = IconData(0xeaf0, fontFamily: _font);

  /// 已标星（实心星）。
  static const IconData starFilled = IconData(0xe601, fontFamily: _font);

  /// 未标星（空心星）。
  static const IconData starEmpty = IconData(0xe605, fontFamily: _font);

  /// 未读（信封 + 圆点）—— 抽屉「未读」与列表左滑「标未读」共用。
  static const IconData unread = IconData(0xe62d, fontFamily: _font);

  /// 收件箱。
  static const IconData inbox = IconData(0xe7b0, fontFamily: _font);

  /// 已标星文件夹（信封 + 星）。
  static const IconData starredFolder = IconData(0xe73e, fontFamily: _font);

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

  /// 文字颜色（A + 色条）。
  static const IconData textColor = IconData(0xe61e, fontFamily: _font);

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

  // ---- iconfont 备用：字库里有、当前没用上 ----

  /// 字体样式（`Aa`）。
  static const IconData fontStyle = IconData(0xe640, fontFamily: _font);

  /// 发送（实心纸飞机）—— [send] 的实心版。
  static const IconData sendSolid = IconData(0xe6be, fontFamily: _font);

  /// 撤销（另一款）—— [undo] 的备选造型。
  static const IconData undoAlt = IconData(0xe600, fontFamily: _font);

  // ---- 待补：iconfont 项目里还没挑，暂用 Material ----

  static const IconData check = Icons.check;
  static const IconData checkCircle = Icons.check_circle_outline;
  static const IconData cloudOff = Icons.cloud_off_outlined;
  static const IconData delete = Icons.delete_outline;

  /// 归档。
  static const IconData archive = Icons.drive_file_move_outlined;

  /// 导入账号（上传）。
  static const IconData importFile = Icons.file_upload_outlined;

  /// 健康检测。
  static const IconData healthCheck = Icons.health_and_safety_outlined;

  /// 提权（钥匙）。
  static const IconData elevate = Icons.vpn_key_outlined;

  static const IconData settings = Icons.settings_outlined;
  static const IconData selectAll = Icons.select_all;
  static const IconData deselect = Icons.deselect;
  static const IconData reply = Icons.reply_outlined;
  static const IconData replyAll = Icons.reply_all_outlined;
  static const IconData forward = Icons.forward_outlined;

  /// 非图片附件。
  static const IconData file = Icons.insert_drive_file_outlined;

  /// 重做 —— 字库里两款撤销造型都朝左，没有镜像版，暂留 Material。
  static const IconData redo = Icons.redo;
}
