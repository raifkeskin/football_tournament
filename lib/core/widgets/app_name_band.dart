import 'package:flutter/material.dart';

import '../app_navigator.dart';
import '../services/active_tournament.dart';
import 'tvl_logo.dart';
import 'web_safe_image.dart';

/// Uygulama adı.
const kAppName = 'Türk Veteranlar Ligi';

/// Uygulama adı ekranlarda (bant, menü, açılış, logo halkası, afiş) görünsün
/// mü? Geçici olarak kapalı; açmak için true yapmak yeterli.
const kShowAppName = false;

/// Tüm ekranların en üstündeki uygulama adı bandı. Durum çubuğu boşluğunu
/// bant üstlenir; altındaki ekranlara üst boşluk verilmez (çift boşluk
/// olmasın).
class AppNameBand extends StatelessWidget {
  const AppNameBand({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          // Kişinin turnuvası temalıysa bant o turnuvanın kimliğiyle.
          ValueListenableBuilder<TournamentTheme?>(
            valueListenable: ActiveTournament.theme,
            builder: (context, t, tvlBand) =>
                t == null ? tvlBand! : _TournamentBand(theme: t, top: top),
            child: _tvlBand(top),
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
                      TvlLogo(size: 46, ringText: true),
                      if (kShowAppName) SizedBox(width: 12),
                      if (kShowAppName)
                        Text(
                          'TÜRK VETERANLAR LİGİ',
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
                // Kişinin birden fazla turnuvası varsa (teması olmayan
                // turnuvadayken de) sağda seçici.
                Positioned(
                  right: 10,
                  top: 0,
                  bottom: 0,
                  child: Center(child: LeagueSwitchButton()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Bant seçicisi: kişinin birden fazla turnuvası varsa ▾ düğmesi; dokununca
/// turnuva listesi açılır. Tek turnuvada hiçbir şey çizmez.
class LeagueSwitchButton extends StatelessWidget {
  const LeagueSwitchButton({super.key, this.color = Colors.white});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<LeagueChoice>>(
      valueListenable: ActiveTournament.myLeagues,
      builder: (context, leagues, _) {
        if (leagues.length < 2) return const SizedBox.shrink();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showLeagueSwitcher(),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: color,
              size: 26,
              semanticLabel: 'Turnuva değiştir',
            ),
          ),
        );
      },
    );
  }
}

/// Turnuva listesi (bant ve menü kullanır). Seçim: tema, ortak filtre ve
/// cihazdaki tercih birlikte değişir.
Future<void> showLeagueSwitcher() async {
  final ctx = appNavigatorKey.currentContext;
  if (ctx == null) return;
  final leagues = ActiveTournament.myLeagues.value;
  final current = ActiveTournament.currentLeagueId.value;
  final picked = await showModalBottomSheet<String>(
    context: ctx,
    backgroundColor: const Color(0xFF1E293B),
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheet).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Turnuva seç',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final l in leagues)
              ListTile(
                leading: SizedBox(
                  width: 40,
                  height: 40,
                  child: l.logoUrl.isEmpty
                      ? const Icon(
                          Icons.emoji_events_outlined,
                          color: Colors.white70,
                        )
                      : WebSafeImage(
                          url: l.logoUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.contain,
                        ),
                ),
                title: Text(
                  l.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                trailing: l.id == current
                    ? const Icon(Icons.check_rounded, color: Color(0xFF10B981))
                    : null,
                onTap: () => Navigator.pop(sheet, l.id),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || picked == current) return;
  await ActiveTournament.choose(picked);
}

/// Turnuva kimliğiyle bant: turnuvanın renkleri, solda logosu, yanında adı;
/// sağda küçük TVL işareti (uygulama markası kaybolmaz).
class _TournamentBand extends StatelessWidget {
  const _TournamentBand({required this.theme, required this.top});

  final TournamentTheme theme;
  final double top;

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
                child: const TvlLogo(size: 26, ringText: false),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// Türkçe büyük harf (Dart'ın toUpperCase'i i → I yapar, İ değil).
String _trUpper(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
