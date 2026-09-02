import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// 正文基准字号 —— 新打的字默认用它，发信时写在最外层 `div` 上。
const double kComposeBaseFontSize = 16;

/// 字符级的**开关型**格式；字号与颜色不是开关，另走 [ComposeTextFormat.withFontSize]
/// 与 [ComposeTextFormat.withColor]。
enum ComposeTextAttribute { bold, italic, underline }

/// 正文里**一个字符**的格式。
///
/// 刻意给每个字都记一份**完整**格式，而不是「只记与基准不同的那几项」：正文
/// `TextField` 的基础样式要跟着光标处的字号走（光标高度、提示文字都看它），若某些字
/// 靠继承基础样式取值，用户一改字号就会串到本该保持原样的旧文字上 —— 那正是
/// 「选中一段改字号，整篇都变了」的老毛病。
@immutable
class ComposeTextFormat {
  const ComposeTextFormat({
    this.fontSize = kComposeBaseFontSize,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color,
  });

  /// 没做过任何排版的字 —— 发信时不为它包 `<span>`。
  static const ComposeTextFormat plain = ComposeTextFormat();

  final double fontSize;
  final bool bold;
  final bool italic;
  final bool underline;

  /// null = 跟随主题正文色 —— 存 null 而不是当时的主题色，切主题不会留下旧色。
  final Color? color;

  bool get isPlain => this == plain;

  bool attribute(ComposeTextAttribute attribute) => switch (attribute) {
    ComposeTextAttribute.bold => bold,
    ComposeTextAttribute.italic => italic,
    ComposeTextAttribute.underline => underline,
  };
  ComposeTextFormat withAttribute(ComposeTextAttribute attribute, bool on) =>
      ComposeTextFormat(
        fontSize: fontSize,
        bold: attribute == ComposeTextAttribute.bold ? on : bold,
        italic: attribute == ComposeTextAttribute.italic ? on : italic,
        underline: attribute == ComposeTextAttribute.underline ? on : underline,
        color: color,
      );

  ComposeTextFormat withFontSize(double size) => ComposeTextFormat(
    fontSize: size,
    bold: bold,
    italic: italic,
    underline: underline,
    color: color,
  );

  /// 颜色可以被设回 null（跟随主题），故不能用 `copyWith` 那套「null 表示不改」。
  ComposeTextFormat withColor(Color? value) => ComposeTextFormat(
    fontSize: fontSize,
    bold: bold,
    italic: italic,
    underline: underline,
    color: value,
  );

  /// 叠在正文基础样式上的覆盖 —— 除颜色外每项都给死值、不留 null 去继承基础样式
  /// （见类注释）。颜色是例外：null 正是「跟随主题」，靠继承基础样式实现。
  TextStyle get styleOverride => TextStyle(
    fontSize: fontSize,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    decoration: underline ? TextDecoration.underline : TextDecoration.none,
    color: color,
    decorationColor: color,
  );

  /// 内联 CSS —— 发信时写进 `<span style="…">`。基准字号由外层 `div` 声明，故与它
  /// 相同时不再重复写一遍。
  List<String> get cssDeclarations => <String>[
    if (fontSize != kComposeBaseFontSize) 'font-size:${fontSize.toInt()}px',
    if (bold) 'font-weight:700',
    if (italic) 'font-style:italic',
    if (underline) 'text-decoration:underline',
    if (color != null)
      'color:#${(color!.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
  ];

  /// 值相等 —— 相邻同格式的字要能合并成一段（[composeTextRuns]），
  /// 排版栏也靠它判断「光标处这一套」有没有变。
  @override
  bool operator ==(Object other) =>
      other is ComposeTextFormat &&
      other.fontSize == fontSize &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.color == color;

  @override
  int get hashCode => Object.hash(fontSize, bold, italic, underline, color);

  @override
  String toString() => 'ComposeTextFormat(${cssDeclarations.join(';')})';
}

/// 一段连续同格式的正文 —— [start] 含、[end] 不含，按 UTF-16 码元下标（与 `String`
/// 的下标一致，可直接 `substring`）。
@immutable
class ComposeTextRun {
  const ComposeTextRun({
    required this.start,
    required this.end,
    required this.format,
  });

  final int start;
  final int end;
  final ComposeTextFormat format;

  int get length => end - start;
}

/// 把字符级格式表合并成尽量少的段 —— 渲染成 `TextSpan`、序列化成 `<span>` 都按段走。
///
/// [formats] 必须与 [text] 等长（每个 UTF-16 码元一格）；短了按 [ComposeTextFormat.plain]
/// 兜底，免得任何一处漏同步就整片正文抛异常。
List<ComposeTextRun> composeTextRuns(
  String text,
  List<ComposeTextFormat> formats,
) {
  assert(
    formats.length == text.length,
    '字符级格式表必须与正文等长：${formats.length} vs ${text.length}',
  );
  if (text.isEmpty) return const <ComposeTextRun>[];
  ComposeTextFormat formatAt(int i) =>
      i < formats.length ? formats[i] : ComposeTextFormat.plain;

  final runs = <ComposeTextRun>[];
  var start = 0;
  var current = formatAt(0);
  for (var i = 1; i <= text.length; i++) {
    // i == text.length 时 next 为 null，与任何格式都不等 —— 正好收尾。
    final next = i == text.length ? null : formatAt(i);
    if (next == current) continue;
    runs.add(ComposeTextRun(start: start, end: i, format: current));
    if (next == null) break;
    start = i;
    current = next;
  }
  return runs;
}

/// 前后两版正文之间的最小改动 —— 公共前缀 / 公共后缀之外那一段。
///
/// 编辑框只把「改完之后的整段文字」交给我们（输入法拼字、粘贴、撤销都一样），
/// 而字符级格式表得知道**在哪儿删了几个、插了几个**才能跟着挪。按前后缀求交集足够：
/// 真实编辑总是连续的一段，即便偶尔算大一点（比如把 `abab` 改成 `ab`），也只是让那
/// 一段重新取一次格式，不会错位。
({int start, int removed, int inserted}) composeTextEdit(
  String before,
  String after,
) {
  final shorter = math.min(before.length, after.length);
  var prefix = 0;
  while (prefix < shorter &&
      before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < shorter - prefix &&
      before.codeUnitAt(before.length - 1 - suffix) ==
          after.codeUnitAt(after.length - 1 - suffix)) {
    suffix++;
  }
  return (
    start: prefix,
    removed: before.length - prefix - suffix,
    inserted: after.length - prefix - suffix,
  );
}

/// 按一次改动挪动字符级格式表 —— 新插入的字统一取 [insertFormat]。
List<ComposeTextFormat> composeSpliceFormats({
  required List<ComposeTextFormat> formats,
  required int start,
  required int removed,
  required int inserted,
  required ComposeTextFormat insertFormat,
}) {
  final int from = math.min<int>(math.max<int>(start, 0), formats.length);
  final int to = math.min<int>(
    from + math.max<int>(removed, 0),
    formats.length,
  );
  return <ComposeTextFormat>[
    ...formats.sublist(0, from),
    for (var i = 0; i < inserted; i++) insertFormat,
    ...formats.sublist(to),
  ];
}

/// 正文 + 字符级格式 + 整篇对齐 → Graph 可发送的正文（内容 + 是否 HTML）。
///
/// 一个字都没排版过、且对齐是默认左对齐 → 纯文本直发（收信方不会看到一堆标签）；
/// 否则包一层 `<div>`：`white-space:pre-wrap` 保留换行 / 空格 / 缩进，基准字号与
/// 对齐写在它上面，**每段非默认格式的字各自包一个 `<span>`** —— 这样只有被排版过的
/// 那几段带样式，其余文字保持原样。
///
/// 文字一律转义，免得正文里的 `<` / `&` 破坏结构。
({String content, bool isHtml}) composeBodyHtml({
  required String text,
  required List<ComposeTextFormat> formats,
  TextAlign align = TextAlign.left,
}) {
  final runs = composeTextRuns(text, formats);
  final styled = runs.any((run) => !run.format.isPlain);
  if (!styled && align == TextAlign.left) {
    return (content: text, isHtml: false);
  }

  final buffer = StringBuffer()
    ..write('<div style="white-space:pre-wrap')
    ..write(';font-size:${kComposeBaseFontSize.toInt()}px')
    ..write(align == TextAlign.left ? '' : ';text-align:${align.name}')
    ..write('">');
  for (final run in runs) {
    final piece = escapeComposeHtml(text.substring(run.start, run.end));
    if (run.format.isPlain) {
      buffer.write(piece);
      continue;
    }
    buffer
      ..write('<span style="')
      ..write(run.format.cssDeclarations.join(';'))
      ..write('">')
      ..write(piece)
      ..write('</span>');
  }
  buffer.write('</div>');
  return (content: buffer.toString(), isHtml: true);
}

/// 正文里的 HTML 特殊字符转义 —— 文字只出现在标签之间、不进属性值，故这三个就够。
String escapeComposeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
