import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/app_session.dart';
import '../match/models/match.dart';
import '../match/screens/match_details_screen.dart';
import 'referee_service.dart';

const kRefYellow = Color(0xFFFACC15);
const kRefMuted = Color(0xFF94A3B8);
const kRefCard = Color(0xFF1E293B);

/// Hakemin maçını açar (maç detayı).
Future<void> openRefereeMatch(BuildContext context, String matchId) async {
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final isAdmin = AppSession.of(context).value.isAdmin;
  try {
    final row = await Supabase.instance.client
        .from('matches')
        .select('*, pitches(name)')
        .eq('id', matchId)
        .single();
    await nav.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'MatchDetailsScreen'),
        builder: (_) => MatchDetailsScreen(
          match: MatchModel.fromMap(
            Map<String, dynamic>.from(row)
              ..['pitch_name'] = (row['pitches'] as Map?)?['name'],
            matchId,
          ),
          isAdmin: isAdmin,
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Maç açılamadı: $e')));
  }
}

/// "Orta Hakem" / "Yardımcı" rozeti.
class RefereeRoleChip extends StatelessWidget {
  const RefereeRoleChip({super.key, required this.center, this.small = false});

  final bool center;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final color = center ? kRefYellow : const Color(0xFF38BDF8);
    final label = center
        ? (small ? 'ORTA' : 'ORTA HAKEM')
        : (small ? 'YARDIMCI' : 'YARDIMCI HAKEM');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: small ? Colors.transparent : color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: small ? color : const Color(0xFF0F172A),
          fontSize: small ? 10.5 : 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Maç listesindeki satır: gün/ay, eşleşme, saat ve turnuva, görev.
class RefereeMatchRow extends StatelessWidget {
  const RefereeMatchRow({super.key, required this.match, this.divider = true});

  final RefereeMatch match;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final d = m.start;
    final played = m.status == 'finished';
    final sub = [
      if (d != null) DateFormat('EEEE', 'tr_TR').format(d),
      ?m.timeLabel,
      m.leagueName,
    ].join(' · ');
    return InkWell(
      onTap: () => openRefereeMatch(context, m.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: divider
              ? Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Text(
                    d == null ? '–' : d.day.toString().padLeft(2, '0'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    d == null
                        ? ''
                        : DateFormat('MMM', 'tr_TR').format(d).toUpperCase(),
                    style: const TextStyle(color: kRefMuted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    played
                        ? '${m.home} ${m.homeScore ?? 0} - '
                              '${m.awayScore ?? 0} ${m.away}'
                        : '${m.home} - ${m.away}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kRefMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            RefereeRoleChip(center: m.isCenter, small: true),
          ],
        ),
      ),
    );
  }
}

/// Bölüm başlığı (büyük harf, soluk).
class RefereeSectionTitle extends StatelessWidget {
  const RefereeSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: kRefMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// "2g 7s" / "5 sa 20 dk" / "başladı".
String refereeCountdown(DateTime? start) {
  if (start == null) return '–';
  final d = start.difference(DateTime.now());
  if (d.isNegative) return 'şimdi';
  if (d.inDays >= 1) return '${d.inDays}g ${d.inHours % 24}s';
  if (d.inHours >= 1) return '${d.inHours} sa ${d.inMinutes % 60} dk';
  return '${d.inMinutes} dk';
}
