import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

Widget buildInstagramEmbed(
  BuildContext context,
  String embedUrl, {
  bool focused = false,
}) => _IgWebView(key: ValueKey(embedUrl), embedUrl: embedUrl, focused: focused);

/// Gömülü sayfada videoyu bulur (genişliği dolduran en büyük görsel/video),
/// sayfayı ona kaydırıp kilitler, oranını bildirir ve ortasına dokunarak
/// oynatır. Instagram sayfası JavaScript ile oluştuğu için öğe gelene kadar
/// bekler; düzen değişirse (ör. oynatınca) yeniden hizalar.
const _focusScript = r'''
(function(){
  if (window.__lmFocus) return; window.__lmFocus = 1;
  var tries = 0, last = '', clicked = false;
  function media(){
    var best = null, ba = 0;
    document.querySelectorAll('video,img').forEach(function(e){
      var r = e.getBoundingClientRect();
      var a = r.width * r.height;
      if (r.width >= window.innerWidth * 0.6 && r.height > 80 && a > ba) { ba = a; best = e; }
    });
    return best;
  }
  function align(){
    var m = media();
    if (!m) {
      if (++tries < 40) return;
      clearInterval(timer); LMEmbed.postMessage('fail'); return;
    }
    var r = m.getBoundingClientRect();
    var top = r.top + window.scrollY;
    var key = (r.width / r.height).toFixed(3) + ':' + Math.round(top);
    if (key !== last) {
      last = key;
      LMEmbed.postMessage('m:' + (r.width / r.height));
    }
    window.scrollTo(0, top);
    document.documentElement.style.overflow = 'hidden';
    document.body.style.overflow = 'hidden';
    if (!clicked) {
      clicked = true;
      setTimeout(function(){
        var el = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
        if (el) el.click();
        setTimeout(function(){
          var v = document.querySelector('video');
          if (v && v.paused) { try { v.play(); } catch (e) {} }
        }, 900);
      }, 350);
    }
  }
  var timer = setInterval(align, 300);
})();
''';

class _IgWebView extends StatefulWidget {
  const _IgWebView({super.key, required this.embedUrl, required this.focused});
  final String embedUrl;
  final bool focused;

  @override
  State<_IgWebView> createState() => _IgWebViewState();
}

class _IgWebViewState extends State<_IgWebView> {
  late final WebViewController _c;
  bool _loading = true;

  /// Videonun en/boy oranı (odaklı görünüm); null: henüz ölçülmedi.
  double? _ratio;

  /// Video bulunamadı: gömülü sayfanın tamamı gösterilir.
  bool _failed = false;

  /// Kendiliğinden oynatma dokunuşu bir sayfa geçişi açarsa (Instagram
  /// bazen oynatmak yerine gönderiye gider) uygulama dışına çıkılmaz.
  DateTime? _autoTapAt;

  @override
  void initState() {
    super.initState();
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();
    _c = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('LMEmbed', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (widget.focused) {
              _c.runJavaScript(_focusScript).catchError((_) {});
            } else if (mounted) {
              setState(() => _loading = false);
            }
          },
          // Gömülü sayfadaki bağlantılar (profil, "Instagram'da gör")
          // Instagram uygulamasında / tarayıcıda açılır.
          onNavigationRequest: (req) {
            if (req.url.contains('/embed')) return NavigationDecision.navigate;
            if (!req.isMainFrame) return NavigationDecision.navigate;
            final t = _autoTapAt;
            if (t != null &&
                DateTime.now().difference(t) < const Duration(seconds: 4)) {
              return NavigationDecision.prevent;
            }
            launchUrl(Uri.parse(req.url), mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
        ),
      );
    final p = _c.platform;
    if (p is AndroidWebViewController) {
      p.setMediaPlaybackRequiresUserGesture(false);
    }
    _c.loadRequest(Uri.parse(widget.embedUrl));
    if (widget.focused) {
      // Betik hiç yanıt vermezse gömülü sayfanın tamamı gösterilir.
      Future.delayed(const Duration(seconds: 14), () {
        if (mounted && _loading) {
          setState(() {
            _failed = true;
            _loading = false;
          });
        }
      });
    }
  }

  void _onMessage(JavaScriptMessage m) {
    if (!mounted) return;
    if (m.message == 'fail') {
      setState(() {
        _failed = true;
        _loading = false;
      });
      return;
    }
    final r = double.tryParse(m.message.replaceFirst('m:', ''));
    if (r == null || r <= 0) return;
    _autoTapAt ??= DateTime.now();
    setState(() {
      _ratio = r.clamp(0.4, 2.5).toDouble();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _c)),
        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
      ],
    );
    if (!widget.focused) return view;
    return LayoutBuilder(
      builder: (context, c) {
        final maxH = c.hasBoundedHeight ? c.maxHeight : double.infinity;
        var w = c.maxWidth;
        double h;
        final r = _ratio;
        if (_failed) {
          h = math.min(maxH, w * 1.6);
        } else if (r != null) {
          h = w / r;
          if (h > maxH) {
            h = maxH;
            w = h * r;
          }
        } else {
          h = math.min(maxH, w * 1.25);
        }
        return Center(
          child: SizedBox(width: w, height: h, child: view),
        );
      },
    );
  }
}
