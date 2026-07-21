import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/schedule_provider.dart';
import '../providers/settings_provider.dart';
import '../models/schedule_item.dart';
import '../services/reminder_service.dart';
import '../utils/translations.dart';
import '../utils/ringtone_utils.dart';
import 'ringtone_picker_screen.dart';

class AddScheduleScreen extends StatefulWidget {
  final ScheduleItem? editItem;

  const AddScheduleScreen({super.key, this.editItem});

  @override
  State<AddScheduleScreen> createState() => _AddScheduleScreenState();
}

class _AddScheduleScreenState extends State<AddScheduleScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  String _selectedRingtone = 'default'; // 铃声 URI
  int _selectedReminderSeconds = 0; // 0 = 不提醒

  bool get isEditing => widget.editItem != null;

  @override
  void initState() {
    super.initState();
    if (widget.editItem != null) {
      _titleController.text = widget.editItem!.title;
      _descriptionController.text = widget.editItem!.description;
      _locationController.text = widget.editItem!.location;
      _selectedDate = widget.editItem!.eventTime;
      _selectedTime = TimeOfDay.fromDateTime(widget.editItem!.eventTime);
      _selectedRingtone = widget.editItem!.ringtoneUri ?? 'default';
    } else {
      _selectedDate = DateTime.now();
      _selectedTime = TimeOfDay.now();
      // 在 initState 后加载默认铃声
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final settings = context.read<SettingsProvider>();
          setState(() {
            _selectedRingtone = settings.defaultRingtone;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  DateTime _getCombinedDateTime() {
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
  }

  /// Custom year / month / day wheel picker.
  ///
  /// 用三个独立的 CupertinoPicker（年、月、日）替代 CupertinoDatePicker，
  /// 因为 CupertinoDatePicker 在中文 locale 下月份显示「一、二、三…」中文数字。
  /// 自定义滚轮让月份显示阿拉伯数字（1、2、3…）。
  void _showDatePickerWheel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    int tempYear = _selectedDate.year;
    int tempMonth = _selectedDate.month; // 1-12
    int tempDay = _selectedDate.day;

    // 计算指定年月的天数
    int daysInMonth(int year, int month) {
      return DateTime(year, month + 1, 0).day;
    }

    // 年滚轮控制器（从当前年 -10 到 +40）
    final nowYear = DateTime.now().year;
    final yearStart = nowYear - 10;
    final yearCount = 50;
    final yearController = FixedExtentScrollController(
      initialItem: tempYear - yearStart,
    );
    final monthController = FixedExtentScrollController(
      initialItem: tempMonth - 1,
    );
    final dayController = FixedExtentScrollController(
      initialItem: tempDay - 1,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // 每次状态刷新时重新计算当月天数
            final y = yearController.selectedItem + yearStart;
            final m = monthController.selectedItem + 1;
            final maxDay = daysInMonth(y, m);

            return SizedBox(
              height: 300,
              child: Column(
                children: [
                  // Toolbar
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isDark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            Translations.tr('cancel'),
                            style: const TextStyle(color: Color(0xFF007AFF)),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        Text(
                          Translations.tr('select_date'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            Translations.tr('confirm'),
                            style: TextStyle(
                              color: const Color(0xFF007AFF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () {
                            final y2 = yearController.selectedItem + yearStart;
                            final m2 = monthController.selectedItem + 1;
                            final d2 = (dayController.selectedItem % daysInMonth(y2, m2)) + 1;
                            setState(() {
                              _selectedDate = DateTime(y2, m2, d2);
                            });
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Year / Month / Day wheels
                  Expanded(
                    child: Row(
                      children: [
                        // Year wheel
                        Expanded(
                          child: CupertinoPicker(
                            scrollController: yearController,
                            itemExtent: 40,
                            backgroundColor: bgColor,
                            looping: true,
                            onSelectedItemChanged: (_) => setSheetState(() {}),
                            children: List.generate(yearCount, (i) {
                              return Center(
                                child: Text(
                                  '${yearStart + i}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        // Month wheel（阿拉伯数字 1-12）
                        Expanded(
                          child: CupertinoPicker(
                            scrollController: monthController,
                            itemExtent: 40,
                            backgroundColor: bgColor,
                            looping: true,
                            onSelectedItemChanged: (_) => setSheetState(() {}),
                            children: List.generate(12, (i) {
                              return Center(
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        // Day wheel（1-31）
                        Expanded(
                          child: CupertinoPicker(
                            scrollController: dayController,
                            itemExtent: 40,
                            backgroundColor: bgColor,
                            looping: true,
                            onSelectedItemChanged: (_) => setSheetState(() {}),
                            children: List.generate(31, (i) {
                              return Center(
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Unit labels row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Center(
                            child: Text(
                              Translations.tr('year_label'),
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              Translations.tr('month_label'),
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              Translations.tr('day_label'),
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Custom time picker with AM/PM toggle + hour + minute wheels.
  ///
  /// 用户要求：上午下午不要用滚轮，改成简单切换按钮。
  /// 左侧用两个垂直排列的按钮（上午 / 下午），点击切换选中状态。
  /// 右侧保持小时和分钟滚轮不变。
  void _showTimePickerWheel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    // Convert 24h → 12h for display
    int tempAmPm = _selectedTime.hour < 12 ? 0 : 1; // 0=上午, 1=下午
    int tempHour = _selectedTime.hour % 12;
    if (tempHour == 0) tempHour = 12;
    int tempMinute = _selectedTime.minute;

    final hourController = FixedExtentScrollController(initialItem: tempHour - 1);
    final minuteController = FixedExtentScrollController(initialItem: tempMinute);

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: 300,
              child: Column(
                children: [
                  // Toolbar
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isDark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            Translations.tr('cancel'),
                            style: const TextStyle(color: Color(0xFF007AFF)),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        Text(
                          Translations.tr('select_time'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            Translations.tr('confirm'),
                            style: TextStyle(
                              color: const Color(0xFF007AFF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () {
                            final h12 = hourController.selectedItem + 1;
                            int h24;
                            if (tempAmPm == 0) {
                              h24 = (h12 == 12) ? 0 : h12;
                            } else {
                              h24 = (h12 == 12) ? 12 : h12 + 12;
                            }
                            setState(() {
                              _selectedTime = TimeOfDay(
                                hour: h24,
                                minute: minuteController.selectedItem % 60,
                              );
                            });
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // AM/PM toggle + hour + minute wheels
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              // AM/PM toggle (buttons, not a wheel)
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // 上午 button
                                    GestureDetector(
                                      onTap: () => setSheetState(() => tempAmPm = 0),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tempAmPm == 0
                                              ? const Color(0xFF007AFF)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: tempAmPm == 0
                                                ? const Color(0xFF007AFF)
                                                : (isDark ? const Color(0xFF38383A) : const Color(0xFFC7C7CC)),
                                          ),
                                        ),
                                        child: Text(
                                          Translations.tr('am'),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: tempAmPm == 0
                                                ? Colors.white
                                                : (isDark ? Colors.white70 : const Color(0xFF1C1C1E)),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    // 下午 button
                                    GestureDetector(
                                      onTap: () => setSheetState(() => tempAmPm = 1),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tempAmPm == 1
                                              ? const Color(0xFF007AFF)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: tempAmPm == 1
                                                ? const Color(0xFF007AFF)
                                                : (isDark ? const Color(0xFF38383A) : const Color(0xFFC7C7CC)),
                                          ),
                                        ),
                                        child: Text(
                                          Translations.tr('pm'),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: tempAmPm == 1
                                                ? Colors.white
                                                : (isDark ? Colors.white70 : const Color(0xFF1C1C1E)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Hours wheel (1-12)
                              Expanded(
                                child: CupertinoPicker(
                                  scrollController: hourController,
                                  itemExtent: 40,
                                  backgroundColor: bgColor,
                                  looping: true,
                                  onSelectedItemChanged: (_) {},
                                  children: List.generate(12, (i) {
                                    return Center(
                                      child: Text(
                                        '${i + 1}',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w500,
                                          color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                              // Minutes wheel (0-59)
                              Expanded(
                                child: CupertinoPicker(
                                  scrollController: minuteController,
                                  itemExtent: 40,
                                  backgroundColor: bgColor,
                                  looping: true,
                                  onSelectedItemChanged: (_) {},
                                  children: List.generate(60, (i) {
                                    return Center(
                                      child: Text(
                                        i.toString().padLeft(2, '0'),
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w500,
                                          color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Unit labels row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              Expanded(
                                child: Center(
                                  child: Text(
                                    '',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    Translations.tr('hours'),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    Translations.tr('minutes'),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Format time with Chinese AM/PM label
  String _formatTimeDisplay(TimeOfDay time) {
    final locale = Translations.currentLocale;
    final amPmStr = time.hour < 12 ? Translations.tr('am') : Translations.tr('pm');
    int h12 = time.hour % 12;
    if (h12 == 0) h12 = 12;
    final mStr = time.minute.toString().padLeft(2, '0');
    if (locale == 'en') {
      return '$h12:$mStr $amPmStr';
    }
    return '$amPmStr $h12:$mStr';
  }

  void _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Translations.tr('title_hint'))),
      );
      return;
    }

    try {
      final eventTime = _getCombinedDateTime();
      final provider = context.read<ScheduleProvider>();

      if (isEditing) {
        final updated = widget.editItem!.copyWith(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          location: _locationController.text.trim(),
          eventTime: eventTime,
          ringtoneUri: _selectedRingtone == 'default' ? null : _selectedRingtone,
        );
        await provider.updateItem(updated);

        // 重新调度提醒闹钟（如果已选择提醒时间）
        if (_selectedReminderSeconds > 0 && widget.editItem!.id != null) {
          _scheduleReminder(
            eventId: widget.editItem!.id!,
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            location: _locationController.text.trim(),
            eventTime: eventTime,
            beforeSeconds: _selectedReminderSeconds,
          );
        } else if (_selectedReminderSeconds <= 0 && widget.editItem!.id != null) {
          // 取消旧闹钟
          ReminderService().cancelReminder(widget.editItem!.id!);
        }
      } else {
        final item = ScheduleItem(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          location: _locationController.text.trim(),
          eventTime: eventTime,
          ringtoneUri: _selectedRingtone == 'default' ? null : _selectedRingtone,
        );
        final eventId = await provider.addItem(item);

        // 如果已选择提醒时间，调度真实闹钟
        if (_selectedReminderSeconds > 0) {
          _scheduleReminder(
            eventId: eventId,
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            location: _locationController.text.trim(),
            eventTime: eventTime,
            beforeSeconds: _selectedReminderSeconds,
          );
        }
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('保存事件失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        surfaceTintColor: bgColor,
        leading: CupertinoBackButton(
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? Translations.tr('edit_event') : Translations.tr('add_event'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              Translations.tr('save'),
              style: const TextStyle(
                color: Color(0xFF007AFF),
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            _buildSectionLabel(Translations.tr('title')),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _titleController,
              hint: Translations.tr('title_hint'),
            ),
            const SizedBox(height: 24),

            // Description
            _buildSectionLabel(Translations.tr('description')),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _descriptionController,
              hint: Translations.tr('description_hint'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Location
            _buildSectionLabel(Translations.tr('location')),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _locationController,
              hint: Translations.tr('location_hint'),
            ),
            const SizedBox(height: 24),

            // Event date/time — iOS wheel pickers
            _buildSectionLabel(Translations.tr('event_time')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildWheelButton(
                    icon: Icons.calendar_today_outlined,
                    label: DateFormat(
                      Translations.currentLocale == 'en'
                          ? 'MM/dd/yyyy'
                          : 'yyyy/MM/dd',
                    ).format(_selectedDate),
                    onTap: _showDatePickerWheel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildWheelButton(
                    icon: Icons.access_time_outlined,
                    label: _formatTimeDisplay(_selectedTime),
                    onTap: _showTimePickerWheel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Reminder
            _buildSectionLabel('提醒'),
            const SizedBox(height: 8),
            _buildWheelButton(
              icon: Icons.notifications_outlined,
              label: _formatReminderText(),
              onTap: _showReminderPicker,
            ),
            const SizedBox(height: 24),

            // Ringtone
            _buildSectionLabel(Translations.tr('ringtone_setting')),
            const SizedBox(height: 8),
            _buildWheelButton(
              icon: Icons.music_note_outlined,
              label: RingtoneUtils.getDisplayName(_selectedRingtone),
              onTap: () async {
                final result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RingtonePickerScreen(),
                  ),
                );
                if (result != null) {
                  setState(() => _selectedRingtone = result);
                }
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF8E8E93),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
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
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: TextStyle(
          fontSize: 16,
          color: isDark ? Colors.white : const Color(0xFF1C1C1E),
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: isDark ? const Color(0xFF636366) : const Color(0xFFC7C7CC),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildWheelButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF007AFF)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                ),
              ),
            ),
            Icon(Icons.expand_more, size: 18, color: const Color(0xFFC7C7CC)),
          ],
        ),
      ),
    );
  }

  // ── 提醒功能（使用真实闹钟路径） ──

  /// 提醒选项列表：{label, seconds}
  static const List<Map<String, dynamic>> _reminderOptions = [
    {'label': '不提醒', 'seconds': 0},
    {'label': '10秒前', 'seconds': 10},
    {'label': '1分钟前', 'seconds': 60},
    {'label': '5分钟前', 'seconds': 300},
    {'label': '10分钟前', 'seconds': 600},
    {'label': '30分钟前', 'seconds': 1800},
    {'label': '1小时前', 'seconds': 3600},
  ];

  String _formatReminderText() {
    if (_selectedReminderSeconds <= 0) return '不提醒';
    final found = _reminderOptions.firstWhere(
      (o) => o['seconds'] == _selectedReminderSeconds,
      orElse: () => {'label': '$_selectedReminderSeconds秒前'},
    );
    return found['label'] as String;
  }

  void _showReminderPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF636366) : const Color(0xFFC7C7CC),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 48),
                    const Text(
                      '提醒',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        '完成',
                        style: TextStyle(
                          color: Color(0xFF007AFF),
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _reminderOptions.length,
                  itemBuilder: (_, i) {
                    final option = _reminderOptions[i];
                    final label = option['label'] as String;
                    final seconds = option['seconds'] as int;
                    final isSelected = _selectedReminderSeconds == seconds;
                    return ListTile(
                      title: Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Color(0xFF007AFF))
                          : null,
                      onTap: () {
                        setState(() => _selectedReminderSeconds = seconds);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 通过原生 MethodChannel 调度一个真实 AlarmManager 闹钟。
  void _scheduleReminder({
    required int eventId,
    required String title,
    required String description,
    required String location,
    required DateTime eventTime,
    required int beforeSeconds,
  }) {
    ReminderService().scheduleReminder(
      eventId: eventId,
      title: title,
      description: description,
      location: location,
      eventTime: eventTime,
      beforeSeconds: beforeSeconds,
    );
  }
}

/// iOS-style back button
class CupertinoBackButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const CupertinoBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.chevron_left, size: 28),
      onPressed: onPressed ?? () => Navigator.pop(context),
      color: const Color(0xFF007AFF),
    );
  }
}
