import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Maç önü Reels videosu (müzikli MP4) web'de üretilir: web/mac-onu.
/// Şimdilik yalnız admin görür. Uygulamada tarayıcıda açılır; video orada
/// oluşturulup paylaşım menüsüyle Instagram'a gönderilir.
const _kPreMatchVideoUrl = 'https://ligmasasi.com/mac-onu/';

/// Tek maç (Karşı Karşıya).
Future<void> openMatchPreviewVideo(String matchId) => _open({'m': matchId});

/// Turnuvanın o günkü maçları (Günün Maçları); [day] 'yyyy-MM-dd'.
Future<void> openDayPreviewVideo(String leagueId, String day) =>
    _open({'l': leagueId, 'd': day});

Future<void> _open(Map<String, String> query) async {
  final base = kIsWeb
      ? Uri.base.resolve('/mac-onu/')
      : Uri.parse(_kPreMatchVideoUrl);
  final uri = base.replace(queryParameters: query);
  if (kIsWeb) {
    await launchUrl(uri, webOnlyWindowName: '_blank');
  } else {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
