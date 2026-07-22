import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../utils/translations.dart';
import '../utils/ringtone_utils.dart';
import '../services/reminder_service.dart';
import 'graveyard_screen.dart';
import 'about_screen.dart';
import 'ringtone_picker_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic> _permissions = {};
  bool _permissionsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    final perms = await ReminderService().checkPermissions();
    if (mounted) {
      setState(() {
        _permissions = perms;
        _permissionsLoaded = true;
      });
    }
  }
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        surfaceTintColor: bgColor,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
          color: const Color(0xFF007AFF),
        ),
        title: Text(
          Translations.tr('settings'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 20),
            children: [
              // ── Language section ──
              _buildSectionHeader(Translations.tr('language')),
              _buildSettingCard(
                context,
                children: [
                  _buildPickerTile(
                    context,
                    icon: Icons.language_outlined,
                    title: Translations.tr('language'),
                    value: Translations.availableLocales.firstWhere(
                      (l) => l['code'] == settings.locale,
                    )['name']!,
                    onTap: () => _showLanguagePicker(context, settings),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Theme section ──
              _buildSectionHeader(Translations.tr('theme')),
              _buildSettingCard(
                context,
                children: [
                  _buildSegmentedThemeTile(context, settings),
                ],
              ),
              const SizedBox(height: 20),

              // ── Vibration section ──
              _buildSectionHeader(Translations.tr('vibration')),
              _buildSettingCard(
                context,
                children: [
                  _buildVibrationTile(context, settings),
                ],
              ),
              const SizedBox(height: 20),

              // ── Default Ringtone section ──
              _buildSectionHeader(Translations.tr('ringtone_setting')),
              _buildSettingCard(
                context,
                children: [
                  _buildPickerTile(
                    context,
                    icon: Icons.music_note_outlined,
                    title: Translations.tr('ringtone_setting'),
                    value: RingtoneUtils.getDisplayName(settings.defaultRingtone),
                    onTap: () async {
                      final result = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RingtonePickerScreen(
                            currentRingtone: settings.defaultRingtone,
                            isDefaultSettings: true,
                          ),
                        ),
                      );
                      if (result != null) {
                        settings.setDefaultRingtone(result);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSectionHeader(''),
              _buildSettingCard(
                context,
                children: [
                  _buildNavTile(
                    context,
                    icon: Icons.delete_outline,
                    title: Translations.tr('graveyard'),
                    subtitle: Translations.tr('graveyard_desc'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GraveyardScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Notification & Test section ──
              _buildSectionHeader(Translations.tr('test_reminder')),
              _buildSettingCard(
                context,
                children: [
                  _buildNavTile(
                    context,
                    icon: Icons.notification_add_outlined,
                    title: Translations.tr('test_reminder'),
                    subtitle: Translations.tr('test_reminder_desc'),
                    onTap: () => _testReminder(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Permission & Power Settings section ──
              _buildSectionHeader(Translations.tr('permission_settings')),
              _buildSettingCard(
                context,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      Translations.tr('permission_guide_main_title'),
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : const Color(0xFF3C3C43),
                      ),
                    ),
                  ),
                  _buildDivider(),
                  // 精确闹钟权限
                  _buildPermissionStatusTile(
                    context: context,
                    icon: Icons.timer_outlined,
                    title: Translations.tr('exact_alarm_permission_title'),
                    statusKey: 'exactAlarm',
                    statusGranted: Translations.tr('permission_exact_alarm_status_granted'),
                    statusDenied: Translations.tr('permission_exact_alarm_status_denied'),
                    onAction: () => ReminderService().openExactAlarmSettings(),
                  ),
                  _buildDivider(),
                  // 悬浮窗权限
                  _buildPermissionStatusTile(
                    context: context,
                    icon: Icons.crop_square_outlined,
                    title: Translations.tr('overlay_permission_title'),
                    statusKey: 'systemAlertWindow',
                    statusGranted: Translations.tr('permission_overlay_status_granted'),
                    statusDenied: Translations.tr('permission_overlay_status_denied'),
                    onAction: () => ReminderService().openSystemAlertWindowSettings(),
                  ),
                  _buildDivider(),
                  // 自启动管理
                  _buildActionTile(
                    context: context,
                    icon: Icons.power_settings_new,
                    title: Translations.tr('permission_auto_launch'),
                    subtitle: Translations.tr('permission_auto_launch_desc'),
                    actionLabel: Translations.tr('permission_auto_launch_action'),
                    onAction: () => ReminderService().openHuaweiAutoLaunch(),
                  ),
                  _buildDivider(),
                  // 电池优化
                  _buildActionTile(
                    context: context,
                    icon: Icons.battery_std,
                    title: Translations.tr('permission_battery'),
                    subtitle: Translations.tr('permission_battery_desc'),
                    actionLabel: Translations.tr('permission_battery_action'),
                    onAction: () => ReminderService().openBatteryOptimizationSettings(),
                  ),
                  _buildDivider(),
                  // 华为纯净模式提示
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Text(
                      Translations.tr('permission_guide_huawei_hint'),
                      style: const TextStyle(fontSize: 12, color: Color(0xFFFF9500)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── About section ──
              _buildSectionHeader(''),
              _buildSettingCard(
                context,
                children: [
                  _buildNavTile(
                    context,
                    icon: Icons.info_outline,
                    title: Translations.tr('check_update'),
                    onTap: () => _checkUpdate(context),
                  ),
                  _buildDivider(),
                  _buildNavTile(
                    context,
                    icon: Icons.article_outlined,
                    title: Translations.tr('about'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AboutScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Vibration intensity tile ──
  Widget _buildVibrationTile(BuildContext context, SettingsProvider settings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.vibration, color: const Color(0xFF007AFF), size: 22),
              const SizedBox(width: 12),
              Text(
                Translations.tr('vibration'),
                style: TextStyle(fontSize: 16, color: textColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // None
              Expanded(
                child: _vibrationChip(
                  label: Translations.tr('vibration_none'),
                  icon: Icons.vibration,
                  intensity: -1,
                  currentIntensity: settings.vibrationIntensity,
                  onTap: () {
                    settings.setVibrationIntensity(-1);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Light
              Expanded(
                child: _vibrationChip(
                  label: Translations.tr('vibration_light'),
                  icon: Icons.vibration,
                  intensity: 0,
                  currentIntensity: settings.vibrationIntensity,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    settings.setVibrationIntensity(0);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Medium
              Expanded(
                child: _vibrationChip(
                  label: Translations.tr('vibration_medium'),
                  icon: Icons.vibration,
                  intensity: 1,
                  currentIntensity: settings.vibrationIntensity,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    settings.setVibrationIntensity(1);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Strong
              Expanded(
                child: _vibrationChip(
                  label: Translations.tr('vibration_strong'),
                  icon: Icons.vibration,
                  intensity: 2,
                  currentIntensity: settings.vibrationIntensity,
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    settings.setVibrationIntensity(2);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vibrationChip({
    required String label,
    required IconData icon,
    required int intensity,
    required int currentIntensity,
    required VoidCallback onTap,
  }) {
    final isSelected = intensity == currentIntensity;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF007AFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF007AFF) : const Color(0xFFC7C7CC),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : const Color(0xFF8E8E93),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared building blocks ──

  Widget _buildSectionHeader(String title) {
    if (title.isEmpty) return const SizedBox(height: 0);
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8E8E93),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingCard(BuildContext context, {required List<Widget> children}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.transparent : Colors.black.withAlpha(8),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildPickerTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: const Color(0xFF007AFF), size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : const Color(0xFF1C1C1E),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF8E8E93),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Color(0xFFC7C7CC), size: 20),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildNavTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: const Color(0xFF007AFF), size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: isDark ? Colors.white : const Color(0xFF1C1C1E),
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8E8E93),
              ),
            )
          : null,
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFC7C7CC), size: 20),
      onTap: onTap,
    );
  }

  Widget _buildSegmentedThemeTile(BuildContext context, SettingsProvider settings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined, color: const Color(0xFF007AFF), size: 22),
              const SizedBox(width: 12),
              Text(
                Translations.tr('theme'),
                style: TextStyle(fontSize: 16, color: textColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildThemeChip(
                label: Translations.tr('light'),
                icon: Icons.light_mode_outlined,
                isSelected: settings.themeMode == ThemeMode.light,
                onTap: () => settings.setThemeMode(ThemeMode.light),
              ),
              const SizedBox(width: 8),
              _buildThemeChip(
                label: Translations.tr('dark'),
                icon: Icons.dark_mode_outlined,
                isSelected: settings.themeMode == ThemeMode.dark,
                onTap: () => settings.setThemeMode(ThemeMode.dark),
              ),
              const SizedBox(width: 8),
              _buildThemeChip(
                label: Translations.tr('system'),
                icon: Icons.settings_outlined,
                isSelected: settings.themeMode == ThemeMode.system,
                onTap: () => settings.setThemeMode(ThemeMode.system),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF007AFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFF007AFF) : const Color(0xFFC7C7CC),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : const Color(0xFF8E8E93),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF8E8E93),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 权限状态卡片：显示权限名称、当前状态（已允许/未允许）、操作按钮。
  Widget _buildPermissionStatusTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String statusKey,
    required String statusGranted,
    required String statusDenied,
    required VoidCallback onAction,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final loaded = _permissionsLoaded;
    final granted = _permissions[statusKey] == true;
    final statusText = !loaded ? '...' : (granted ? statusGranted : statusDenied);
    final statusColor = !loaded
        ? const Color(0xFF8E8E93)
        : (granted ? const Color(0xFF34C759) : const Color(0xFFFF3B30));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF007AFF), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 16, color: textColor),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(fontSize: 13, color: statusColor, fontWeight: FontWeight.w500),
          ),
          if (!loaded)
            const SizedBox(width: 8)
          else if (!granted) ...[
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: ElevatedButton(
                onPressed: () {
                  onAction();
                  // 返回后刷新状态
                  Future.delayed(const Duration(seconds: 2), _loadPermissions);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(Translations.tr('go_to_settings')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 动作引导卡片：带描述文字和操作按钮。
  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: const Color(0xFF007AFF), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, color: textColor),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      indent: 52,
      color: Color(0xFFE5E5EA),
    );
  }

  void _showLanguagePicker(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Translations.tr('language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: Translations.availableLocales.map((locale) {
            return RadioListTile<String>(
              title: Text(locale['name']!),
              value: locale['code']!,
              groupValue: settings.locale,
              activeColor: const Color(0xFF007AFF),
              onChanged: (value) {
                if (value != null) {
                  settings.setLocale(value);
                  Navigator.pop(ctx);
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translations.tr('cancel')),
          ),
        ],
      ),
    );
  }

  void _testReminder(BuildContext context) async {
    try {
      await ReminderService().testNotification(delayMs: 10000);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Translations.tr('test_reminder_sent')),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('测试提醒失败: $e')),
        );
      }
    }
  }

  void _checkUpdate(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Translations.tr('check_update')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFF34C759), size: 48),
            const SizedBox(height: 16),
            Text(Translations.tr('already_latest')),
            const SizedBox(height: 8),
            Text(
              '${Translations.tr('current_version')}: v1.0.0',
              style: const TextStyle(color: Color(0xFF8E8E93)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translations.tr('confirm')),
          ),
        ],
      ),
    );
  }
}

