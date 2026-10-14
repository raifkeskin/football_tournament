import 'package:flutter/material.dart';

import '../utils/string_utils.dart';
import 'web_safe_image.dart';

/// Takım logosu: logo varsa zeminsiz, olduğu gibi (kırpılmadan) gösterilir;
/// yoksa baş harfli yeşil rozet.
class TeamCrest extends StatelessWidget {
  const TeamCrest({
    super.key,
    required this.name,
    required this.logoUrl,
    this.size = 40,
    this.circle = false,
    this.ringColor,
  });

  final String name;
  final String logoUrl;
  final double size;

  /// Rozet daire mi (yoksa yuvarlatılmış kare).
  final bool circle;

  /// Üst üste dizilen logolarda her birini ayıran halka ve zemin rengi
  /// (kartın kendi rengi verilir).
  final Color? ringColor;

  static String initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w.characters.first)
      .join()
      .trUpper;

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoUrl.trim().isNotEmpty;
    final radius = BorderRadius.circular(circle ? size / 2 : size * 0.28);
    final ring = ringColor;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: !hasLogo
          ? BoxDecoration(
              color: const Color(0xFF064E3B),
              borderRadius: radius,
              border: ring == null ? null : Border.all(color: ring, width: 2),
            )
          : ring == null
          ? null
          : BoxDecoration(
              color: ring,
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 2),
            ),
      child: hasLogo
          ? WebSafeImage(
              url: logoUrl,
              width: size,
              height: size,
              fit: BoxFit.contain,
              fallbackIconSize: size * 0.5,
            )
          : Text(
              initials(name),
              style: TextStyle(
                color: const Color(0xFF6EE7B7),
                fontSize: size * 0.34,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}
