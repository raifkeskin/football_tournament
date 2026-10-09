import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/app_navigator.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/table_feed.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../team/models/team.dart';
import '../../tournament/models/league.dart';
import '../models/match.dart';
import 'match_details_screen.dart';

/// Yayın Rehberi: seçili gün (varsayılan bugün), görülebilen turnuvalarda
/// yayın linki eklenmiş maçlar, saat sırasıyla. Biten (MS) maçlar gri;
/// dokununca maç detayı. Gün, bantta sağdaki takvimden seçilir.
class BroadcastGuideScreen extends StatefulWidget {
  const BroadcastGuideScreen({super.key});

  /// Seçili gün (yalnız tarih).
  static final date = ValueNotifier<DateTime>(_dayOf(DateTime.now()));

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Bantdaki takvim: gün seçtirir; yayın linkli maç olan günler işaretli.
  static Future<void> pickDate() async {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    final picked = await showAppDatePicker(
      context: ctx,
      initialDate: date.value,
      firstYear: 2020,
      lastYear: DateTime.now().year + 2,
      title: 'Yayın Günü',
      markedDays: _broadcastDays,
    );
    if (picked != null) date.value = _dayOf(picked);
  }

  /// Verilen ayda yayın linki eklenmiş maçı olan günler.
  static Future<Set<int>> _broadcastDays(int year, int month) async {
    try {
      final f = DateFormat('yyyy-MM-dd');
      final rows = await Supabase.instance.client
          .from('matches')
          .select('match_date, match_media!inner(media_type)')
          .eq('match_media.media_type', 'Maç Yayın Linki')
          .gte('match_date', f.format(DateTime(year, month, 1)))
          .lte('match_date', f.format(DateTime(year, month + 1, 0)));
      return {
        for (final r in rows)
          ?DateTime.tryParse((r['match_date'] ?? '').toString())?.day,
      };
    } catch (_) {
      return const <int>{};
    }
  }

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

  /// Gün başına akış (o güne dönünce yeniden kurulmaz).
  final Map<String, Stream<List<MatchModel>>> _byDay = {};

  @override
  void initState() {
    super.initState();
    BroadcastGuideScreen.date.addListener(_onDate);
  }

  @override
  void dispose() {
    BroadcastGuideScreen.date.removeListener(_onDate);
    super.dispose();
  }

  void _onDate() {
    if (mounted) setState(() {});
  }

  /// Günün maçları; yalnızca yayın linki olanlar.
  Stream<List<MatchModel>> _matchesOn(String dayKey) => _byDay.putIfAbsent(
    dayKey,
    () =>
        watchTableRows(
          Supabase.instance.client,
          table: 'matches',
          column: 'match_date',
          value: dayKey,
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
        }),
  );

  @override
  Widget build(BuildContext context) {
    final day = BroadcastGuideScreen.date.value;
    final today = BroadcastGuideScreen._dayOf(DateTime.now());
    final isToday = day == today;
    // Başlık yok: menü, turnuva kimliği ve takvim üst bantta.
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
                stream: _matchesOn(DateFormat('yyyy-MM-dd').format(day)),
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
                              constraints: const BoxConstraints(minHeight: 46),
                              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      DateFormat(
                                        'dd MMMM EEEE',
                                        'tr_TR',
                                      ).format(day),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  // Başka gündeyken bugüne dönüş.
                                  if (!isToday)
                                    TextButton(
                                      onPressed: () =>
                                          BroadcastGuideScreen.date.value =
                                              today,
                                      child: const Text('Bugün'),
                                    ),
                                ],
                              ),
                            ),
                            if (matches.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 36,
                                  horizontal: 16,
                                ),
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.live_tv_rounded,
                                      size: 44,
                                      color: Colors.white24,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      isToday
                                          ? 'Bugün canlı yayın maçı bulunmuyor.'
                                          : 'Bu tarihte canlı yayın maçı '
                                                'bulunmuyor.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
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
