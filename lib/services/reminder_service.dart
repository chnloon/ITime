import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/schedule_item.dart';

/// Flutter 侧提醒调度服务。
///
/// 通过 MethodChannel 与 Kotlin 原生侧通信：
///   - 设置/取消 AlarmManager 闹钟
///   - 接收来自原生通知的用户操作回调
///   - 检查/请求运行时权限
class ReminderService {
  ReminderService._();

  static final ReminderService _instance = ReminderService._();
  factory ReminderService() => _instance;

  static const MethodChannel _channel = MethodChannel(
    'com.chnloon.oigo/reminder',
  );

  /// "详情"事件流 — HomeScreen 监听此流实现滚动到目标卡片
  static final _showDetailController = StreamController<int>.broadcast();
  static Stream<int> get showDetailStream => _showDetailController.stream;

  bool _initialized = false;

  /// 初始化：注册 MethodChannel 回调，并重建所有提醒闹钟。
  Future<void> initialize() async {
    if (_initialized) return;

    _channel.setMethodCallHandler(_handleMethodCall);
    _initialized = true;
    debugPrint('ReminderService initialized');
  }

  /// 处理来自原生侧的方法调用
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'showDetail':
        final eventId = call.arguments as int;
        debugPrint('ReminderService: showDetail for event $eventId');
        _showDetailController.add(eventId);
        break;
      default:
        debugPrint('ReminderService: unknown method ${call.method}');
    }
  }

  /// 注册一个提醒闹钟（原生 AlarmManager）。
  Future<void> registerReminder(ScheduleItem item) async {
    if (item.id == null) return;
    if (item.reminderMinutes <= 0) return;

    final alarmTime = item.eventTime.subtract(
      Duration(minutes: item.reminderMinutes),
    );

    if (alarmTime.isBefore(DateTime.now())) return;

    try {
      await _channel.invokeMethod('setReminder', {
        'eventId': item.id,
        'title': item.title,
        'location': item.location,
        'latitude': item.latitude,
        'longitude': item.longitude,
        'eventTime': item.eventTime.toIso8601String(),
        'alarmTimeMillis': alarmTime.millisecondsSinceEpoch,
        'ringtoneUri': item.ringtoneUri ?? '',
      });
      debugPrint('Reminder registered: "${item.title}" at $alarmTime');
    } catch (e) {
      debugPrint('Failed to register reminder: $e');
    }
  }

  /// 取消一个提醒闹钟。
  Future<void> cancelReminder(int eventId) async {
    try {
      await _channel.invokeMethod('cancelReminder', eventId);
      debugPrint('Reminder cancelled for event $eventId');
    } catch (e) {
      debugPrint('Failed to cancel reminder: $e');
    }
  }

  /// 应用启动时批量重建所有提醒闹钟。
  Future<void> rescheduleAll(List<ScheduleItem> items) async {
    for (final item in items) {
      await registerReminder(item);
    }
    debugPrint('Rescheduled ${items.length} reminders');
  }

  // ─── 权限管理 ───────────────────────────────────────────────

  /// 检查所有运行时权限状态。
  /// 返回 { postNotifications: bool, exactAlarm: bool, systemAlertWindow: bool }。
  Future<Map<String, dynamic>> checkPermissions() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'checkPermissions',
      );
      if (result == null) return _defaultPerms();
      return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint('checkPermissions failed: $e');
      return _defaultPerms();
    }
  }

  Map<String, dynamic> _defaultPerms() => {
        'postNotifications': false,
        'exactAlarm': false,
        'systemAlertWindow': false,
        'fullScreenIntent': true,
      };

  /// 请求 POST_NOTIFICATIONS 权限（Android 13+）。
  Future<bool> requestPostNotificationsPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestPostNotificationsPermission',
      );
      return result ?? false;
    } catch (e) {
      debugPrint('requestPostNotificationsPermission failed: $e');
      return false;
    }
  }

  /// 请求 SCHEDULE_EXACT_ALARM 权限（Android 12+）。
  Future<bool> requestExactAlarmPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestExactAlarmPermission',
      );
      return result ?? false;
    } catch (e) {
      debugPrint('requestExactAlarmPermission failed: $e');
      return false;
    }
  }

  /// 打开 SCHEDULE_EXACT_ALARM 系统设置页面（Android 12+）。
  Future<void> openExactAlarmSettings() async {
    try {
      await _channel.invokeMethod('openExactAlarmSettings');
    } catch (e) {
      debugPrint('openExactAlarmSettings failed: $e');
    }
  }

  /// 检查悬浮窗权限（SYSTEM_ALERT_WINDOW）。
  /// 国产 ROM（MIUI/EMUI/ColorOS）需要此权限才能弹出通知横幅。
  Future<bool> checkSystemAlertWindow() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'checkSystemAlertWindow',
      );
      return result ?? false;
    } catch (e) {
      debugPrint('checkSystemAlertWindow failed: $e');
      return false;
    }
  }

  /// 打开悬浮窗权限设置页面。
  Future<void> openSystemAlertWindowSettings() async {
    try {
      await _channel.invokeMethod('openSystemAlertWindowSettings');
    } catch (e) {
      debugPrint('openSystemAlertWindowSettings failed: $e');
    }
  }

  /// 打开 App 通知设置页面。
  Future<void> openAppNotificationSettings() async {
    try {
      await _channel.invokeMethod('openAppNotificationSettings');
    } catch (e) {
      debugPrint('openAppNotificationSettings failed: $e');
    }
  }

  /// 检查全屏 Intent 权限（Android 14+）。
  /// setFullScreenIntent 需要此权限才能触发横幅 Activity。
  Future<bool> checkFullScreenIntent() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'checkFullScreenIntent',
      );
      return result ?? true;
    } catch (e) {
      debugPrint('checkFullScreenIntent failed: $e');
      return true;
    }
  }

  /// 打开系统通知设置页面让用户手动启用全屏通知。
  Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (e) {
      debugPrint('openNotificationSettings failed: $e');
    }
  }

  /// 为事件调度一个真实闹钟提醒（走完整 AlarmManager 路径）。
  /// [beforeSeconds] 表示事件前多少秒触发提醒。
  Future<void> scheduleReminder({
    required int eventId,
    required String title,
    required String description,
    required String location,
    required DateTime eventTime,
    required int beforeSeconds,
    String ringtoneUri = '',
    double latitude = 0.0,
    double longitude = 0.0,
  }) async {
    final alarmTime = eventTime.subtract(Duration(seconds: beforeSeconds));
    if (alarmTime.isBefore(DateTime.now())) {
      debugPrint('scheduleReminder: 提醒时间已过，跳过');
      return;
    }
    try {
      await _channel.invokeMethod('setReminder', {
        'eventId': eventId,
        'title': title,
        'description': description,
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'eventTime': eventTime.toIso8601String(),
        'alarmTimeMillis': alarmTime.millisecondsSinceEpoch,
        'ringtoneUri': ringtoneUri,
      });
      debugPrint('提醒已调度: eventId=$eventId, alarmTime=${alarmTime.toIso8601String()}');
    } catch (e) {
      debugPrint('scheduleReminder failed: $e');
    }
  }

  /// ★ 测试提醒：调度一个真实闹钟（走完整 AlarmManager 路径）。
  /// [delayMs] 指定多少毫秒后触发，默认 10 秒。
  /// 用于验证通知系统是否正常工作。
  Future<void> testNotification({int delayMs = 10000}) async {
    try {
      await _channel.invokeMethod('testNotification', {'delayMs': delayMs});
      debugPrint('测试提醒已触发: delay=${delayMs}ms');
    } catch (e) {
      debugPrint('testNotification failed: $e');
    }
  }

  /// 检查并请求所有必需的权限。
  /// 返回 true 表示所有权限都已就绪。
  Future<bool> ensureAllPermissions() async {
    final perms = await checkPermissions();

    if (perms['postNotifications'] == false) {
      final granted = await requestPostNotificationsPermission();
      if (!granted) return false;
    }

    if (perms['exactAlarm'] == false) {
      return false; // 需要用户手动授权
    }

    return true;
  }

  /// 清理资源
  void dispose() {
    _showDetailController.close();
  }
}
