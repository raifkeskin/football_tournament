import 'in_app_browser_stub.dart'
    if (dart.library.js_interop) 'in_app_browser_web.dart'
    as impl;

/// Web sayfası Instagram, Facebook vb. uygulamaların içindeki tarayıcıda
/// açıldıysa o uygulamanın adı; değilse (ya da uygulamada) `null`.
/// Bu tarayıcılar dosya indirmeye izin vermez.
String? inAppBrowserName() => impl.inAppBrowserName();
