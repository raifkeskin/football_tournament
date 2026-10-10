import 'package:flutter/widgets.dart';

/// Hata kaydı için kullanıcının bulunduğu ekran: açık sayfaların adları ve
/// ana gezgindeki sekme (ör. "Profil › TeamSquadScreen › Popup").
///
/// Web derlemesinde sınıf adları sıkıştırıldığı için sayfa adı rotanın
/// `RouteSettings.name` alanından okunur; adsız sayfa "Sayfa", diyalog
/// "Popup" olarak görünür.
class ScreenTrail extends NavigatorObserver {
  ScreenTrail._();

  static final instance = ScreenTrail._();

  /// Ana gezginin seçili sekmesi (MainNavigator yazar).
  static String? tab;

  final _routes = <Route<dynamic>>[];

  static String _name(Route<dynamic> route) {
    final n = route.settings.name;
    if (n != null && n.isNotEmpty && n != '/') return n;
    return route is PopupRoute ? 'Popup' : 'Sayfa';
  }

  /// Son [depth] sayfa; ilk sayfa ana gezginse yerine sekme adı yazılır.
  static String describe({int depth = 4}) {
    final names = <String>[];
    for (final r in instance._routes) {
      final n = _name(r);
      names.add(n == 'MainNavigator' && tab != null ? tab! : n);
    }
    if (names.isEmpty && tab != null) names.add(tab!);
    final start = names.length > depth ? names.length - depth : 0;
    return names.sublist(start).join(' › ');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (newRoute == null) {
      if (i >= 0) _routes.removeAt(i);
    } else if (i >= 0) {
      _routes[i] = newRoute;
    } else {
      _routes.add(newRoute);
    }
  }
}
