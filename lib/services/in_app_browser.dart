import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openInAppBrowser(BuildContext context, String rawUrl) async {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return;

  final normalized =
      trimmed.startsWith('http://') || trimmed.startsWith('https://')
          ? trimmed
          : 'https://$trimmed';

  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link geçersiz.')));
    return;
  }

  try {
    if (kIsWeb) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
      return;
    }

    final ok = await launchUrl(
      uri,
      mode: LaunchMode.inAppWebView,
      webViewConfiguration: const WebViewConfiguration(
        enableJavaScript: true,
        enableDomStorage: true,
      ),
    );
    if (!ok) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Link açılamadı: $e')));
  }
}
