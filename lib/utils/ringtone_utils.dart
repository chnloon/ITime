import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;

/// 铃声工具类 — 管理预装铃声的试听、提取和选择。
///
/// ## 铃声数据
///
/// 7 个预装 .wav 文件，存放在 `assets/ringtones/`。
/// 使用 audioplayers 包进行试听预览。
/// 提取到临时文件后，将文件路径传给 Kotlin 原生侧用于通知铃声。
class RingtoneUtils {
  RingtoneUtils._();

  /// 预装铃声列表。
  /// [key] = 标识符（不含路径和扩展名），[path] = asset 路径
  static const List<Map<String, String>> builtInRingtones = [
    {'key': 'ascending', 'path': 'assets/ringtones/ascending.wav'},
    {'key': 'classic_beep', 'path': 'assets/ringtones/classic_beep.wav'},
    {'key': 'crystal_chime', 'path': 'assets/ringtones/crystal_chime.wav'},
    {'key': 'digital_ping', 'path': 'assets/ringtones/digital_ping.wav'},
    {'key': 'double_tap', 'path': 'assets/ringtones/double_tap.wav'},
    {'key': 'gentle_alert', 'path': 'assets/ringtones/gentle_alert.wav'},
    {'key': 'marimba', 'path': 'assets/ringtones/marimba.wav'},
  ];

  /// 判断一个 URI 是否为预装铃声
  static bool isBuiltIn(String? uri) {
    if (uri == null || uri.isEmpty) return false;
    return builtInRingtones.any((r) => uri.startsWith('builtin:'));
  }

  /// 根据标识符获取 asset 路径
  static String? getAssetPath(String? uri) {
    if (uri == null || uri.isEmpty) return null;
    if (uri == 'default') return null;
    // builtin:xxx 格式
    if (uri.startsWith('builtin:')) {
      final key = uri.substring(8);
      final match = builtInRingtones.firstWhere(
        (r) => r['key'] == key,
        orElse: () => <String, String>{},
      );
      return match['path'];
    }
    // 已经是文件路径，直接返回
    return uri;
  }

  /// 从 asset 路径提取铃声文件到应用缓存目录，返回文件路径。
  /// 用于将预装铃声传给 Kotlin 原生通知系统使用。
  static Future<String?> extractToCache(String? ringtoneUri) async {
    if (ringtoneUri == null || ringtoneUri.isEmpty || ringtoneUri == 'default') {
      return null;
    }

    try {
      // builtin:xxx → 从 asset 提取
      if (ringtoneUri.startsWith('builtin:')) {
        final assetPath = getAssetPath(ringtoneUri);
        if (assetPath == null) return null;

        final data = await rootBundle.load(assetPath);
        final fileName = p.basename(assetPath);
        final cacheDir = Directory.systemTemp.path;
        final file = File('$cacheDir/$fileName');
        if (!file.existsSync()) {
          await file.writeAsBytes(data.buffer.asUint8List());
        }
        return file.path;
      }

      // 已经是文件路径（用户自定义铃声）
      return ringtoneUri;
    } catch (e) {
      debugPrint('提取铃声文件失败: $e');
      return null;
    }
  }

  /// 获取铃声的显示名称。
  static String getDisplayName(String? ringtoneUri) {
    if (ringtoneUri == null || ringtoneUri.isEmpty || ringtoneUri == 'default') {
      return '默认铃声';
    }
    if (ringtoneUri.startsWith('builtin:')) {
      final key = ringtoneUri.substring(8);
      // 返回 key 作为显示名称（调用方通过 Translations 翻译）
      return key;
    }
    // 自定义铃声：提取文件名
    final parts = ringtoneUri.split('/');
    final filename = parts.last;
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex > 0) {
      return filename.substring(0, dotIndex);
    }
    return filename;
  }
}

/// 铃声试听管理器 — 封装 audioplayers 播放控制。
class RingtonePlayer {
  RingtonePlayer._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _isPlaying = false;

  /// 播放预装铃声试听。
  static Future<void> previewBuiltIn(String assetPath) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(assetPath.replaceFirst('assets/', '')));
      _isPlaying = true;
    } catch (e) {
      debugPrint('试听播放失败: $e');
    }
  }

  /// 播放本地文件试听。
  static Future<void> previewFile(String filePath) async {
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(filePath));
      _isPlaying = true;
    } catch (e) {
      debugPrint('文件试听播放失败: $e');
    }
  }

  /// 停止播放。
  static Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
  }

  /// 释放资源。
  static void dispose() {
    _player.dispose();
    _isPlaying = false;
  }

  static bool get isPlaying => _isPlaying;
}
