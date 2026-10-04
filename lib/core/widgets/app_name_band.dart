import 'package:flutter/material.dart';

import '../services/active_tournament.dart';
import 'tvl_logo.dart';
import 'web_safe_image.dart';

/// Uygulama adı.
const kAppName = 'Türk Veteranlar Ligi';

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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TvlLogo(size: 46, ringText: true),
                SizedBox(width: 12),
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
                    shadows: [Shadow(color: Color(0x66000000), blurRadius: 4)],
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
