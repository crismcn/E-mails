import 'dart:io';

import 'package:flutter_contacts/flutter_contacts.dart';

/// 「从系统通讯录挑一位联系人的邮箱」这一步的抽象 —— 走平台通道，
/// 测试里注入假实现即可验证挑完之后的逻辑（多地址选择、拼进收件人框）。
typedef ContactEmailPicker = Future<ContactPick> Function();

/// 取联系人的结果 —— 刻意区分三种，因为界面反馈完全不同：
/// 取到了就填进输入框、用户取消就什么都不做、没权限要给提示。
enum ContactPickStatus { picked, cancelled, denied }

class ContactPick {
  const ContactPick(this.status, {this.emails = const <String>[]});

  const ContactPick.cancelled() : this(ContactPickStatus.cancelled);
  const ContactPick.denied() : this(ContactPickStatus.denied);

  final ContactPickStatus status;

  /// 选中联系人名下的邮箱地址（已去空、保序、去重）。可能为空 —— 该联系人没留邮箱。
  final List<String> emails;
}

/// 调系统通讯录选人，取回其邮箱地址。
///
/// 权限：**iOS 不需要**（系统选择器在应用外进程弹出）；**Android 需要
/// `READ_CONTACTS`** —— 想拿到邮箱就得带 `properties`，插件在没权限时会抛
/// `PlatformException`，所以只在 Android 上先要权限。
Future<ContactPick> pickSystemContactEmails() async {
  if (Platform.isAndroid &&
      !await FlutterContacts.permissions.has(PermissionType.read)) {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    final granted =
        status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
    if (!granted) return const ContactPick.denied();
  }

  final contact = await FlutterContacts.native.showPicker(
    properties: const {ContactProperty.email},
  );
  if (contact == null) return const ContactPick.cancelled();

  final seen = <String>{};
  final emails = <String>[];
  for (final email in contact.emails) {
    final address = email.address.trim();
    if (address.isEmpty || !seen.add(address.toLowerCase())) continue;
    emails.add(address);
  }
  return ContactPick(ContactPickStatus.picked, emails: emails);
}
