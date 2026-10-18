import 'package:flutter/widgets.dart';

/// Bir sayfa ya da popup kapanınca klavye odağını bırakır. Klavye açıkken
/// kapanan popup'tan sonra işletim sistemi klavye boşluğunu bazen sıfırlamıyor;
/// alttaki ekran klavye yüksekliği kadar kısalmış kalıyordu (Android ve iOS).
class KeyboardDismissObserver extends NavigatorObserver {
  KeyboardDismissObserver._();

  static final instance = KeyboardDismissObserver._();

  void _dismiss() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _dismiss();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _dismiss();
}
