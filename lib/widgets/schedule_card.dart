import 'dart:async';
import 'package:flutter/material.dart';
import '../models/schedule_item.dart';
import '../utils/date_helper.dart';
import '../utils/translations.dart';
import '../services/map_service.dart';

/// Global manager for card slide states.
/// Any tap outside the card triggers [closeAll] to slide all cards back.
typedef CardSlideCloser = void Function();

class CardSlideManager {
  static final List<CardSlideCloser> _closers = [];

  static void register(CardSlideCloser closer) {
    _closers.add(closer);
  }

  static void unregister(CardSlideCloser closer) {
    _closers.remove(closer);
  }

  /// Close all open card slides.
  static void closeAll() {
    for (final closer in _closers.toList()) {
      closer();
    }
  }
}

class ScheduleCard extends StatefulWidget {
  final ScheduleItem item;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const ScheduleCard({
    super.key,
    required this.item,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<ScheduleCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  bool _isSlid = false;
  Duration _remaining = Duration.zero;
  Timer? _countdownTimer;
  Timer? _scrollTimer;
  final _titleScrollCtrl = ScrollController();
  bool _titleOverflows = false;
  int _scrollDirection = 1;

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
    _updateRemaining();
    // Live countdown update every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
      if (mounted) setState(() {});
    });
    CardSlideManager.register(_closeSlide);
    _initTitleScroll();
  }

  void _updateRemaining() {
    _remaining = DateHelper.getCountdown(widget.item.eventTime);
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

  void _initTitleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_titleScrollCtrl.hasClients &&
          _titleScrollCtrl.position.maxScrollExtent > 0) {
        setState(() => _titleOverflows = true);
        _startAutoScroll();
      }
    });
  }

  void _startAutoScroll() {
    _scrollTimer?.cancel();
    if (!_titleOverflows) return;
    _scrollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_titleScrollCtrl.hasClients) return;
      final maxExtent = _titleScrollCtrl.position.maxScrollExtent;
      if (_scrollDirection == 1) {
        _titleScrollCtrl.animateTo(
          maxExtent,
          duration: const Duration(milliseconds: 1500),
          curve: Curves.easeInOut,
        );
      } else {
        _titleScrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 1500),
          curve: Curves.easeInOut,
        );
      }
      _scrollDirection *= -1;
    });
  }

  /// Card background color.
  /// - Expired: gray
  /// - Active:  clean white in light mode, dark in dark mode
  Color _getCardColor(bool isDark) {
    if (widget.item.eventTime.isBefore(DateTime.now())) {
      return isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    }
    if (isDark) return const Color(0xFF1C1C1E);
    return Colors.white;
  }

  /// Accent color by urgency level (left border + subtle shadow tint).
  /// - Expired:  gray
  /// - ≤24h:     red    (urgent)
  /// - ≤3d:      orange (approaching)
  /// - >3d:      green  (plenty of time)
  Color _getAccentColor(int urgency, bool isDark) {
    if (widget.item.eventTime.isBefore(DateTime.now())) {
      return isDark ? const Color(0xFF3A3A3C) : const Color(0xFFC7C7CC);
    }
    switch (urgency) {
      case 2:
        return const Color(0xFFFF3B30);
      case 1:
        return const Color(0xFFFF9500);
      default:
        return const Color(0xFF34C759);
    }
  }

  /// Countdown display
  /// - >24h: two lines (XX天 / XX:XX:XX)
  /// - <24h: one line (XX:XX:XX)
  String _formatCountdownText() {
    if (_remaining.isNegative) return Translations.tr('expired');
    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;
    final minutes = _remaining.inMinutes % 60;
    final seconds = _remaining.inSeconds % 60;

    final timeStr =
        '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    if (days > 0) {
      return '$days${Translations.tr('day_unit')}\n$timeStr';
    } else {
      return timeStr;
    }
  }

  Future<void> _navigate() async {
    if (widget.item.latitude != null && widget.item.longitude != null) {
      try {
        await MapService.navigateToLocation(
          latitude: widget.item.latitude!,
          longitude: widget.item.longitude!,
          label: widget.item.title,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Translations.tr('no_map_app'))),
          );
        }
      }
    } else if (widget.item.location.isNotEmpty) {
      try {
        await MapService.navigateToAddress(widget.item.location);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Translations.tr('no_map_app'))),
          );
        }
      }
    } else {
      _showLocationInputDialog();
    }
  }

  void _showLocationInputDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Translations.tr('enter_location')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: Translations.tr('location_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translations.tr('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (controller.text.isNotEmpty) {
                MapService.navigateToAddress(controller.text);
              }
            },
            child: Text(Translations.tr('navigate')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _scrollTimer?.cancel();
    _titleScrollCtrl.dispose();
    CardSlideManager.unregister(_closeSlide);
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _updateRemaining();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBgColor = _getCardColor(isDark);
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subtitleColor = const Color(0xFF8E8E93);
    final urgency = DateHelper.getUrgencyLevel(widget.item.eventTime);
    final accentColor = _getAccentColor(urgency, isDark);

    return GestureDetector(
      onTap: _closeSlide,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(14),
          ),
        child: Stack(
          children: [
            // ── Delete button (embedded at the right edge, behind card) ──
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: SizedBox(
                width: 70,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      widget.onDelete();
                      _closeSlide();
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          color: const Color(0xFFFF3B30),
                          size: 24,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          Translations.tr('delete'),
                          style: const TextStyle(
                            color: Color(0xFFFF3B30),
                            fontSize: 12,
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
                color: cardBgColor,
                child: Stack(
                  children: [
                    // ── Card content body ──
                    GestureDetector(
                      onHorizontalDragEnd: (details) {
                        if (details.primaryVelocity != null) {
                          if (details.primaryVelocity! < -200) {
                            if (!_isSlid) _toggleSlide();
                          } else if (details.primaryVelocity! > 200) {
                            if (_isSlid) _closeSlide();
                          }
                        }
                      },
                      onTap: () {
                        _closeSlide();
                        widget.onEdit();
                      },
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            // ── Leading: countdown only, multi-line ──
                            SizedBox(
                              width: 72,
                              child: Center(
                                child: Text(
                                  _formatCountdownText(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: textColor,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // ── Middle: Title + Description + Date ──
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Title — auto-scroll marquee when overflowing
                                    _titleOverflows
                                        ? SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            controller: _titleScrollCtrl,
                                            child: Text(
                                              widget.item.title,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: textColor,
                                              ),
                                            ),
                                          )
                                        : Text(
                                            widget.item.title,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: textColor,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    if (widget.item.description.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
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
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // ── Trailing: Navigation button ──
                            GestureDetector(
                              onTap: _navigate,
                              child: Container(
                                width: 44,
                                alignment: Alignment.center,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF007AFF).withAlpha(25),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.navigation,
                                    color: Color(0xFF007AFF),
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                    // ── Bottom urgency accent strip (painted on top of card) ──
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(14),
                            bottomRight: Radius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
