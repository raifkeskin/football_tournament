import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../core/app_navigator.dart';
import '../../core/widgets/admin_page.dart';

/// Maç önü Reels videosu (müzikli MP4) web/mac-onu sayfasında üretilir.
/// Şimdilik yalnız admin görür. Uygulamada sayfa uygulamanın içinde açılır:
/// önizleme, kaydet (galeri) ve paylaş (paylaşım menüsü) uygulama içinde
/// kalır. Web'de yeni sekmede açılır.
const _kPreMatchVideoUrl = 'https://ligmasasi.com/mac-onu/';

/// Tek maç (Karşı Karşıya).
Future<void> openMatchPreviewVideo(String matchId) => _open({'m': matchId});

/// Turnuvanın o günkü maçları (Günün Maçları); [day] 'yyyy-MM-dd'.
Future<void> openDayPreviewVideo(String leagueId, String day) =>
    _open({'l': leagueId, 'd': day});

/// Özel liglerin verisi yalnız giriş yapmış kullanıcıya açık; oturum anahtarı
/// adres parçasıyla (sunucuya gitmez) sayfaya verilir.
Uri _uri(Map<String, String> query) {
  final base = kIsWeb
      ? Uri.base.resolve('/mac-onu/')
      : Uri.parse(_kPreMatchVideoUrl);
  final token = Supabase.instance.client.auth.currentSession?.accessToken;
  final uri = base.replace(queryParameters: query);
  return token == null ? uri : uri.replace(fragment: 't=$token');
}

Future<void> _open(Map<String, String> query) async {
  final uri = _uri(query);
  if (kIsWeb) {
    await launchUrl(uri, webOnlyWindowName: '_blank');
    return;
  }
  await appNavigatorKey.currentState?.push(
    MaterialPageRoute<void>(builder: (_) => _PreMatchVideoScreen(uri: uri)),
  );
}

class _PreMatchVideoScreen extends StatefulWidget {
  const _PreMatchVideoScreen({required this.uri});
  final Uri uri;

  @override
  State<_PreMatchVideoScreen> createState() => _PreMatchVideoScreenState();
}

class _PreMatchVideoScreenState extends State<_PreMatchVideoScreen> {
  late final WebViewController _c;
  bool _loading = true;

  // Sayfadan parça parça gelen video.
  String? _id, _action, _name;
  List<String?> _parts = const [];

  @override
  void initState() {
    super.initState();
    final params = defaultTargetPlatform == TargetPlatform.iOS
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const {},
          )
        : const PlatformWebViewControllerCreationParams();
    _c = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B1220))
      ..addJavaScriptChannel(
        'LmApp',
        onMessageReceived: (m) => _onMessage(m.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(widget.uri);
    final p = _c.platform;
    if (p is AndroidWebViewController) {
      p.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  void _say(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t),
        backgroundColor: error ? const Color(0xFFB91C1C) : null,
      ),
    );
  }

  Future<void> _onMessage(String raw) async {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      switch (m['t']) {
        case 'copy':
          await Clipboard.setData(ClipboardData(text: '${m['text']}'));
        case 'begin':
          _id = '${m['id']}';
          _action = '${m['action']}';
          _name = '${m['name']}';
          _parts = List<String?>.filled((m['n'] as num).toInt(), null);
        case 'chunk':
          if ('${m['id']}' == _id) {
            _parts[(m['i'] as num).toInt()] = '${m['d']}';
          }
        case 'end':
          if ('${m['id']}' != _id || _parts.any((e) => e == null)) {
            _say('Video aktarılamadı, yeniden dene.', error: true);
            return;
          }
          final bytes = base64Decode(_parts.join());
          _parts = const [];
          await _deliver(bytes, _action ?? 'save', _name ?? 'mac-onu.mp4');
      }
    } catch (e) {
      _say('İşlem yapılamadı: $e', error: true);
    }
  }

  Future<void> _deliver(Uint8List bytes, String action, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    if (action == 'share') {
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      return;
    }
    try {
      if (!await Gal.hasAccess(toAlbum: false)) {
        await Gal.requestAccess(toAlbum: false);
      }
      await Gal.putVideo(file.path);
      _say('Video galeriye kaydedildi.');
    } on GalException catch (e) {
      _say(
        e.type == GalExceptionType.accessDenied
            ? 'Galeriye kaydetmek için izin gerekli.'
            : 'Kaydedilemedi: ${e.type.message}',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Maç Önü Videosu',
      body: Stack(
        children: [
          WebViewWidget(controller: _c),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
