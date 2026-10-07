import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_navigator.dart';
import '../services/active_tournament.dart';
import 'app_logo.dart';
import 'notification_bell.dart';
import 'web_safe_image.dart';

/// Uygulama adı.
const kAppName = 'Lig Masası';

/// Uygulama adı ekranlarda (bant, menü, açılış, logo halkası, afiş) görünsün
/// mü? Geçici olarak kapalı; açmak için true yapmak yeterli.
const kShowAppName = false;

/// Tüm ekranların en üstündeki uygulama adı bandı. Durum çubuğu boşluğunu
/// bant üstlenir; altındaki ekranlara üst boşluk verilmez (çift boşluk
/// olmasın).
class AppNameBand extends StatelessWidget {
  const AppNameBand({super.key, required this.child});

  final Widget child;

  /// Açık olan "genel bant" ekranlarının sayısı (giriş ekranı). Sıfırdan
  /// büyükse bantta turnuva kimliği gösterilmez.
  static final genericScreens = ValueNotifier<int>(0);

  /// Yönetim paneli açıkken bantta solda menü, sağda çıkış düğmesi
  /// (panelin ayrı başlık çubuğu yok). null: düğme yok.
  static final panelActions = ValueNotifier<BandActions?>(null);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          // Kişinin turnuvası temalıysa bant o turnuvanın kimliğiyle.
          KeyedSubtree(
            key: _bandKey,
            child: ListenableBuilder(
              listenable: Listenable.merge([
                ActiveTournament.theme,
                genericScreens,
                panelActions,
                LeagueSwitchScope.panel,
              ]),
              builder: (context, tvlBand) {
                // Yönetim panelinde turnuva kimliği yok: uygulama bandı.
                final t = LeagueSwitchScope.panel.value
                    ? null
                    : ActiveTournament.theme.value;
                final actions = genericScreens.value > 0
                    ? null
                    : panelActions.value;
                if (t == null || genericScreens.value > 0) {
                  // Turnuva seçilmemişse de kişinin turnuvaları arasında
                  // geçiş yapılabilsin (giriş ekranında değil).
                  final switcher = genericScreens.value > 0
                      ? null
                      : const Positioned(
                          right: 4,
                          bottom: 3,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LeagueSwitchButton(),
                              NotificationBell(),
                            ],
                          ),
                        );
                  if (actions == null) {
                    return switcher == null
                        ? tvlBand!
                        : Stack(children: [tvlBand!, switcher]);
                  }
                  return Stack(
                    children: [
                      tvlBand!,
                      Positioned(
                        left: 4,
                        bottom: 3,
                        child: actions.menuButton(Colors.white),
                      ),
                      Positioned(
                        right: 4,
                        bottom: 3,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const NotificationBell(),
                            actions.logoutButton(),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                return _TournamentBand(theme: t, top: top, actions: actions);
              },
              child: _tvlBand(top),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tvlBand(double top) {
    return Column(
      children: [
        // Yeşil bant: solda logo (yazıdan büyük), yanında uygulama adı.
        // Yazı tipi uygulamaya gömülü (pubspec fonts).
        Container(
          padding: EdgeInsets.only(top: top),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF064E3B), Color(0xFF10B981), Color(0xFF064E3B)],
            ),
            border: Border(bottom: BorderSide(color: Colors.white, width: 1.5)),
          ),
          child: const SizedBox(
            height: 50,
            child: Stack(
              children: [
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AppLogo(size: 40),
                      if (kShowAppName) SizedBox(width: 12),
                      if (kShowAppName)
                        Text(
                          'LİG MASASI',
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'BarlowCondensed',
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontSize: 18,
                            letterSpacing: 2.6,
                            decoration: TextDecoration.none,
                            shadows: [
                              Shadow(color: Color(0x66000000), blurRadius: 4),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Turnuva seçicisi yalnızca ana sekmelerde (Ana Sayfa, Haberler, Fikstür,
/// Puan Durumu, İstatistik) görünür. Üstüne açılan sayfalarda (takım kadrosu,
/// maç detayı, yönetim ekranları) ve Profil / yönetim panelinde turnuva
/// değiştirmek ekrandakini değiştirmediği için gizlenir.
class LeagueSwitchScope {
  LeagueSwitchScope._();

  static final enabled = ValueNotifier<bool>(false);

  /// Yönetim paneli (ve üstüne açılan yönetim ekranları): bant turnuva
  /// kimliği yerine uygulama bandını gösterir; panel tüm turnuvaları yönetir.
  static final panel = ValueNotifier<bool>(false);

  static Route<dynamic>? _homeRoute;
  static var _mainTab = false;

  /// Kök gezginin gözlemcisi (MaterialApp.navigatorObservers).
  static final NavigatorObserver observer = _TopPageObserver();

  /// Ana gezgin: kendi sayfası ve açık sekmenin ana sekme olup olmadığı.
  static void setHome(
    Route<dynamic>? route, {
    required bool mainTab,
    bool panelTab = false,
  }) {
    _homeRoute = route;
    _mainTab = mainTab;
    _panelTab = panelTab;
    _update();
  }

  static void clearHome(Route<dynamic>? route) {
    if (route != null && _homeRoute == route) {
      _homeRoute = null;
      _panelTab = false;
      _update();
    }
  }

  static var _panelTab = false;

  static void _update() {
    final home = _homeRoute;
    final v =
        home != null &&
        _mainTab &&
        (observer as _TopPageObserver).topPage == home;
    final p = home != null && _panelTab;
    if (enabled.value == v && panel.value == p) return;
    // Gezinme ya da çizim sırasında bandı yeniden kurmak hata verir: çerçeve
    // bitince uygula.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _update());
      return;
    }
    enabled.value = v;
    panel.value = p;
  }
}

/// En üstteki tam sayfayı izler (açılır pencereler / diyaloglar sayılmaz).
class _TopPageObserver extends NavigatorObserver {
  final _stack = <Route<dynamic>>[];

  Route<dynamic>? get topPage {
    for (var i = _stack.length - 1; i >= 0; i--) {
      if (_stack[i] is PageRoute) return _stack[i];
    }
    return null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    LeagueSwitchScope._update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    LeagueSwitchScope._update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    LeagueSwitchScope._update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (newRoute != null) {
      if (i >= 0) {
        _stack[i] = newRoute;
      } else {
        _stack.add(newRoute);
      }
    } else if (i >= 0) {
      _stack.removeAt(i);
    }
    LeagueSwitchScope._update();
  }
}

/// Bandın konumu (açılır liste bandın hemen altına yerleşir).
final _bandKey = GlobalKey();

/// Açılır liste açıkken ok yukarı döner.
final _switcherOpen = ValueNotifier<bool>(false);

/// Bant seçicisi: kişinin birden fazla turnuvası varsa ▾ düğmesi; dokununca
/// bandın altında turnuva listesi açılır. Tek turnuvada hiçbir şey çizmez.
class LeagueSwitchButton extends StatelessWidget {
  const LeagueSwitchButton({super.key, this.color = Colors.white});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ActiveTournament.myLeagues,
        LeagueSwitchScope.enabled,
      ]),
      builder: (context, _) {
        if (ActiveTournament.myLeagues.value.length < 2 ||
            !LeagueSwitchScope.enabled.value) {
          return const SizedBox.shrink();
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showLeagueSwitcher(),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: ValueListenableBuilder<bool>(
              valueListenable: _switcherOpen,
              builder: (context, open, _) => AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: color,
                  size: 26,
                  semanticLabel: 'Turnuva değiştir',
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Turnuva listesi: bandın hemen altında, sağa yaslı açılır kart. Seçim:
/// tema, ortak filtre ve cihazdaki tercih birlikte değişir.
Future<void> showLeagueSwitcher() async {
  final nav = appNavigatorKey.currentState;
  final box = _bandKey.currentContext?.findRenderObject() as RenderBox?;
  if (nav == null ||
      box == null ||
      _switcherOpen.value ||
      !LeagueSwitchScope.enabled.value) {
    return;
  }
  final band = box.localToGlobal(Offset.zero) & box.size;
  _switcherOpen.value = true;
  final picked = await nav.push<String>(_LeagueDropdownRoute(band: band));
  _switcherOpen.value = false;
  if (picked == null || picked == ActiveTournament.currentLeagueId.value) {
    return;
  }
  await ActiveTournament.choose(picked);
}

class _LeagueDropdownRoute extends PopupRoute<String> {
  _LeagueDropdownRoute({required this.band});

  final Rect band;

  @override
  Color? get barrierColor => Colors.black45;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Kapat';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final leagues = ActiveTournament.myLeagues.value;
    final current = ActiveTournament.currentLeagueId.value;
    final accent =
        ActiveTournament.theme.value?.secondary ?? const Color(0xFF10B981);
    final width = (band.width - 24).clamp(0.0, 340.0);
    final maxHeight = MediaQuery.sizeOf(context).height - band.bottom - 24;
    return Stack(
      children: [
        Positioned(
          top: band.bottom + 6,
          right: MediaQuery.sizeOf(context).width - band.right + 12,
          width: width,
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              alignment: Alignment.topRight,
              scale: Tween<double>(begin: 0.92, end: 1).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: Material(
                color: const Color(0xFF1E293B),
                elevation: 12,
                shadowColor: Colors.black,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                        child: Text(
                          ActiveTournament.isRealUser
                              ? 'TURNUVALARIM'
                              : 'TURNUVALAR',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      for (final l in leagues)
                        _LeagueRow(
                          league: l,
                          selected: l.id == current,
                          accent: accent,
                          onTap: () => Navigator.pop(context, l.id),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeagueRow extends StatelessWidget {
  const _LeagueRow({
    required this.league,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final LeagueChoice league;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initials = league.name.trim().isEmpty
        ? '?'
        : _trUpper(
            league.name.trim().split(RegExp(r'\s+')).first,
          ).characters.take(2).toString();
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: league.logoUrl.isNotEmpty
                  ? WebSafeImage(
                      url: league.logoUrl,
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                    )
                  : Container(
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF475569),
                      ),
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontFamily: 'BarlowCondensed',
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                league.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            if (selected) Icon(Icons.check_rounded, color: accent, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Turnuva kimliğiyle bant: turnuvanın renkleri, solda logosu, yanında adı;
/// sağda küçük Lig Masası işareti (uygulama markası kaybolmaz).
class _TournamentBand extends StatelessWidget {
  const _TournamentBand({required this.theme, required this.top, this.actions});

  final TournamentTheme theme;
  final double top;
  final BandActions? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.primaryDark, theme.primary, theme.primaryDark],
        ),
        border: Border(bottom: BorderSide(color: theme.secondary, width: 2)),
      ),
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            if (actions != null)
              actions!.menuButton(Colors.white)
            else
              const SizedBox(width: 12),
            if (theme.logoUrl.isNotEmpty)
              WebSafeImage(
                url: theme.logoUrl,
                width: 44,
                height: 44,
                fit: BoxFit.contain,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (ActiveTournament.myLeagues.value.length > 1) {
                    showLeagueSwitcher();
                  }
                },
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        _trUpper(theme.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'BarlowCondensed',
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontSize: 19,
                          letterSpacing: 1.8,
                          decoration: TextDecoration.none,
                          shadows: const [
                            Shadow(color: Color(0x66000000), blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                    LeagueSwitchButton(color: theme.secondary),
                  ],
                ),
              ),
            ),
            Opacity(
              opacity: 0.85,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.secondary, width: 1.5),
                ),
                child: const AppLogo(size: 26),
              ),
            ),
            const SizedBox(width: 2),
            const NotificationBell(),
            if (actions != null)
              actions!.logoutButton()
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// Türkçe büyük harf (Dart'ın toUpperCase'i i → I yapar, İ değil).
String _trUpper(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Bantta yönetim paneli düğmeleri.
@immutable
class BandActions {
  const BandActions({required this.onMenu, required this.onLogout});

  final VoidCallback onMenu;
  final VoidCallback onLogout;

  // Bant gezginin dışında: düğmeler için şeffaf Material gerekir.
  Widget menuButton(Color color) => Material(
    type: MaterialType.transparency,
    child: IconButton(
      // Tooltip yok: bant Overlay'in dışında.
      onPressed: onMenu,
      icon: Icon(Icons.menu_rounded, color: color, semanticLabel: 'Menü'),
    ),
  );

  Widget logoutButton() => Material(
    type: MaterialType.transparency,
    child: IconButton(
      onPressed: onLogout,
      icon: const Icon(
        Icons.logout_rounded,
        color: Color(0xFFF87171),
        semanticLabel: 'Çıkış Yap',
      ),
    ),
  );
}
