import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/schedule_provider.dart';
import '../services/database_service.dart';
import '../models/schedule_item.dart';
import '../widgets/empty_state.dart';
import '../widgets/schedule_card.dart';
import '../utils/translations.dart';
import '../utils/date_helper.dart';

class GraveyardScreen extends StatefulWidget {
  const GraveyardScreen({super.key});

  @override
  State<GraveyardScreen> createState() => _GraveyardScreenState();
}

class _GraveyardScreenState extends State<GraveyardScreen> {
  List<ScheduleItem> _items = [];
  List<ScheduleItem> _filteredItems = [];
  final _searchController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    final items = await DatabaseService.getGraveyardSchedules();
    setState(() {
      _items = items;
      _filteredItems = items;
      _isLoading = false;
    });
  }

  void _search(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = List.from(_items);
      } else {
        _filteredItems = _items.where((item) {
          final lowerQuery = query.toLowerCase();
          return item.title.toLowerCase().contains(lowerQuery) ||
              item.description.toLowerCase().contains(lowerQuery) ||
              item.location.toLowerCase().contains(lowerQuery);
        }).toList();
      }
    });
  }

  Future<void> _restoreItem(ScheduleItem item) async {
    await DatabaseService.restore(item.id!);
    if (mounted) {
      context.read<ScheduleProvider>().loadItems();
      _loadItems();
    }
  }

  Future<void> _permanentlyDelete(ScheduleItem item) async {
    await DatabaseService.permanentDelete(item.id!);
    _loadItems();
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
          Translations.tr('graveyard'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _search,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                ),
                decoration: InputDecoration(
                  hintText: Translations.tr('search_hint'),
                  hintStyle: TextStyle(
                    color: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93),
                    size: 20,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93),
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _search('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredItems.isEmpty
                    ? EmptyState(
                        icon: Icons.delete_outline,
                        titleKey: 'no_graveyard_items',
                        descriptionKey: 'no_graveyard_items_desc',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = _filteredItems[index];
                          return _buildGraveyardItem(item, isDark);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraveyardItem(ScheduleItem item, bool isDark) {
    return _GraveyardCard(
      item: item,
      isDark: isDark,
      onRestore: () => _restoreItem(item),
      onDelete: () => _permanentlyDelete(item),
    );
  }
}

/// Slide-to-reveal-delete card for graveyard items.
class _GraveyardCard extends StatefulWidget {
  final ScheduleItem item;
  final bool isDark;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _GraveyardCard({
    required this.item,
    required this.isDark,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  State<_GraveyardCard> createState() => _GraveyardCardState();
}

class _GraveyardCardState extends State<_GraveyardCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  bool _isSlid = false;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.28, 0),
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    CardSlideManager.register(_closeSlide);
  }

  void _toggleSlide() {
    if (_isSlid) {
      _slideController.reverse();
    } else {
      _slideController.forward();
    }
    _isSlid = !_isSlid;
  }

  void _closeSlide() {
    if (_isSlid) {
      _slideController.reverse();
      _isSlid = false;
    }
  }

  @override
  void dispose() {
    CardSlideManager.unregister(_closeSlide);
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = widget.isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subtitleColor = const Color(0xFF8E8E93);

    return GestureDetector(
      onTap: _closeSlide,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: widget.isDark ? Colors.black26 : Colors.black.withAlpha(8),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Stack(
          children: [
            // ── Delete button (revealed on slide) ──
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: SizedBox(
                width: 70,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      _closeSlide();
                      widget.onDelete();
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.delete_forever,
                          color: Color(0xFFFF3B30),
                          size: 24,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          Translations.tr('permanently_delete'),
                          style: const TextStyle(
                            color: Color(0xFFFF3B30),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ── Card content (slides left) ──
            SlideTransition(
              position: _slideAnimation,
              child: Container(
                color: cardColor,
                child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity != null) {
                    if (details.primaryVelocity! < -200) {
                      if (!_isSlid) _toggleSlide();
                    } else if (details.primaryVelocity! > 200) {
                      if (_isSlid) _closeSlide();
                    }
                  }
                },
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: GestureDetector(
                    onTap: widget.onRestore,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.restore_outlined,
                        color: Color(0xFF007AFF),
                        size: 20,
                      ),
                    ),
                  ),
                  title: Text(
                    widget.item.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.item.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.item.description,
                            style: TextStyle(
                              fontSize: 13,
                              color: subtitleColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          DateHelper.formatEventDateTime(
                            widget.item.eventTime,
                            Translations.currentLocale,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: subtitleColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}
