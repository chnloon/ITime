import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'providers/schedule_provider.dart';
import 'providers/settings_provider.dart';
import 'services/reminder_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize locale data for intl DateFormat
  await initializeDateFormatting('zh_CN', null);
  await initializeDateFormatting('zh_HK', null);
  await initializeDateFormatting('en', null);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ScheduleProvider()),
      ],
      child: const OiGoApp(),
    ),
  );

  // 初始化提醒服务（注册 MethodChannel 回调处理器）
  // 实际提醒闹钟重建由 ScheduleProvider.loadItems() → _rescheduleAllReminders() 完成
  await ReminderService().initialize();
}
