import 'dart:math' as math;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

final _registered = <String>{};

Widget buildInstagramEmbed(
  BuildContext context,
  String embedUrl, {
  bool focused = false,
}) {
  final viewType = 'ig-embed-${embedUrl.hashCode}';
  if (_registered.add(viewType)) {
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final f = web.document.createElement('iframe') as web.HTMLIFrameElement;
      f.src = embedUrl;
      f.style.border = 'none';
      f.style.width = '100%';
      f.style.height = '100%';
      f.style.background = '#000';
      f.allow = 'autoplay; encrypted-media; fullscreen';
      return f;
    });
  }
  final view = HtmlElementView(key: ValueKey(viewType), viewType: viewType);
  if (!focused) return view;
  // Kart içinde: yükseklik sınırsızsa gömülü sayfanın tamamına yetecek kadar.
  return LayoutBuilder(
    builder: (context, c) => c.hasBoundedHeight
        ? view
        : SizedBox(height: math.min(640, c.maxWidth * 1.6), child: view),
  );
}
