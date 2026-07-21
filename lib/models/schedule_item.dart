class ScheduleItem {
  final int? id;
  final String title;
  final String description;
  final String location;
  final DateTime eventTime;
  final double? latitude;
  final double? longitude;
  final int isDeleted;
  /// 提前提醒分钟数；0 = 不提醒
  final int reminderMinutes;
  /// 自定义铃声 URI（空字符串或 'default' 表示默认铃声）
  final String? ringtoneUri;
  final DateTime createdAt;
  final DateTime updatedAt;

  ScheduleItem({
    this.id,
    required this.title,
    this.description = '',
    this.location = '',
    required this.eventTime,
    this.latitude,
    this.longitude,
    this.isDeleted = 0,
    this.reminderMinutes = 0,
    this.ringtoneUri,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'description': description,
      'location': location,
      'event_time': eventTime.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'is_deleted': isDeleted,
      'reminder_minutes': reminderMinutes,
      'ringtone_uri': ringtoneUri ?? '',
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ScheduleItem.fromMap(Map<String, dynamic> map) {
    return ScheduleItem(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      location: map['location'] as String? ?? '',
      eventTime: DateTime.parse(map['event_time'] as String),
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      isDeleted: map['is_deleted'] as int? ?? 0,
      reminderMinutes: map['reminder_minutes'] as int? ?? 0,
      ringtoneUri: map['ringtone_uri'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  ScheduleItem copyWith({
    int? id,
    String? title,
    String? description,
    String? location,
    DateTime? eventTime,
    double? latitude,
    double? longitude,
    int? isDeleted,
    int? reminderMinutes,
    String? ringtoneUri,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScheduleItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      eventTime: eventTime ?? this.eventTime,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isDeleted: isDeleted ?? this.isDeleted,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      ringtoneUri: ringtoneUri ?? this.ringtoneUri,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 铃声的显示名称
  String get ringtoneDisplayName {
    if (ringtoneUri == null || ringtoneUri!.isEmpty || ringtoneUri == 'default') {
      return '默认铃声';
    }
    final parts = ringtoneUri!.split('/');
    final filename = parts.last;
    // 去掉扩展名
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex > 0) {
      return filename.substring(0, dotIndex);
    }
    return filename;
  }
}
