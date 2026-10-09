import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/table_feed.dart';
import '../../team/models/team.dart';
import '../../tournament/models/league.dart';
import '../models/match.dart';
import 'match_details_screen.dart';

/// Yayın Rehberi: bugün, görülebilen turnuvalarda yayın linki eklenmiş
/// maçlar, saat sırasıyla. Biten (MS) maçlar gri; dokununca maç detayı.
class BroadcastGuideScreen extends StatefulWidget {
  const BroadcastGuideScreen({super.key});

  @override
  State<BroadcastGuideScreen> createState() => _BroadcastGuideScreenState();
}

class _BroadcastGuideScreenState extends State<BroadcastGuideScreen> {
  static const _bg = Color(0xFF0F172A);
  static const _card = Color(0xFF1E293B);

  late final Stream<List<League>> _leagues = ServiceLocator.leagueService
      .watchLeagues();
  late final Stream<List<Team>> _teams = ServiceLocator.teamService
      .watchAllTeams();

  late final DateTime _today = DateTime.now();
  late final String _todayKey = DateFormat('yyyy-MM-dd').format(_today);

  /// Bugünün maçları; yalnızca yayın linki olanlar.
  late final Stream<List<MatchModel>> _matches =
      watchTableRows(
        Supabase.instance.client,
        table: 'matches',
        column: 'match_date',
        value: _todayKey,
      ).asyncMap((rows) async {
        final matches = [
          for (final r in rows)
            MatchModel.fromMap(r, (r['id'] ?? '').toString()),
        ];
        if (matches.isEmpty) return matches;
        final media = await Supabase.instance.client
            .from('match_media')
            .select('match_id, url')
            .eq('media_type', 'Maç Yayın Linki')
            .inFilter('match_id', [for (final m in matches) m.id]);
        final withLink = {
          for (final r in media)
            if ((r['url'] ?? '').toString().trim().isNotEmpty)
              (r['match_id'] ?? '').toString(),
        };
        return matches.where((m) => withLink.contains(m.id)).toList()..sort(
          (a, b) => (a.matchTime ?? '99').compareTo(b.matchTime ?? '99'),
        );
      });

  @override
  Widget build(BuildContext context) {
    // Başlık yok: menü düğmesi ve turnuva kimliği üst bantta.
    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<List<League>>(
        stream: _leagues,
        builder: (context, leagueSnap) {
          final leagueName = {
            for (final l in leagueSnap.data ?? const <League>[]) l.id: l.name,
          };
          return StreamBuilder<List<Team>>(
            stream: _teams,
            builder: (context, teamSnap) {
              final teamName = {
                for (final t in teamSnap.data ?? const <Team>[]) t.id: t.name,
              };
              return StreamBuilder<List<MatchModel>>(
                stream: _matches,
                builder: (context, snap) {
                  if (!snap.hasData || !leagueSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  // Yalnızca kişinin görebildiği (aktif) turnuvalar.
                  final matches = [
                    for (final m in snap.data!)
                      if (leagueName.containsKey(m.leagueId)) m,
                  ];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 120),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              color: Colors.white.withValues(alpha: 0.05),
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                12,
                              ),
                              child: Text(
                                DateFormat(
                                  'dd MMMM EEEE',
                                  'tr_TR',
                                ).format(_today),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (matches.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: 36,
                                  horizontal: 16,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.live_tv_rounded,
                                      size: 44,
                                      color: Colors.white24,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Bugün canlı yayın maçı bulunmuyor.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              for (var i = 0; i < matches.length; i++)
                                _BroadcastRow(
                                  match: matches[i],
                                  homeName:
                                      teamName[matches[i].homeTeamId] ??
                                      'Ev Sahibi',
                                  awayName:
                                      teamName[matches[i].awayTeamId] ??
                                      'Deplasman',
                                  leagueName:
                                      leagueName[matches[i].leagueId] ?? '',
                                  divider: i < matches.length - 1,
                                ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _BroadcastRow extends StatelessWidget {
  const _BroadcastRow({
    required this.match,
    required this.homeName,
    required this.awayName,
    required this.leagueName,
    required this.divider,
  });

  final MatchModel match;
  final String homeName;
  final String awayName;
  final String leagueName;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final finished = match.status == MatchStatus.finished;
    final live =
        match.status == MatchStatus.live ||
        match.status == MatchStatus.halftime;
    final time = (match.matchTime ?? '').trim();
    final timeText = finished
        ? 'MS'
        : time.isEmpty
        ? '--:--'
        : (time.length >= 5 ? time.substring(0, 5) : time);
    // Biten maç gri.
    final main = finished ? Colors.white38 : Colors.white;
    final sub = finished ? Colors.white24 : const Color(0xFF94A3B8);

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MatchDetailsScreen(
            match: match,
            isAdmin: AppSession.of(context).value.isAdmin,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          border: divider
              ? Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Column(
                children: [
                  Text(
                    timeText,
                    style: TextStyle(
                      color: finished ? Colors.white38 : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (live)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Canlı',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.schedule_rounded,
                      size: 20,
                      color: finished ? Colors.white24 : Colors.white54,
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
                    '$homeName - $awayName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: main,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(Icons.tv_rounded, size: 16, color: sub),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [
                            'YouTube',
                            leagueName,
                          ].where((e) => e.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: sub,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
