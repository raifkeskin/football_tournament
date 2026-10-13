import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class WebResponsiveFrame extends StatelessWidget {
  const WebResponsiveFrame({
    super.key,
    required this.child,
    this.maxContentWidth = 600,
    // Uygulamanın koyu zemininden (0xFF0F172A) bir ton koyu; geniş ekranda
    // içerik sütunu kenarlardan ayrışsın diye.
    this.backgroundColor = const Color(0xFF020617),
    this.contentBackgroundColor,
  });

  final Widget child;
  final double maxContentWidth;
  final Color backgroundColor;
  final Color? contentBackgroundColor;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    final width = MediaQuery.sizeOf(context).width;
    final showSideBorders = width > maxContentWidth;
    final contentColor =
        contentBackgroundColor ?? Theme.of(context).scaffoldBackgroundColor;

    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: showSideBorders
                  ? const Border.symmetric(
                      vertical: BorderSide(color: Color(0xFF1E293B)),
                    )
                  : null,
            ),
            child: Material(color: contentColor, child: child),
          ),
        ),
      ),
    );
  }
}
