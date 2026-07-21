import 'package:intl/intl.dart';

class DateHelper {
  /// Calculate the countdown duration from now to event time
  static Duration getCountdown(DateTime eventTime) {
    return eventTime.difference(DateTime.now());
  }

  /// Get urgency level: 0=green (>3 days), 1=yellow (1-3 days), 2=red (<1 day)
  static int getUrgencyLevel(DateTime eventTime) {
    final diff = eventTime.difference(DateTime.now());
    if (diff.isNegative) return -1; // expired
    if (diff.inHours < 24) return 2; // red - within 1 day
    if (diff.inHours < 72) return 1; // yellow - within 3 days
    return 0; // green - more than 3 days
  }

  /// Format countdown text
  static String formatCountdown(Duration duration, String locale) {
    if (duration.isNegative) {
      return _getExpiredText(locale);
    }

    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (locale == 'en') {
      if (days > 0) {
        return '${days}d ${hours}h ${minutes}m ${seconds}s';
      } else if (hours > 0) {
        return '${hours}h ${minutes}m ${seconds}s';
      } else if (minutes > 0) {
        return '${minutes}m ${seconds}s';
      } else {
        return '${seconds}s';
      }
    } else if (locale == 'zh_HK') {
      if (days > 0) {
        return '$days天 $hours小時 $minutes分鐘 $seconds秒';
      } else if (hours > 0) {
        return '$hours小時 $minutes分鐘 $seconds秒';
      } else if (minutes > 0) {
        return '$minutes分鐘 $seconds秒';
      } else {
        return '$seconds秒';
      }
    } else {
      // Default: Simplified Chinese
      if (days > 0) {
        return '$days天 $hours小时 $minutes分钟 $seconds秒';
      } else if (hours > 0) {
        return '$hours小时 $minutes分钟 $seconds秒';
      } else if (minutes > 0) {
        return '$minutes分钟 $seconds秒';
      } else {
        return '$seconds秒';
      }
    }
  }

  /// Short countdown format: HH:MM:SS (zero-padded)
  static String formatCountdownShort(Duration duration) {
    if (duration.isNegative) return '00:00:00';
    final totalHours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return '${totalHours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static String _getExpiredText(String locale) {
    switch (locale) {
      case 'en':
        return 'Expired';
      case 'zh_HK':
        return '已過期';
      default:
        return '已过期';
    }
  }

  /// Format event date/time for display
  static String formatEventDateTime(DateTime dateTime, String locale) {
    final formatter = DateFormat(
      locale == 'en' ? 'MM/dd/yyyy HH:mm' : 'yyyy/MM/dd HH:mm',
      locale,
    );
    return formatter.format(dateTime);
  }
}
