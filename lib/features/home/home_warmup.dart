import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/active_tournament.dart';
import '../../core/services/app_session.dart';
import '../../core/services/service_locator.dart';
import '../../core/widgets/web_safe_image.dart';
import '../sponsors/sponsor.dart';
import '../tournament/models/league.dart';
import '../tournament/models/league_extras.dart';
import 'widgets/home_dashboard.dart';
import 'widgets/overdue_results_banner.dart';

/// Açılış ekranı görünürken ana sayfayı hazırlar: oturum, turnuva listesi,
/// pano verisi, haberler, sponsorlar ve görseller belleğe alınır. Ana sayfa
/// ilk karede dolu açılır; sonradan gelen alan ve geç oturan logo olmaz.
///
/// Açılan akışlar ana sayfa bağlanana kadar tutulur ([release]); aksi halde
/// paylaşılan akış son dinleyici gidince kapanır ve veri yeniden indirilir.
class HomeWarmup {
  HomeWarmup._();

  static final _subs = <StreamSubscription<dynamic>>[];
  static String? _uid;
  static List<League>? _leagues;
  static List<NewsItem>? _news;

  /// Hazırlanan turnuva listesi (aynı hesap için), ana sayfanın ilk karesi.
  static List<League>? get leagues => _sameUser ? _leagues : null;

  /// Hazırlanan haber akışı (aynı hesap için), haber kartının ilk karesi.
  static List<NewsItem>? get news => _sameUser ? _news : null;

  static bool get _sameUser =>
      _uid == Supabase.instance.client.auth.currentUser?.id;

  /// En fazla [limit] kadar bekler; süre dolarsa eksikler ana sayfada
  /// arkadan gelir (bağlantı yavaşken açılış takılmaz).
  static Future<void> run(
    BuildContext context,
    AppSessionController session, {
    Duration limit = const Duration(milliseconds: 2500),
  }) async {
    _uid = Supabase.instance.client.auth.currentUser?.id;
    try {
      await _run(context, session).timeout(limit);
    } catch (_) {
      // Süre doldu ya da bağlantı yok: ana sayfa kendi yükler.
    }
  }

  static Future<void> _run(
    BuildContext context,
    AppSessionController session,
  ) async {
    await _sessionReady(session);
    final leaguesF = _first(ServiceLocator.leagueService.watchLeagues());
    final newsF = _first(ServiceLocator.leagueService.watchNewsFeed());
    final leagues = _leagues = await leaguesF;
    final s = session.value;
    // Pasif turnuva admin dahil kimseye gösterilmez (verisi de gelmez).
    final visible = [
      for (final l in leagues)
        if (l.isActive) l,
    ];
    if (visible.isEmpty || !context.mounted) return;
    // Ana sayfanın seçtiği turnuva: uygulamanın büründüğü, yoksa varsayılan.
    final themed = ActiveTournament.currentLeagueId.value;
    final league = visible.firstWhere(
      (l) => l.id == themed,
      orElse: () =>
          visible.firstWhere((l) => l.isDefault, orElse: () => visible.first),
    );
    final logo = ActiveTournament.theme.value?.logoUrl ?? '';
    await Future.wait([
      HomeDashboard.warmUp(context, league, s),
      _sponsors(context, league.id),
      OverdueResultsBanner.warmUp(league.id, s),
      if (logo.trim().isNotEmpty) precacheWebSafeImage(context, logo),
      newsF.then((v) => _news = v),
    ]);
  }

  /// Ana sayfa bağlandıktan sonra açılışın akışları bırakılır.
  static void release() {
    Timer(const Duration(seconds: 5), () {
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
    });
  }

  static Future<void> _sessionReady(AppSessionController session) {
    if (!session.value.isLoading) return Future<void>.value();
    final done = Completer<void>();
    void check() {
      if (!session.value.isLoading && !done.isCompleted) done.complete();
    }

    session.addListener(check);
    return done.future.whenComplete(() => session.removeListener(check));
  }

  /// Akışın ilk değeri; dinleyici [release]'e kadar açık kalır.
  static Future<T> _first<T>(Stream<T> stream) {
    final done = Completer<T>();
    _subs.add(
      stream.listen(
        (v) {
          if (!done.isCompleted) done.complete(v);
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
      ),
    );
    return done.future;
  }

  static Future<void> _sponsors(BuildContext context, String leagueId) async {
    final feed =
        await SponsorFeed.cached(leagueId) ?? await SponsorFeed.fetch(leagueId);
    if (!context.mounted) return;
    await Future.wait([
      for (final s in feed.sponsors) precacheWebSafeImage(context, s.logoUrl),
    ]);
  }
}
