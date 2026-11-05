import 'package:flutter/widgets.dart';

import 'instagram_embed_io.dart'
    if (dart.library.html) 'instagram_embed_web.dart';

/// Instagram gönderisi / Reels'in gömülü oynatıcısı (Instagram'ın kendi
/// embed sayfası): telefonda WebView, web'de iframe. Video Instagram'dan
/// oynar; bize trafik düşmez.
class InstagramEmbed extends StatelessWidget {
  const InstagramEmbed({super.key, required this.url});

  /// Normalleştirilmiş adres: https://www.instagram.com/{p|reel}/KOD/
  final String url;

  static String embedUrl(String url) {
    final u = url.endsWith('/') ? url : '$url/';
    return '${u}embed/';
  }

  @override
  Widget build(BuildContext context) =>
      buildInstagramEmbed(context, embedUrl(url));
}
