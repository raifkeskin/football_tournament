import 'package:flutter/material.dart';

import '../../core/services/app_session.dart';
import '../../core/services/app_settings.dart';
import 'tournament_request_screen.dart';

/// "Turnuvanı Kur" girişlerinin ortak kuralları.
class TournamentRequestAccess {
  TournamentRequestAccess._();

  /// Admin her zaman görür; diğerleri admin panelindeki anahtar açıksa.
  /// Kurucu başkan görmez (zaten turnuvası var).
  static bool visible(AppSessionState s) {
    if (s.isAdmin) return true;
    if (!AppSettings.tournamentRequestsEnabled.value) return false;
    return !s.isLeagueOwner;
  }

  /// [bandBack] false: giriş ekranından (üst bant yokken) açılır.
  static Future<void> open(BuildContext context, {bool bandBack = true}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'TournamentRequestIntroScreen'),
          builder: (_) => TournamentRequestIntroScreen(bandBack: bandBack),
        ),
      );
}

const kRequestGold = Color(0xFFFBBF24);

/// Ana sayfada selamlamanın altındaki ince şerit.
class TournamentRequestStrip extends StatelessWidget {
  const TournamentRequestStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.tournamentRequestsEnabled,
      builder: (context, _, _) {
        if (!TournamentRequestAccess.visible(session)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Material(
            color: kRequestGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => TournamentRequestAccess.open(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: kRequestGold.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.emoji_events_rounded,
                      size: 18,
                      color: kRequestGold,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Turnuvanı Lig Masası\'nda kur',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      'Talep oluştur ›',
                      style: TextStyle(
                        color: kRequestGold,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Giriş ekranında formun altındaki çerçeveli kart.
class TournamentRequestLoginCard extends StatelessWidget {
  const TournamentRequestLoginCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.tournamentRequestsEnabled,
      builder: (context, on, _) {
        // Giriş ekranında oturum yok: yalnız anahtar açıksa.
        if (!on) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => TournamentRequestAccess.open(context),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kRequestGold.withValues(alpha: 0.4)),
                color: kRequestGold.withValues(alpha: 0.06),
              ),
              child: const Row(
                children: [
                  Icon(Icons.emoji_events_rounded, color: kRequestGold),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Turnuva mı düzenliyorsun?',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Lig Masası\'nda kur.',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Talep oluştur ›',
                    style: TextStyle(
                      color: kRequestGold,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
