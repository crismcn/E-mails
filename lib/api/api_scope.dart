import 'package:flutter/widgets.dart';

import 'api_service.dart';

/// 将 [ApiService] 沿 Widget 树向下提供 —— App 级组合根的注入点。
///
/// 与 [SettingsScope] 同构：包在根部（`MaterialApp` 之上），页面用
/// `ApiScope.of(context)` 取到唯一的服务实例，进而做导入持久化 / 载入账号。
///
/// [ApiService] 不是 [Listenable]（其内部状态由各 store 承载），故用普通
/// [InheritedWidget] 即可；实例在 App 生命周期内不变。
class ApiScope extends InheritedWidget {
  const ApiScope({super.key, required this.service, required super.child});

  final ApiService service;

  static ApiService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ApiScope>();
    assert(scope != null, '未找到 ApiScope，请在根部包裹。');
    return scope!.service;
  }

  @override
  bool updateShouldNotify(ApiScope oldWidget) => service != oldWidget.service;
}
