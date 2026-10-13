import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/youtube_player_page.dart';

/// Bilinen video platformları: host parçası → (ad, "'da İzle" eki).
/// Listede olmayan her site de kabul edilir; yalnız adı gösterilmez.
const _platforms = <String, (String, String)>{
  'youtu': ('YouTube', "YouTube'da"),
  'instagram': ('Instagram', "Instagram'da"),
  'sosyalhalisaha': ('Sosyal Halısaha', "Sosyal Halısaha'da"),
  'tiktok': ('TikTok', "TikTok'ta"),
  'facebook': ('Facebook', "Facebook'ta"),
  'fb.watch': ('Facebook', "Facebook'ta"),
  'vimeo': ('Vimeo', "Vimeo'da"),
};

(String, String)? _platformOf(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  if (host.isEmpty) return null;
  for (final e in _platforms.entries) {
    if (host.contains(e.key)) return e.value;
  }
  return null;
}

/// Platform adı ("Sosyal Halısaha"); bilinmiyorsa null.
String? videoPlatformName(String url) => _platformOf(url)?.$1;

/// Kart düğmesi: "Sosyal Halısaha'da İzle"; bilinmiyorsa "İzle".
String videoWatchLabel(String url) {
  final p = _platformOf(url);
  return p == null ? 'İzle' : '${p.$2} İzle';
}

/// Maç videosu linkini açar:
/// - YouTube → uygulama içi oynatıcı,
/// - Instagram → Instagram uygulaması (yoksa tarayıcı),
/// - diğer her site (halısaha platformları vb.) → uygulama içi tarayıcı
///   (iOS Safari görünümü / Android Chrome sekmesi); video platformun kendi
///   oynatıcısında, reklamlarıyla birlikte oynar.
Future<void> openMatchVideo(BuildContext context, String url) async {
  final trimmed = url.trim();
  if (youtubeVideoId(trimmed) != null) {
    await openYoutubeInApp(context, trimmed);
    return;
  }
  final uri = Uri.tryParse(trimmed);
  var ok = false;
  if (uri != null) {
    try {
      if (kIsWeb) {
        ok = await launchUrl(uri, webOnlyWindowName: '_blank');
      } else if (uri.host.contains('instagram')) {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        if (!ok) {
          ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Video linki açılamadı.')));
  }
}
