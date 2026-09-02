// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '邮箱管理';

  @override
  String get statTotal => '总账号';

  @override
  String get statValid => '有效账号';

  @override
  String get statError => '异常账号';

  @override
  String get filterAllGroups => '全部分组';

  @override
  String get searchHint => '搜索邮箱号';

  @override
  String get mailSearchHint => '搜索邮件';

  @override
  String get searchClear => '清除';

  @override
  String refreshLastUpdated(String time) {
    return '上次更新时间：$time';
  }

  @override
  String get mailArchived => '已归档';

  @override
  String get mailDeleted => '已删除';

  @override
  String get mailMarkedRead => '已标记为已读';

  @override
  String get mailMarkedUnread => '已标记为未读';

  @override
  String get mailFlagged => '已标星';

  @override
  String get mailUnflagged => '已取消标星';

  @override
  String mailActionFailedToast(String message) {
    return '操作失败：$message';
  }

  @override
  String get mailEmpty => '暂无邮件';

  @override
  String get mailLoadFailed => '邮件加载失败';

  @override
  String mailLoadFailedToast(String message) {
    return '加载失败：$message';
  }

  @override
  String get commonRetry => '重试';

  @override
  String get mailAccountCopied => '已复制邮箱号';

  @override
  String get folderInbox => '收件箱';

  @override
  String get folderUnread => '未读邮件';

  @override
  String get folderFlagged => '已标星';

  @override
  String get folderSent => '已发送';

  @override
  String get composeTitle => '新建邮件';

  @override
  String get composeTo => '收件人：';

  @override
  String get composeCc => '抄　送：';

  @override
  String get composeBcc => '密　送：';

  @override
  String get composeFrom => '发件人：';

  @override
  String get composeCcFrom => '抄送/密送, 发件人：';

  @override
  String get composeRecipientDelete => '删除';

  @override
  String get composeRecipientEdit => '编辑';

  @override
  String get composeRecipientMoveToTo => '移至收件人';

  @override
  String get composeRecipientMoveToCc => '移至抄送';

  @override
  String get composeRecipientMoveToBcc => '移至密送';

  @override
  String get composeRecipientOptions => '收件人操作';

  @override
  String get composeImportance => '重要性：';

  @override
  String get composeImportanceHigh => '高';

  @override
  String get composeImportanceNormal => '正常';

  @override
  String get composeImportanceLow => '低';

  @override
  String get composeSubject => '主　题：';

  @override
  String get composeBodyHint => '正文';

  @override
  String get composeSending => '发送中…';

  @override
  String get composeSent => '已发送';

  @override
  String composeSendFailed(String message) {
    return '发送失败：$message';
  }

  @override
  String get composeNoRecipient => '请先填写收件人';

  @override
  String composeInvalidRecipient(String value) {
    return '收件人邮箱格式有误：$value';
  }

  @override
  String composeAttachTooLarge(String limit) {
    return '附件总大小超过 $limit，请删掉一些再发';
  }

  @override
  String get composeAttachRemove => '移除附件';

  @override
  String composeAttachEmptyFile(String name) {
    return '「$name」读不到内容，已跳过';
  }

  @override
  String get composeContactPick => '选择联系人';

  @override
  String get composeContactPickEmail => '选择邮箱地址';

  @override
  String get composeContactNoEmail => '该联系人没有邮箱地址';

  @override
  String get composeContactDenied => '没有通讯录权限，无法选择联系人';

  @override
  String get composeAlignLeft => '左对齐';

  @override
  String get composeAlignCenter => '居中';

  @override
  String get composeAlignRight => '右对齐';

  @override
  String get composeIndentIncrease => '增加缩进';

  @override
  String get composeIndentDecrease => '减少缩进';

  @override
  String get loadMoreLoading => '加载中...';

  @override
  String get loadMoreNoMore => '没有更多邮件';

  @override
  String get menuImport => '导入';

  @override
  String get menuSettings => '设置';

  @override
  String get loadMore => '上拉加载更多';

  @override
  String get unread => '未读';

  @override
  String get mailReplyHint => '回复';

  @override
  String threadUnread(int count) {
    return '$count 封未读';
  }

  @override
  String get threadLoadHistory => '下拉加载更多历史邮件';

  @override
  String get threadLoadHistoryNoMore => '没有更多历史邮件';

  @override
  String get detailRecipient => '收件人：';

  @override
  String detailAttachmentCount(int count) {
    return '$count 个附件';
  }

  @override
  String get detailAttachmentOpen => '打开';

  @override
  String get detailAttachmentDownload => '下载';

  @override
  String detailAttachmentSaved(String name) {
    return '已保存 $name';
  }

  @override
  String get detailAttachmentOpenFallback => '手机上没有能打开它的应用，改为下载';

  @override
  String detailAttachmentFailed(String message) {
    return '附件获取失败：$message';
  }

  @override
  String get actionReply => '回复';

  @override
  String get actionReplyAll => '全部回复';

  @override
  String get actionForward => '转发';

  @override
  String get actionDelete => '删除';

  @override
  String get actionMore => '更多';

  @override
  String get linkOpenFailed => '无法打开链接';

  @override
  String get statusValid => '有效';

  @override
  String get statusTokenExpired => 'Token 过期';

  @override
  String get statusPasswordError => '密码错误';

  @override
  String get statusUnknown => '未知';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeDark => '暗黑';

  @override
  String get settingsThemeLight => '亮白';

  @override
  String get settingsLanguage => '语言';

  @override
  String get importTitle => '导入邮箱';

  @override
  String get importCsvSection => '导入 CSV 文件';

  @override
  String get importCsvHint => '点击选择 CSV 文件';

  @override
  String get importCsvOnly => '仅支持 .csv 格式';

  @override
  String importCsvPicked(String name) {
    return '已选择：$name';
  }

  @override
  String get importPasteSection => '或 粘贴数据';

  @override
  String get importPasteHint =>
      '请粘贴数据，格式如下：\n邮箱----密码----client_id----refresh_token----创建时间\n\nuser1@example.com----123456----xxxx----xxxx----2024-01-01 10:00:00\nuser2@example.com----123456----xxxx----xxxx----2024-01-01 10:00:00';

  @override
  String get importFormatSection => '格式说明';

  @override
  String get importFieldEmail => '邮箱';

  @override
  String get importFieldEmailDesc => '邮箱地址';

  @override
  String get importFieldPassword => '密码';

  @override
  String get importFieldPasswordDesc => '邮箱密码';

  @override
  String get importFieldClientId => 'client_id';

  @override
  String get importFieldClientIdDesc => '应用客户端 ID';

  @override
  String get importFieldRefreshToken => 'refresh_token';

  @override
  String get importFieldRefreshTokenDesc => '刷新令牌';

  @override
  String get importFieldCreatedAt => '创建时间';

  @override
  String get importFieldCreatedAtDesc => '如 2024-01-01 10:00:00';

  @override
  String get importConfirm => '确认导入';

  @override
  String get importEmpty => '请先粘贴数据或选择 CSV 文件';

  @override
  String get importNoValid => '未识别到有效数据，请检查格式';

  @override
  String importResultCount(int count) {
    return '成功导入 $count 个邮箱';
  }

  @override
  String importResultInvalid(int count) {
    return '，$count 行格式有误已忽略';
  }

  @override
  String selectionTitle(int count) {
    return '已选择 $count 项';
  }

  @override
  String get actionHealthCheck => '健康检测';

  @override
  String get actionElevate => '提权';

  @override
  String get actionSelectAll => '全选';

  @override
  String get accountElevateTodo => '提权功能尚未实现';

  @override
  String get accountChecking => '检查中…';

  @override
  String accountCheckSummary(int ok, int bad) {
    return '检查完成：正常 $ok，异常 $bad';
  }

  @override
  String get accountDeleteTitle => '删除邮箱';

  @override
  String accountDeleteMultiBody(int count) {
    return '删除后需重新导入才能恢复，确定删除选中的 $count 个邮箱？';
  }

  @override
  String accountDeleted(int count) {
    return '已删除 $count 个账号';
  }

  @override
  String get commonCancel => '取消';
}
