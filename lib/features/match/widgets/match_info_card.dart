import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../media_credits/media_credit.dart';
import '../../media_credits/media_credit_card.dart';
import '../models/match.dart';
import 'match_weather.dart';

/// Maç detayı › Detay sekmesinin en altındaki "Maç bilgisi" kartı: tarih,
/// stat, hakem, yayıncı, fotoğrafçı ve açılır/kapanır hava durumu. Maç
/// olayları eklendikçe kart aşağı iner.
class MatchInfoCard extends StatelessWidget {
  const MatchInfoCard({super.key, required this.match});

  final MatchModel match;

  String? get _when {
    final d = DateTime.tryParse((match.matchDate ?? '').trim());
    final t = (match.matchTime ?? '').trim();
    final time = t.length >= 5 ? t.substring(0, 5) : t;
    final parts = [
      if (d != null) DateFormat('d MMMM y EEEE', 'tr_TR').format(d),
      if (time.isNotEmpty) time,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final when = _when;
    final pitch = (match.pitchName ?? '').trim();
    final referee = (match.refereeName ?? '').trim();
    final played =
        match.status == MatchStatus.live ||
        match.status == MatchStatus.halftime ||
        match.status == MatchStatus.finished;
    const gap = SizedBox(height: 10);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Maç bilgisi',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          if (when != null) ...[
            MatchInfoLine(
              icon: Icons.event_rounded,
              label: 'Tarih',
              value: when,
            ),
            gap,
          ],
          if (pitch.isNotEmpty) ...[
            MatchInfoLine(
              icon: Icons.stadium_outlined,
              label: 'Stad',
              value: pitch,
            ),
            gap,
          ],
          if (referee.isNotEmpty) ...[
            MatchInfoLine(
              icon: Icons.sports_rounded,
              label: 'Hakem',
              value: referee,
            ),
            gap,
          ],
          MediaCreditChip(
            leagueId: match.leagueId,
            kind: MediaCreditKind.broadcast,
            asRow: true,
            padding: const EdgeInsets.only(bottom: 10),
          ),
          MediaCreditChip(
            leagueId: match.leagueId,
            kind: MediaCreditKind.photo,
            asRow: true,
            padding: const EdgeInsets.only(bottom: 10),
          ),
          MatchWeatherPanel(
            matchId: match.id,
            played: played,
            embedded: true,
            kickoffLabel: (match.matchTime ?? '').trim().length >= 5
                ? match.matchTime!.trim().substring(0, 5)
                : null,
          ),
        ],
      ),
    );
  }
}
