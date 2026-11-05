import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget buildInstagramEmbed(BuildContext context, String embedUrl) =>
    _IgWebView(key: ValueKey(embedUrl), embedUrl: embedUrl);

class _IgWebView extends StatefulWidget {
  const _IgWebView({super.key, required this.embedUrl});
  final String embedUrl;

  @override
  State<_IgWebView> createState() => _IgWebViewState();
}

class _IgWebViewState extends State<_IgWebView> {
  late final WebViewController _c;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          // Gömülü sayfadaki bağlantılar (profil, "Instagram'da gör")
          // Instagram uygulamasında / tarayıcıda açılır.
          onNavigationRequest: (req) {
            if (req.url.contains('/embed')) return NavigationDecision.navigate;
            if (!req.isMainFrame) return NavigationDecision.navigate;
            launchUrl(Uri.parse(req.url), mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.embedUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _c)),
        if (_loading)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
      ],
    );
  }
}
