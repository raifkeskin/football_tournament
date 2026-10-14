import 'package:web/web.dart' as web;

String? inAppBrowserName() {
  final ua = web.window.navigator.userAgent;
  if (ua.contains('Instagram')) return 'Instagram';
  if (ua.contains('FBAN') || ua.contains('FBAV') || ua.contains('FB_IAB')) {
    return 'Facebook';
  }
  if (ua.contains('musical_ly') || ua.contains('BytedanceWebview')) {
    return 'TikTok';
  }
  if (ua.contains('Twitter')) return 'X';
  if (ua.contains('LinkedInApp')) return 'LinkedIn';
  if (ua.contains('Snapchat')) return 'Snapchat';
  return null;
}
