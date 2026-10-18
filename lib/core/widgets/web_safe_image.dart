import 'package:flutter/widgets.dart';

import 'web_safe_image_stub.dart'
    if (dart.library.html) 'web_safe_image_web.dart';

/// Görseli belleğe önceden yükler: sonra çizilen [WebSafeImage] ilk karede
/// hazır görünür (geç oturan logo yok). Yüklenemezse sessizce geçer.
Future<void> precacheWebSafeImage(BuildContext context, String url) {
  final u = url.trim();
  if (u.isEmpty) return Future<void>.value();
  return precacheWebSafeImageImpl(context, u);
}

class WebSafeImage extends StatelessWidget {
  const WebSafeImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.isCircle = false,
    this.fallbackIconSize,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final bool isCircle;
  final double? fallbackIconSize;

  @override
  Widget build(BuildContext context) {
    return buildWebSafeImage(
      context,
      url: url,
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
      isCircle: isCircle,
      fallbackIconSize: fallbackIconSize,
    );
  }
}
