import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class WebResponsiveFrame extends StatelessWidget {
  const WebResponsiveFrame({
    super.key,
    required this.child,
    this.maxContentWidth = 600,
    this.backgroundColor = const Color(0xFFF2F2F2),
    this.backgroundImageAsset = 'assets/acilis2.png',
    this.contentBackgroundColor,
  });

  final Widget child;
  final double maxContentWidth;
  final Color backgroundColor;
  final String backgroundImageAsset;
  final Color? contentBackgroundColor;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    final width = MediaQuery.sizeOf(context).width;
    final showBackgroundImage = width > (maxContentWidth + 80);
    final contentColor =
        contentBackgroundColor ?? Theme.of(context).scaffoldBackgroundColor;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (showBackgroundImage)
          DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(backgroundImageAsset),
                fit: BoxFit.cover,
              ),
            ),
          )
        else
          ColoredBox(color: backgroundColor),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: Material(
              color: contentColor,
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}
