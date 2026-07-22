import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/schedule_provider.dart';
import '../services/reminder_service.dart';
import '../widgets/schedule_card.dart';
import '../widgets/empty_state.dart';
import '../utils/translations.dart';
import 'add_schedule_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  StreamSubscription<int>? _detailSubscription;
  int? _highlightedEventId;
  bool _permissionWarningShown = false;
  bool _exactAlarmMissing = false;
  bool _systemAlertWindowMissing = false;
  late AnimationController _fabController;
  late Animation<double> _fabScale;

  /// 估算的卡片高度（用于滚动定位）
  static const double _cardHeight = 104.0;
  static const double _headerHeight = 120.0;

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _fabScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.easeInOut),
    );
    _detailSubscription = ReminderService.showDetailStream.listen((eventId) {
      if (!mounted) return;
      _scrollToItem(eventId);
    });
    _checkPermissions();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShownGuide = prefs.getBool('permission_guide_shown') ?? false;
    if (!hasShownGuide && mounted) {
      _showPermissionGuide();
      await prefs.setBool('permission_guide_shown', true);
    }
  }

  /// 首次启动权限引导对话框：依次引导通知 → 精确闹钟 → 悬浮窗 → ROM白名单
  void _showPermissionGuide() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PermissionGuideDialog(
        onComplete: () {
          // 引导完成后刷新权限状态
          _checkPermissions();
        },
      ),
    );
  }

  Future<void> _checkPermissions() async {
    final perms = await ReminderService().checkPermissions();
    if (!mounted) return;
    setState(() {
      _permissionWarningShown = true;
      _exactAlarmMissing = perms['exactAlarm'] == false;
      _systemAlertWindowMissing = perms['systemAlertWindow'] == false;
    });
  }

  Future<void> _requestExactAlarm() async {
    await ReminderService().requestExactAlarmPermission();
    await Future.delayed(const Duration(seconds: 1));
    final perms = await ReminderService().checkPermissions();
    if (!mounted) return;
    setState(() {
      _exactAlarmMissing = perms['exactAlarm'] == false;
    });
  }

  @override
  void dispose() {
    _detailSubscription?.cancel();
    _scrollController.dispose();
    _fabController.dispose();
    super.dispose();
  }

  /// 滚动到指定 eventId 的卡片位置，并短暂高亮
  void _scrollToItem(int eventId) {
    final provider = context.read<ScheduleProvider>();
    if (!provider.initialized || provider.items.isEmpty) return;

    final index = provider.items.indexWhere((item) => item.id == eventId);
    if (index < 0) return;

    setState(() => _highlightedEventId = eventId);

    final targetOffset = _headerHeight + index * _cardHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final clampedOffset = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedEventId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      body: Consumer<ScheduleProvider>(
        builder: (context, provider, _) {
          if (!provider.initialized) {
            return const Center(child: CircularProgressIndicator());
          }

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: CardSlideManager.closeAll,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  floating: true,
                  backgroundColor: bgColor,
                  surfaceTintColor: bgColor,
                  title: Text(
                    Translations.tr('app_name'),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: Icon(
                        Icons.settings_outlined,
                        color: const Color(0xFF007AFF),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(8),
                    child: Container(
                      height: 0.5,
                      color: isDark
                          ? const Color(0xFF38383A)
                          : const Color(0xFFC6C8C8),
                    ),
                  ),
                ),

                // ── 权限警告横幅 ──
                if (_permissionWarningShown)
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        // 精确闹钟权限
                        if (_exactAlarmMissing)
                          _buildWarningBanner(
                            icon: Icons.alarm,
                            color: const Color(0xFFFFD60A),
                            message: Translations.tr('exact_alarm_permission_desc'),
                            buttonText: Translations.tr('grant_permission'),
                            onPressed: _requestExactAlarm,
                          ),
                        // 悬浮窗权限
                        if (_systemAlertWindowMissing)
                          _buildWarningBanner(
                            icon: Icons.crop_square_outlined,
                            color: const Color(0xFFFF9500),
                            message: Translations.tr('system_alert_warning'),
                            buttonText: Translations.tr('go_to_settings'),
                            onPressed: () {
                              ReminderService().openSystemAlertWindowSettings();
                            },
                          ),
                      ],
                    ),
                  ),

                // ── 内容区域 ──
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (provider.items.isEmpty) {
                          return SizedBox(
                            height: max(
                              MediaQuery.of(context).size.height * 0.55,
                              300,
                            ),
                            child: EmptyState(
                              icon: Icons.calendar_today_outlined,
                              titleKey: 'no_events',
                              descriptionKey: 'no_events_desc',
                            ),
                          );
                        }
                        final item = provider.items[index];
                        final isHighlighted = item.id == _highlightedEventId;
                        return AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: isHighlighted ? 1.0 : 1.0,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: isHighlighted
                                  ? [
                                      BoxShadow(
                                        color:
                                            const Color(0xFF007AFF).withAlpha(60),
                                        blurRadius: 12,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: ScheduleCard(
                              key: ValueKey(item.id),
                              item: item,
                              onDelete: () {
                                provider.deleteItem(item.id!);
                              },
                              onEdit: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AddScheduleScreen(editItem: item),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                      childCount:
                          provider.items.isEmpty ? 1 : provider.items.length,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      // FAB - iOS style with gentle pulse animation
      floatingActionButton: AnimatedBuilder(
        animation: _fabScale,
        builder: (context, child) {
          return Transform.scale(
            scale: _fabScale.value,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF007AFF).withAlpha(77),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.add, color: Colors.white, size: 28),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddScheduleScreen(),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// 构建黄色的权限提醒横幅
  Widget _buildWarningBanner({
    required IconData icon,
    required Color color,
    required String message,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : const Color(0xFF3C3C43),
              ),
            ),
          ),
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(buttonText, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
//  首次启动权限引导对话框
// ═══════════════════════════════════════════════════

/// 引导用户依次授予通知、精确闹钟权限，
/// 最后指导用户将 OiGo 加入系统白名单（国产 ROM 专属）。
class _PermissionGuideDialog extends StatefulWidget {
  final VoidCallback? onComplete;

  const _PermissionGuideDialog({this.onComplete});

  @override
  State<_PermissionGuideDialog> createState() => _PermissionGuideDialogState();
}

class _PermissionGuideDialogState extends State<_PermissionGuideDialog> {
  int _currentStep = 0; // 0=通知, 1=精确闹钟, 2=悬浮窗, 3=系统白名单
  bool _notifGranted = false;
  bool _exactAlarmGranted = false;
  bool _overlayGranted = false;

  static const _stepCount = 4;

  bool get _allDone => _notifGranted && _exactAlarmGranted && _overlayGranted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            Icons.security_outlined,
            color: const Color(0xFF007AFF),
            size: 24,
          ),
          const SizedBox(width: 10),
          Text(
            Translations.tr('permission_guide_title'),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1C1C1E),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度指示器
            Row(
              children: List.generate(_stepCount, (i) {
                final isActive = i <= _currentStep;
                final isDone = _isStepDone(i);
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isDone
                          ? const Color(0xFF34C759)
                          : isActive
                              ? const Color(0xFF007AFF)
                              : (isDark
                                  ? const Color(0xFF38383A)
                                  : const Color(0xFFE5E5EA)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),

            // 当前步骤的内容
            _buildStepContent(),
          ],
        ),
      ),
      actions: [
        if (_currentStep < _stepCount - 1)
          TextButton(
            onPressed: () {
              // 跳过当前步骤到下一步
              setState(() {
                _currentStep++;
              });
            },
            child: Text(
              Translations.tr('ok_got_it'),
              style: const TextStyle(color: Color(0xFF8E8E93)),
            ),
          ),
        if (_currentStep == _stepCount - 1 || _allDone)
          TextButton(
            onPressed: () {
              widget.onComplete?.call();
              Navigator.of(context).pop();
            },
            child: Text(
              Translations.tr('confirm'),
              style: const TextStyle(color: Color(0xFF007AFF)),
            ),
          ),
      ],
    );
  }

  bool _isStepDone(int step) {
    switch (step) {
      case 0: return _notifGranted;
      case 1: return _exactAlarmGranted;
      case 2: return _overlayGranted;
      case 3: return true; // ROM 白名单步骤无需授权按钮
      default: return false;
    }
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildNotificationStep();
      case 1:
        return _buildPermissionStep(
          icon: Icons.alarm,
          color: const Color(0xFF007AFF),
          title: Translations.tr('exact_alarm_permission_title'),
          desc: Translations.tr('exact_alarm_permission_desc'),
          isGranted: _exactAlarmGranted,
          onGrant: () => _requestAndAdvance(
            ReminderService().requestExactAlarmPermission(),
            (granted) => _exactAlarmGranted = granted,
          ),
        );
      case 2:
        return _buildOverlayStep();
      case 3:
        return _buildRomWhitelistStep();
      default:
        return const SizedBox.shrink();
    }
  }

  /// 请求权限并自动前进到下一步
  Future<void> _requestAndAdvance(
    Future<bool> requestFuture,
    void Function(bool) setGranted,
  ) async {
    final granted = await requestFuture;
    if (!mounted) return;
    setState(() {
      setGranted(granted);
      if (_currentStep < _stepCount - 1) {
        _currentStep++;
      }
    });
  }

  /// 构建第 3 步：悬浮窗权限。
  /// 需要用户授予 SYSTEM_ALERT_WINDOW 权限，弹出悬浮窗横幅。
  Widget _buildOverlayStep() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFFF9500).withAlpha(26),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            _overlayGranted ? Icons.check_circle : Icons.crop_square_outlined,
            color: _overlayGranted ? const Color(0xFF34C759) : const Color(0xFFFF9500),
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          Translations.tr('overlay_permission_title'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          Translations.tr('overlay_permission_desc'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF8E8E93),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _overlayGranted
                ? null
                : () async {
                    await ReminderService().openSystemAlertWindowSettings();
                    // 等待用户返回后检查权限
                    await Future.delayed(const Duration(seconds: 2));
                    final granted = await ReminderService().checkSystemAlertWindow();
                    if (!mounted) return;
                    setState(() {
                      _overlayGranted = granted;
                      if (_currentStep < _stepCount - 1) {
                        _currentStep++;
                      }
                    });
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: _overlayGranted
                  ? const Color(0xFF34C759)
                  : const Color(0xFFFF9500),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
            ),
            child: Text(
              _overlayGranted
                  ? '✓ ${Translations.tr('confirm')}'
                  : Translations.tr('go_to_settings'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建第 4 步：国产 ROM 系统白名单引导。
  /// MIUI / EMUI / ColorOS 需要在系统设置中额外开启：
  ///   - 自启动
  ///   - 忽略电池优化
  ///   - 允许弹出通知
  Widget _buildRomWhitelistStep() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFFF9500).withAlpha(26),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.security_outlined,
            color: Color(0xFFFF9500),
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          Translations.tr('rom_whitelist_title'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          Translations.tr('rom_whitelist_desc'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF8E8E93),
          ),
        ),
        const SizedBox(height: 16),
        // 步骤列表
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF2C2C2E)
                : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRomStep(1, Translations.tr('rom_step_autostart')),
              const SizedBox(height: 10),
              _buildRomStep(2, Translations.tr('rom_step_battery')),
              const SizedBox(height: 10),
              _buildRomStep(3, Translations.tr('rom_step_popup')),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          Translations.tr('rom_whitelist_note'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white38 : const Color(0xFF8E8E93),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              ReminderService().openAppNotificationSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
            ),
            child: Text(
              Translations.tr('rom_open_settings'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建 ROM 引导步骤行。
  Widget _buildRomStep(int number, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFF007AFF),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Center(
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : const Color(0xFF3C3C43),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionStep({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
    required bool isGranted,
    required VoidCallback onGrant,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: isGranted ? const Color(0xFF34C759).withAlpha(26) : color.withAlpha(26),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            isGranted ? Icons.check_circle : icon,
            color: isGranted ? const Color(0xFF34C759) : color,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          desc,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF8E8E93),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isGranted ? null : onGrant,
            style: ElevatedButton.styleFrom(
              backgroundColor: isGranted ? const Color(0xFF34C759) : color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
            ),
            child: Text(
              isGranted
                  ? '✓ ${Translations.tr('confirm')}'
                  : Translations.tr('grant_permission'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建第 1 步：通知权限。
  Widget _buildNotificationStep() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Future<void> requestNotif() async {
      final granted = await ReminderService().requestPostNotificationsPermission();
      if (!mounted) return;
      setState(() => _notifGranted = granted);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFFF9500).withAlpha(26),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            _notifGranted ? Icons.check_circle : Icons.notifications_outlined,
            color: _notifGranted ? const Color(0xFF34C759) : const Color(0xFFFF9500),
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          Translations.tr('notif_permission_title'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          Translations.tr('notif_permission_desc'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF8E8E93),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _notifGranted ? null : requestNotif,
            style: ElevatedButton.styleFrom(
              backgroundColor: _notifGranted ? const Color(0xFF34C759) : const Color(0xFFFF9500),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
            ),
            child: Text(
              _notifGranted
                  ? '✓ ${Translations.tr('confirm')}'
                  : Translations.tr('grant_permission'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
