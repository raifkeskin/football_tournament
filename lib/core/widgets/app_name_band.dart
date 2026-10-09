import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  /// Giriş ekranı bandındaki ada dokunuş (gizli admin girişi için giriş
  /// ekranı verir).
  static VoidCallback? onLoginTitleTap;

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
                LeagueSwitchScope.homeTab,
                LeagueSwitchScope.calendarTab,
                LeagueSwitchScope.bandHidden,
                LeagueSwitchScope.pageBand,
                LeagueSwitchScope.tabAction,
              ]),
              builder: (context, tvlBand) {
                // Yönetim panelinde turnuva kimliği yok: uygulama bandı.
                // Giriş ekranı: rol kartlarının üstünde logo ve kısa tanıtım.
                if (genericScreens.value > 0) return _loginBand(top);
                if (LeagueSwitchScope.bandHidden.value) {
                  return SizedBox(height: top);
                }
                // Sayfa banda kendi içeriğini verdiyse (ör. Turnuva Sayfası).
                final page = LeagueSwitchScope.pageBand.value;
                if (page != null) {
                  return _TournamentBand(
                    theme: page.theme,
                    top: top,
                    leading: _BandBackButton(onTap: page.onBack),
                    trailing: page.trailing,
                  );
                }
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
                      : Positioned(
                          right: 4,
                          bottom: 3,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const LeagueSwitchButton(),
                              ?LeagueSwitchScope.tabAction.value,
                              const NotificationBell(),
                            ],
                          ),
                        );
                  if (actions == null) {
                    return Stack(
                      children: [
                        tvlBand!,
                        ?switcher,
                        if (LeagueSwitchScope.homeTab.value)
                          const Positioned(
                            left: 6,
                            bottom: 6,
                            child: BandMenuButton(),
                          ),
                      ],
                    );
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
                            if (actions.onLogout != null)
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

  Widget _loginBand(double top) => _LoginBand(top: top);

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

/// Giriş ekranı bandı: logo ve uygulama adı.
class _LoginBand extends StatelessWidget {
  const _LoginBand({required this.top});

  final double top;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(18, top + 16, 18, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B3D24), Color(0xFF0F172A)],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.15),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.asset(
                'assets/images/app_logo_sample.png',
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            // Gizli admin girişi: ada üç kez dokunmak.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => AppNameBand.onLoginTitleTap?.call(),
              child: Text(
                _trUpper(kAppName),
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontSize: 30,
                  height: 1,
                  letterSpacing: 0.8,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
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

  /// Menülü ana sekme en üstte (Ana Sayfa, Puan Durumu, Yayın Rehberi):
  /// bantta solda menü düğmesi.
  static final homeTab = ValueNotifier<bool>(false);

  /// Açık ana sekmenin bantta sağdaki düğmesi (ör. Yayın Rehberi: takvim).
  static final tabAction = ValueNotifier<Widget?>(null);

  /// En üstteki sayfanın banda verdiği içerik (ör. Turnuva Sayfası: geri,
  /// turnuva kimliği, sezon seçici). null: olağan bant.
  static final pageBand = ValueNotifier<PageBand?>(null);
  static final _pageBands = <Route<dynamic>, PageBand>{};

  /// Sayfa kendi bant içeriğini verir (null: kaldırır).
  static void setPageBand(Route<dynamic>? route, PageBand? band) {
    if (route == null) return;
    if (band == null) {
      _pageBands.remove(route);
    } else {
      _pageBands[route] = band;
    }
    _update();
  }

  /// Takvim sekmesi en üstte: turnuva bandı tamamen gizlenir.
  static final calendarTab = ValueNotifier<bool>(false);

  /// Ana gezgin çekmecesinin gerçek açılma durumu.
  static final drawerOpen = ValueNotifier<bool>(false);

  static void setDrawerOpen(bool open) {
    if (drawerOpen.value != open) drawerOpen.value = open;
  }

  /// Tam ekran detay gibi sayfalar için ortak bandı gizler.
  static final bandHidden = ValueNotifier<bool>(false);
  static final _bandHiddenRoutes = <Route<dynamic>>{};

  static void setBandHidden(Route<dynamic>? route, bool hidden) {
    if (route == null) return;
    if (hidden) {
      _bandHiddenRoutes.add(route);
    } else {
      _bandHiddenRoutes.remove(route);
    }
    _update();
  }

  /// Bantdaki menü düğmesinin açtığı / kapattığı yan menü (ana gezgin verir).
  static VoidCallback? openMenu;
  static VoidCallback? closeMenu;

  /// Menü açıksa kapatır, kapalıysa açar.
  static void toggleMenu() =>
      drawerOpen.value ? closeMenu?.call() : openMenu?.call();

  /// Kayıtlı ana gezgin sayfaları ve durumları. Girişten sonra bir an iki
  /// ana gezgin birlikte bulunabilir; eskisi kapanırken yenisinin kaydını
  /// silmesin diye her sayfa kendi kaydını tutar. Geçerli olan en üstteki.
  static final _homes =
      <
        Route<dynamic>,
        ({
          bool mainTab,
          bool panelTab,
          bool homeTab,
          bool calendarTab,
          Widget? action,
        })
      >{};

  /// Kök gezginin gözlemcisi (MaterialApp.navigatorObservers).
  static final NavigatorObserver observer = _TopPageObserver();

  /// Ana gezgin: kendi sayfası ve açık sekmenin ana sekme olup olmadığı.
  static void setHome(
    Route<dynamic>? route, {
    required bool mainTab,
    bool panelTab = false,
    bool homeTab = false,
    bool calendarTab = false,
    Widget? action,
  }) {
    if (route == null) return;
    _homes[route] = (
      mainTab: mainTab,
      panelTab: panelTab,
      homeTab: homeTab,
      calendarTab: calendarTab,
      action: action,
    );
    _update();
  }

  static void clearHome(Route<dynamic>? route) {
    if (route != null && _homes.remove(route) != null) _update();
  }

  static void _update() {
    final pageObserver = observer as _TopPageObserver;
    final top = pageObserver.topPage;
    final homeRoute = pageObserver._stack.reversed
        .cast<Route<dynamic>?>()
        .firstWhere(
          (route) => route != null && _homes.containsKey(route),
          orElse: () => null,
        );
    final home = homeRoute == null ? null : _homes[homeRoute];
    final isHomeTop = top != null && top == homeRoute;
    final v = isHomeTop && home != null && home.mainTab;
    final p = home != null && home.panelTab;
    final h = isHomeTop && home != null && home.homeTab;
    final c = isHomeTop && home != null && home.calendarTab;
    final hidden = c || (top != null && _bandHiddenRoutes.contains(top));
    final pb = top == null ? null : _pageBands[top];
    final a = isHomeTop ? home?.action : null;
    if (enabled.value == v &&
        panel.value == p &&
        homeTab.value == h &&
        calendarTab.value == c &&
        bandHidden.value == hidden &&
        pageBand.value == pb &&
        tabAction.value == a) {
      return;
    }
    // Gezinme ya da çizim sırasında bandı yeniden kurmak hata verir: çerçeve
    // bitince uygula.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _update());
      return;
    }
    enabled.value = v;
    panel.value = p;
    homeTab.value = h;
    calendarTab.value = c;
    bandHidden.value = hidden;
    pageBand.value = pb;
    tabAction.value = a;
  }
}

/// Sayfanın banda verdiği içerik: solda geri düğmesi, ortada [theme]
/// turnuvasının logosu ve adı, sağda [trailing].
@immutable
class PageBand {
  const PageBand({required this.theme, required this.onBack, this.trailing});

  final TournamentTheme theme;
  final VoidCallback onBack;
  final Widget? trailing;
}

/// Bandın kök gezgin katmanındaki konumu (bandın altında açılan listeler
/// için).
Rect? bandRectInOverlay() {
  final nav = appNavigatorKey.currentState;
  final box = _bandKey.currentContext?.findRenderObject() as RenderBox?;
  if (nav == null || box == null) return null;
  final overlayBox = nav.overlay?.context.findRenderObject() as RenderBox?;
  final topLeft = overlayBox == null
      ? box.localToGlobal(Offset.zero)
      : box.localToGlobal(Offset.zero) - overlayBox.localToGlobal(Offset.zero);
  return topLeft & box.size;
}

/// Bantta geri düğmesi (en solda).
class _BandBackButton extends StatelessWidget {
  const _BandBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: IconButton(
        onPressed: onTap,
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white,
          size: 22,
          semanticLabel: 'Geri',
        ),
      ),
    );
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
  // Liste gezginin katmanında çizilir; gezgin bandın altından başladığı
  // için bandın konumu o katmana göre hesaplanır (yoksa bant yüksekliği iki
  // kez sayılır ve liste aşağıda açılır).
  final overlayBox = nav.overlay?.context.findRenderObject() as RenderBox?;
  final topLeft = overlayBox == null
      ? box.localToGlobal(Offset.zero)
      : box.localToGlobal(Offset.zero) - overlayBox.localToGlobal(Offset.zero);
  final band = topLeft & box.size;
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
  Color? get barrierColor => Colors.black38;

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
    final maxHeight = MediaQuery.sizeOf(context).height - band.bottom - 24;
    // Bandın hemen altına yapışık, bant genişliğinde aşağı açılan liste.
    return Stack(
      children: [
        Positioned(
          top: band.bottom,
          left: band.left,
          width: band.width,
          child: SizeTransition(
            sizeFactor: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            alignment: Alignment.topCenter,
            child: Material(
              color: const Color(0xFF1E293B),
              elevation: 12,
              shadowColor: Colors.black,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    for (final l in leagues)
                      _LeagueRow(
                        league: l,
                        selected: l.id == current,
                        accent: accent,
                        // Seçince liste kapanır, turnuva değişir.
                        onTap: () => Navigator.pop(context, l.id),
                      ),
                  ],
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: league.logoUrl.isNotEmpty
                  ? WebSafeImage(
                      url: league.logoUrl,
                      width: 30,
                      height: 30,
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
/// sağda bildirim zili.
class _TournamentBand extends StatelessWidget {
  const _TournamentBand({
    required this.theme,
    required this.top,
    this.actions,
    this.leading,
    this.trailing,
  });

  final TournamentTheme theme;
  final double top;
  final BandActions? actions;

  /// Verilirse soldaki düğme (ör. geri); yoksa menü / panel düğmesi.
  final Widget? leading;

  /// Verilirse sağdaki içerik (ör. sezon seçici); yoksa bildirim zili.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Widget left =
        leading ??
        (actions != null
            ? actions!.menuButton(Colors.white)
            : LeagueSwitchScope.homeTab.value
            ? const Padding(
                padding: EdgeInsets.only(left: 6),
                child: BandMenuButton(),
              )
            : const SizedBox.shrink());
    final Widget right =
        trailing ??
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?LeagueSwitchScope.tabAction.value,
            const NotificationBell(),
            if (actions?.onLogout != null)
              actions!.logoutButton()
            else
              const SizedBox(width: 4),
          ],
        );
    // İki yan eşit genişlikte: turnuva kimliği tam ortada kalır.
    final side = trailing != null ? 112.0 : 96.0;
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
            SizedBox(
              width: side,
              child: Align(alignment: Alignment.centerLeft, child: left),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (leading == null &&
                      ActiveTournament.myLeagues.value.length > 1) {
                    showLeagueSwitcher();
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (theme.logoUrl.isNotEmpty) ...[
                      WebSafeImage(
                        url: theme.logoUrl,
                        width: 34,
                        height: 34,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        _trUpper(theme.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'BarlowCondensed',
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontSize: 16,
                          letterSpacing: 1.2,
                          decoration: TextDecoration.none,
                          shadows: [
                            Shadow(color: Color(0x66000000), blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                    if (leading == null)
                      LeagueSwitchButton(color: theme.secondary),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: side,
              child: Align(alignment: Alignment.centerRight, child: right),
            ),
          ],
        ),
      ),
    );
  }
}

/// Menü düğmesi: futbol topu. Menü açılırken top dilimlere ayrılır
/// (hamburger), sonra dilimler X olur; X'e basınca menü kapanır ve top
/// yeniden birleşir.
class BandMenuButton extends StatefulWidget {
  const BandMenuButton({super.key, this.size = 40});

  final double size;

  @override
  State<BandMenuButton> createState() => _BandMenuButtonState();
}

class _BandMenuButtonState extends State<BandMenuButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 560),
    vsync: this,
  );
  static ui.Image? _ballImage;

  @override
  void initState() {
    super.initState();
    LeagueSwitchScope.drawerOpen.addListener(_syncDrawerState);
    _controller.value = LeagueSwitchScope.drawerOpen.value ? 1 : 0;
    if (_ballImage == null) _loadBallImage();
  }

  Future<void> _loadBallImage() async {
    try {
      final data = await rootBundle.load('assets/images/menu_soccer_ball.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      _ballImage ??= frame.image;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _syncDrawerState() {
    if (LeagueSwitchScope.drawerOpen.value) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    LeagueSwitchScope.drawerOpen.removeListener(_syncDrawerState);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = LeagueSwitchScope.drawerOpen.value;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: LeagueSwitchScope.toggleMenu,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Semantics(
            button: true,
            label: isOpen ? 'Menüyü kapat' : 'Menüyü aç',
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _BallMenuPainter(
                  progress: _controller.value,
                  ballImage: _ballImage,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uygulamanın yuvarlak üst çubuk düğmesi (menü topuyla aynı görünüm):
/// yarı saydam zemin, yeşil ince kenar, beyaz ikon.
class BandIconButton extends StatelessWidget {
  const BandIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: _BallMenuPainter.glow.withValues(alpha: 0.55),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: _BallMenuPainter.glow.withValues(alpha: 0.25),
                blurRadius: 8,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.5),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// Topun dilimleri: üst kapak, orta kuşak, alt kapak. [progress] 0: top
/// (ince kesik çizgilerle), ~0.45: dilimler ayrık (hamburger), 1: üst ve alt
/// dilim çapraz çubuklara dönüşüp X olur, orta dilim kaybolur.
class _BallMenuPainter extends CustomPainter {
  const _BallMenuPainter({required this.progress, required this.ballImage});

  final double progress;
  final ui.Image? ballImage;

  static const glow = Color(0xFF34D399);
  static const _gold = Color(0xFFFBBF24);

  static double _ease(double v) {
    final t = v.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.42;
    final split = _ease(progress / 0.45);
    final morph = _ease((progress - 0.45) / 0.55);
    // Dilim aralığı: dururken ince kesik, açılırken belirgin.
    final gap = _lerp(0.7, r * 0.2, split);

    void piece({
      required double sliceTop,
      required double sliceBottom,
      required double shift,
      required double angle,
      required double alpha,
      required double barScale,
    }) {
      if (alpha <= 0) return;
      final sliceCenter = (sliceTop + sliceBottom) / 2;
      final sliceH = sliceBottom - sliceTop;
      // Dilimden çubuğa: merkez, boy, en ve açı birlikte değişir.
      final cy = _lerp(c.dy + sliceCenter + shift, c.dy, morph);
      final w = _lerp(r * 2, r * 2.25, morph) * barScale;
      final h = _lerp(sliceH, r * 0.52, morph);
      canvas.save();
      canvas.translate(c.dx, cy);
      canvas.rotate(angle * morph);
      final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
      final bar = Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(2 * morph)));
      // Topun yuvarlağı: çubuğa dönerken büyüyerek kaybolur.
      final ballCenter = Offset(0, _lerp(-sliceCenter, 0, morph));
      final circle = Path()
        ..addOval(
          Rect.fromCircle(center: ballCenter, radius: _lerp(r, r * 4, morph)),
        );
      final shape = Path.combine(PathOperation.intersect, bar, circle);

      // Dış parıltı.
      canvas.drawPath(
        shape,
        Paint()
          ..color = glow.withValues(alpha: 0.55 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 2.2),
      );
      canvas.save();
      canvas.clipPath(shape);
      final img = ballImage;
      final imgSize = _lerp(r * 2, r * 2.4, morph);
      final dst = Rect.fromCenter(
        center: ballCenter,
        width: imgSize,
        height: imgSize,
      );
      if (img != null) {
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          dst,
          Paint()
            ..filterQuality = FilterQuality.high
            ..color = Colors.white.withValues(alpha: alpha),
        );
      } else {
        canvas.drawRect(
          rect.inflate(r),
          Paint()..color = Colors.white.withValues(alpha: alpha),
        );
      }
      canvas.restore();
      // Kenar: yeşil, açılırken kesik yüzeylerde altın parıltı.
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = Color.lerp(
            glow,
            _gold,
            split * (1 - morph) * 0.7,
          )!.withValues(alpha: 0.9 * alpha),
      );
      canvas.restore();
    }

    // Orta kuşak (X olurken kaybolur ve daralır).
    piece(
      sliceTop: -r / 3 + gap / 2,
      sliceBottom: r / 3 - gap / 2,
      shift: 0,
      angle: 0,
      alpha: 1 - morph,
      barScale: 1 - morph * 0.6,
    );
    // Üst kapak → "\" çubuğu, alt kapak → "/" çubuğu.
    piece(
      sliceTop: -r,
      sliceBottom: -r / 3 - gap / 2,
      shift: -gap * 0.6,
      angle: 0.785398,
      alpha: 1,
      barScale: 1,
    );
    piece(
      sliceTop: r / 3 + gap / 2,
      sliceBottom: r,
      shift: gap * 0.6,
      angle: -0.785398,
      alpha: 1,
      barScale: 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BallMenuPainter oldDelegate) =>
      progress != oldDelegate.progress || ballImage != oldDelegate.ballImage;
}

/// Türkçe büyük harf (Dart'ın toUpperCase'i i → I yapar, İ değil).
String _trUpper(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Bantta yönetim paneli düğmeleri.
@immutable
class BandActions {
  const BandActions({required this.onMenu, this.onLogout, this.onHome});

  final VoidCallback onMenu;

  /// null: çıkış düğmesi yok (yalnız ev düğmesi isteyen alt sayfalar).
  final VoidCallback? onLogout;

  /// Verilirse soldaki düğme ev ikonu olur ve ana sayfaya döner.
  final VoidCallback? onHome;

  // Bant gezginin dışında: düğmeler için şeffaf Material gerekir.
  Widget menuButton(Color color) => Material(
    type: MaterialType.transparency,
    child: IconButton(
      // Tooltip yok: bant Overlay'in dışında.
      onPressed: onHome ?? onMenu,
      icon: onHome != null
          ? Icon(Icons.home_rounded, color: color, semanticLabel: 'Ana Sayfa')
          : Icon(Icons.menu_rounded, color: color, semanticLabel: 'Menü'),
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
