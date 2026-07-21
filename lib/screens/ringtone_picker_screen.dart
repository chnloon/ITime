import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/translations.dart';
import '../utils/ringtone_utils.dart';

/// 铃声选择器屏幕。
///
/// 显示 7 个预装铃声（可试听/选择）+ 自定义铃声选项。
/// 返回选中铃声的 URI 字符串。
///
/// URI 格式：
///   - 预装铃声: `builtin:<key>`（如 `builtin:ascending`）
///   - 自定义铃声: 文件绝对路径
///   - 默认: `default`
class RingtonePickerScreen extends StatefulWidget {
  /// 当前选中的铃声 URI
  final String? currentRingtone;

  /// 是否用于设置页面的默认铃声（显示默认铃声选项）
  final bool isDefaultSettings;

  const RingtonePickerScreen({
    super.key,
    this.currentRingtone,
    this.isDefaultSettings = false,
  });

  @override
  State<RingtonePickerScreen> createState() => _RingtonePickerScreenState();
}

class _RingtonePickerScreenState extends State<RingtonePickerScreen> {
  late String _selectedRingtone;

  @override
  void initState() {
    super.initState();
    _selectedRingtone = widget.currentRingtone ?? 'default';
  }

  /// 选择预装铃声
  void _selectBuiltIn(String key) {
    Navigator.pop(context, 'builtin:$key');
  }

  /// 选择自定义铃声（打开文件选择器）
  Future<void> _pickCustomRingtone() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'ogg', 'm4a', 'aac', 'flac'],
      );
      if (result != null && result.files.single.path != null) {
        Navigator.pop(context, result.files.single.path!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Translations.tr('ringtone_invalid'))),
        );
      }
    }
  }

  /// 试听预装铃声
  Future<void> _previewBuiltIn(String assetPath) async {
    await RingtonePlayer.previewBuiltIn(assetPath);
  }

  /// 停止试听
  Future<void> _stopPreview() async {
    await RingtonePlayer.stop();
  }

  /// 构建预装铃声列表项
  Widget _buildBuiltInTile(Map<String, String> ringtone) {
    final key = ringtone['key']!;
    final path = ringtone['path']!;
    final uri = 'builtin:$key';
    final isSelected = _selectedRingtone == uri;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Icon(
          isSelected ? Icons.check_circle : Icons.music_note_outlined,
          color: isSelected
              ? const Color(0xFF007AFF)
              : (isDark ? Colors.white70 : const Color(0xFF8E8E93)),
          size: 24,
        ),
        title: Text(
          Translations.tr(key), // key matches translation key
          style: TextStyle(
            fontSize: 16,
            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Preview button
            IconButton(
              icon: const Icon(Icons.play_circle_outline, size: 22),
              color: const Color(0xFF007AFF),
              onPressed: () => _previewBuiltIn(path),
            ),
            // Select circle
            GestureDetector(
              onTap: () => _selectBuiltIn(key),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF007AFF)
                        : const Color(0xFFC7C7CC),
                    width: 2,
                  ),
                  color: isSelected ? const Color(0xFF007AFF) : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
              ),
            ),
          ],
        ),
        onTap: () => _selectBuiltIn(key),
      ),
    );
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
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
          color: const Color(0xFF007AFF),
        ),
        title: Text(
          Translations.tr('choose_ringtone'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Pre-installed ringtones ──
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 20, bottom: 8),
            child: Text(
              Translations.tr('ringtone').toUpperCase(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8E93),
                letterSpacing: 0.5,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children:
                  RingtoneUtils.builtInRingtones.map(_buildBuiltInTile).toList(),
            ),
          ),
          const SizedBox(height: 8),

          // ── Stop preview button ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _stopPreview,
                icon: const Icon(Icons.stop_circle_outlined, size: 20),
                label: Text(Translations.tr('stop_preview')),
              ),
            ),
          ),

          // ── Silence option ──
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 20, bottom: 8),
            child: Text(
              Translations.tr('other_options').toUpperCase(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8E93),
                letterSpacing: 0.5,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Default ringtone
                if (widget.isDefaultSettings)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      _selectedRingtone == 'default'
                          ? Icons.check_circle
                          : Icons.settings_remote_outlined,
                      color: _selectedRingtone == 'default'
                          ? const Color(0xFF007AFF)
                          : (isDark ? Colors.white70 : const Color(0xFF8E8E93)),
                      size: 24,
                    ),
                    title: Text(
                      Translations.tr('default_ringtone_name'),
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      ),
                    ),
                    trailing: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedRingtone == 'default'
                              ? const Color(0xFF007AFF)
                              : const Color(0xFFC7C7CC),
                          width: 2,
                        ),
                        color: _selectedRingtone == 'default'
                            ? const Color(0xFF007AFF)
                            : Colors.transparent,
                      ),
                      child: _selectedRingtone == 'default'
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                    onTap: () => Navigator.pop(context, 'default'),
                  ),
                if (widget.isDefaultSettings)
                  const Divider(height: 1, indent: 52, color: Color(0xFFE5E5EA)),

                // Custom ringtone
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(
                    Icons.folder_outlined,
                    color: Color(0xFF007AFF),
                    size: 24,
                  ),
                  title: Text(
                    Translations.tr('custom_ringtone'),
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    ),
                  ),
                  subtitle: Text(
                    Translations.tr('custom_ringtone_desc'),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: Color(0xFFC7C7CC), size: 20),
                  onTap: _pickCustomRingtone,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
