import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:email_manager/data/compose_rich_text.dart';

/// 逐字格式表的三件事：跟着编辑挪、合并成段、序列化成 HTML。
///
/// 「选中一段改格式，别处跟着变」的老毛病就出在这三步上，故都单测。
void main() {
  test('composeTextEdit：插入 / 删除 / 替换 / 没改都只圈出改动那一段', () {
    expect(composeTextEdit('abc', 'abXc'), (start: 2, removed: 0, inserted: 1));
    expect(composeTextEdit('abc', 'ac'), (start: 1, removed: 1, inserted: 0));
    expect(composeTextEdit('abc', 'aXYc'), (start: 1, removed: 1, inserted: 2));
    expect(composeTextEdit('abc', 'abc'), (start: 3, removed: 0, inserted: 0));
    expect(composeTextEdit('', 'ab'), (start: 0, removed: 0, inserted: 2));
  });

  test('composeSpliceFormats：删掉的字连格式一起删，插入的字取给定格式', () {
    const bold = ComposeTextFormat(bold: true);
    final formats = <ComposeTextFormat>[
      ComposeTextFormat.plain,
      bold,
      ComposeTextFormat.plain,
    ];

    // 'abc' → 'bc'：删掉第一个字，粗体那个字的格式跟着挪到下标 0。
    expect(
      composeSpliceFormats(
        formats: formats,
        start: 0,
        removed: 1,
        inserted: 0,
        insertFormat: ComposeTextFormat.plain,
      ),
      <ComposeTextFormat>[bold, ComposeTextFormat.plain],
    );

    // 'abc' → 'abXc'：在粗体后面插一个字，插入的取传进来的那份，其余不动。
    expect(
      composeSpliceFormats(
        formats: formats,
        start: 2,
        removed: 0,
        inserted: 1,
        insertFormat: bold,
      ),
      <ComposeTextFormat>[
        ComposeTextFormat.plain,
        bold,
        bold,
        ComposeTextFormat.plain,
      ],
    );
  });

  test('composeSpliceFormats：越界的下标被夹住，不抛异常', () {
    // 真机上输入法 / 撤销偶尔会给出与格式表长度不一致的改动，夹住比崩掉好。
    expect(
      composeSpliceFormats(
        formats: <ComposeTextFormat>[ComposeTextFormat.plain],
        start: 9,
        removed: 9,
        inserted: 0,
        insertFormat: ComposeTextFormat.plain,
      ),
      <ComposeTextFormat>[ComposeTextFormat.plain],
    );
  });

  test('composeTextRuns：相邻同格式合成一段，格式一变就断开', () {
    const bold = ComposeTextFormat(bold: true);
    final runs = composeTextRuns('abcd', <ComposeTextFormat>[
      ComposeTextFormat.plain,
      bold,
      bold,
      ComposeTextFormat.plain,
    ]);
    expect(runs.map((r) => (r.start, r.end)), [(0, 1), (1, 3), (3, 4)]);
    expect(runs[1].format.bold, isTrue);
    expect(composeTextRuns('', const <ComposeTextFormat>[]), isEmpty);
  });

  test('composeBodyHtml：一个字都没排版过 → 纯文本直发', () {
    final body = composeBodyHtml(
      text: 'hi',
      formats: List<ComposeTextFormat>.filled(2, ComposeTextFormat.plain),
    );
    expect(body.isHtml, isFalse);
    expect(body.content, 'hi');
  });

  test('composeBodyHtml：只给排版过的那几段包 span，其余文字原样', () {
    const red = ComposeTextFormat(
      bold: true,
      fontSize: 28,
      color: Color(0xFFFF0000),
    );
    final body = composeBodyHtml(
      text: 'a<b>c',
      formats: <ComposeTextFormat>[
        ComposeTextFormat.plain,
        red,
        red,
        red,
        ComposeTextFormat.plain,
      ],
    );
    expect(body.isHtml, isTrue);
    // 基准字号与 pre-wrap 在外层 div 上；被排版的那段带自己的字号 / 粗细 / 颜色；
    // 正文里的 `<` `>` 一律转义，免得破坏结构。
    expect(
      body.content,
      '<div style="white-space:pre-wrap;font-size:16px">a'
      '<span style="font-size:28px;font-weight:700;color:#ff0000">&lt;b&gt;</span>'
      'c</div>',
    );
  });

  test('composeBodyHtml：对齐是整篇的，写在外层 div 上（正文没排版也照样出 HTML）', () {
    final body = composeBodyHtml(
      text: 'hi',
      formats: List<ComposeTextFormat>.filled(2, ComposeTextFormat.plain),
      align: TextAlign.center,
    );
    expect(body.isHtml, isTrue);
    expect(
      body.content,
      '<div style="white-space:pre-wrap;font-size:16px;text-align:center">hi</div>',
    );
  });
}
