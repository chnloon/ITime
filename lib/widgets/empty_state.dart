import 'package:flutter/material.dart';
import '../utils/translations.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String titleKey;
  final String descriptionKey;

  const EmptyState({
    super.key,
    required this.icon,
    required this.titleKey,
    required this.descriptionKey,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 72,
              color: isDark ? const Color(0xFF38383A) : const Color(0xFFC7C7CC),
            ),
            const SizedBox(height: 20),
            Text(
              Translations.tr(titleKey),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              Translations.tr(descriptionKey),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? const Color(0xFF636366) : const Color(0xFFAEAEB2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
