import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

final Map<String, String> _viewTypeByKey = {};

Widget buildWebSafeImage(
  BuildContext context, {
  required String url,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  BorderRadius? borderRadius,
  bool isCircle = false,
  double? fallbackIconSize,
}) {
  final trimmed = url.trim();
  final fallback = Icon(
    Icons.shield,
    color: Colors.grey,
    size: fallbackIconSize,
  );

  if (trimmed.isEmpty) {
    return SizedBox(
      width: width,
      height: height,
      child: Center(child: fallback),
    );
  }

  final fitCss = switch (fit) {
    BoxFit.contain => 'contain',
    BoxFit.fill => 'fill',
    BoxFit.fitHeight => 'contain',
    BoxFit.fitWidth => 'contain',
    BoxFit.none => 'none',
    BoxFit.scaleDown => 'scale-down',
    _ => 'cover',
  };

  final radiusPx =
      isCircle ? 9999 : (borderRadius?.topLeft.x ?? 0).toDouble();
  final w = (width ?? 0).toDouble();
  final h = (height ?? 0).toDouble();

  final key = '$trimmed|$w|$h|$fitCss|$radiusPx|$isCircle';
  final viewType =
      _viewTypeByKey[key] ??= 'websafeimg_${_viewTypeByKey.length}_${key.hashCode}';

  try {
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final container = html.DivElement();
      container.style.width = w > 0 ? '${w}px' : '100%';
      container.style.height = h > 0 ? '${h}px' : '100%';
      container.style.overflow = 'hidden';
      container.style.borderRadius = '${radiusPx}px';

      final img = html.ImageElement();
      img.src = trimmed;
      img.style.width = '100%';
      img.style.height = '100%';
      img.style.objectFit = fitCss;
      img.style.border = '0';
      img.onError.listen((_) {
        img.style.display = 'none';
      });
      container.append(img);
      return container;
    });
  } catch (_) {}

  return SizedBox(
    width: width,
    height: height,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Center(child: fallback),
        HtmlElementView(viewType: viewType),
      ],
    ),
  );
}
