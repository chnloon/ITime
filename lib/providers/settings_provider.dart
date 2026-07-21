import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/translations.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _localeKey = 'locale';
  static const String _themeKey = 'theme_mode';
  static const String _vibrationIntensityKey = 'vibration_intensity';
  static const String _defaultRingtoneKey = 'default_ringtone';

  String _locale = 'zh_CN';
  ThemeMode _themeMode = ThemeMode.system;
  int _vibrationIntensity = -1; // -1=none, 0=light, 1=medium, 2=strong
  String _defaultRingtone = 'default'; // 'default' or asset path or file URI

  String get locale => _locale;
  ThemeMode get themeMode => _themeMode;
  int get vibrationIntensity => _vibrationIntensity;
  String get defaultRingtone => _defaultRingtone;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _locale = prefs.getString(_localeKey) ?? 'zh_CN';
    // 默认浅色主题
    _themeMode = ThemeMode.light;
    // 清除旧的主题缓存
    await prefs.remove(_themeKey);
    _vibrationIntensity = prefs.getInt(_vibrationIntensityKey) ?? -1;
    _defaultRingtone = prefs.getString(_defaultRingtoneKey) ?? 'default';
    Translations.setLocale(_locale);
    notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    _locale = locale;
    Translations.setLocale(locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
    notifyListeners();
  }

  Future<void> setVibrationIntensity(int intensity) async {
    _vibrationIntensity = intensity;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_vibrationIntensityKey, intensity);
    notifyListeners();
  }

  Future<void> setDefaultRingtone(String ringtone) async {
    _defaultRingtone = ringtone;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultRingtoneKey, ringtone);
    notifyListeners();
  }

  /// Get available theme modes for UI display
  static List<Map<String, dynamic>> get availableThemes => [
        {'mode': ThemeMode.light, 'key': 'light'},
        {'mode': ThemeMode.dark, 'key': 'dark'},
        {'mode': ThemeMode.system, 'key': 'system'},
      ];
}
