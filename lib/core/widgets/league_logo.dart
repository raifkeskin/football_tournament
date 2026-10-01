import 'package:flutter/material.dart';

import 'web_safe_image.dart';

/// Turnuva logosu; logo yüklenmemişse kupa ikonu gösterilir.
class LeagueLogo extends StatelessWidget {
  const LeagueLogo({
    super.key,
    required this.url,
    this.size = 20,
    this.fallbackColor = const Color(0xFF10B981),
  });

  final String? url;
  final double size;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();
    if (u.isEmpty) {
      return Icon(Icons.emoji_events_rounded, color: fallbackColor, size: size);
    }
    return WebSafeImage(
      url: u,
      width: size,
      height: size,
      fit: BoxFit.contain,
      fallbackIconSize: size * 0.8,
    );
  }
}
