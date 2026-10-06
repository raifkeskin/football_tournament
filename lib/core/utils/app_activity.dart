import 'package:flutter/widgets.dart';

/// Uygulama ön planda mı? (Web'de sekme görünür mü?)
///
/// Arka planda canlı bağlantılar kapatılır (bkz. `resilientStream`); her
/// açık uygulama Supabase'de eşzamanlı bağlantı sayılır ve bu sayı planın
/// sınırıdır. Ön plana dönünce akışlar yeniden bağlanıp taze veriyi okur.
class AppActivity with WidgetsBindingObserver {
  AppActivity._();

  static final foreground = ValueNotifier<bool>(true);

  static final _instance = AppActivity._();
  static var _started = false;

  static void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(_instance);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        foreground.value = true;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        foreground.value = false;
    }
  }
}
