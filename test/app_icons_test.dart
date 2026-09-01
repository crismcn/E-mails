import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 守住「`app_icons.dart` 里的码点都还在字库里」这条。
///
/// 为什么需要它：iconfont 每次重新下载都可能**重排码点**，老码点会凭空消失。
/// debug / profile 不裁字库，跑起来照常（缺的字形只是画不出来），只有 release 的
/// `--tree-shake-icons` 会逐个去字库找，缺一个就整个打包失败，而且报的是十进制码点
/// （`Codepoint 59198 not found in font`），得换算成 hex 才能定位。把这条前移到
/// `flutter test`，覆盖字库后立刻就知道要改哪几个常量。
///
/// **它管不到的那一半**：码点还在、但那个位置换了别的图形（或两个图形互换了位置）。
/// 那种情况编译、打包、测试全都过，只是界面上图标不对。所以覆盖字库后仍要把字形渲染
/// 出来看一眼，做法见 CLAUDE.md §4.2。
void main() {
  test('app_icons.dart 引用的 iconfont 码点都在 iconfont.json 里', () {
    final glyphs =
        (jsonDecode(File('assets/fonts/iconfont.json').readAsStringSync())
                as Map<String, dynamic>)['glyphs']
            as List<dynamic>;

    // font_class → 码点。名字仅用于报错时给线索，不用来决定映射（名字不可信，
    // 见 AppIcons.selectAll 的注释）。
    final available = <int, String>{};
    for (final glyph in glyphs.cast<Map<String, dynamic>>()) {
      available[int.parse(glyph['unicode'] as String, radix: 16)] =
          glyph['font_class'] as String;
    }

    final source = File('lib/theme/app_icons.dart').readAsStringSync();
    final refs = RegExp(
      r'(\w+)\s*=\s*IconData\(0x([0-9a-fA-F]+),\s*fontFamily:\s*_font\)',
    ).allMatches(source);

    expect(refs, isNotEmpty, reason: '没解析到任何 iconfont 常量，正则该跟着改');

    final missing = <String>[];
    for (final ref in refs) {
      final codePoint = int.parse(ref.group(2)!, radix: 16);
      if (!available.containsKey(codePoint)) {
        missing.add(
          '${ref.group(1)} = 0x${codePoint.toRadixString(16).toUpperCase()}'
          '（十进制 $codePoint）',
        );
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          '这些常量的码点已不在字库里，release 打包会失败：\n  ${missing.join('\n  ')}\n'
          '按 font_class 在 assets/fonts/iconfont.json 里找到新码点改过去。',
    );
  });
}
