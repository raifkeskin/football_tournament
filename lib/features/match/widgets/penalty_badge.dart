import 'package:flutter/material.dart';

/// Penaltı skoru: sarı kutuda "4 P". Normal skor kutusunun yanında durur.
class PenaltyBadge extends StatelessWidget {
  const PenaltyBadge(this.goals, {super.key, this.size = 12});

  final int goals;

  /// Rakamın yazı boyu; "P" bunun %70'i.
  final double size;

  static const color = Color(0xFFFBBF24);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.42, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.5),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$goals'),
            TextSpan(
              text: ' P',
              style: TextStyle(
                fontSize: size * 0.7,
                color: const Color(0xFF1A1300).withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
        style: TextStyle(
          color: const Color(0xFF1A1300),
          fontWeight: FontWeight.w800,
          fontSize: size,
          height: 1.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
