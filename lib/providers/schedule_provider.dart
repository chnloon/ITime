import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/schedule_item.dart';
import '../services/database_service.dart';

class ScheduleProvider extends ChangeNotifier {
  List<ScheduleItem> _items = [];
  bool _initialized = false;
  Timer? _expiryTimer;

  List<ScheduleItem> get items => _items;
  bool get initialized => _initialized;

  ScheduleProvider() {
    loadItems();
    // 每隔 10 秒检查一次是否有事件过期，实时移入回收站
    _expiryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _cleanExpiredItems();
    });
  }

  /// Public refresh — used by home_screen to trigger UI update after
  /// receiving native intent (e.g. from external share).
  void refresh() {
    notifyListeners();
  }

  // ════════════════════════════════════════════
  //  数据加载
  // ════════════════════════════════════════════

  Future<void> loadItems() async {
    try {
      _items = await DatabaseService.getActiveSchedules();
      await _cleanExpiredItems();
    } catch (e) {
      debugPrint('Error loading items: $e');
      _items = [];
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  // ════════════════════════════════════════════
  //  过期处理 — 实时检测，过期即软删除到回收站
  // ════════════════════════════════════════════

  Future<void> _cleanExpiredItems() async {
    final now = DateTime.now();
    bool hasExpired = false;
    for (final item in _items) {
      if (item.eventTime.isBefore(now) && item.id != null) {
        try {
          await DatabaseService.softDelete(item.id!);
          hasExpired = true;
        } catch (e) {
          debugPrint('softDelete failed for item ${item.id}: $e');
        }
      }
    }
    if (hasExpired) {
      // 从内存列表移除已过期事件（数据库已软删除），
      // 让它们立即从首页消失，同时出现在回收站页。
      _items.removeWhere((item) => item.eventTime.isBefore(now));
      notifyListeners();
    }
  }

  // ════════════════════════════════════════════
  //  CRUD
  // ════════════════════════════════════════════

  Future<int> addItem(ScheduleItem item) async {
    final id = await DatabaseService.insert(item);
    final newItem = item.copyWith(id: id);
    _items.add(newItem);
    _items.sort((a, b) => a.eventTime.compareTo(b.eventTime));
    notifyListeners();
    return id;
  }

  Future<void> updateItem(ScheduleItem item) async {
    await DatabaseService.update(item);
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      _items[index] = item;
      notifyListeners();
    }
  }

  Future<void> deleteItem(int id) async {
    await DatabaseService.softDelete(id);
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
