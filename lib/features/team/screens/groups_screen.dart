import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../match/models/match.dart';
import '../models/team.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/utils/table_feed.dart';
import 'team_squad_screen.dart';

import '../../../core/widgets/web_safe_image.dart';
import '../utils/standings.dart';
import '../../share/poster_share.dart';
import '../../share/standings_poster.dart';

/// Bir turnuva + sezon + grubun puan durumu. Başlık çubuğu ve grup sekmesi
/// yok; Turnuva Sayfası'nın Puan Durumu sekmesinde gösterilir.
class StandingsView extends StatefulWidget {
  const StandingsView({
    super.key,
    required this.leagueId,
    required this.seasonId,
    required this.groupId,
  });

  final String leagueId;
  final String seasonId;
  final String groupId;

  @override
  State<StandingsView> createState() => _StandingsViewState();
}

class _StandingsViewState extends State<StandingsView> {
  late Stream<List<GroupModel>> _groupsStream = ServiceLocator.leagueService
      .watchGroups(widget.seasonId);

  @override
  void didUpdateWidget(covariant StandingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seasonId != widget.seasonId) {
      _groupsStream = ServiceLocator.leagueService.watchGroups(widget.seasonId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroupModel>>(
      stream: _groupsStream,
      builder: (context, snap) {
        final group = (snap.data ?? const <GroupModel>[])
            .where((g) => g.id == widget.groupId)
            .firstOrNull;
        return ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _GroupStandingsTable(
              key: ValueKey('${widget.seasonId}|${widget.groupId}'),
              leagueId: widget.leagueId,
              seasonId: widget.seasonId,
              groupId: widget.groupId,
              groupName: group?.name ?? '',
              fetchGroupId: null,
            ),
          ],
        );
      },
    );
  }
}

/// Grubun puan durumu afişi (Instagram hikaye boyutu).
Future<void> shareGroupStandings(
  BuildContext context, {
  required String leagueId,
  required String seasonId,
  required String groupId,
}) async {
  final leagueService = ServiceLocator.leagueService;
  try {
    final client = Supabase.instance.client;
    final results = await Future.wait<Object?>([
      client
          .from('matches')
          .select()
          .eq('league_id', leagueId)
          .eq('season_id', seasonId),
      ServiceLocator.teamService.watchAllTeams().first,
      leagueService.watchGroups(seasonId).first,
      client
          .from('leagues')
          .select('name, logo_url')
          .eq('id', leagueId)
          .maybeSingle(),
      client.from('seasons').select('name').eq('id', seasonId).maybeSingle(),
    ]);
    final matches = (results[0] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final seasonGroups = results[2] as List<GroupModel>;
    final group = seasonGroups.where((g) => g.id == groupId).firstOrNull;
    if (group == null) return;
    final rows = computeGroupStandings(
      leagueId: leagueId,
      groupId: group.id,
      groupName: group.name,
      seasonMatches: matches,
      allTeams: results[1] as List<Team>,
    );
    if (!context.mounted) return;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paylaşılacak puan durumu yok.')),
      );
      return;
    }
    final league = results[3] as Map?;
    final leagueLogo = (league?['logo_url'] ?? '').toString();
    final leagueName = (league?['name'] ?? '').toString();
    final seasonName = ((results[4] as Map?)?['name'] ?? '').toString();
    await showPosterPreview(
      context: context,
      fileName: 'puan_durumu_${group.name}'.replaceAll(' ', '_'),
      leagueId: leagueId,
      imageUrls: [
        leagueLogo,
        for (final r in rows) r.logo,
      ].where((u) => u.trim().isNotEmpty).toList(),
      poster: StandingsPoster(
        leagueName: leagueName,
        leagueLogo: leagueLogo,
        subtitle: [
          seasonName,
          if (seasonGroups.length > 1) group.name,
        ].where((e) => e.trim().isNotEmpty).join(' · '),
        rows: rows,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Afiş hazırlanamadı: $e')));
  }
}

class _GroupStandingsTable extends StatefulWidget {
  final String leagueId;
  final String seasonId;
  final String groupId;
  final String groupName;
  final String? fetchGroupId;

  const _GroupStandingsTable({
    super.key,
    required this.leagueId,
    required this.seasonId,
    required this.groupId,
    required this.groupName,
    required this.fetchGroupId,
  });

  @override
  State<_GroupStandingsTable> createState() => _GroupStandingsTableState();
}

class _GroupStandingsTableState extends State<_GroupStandingsTable> {
  Stream<List<Map<String, dynamic>>>? _matchesStream;
  Stream<List<Team>>? _teamsStream;

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  void didUpdateWidget(covariant _GroupStandingsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leagueId != widget.leagueId ||
        oldWidget.seasonId != widget.seasonId ||
        oldWidget.fetchGroupId != widget.fetchGroupId) {
      _initStreams();
    }
  }

  void _initStreams() {
    _matchesStream = _watchLeagueMatchesRaw(
      widget.leagueId,
      widget.seasonId,
      widget.fetchGroupId,
    );
    _teamsStream = ServiceLocator.teamService.watchAllTeams();
  }

  Stream<List<Map<String, dynamic>>> _watchLeagueMatchesRaw(
    String leagueId,
    String seasonId,
    String? fetchGroupId,
  ) {
    final id = leagueId.trim();
    final sId = seasonId.trim();
    if (id.isEmpty || sId.isEmpty) {
      return const Stream<List<Map<String, dynamic>>>.empty();
    }
    // Sezonun maçları tek akışta; gol vb. değişiklikte yalnızca değişen
    // satır işlenir (bkz. watchTableRows). Tüm grup tabloları aynı akışı
    // paylaşır.
    final feed =
        watchTableRows(
          Supabase.instance.client,
          table: 'matches',
          column: 'season_id',
          value: sId,
          orderBy: 'match_date',
        ).map(
          (rows) => rows
              .where((r) => (r['league_id'] ?? '').toString().trim() == id)
              .toList(),
        );
    if (fetchGroupId == null) return feed;
    return feed.map(
      (rows) => rows
          .where((r) => (r['group_id'] ?? '').toString().trim() == fetchGroupId)
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    const midText = Color(0xFF94A3B8);
    const accentGreen = Color(0xFF10B981);

    return Padding(
      padding: EdgeInsets.zero,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _matchesStream,
        builder: (context, mergedSnapshot) {
          if (mergedSnapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final seasonMatches =
              mergedSnapshot.data ?? const <Map<String, dynamic>>[];

          return StreamBuilder<List<Team>>(
            stream: _teamsStream,
            builder: (context, teamsSnapshot) {
              if (teamsSnapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final rows = computeGroupStandings(
                leagueId: widget.leagueId,
                groupId: widget.groupId,
                groupName: widget.groupName,
                seasonMatches: seasonMatches,
                allTeams: teamsSnapshot.data ?? const <Team>[],
              );

              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '${widget.groupName} için henüz takım/maç verisi yok.',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }

              // 4'ten az takımda bölge şeritleri anlamsız (hepsi yeşil olur).
              final showZones = rows.length > 4;

              // Kenarlardan boşluklu, yuvarlak köşeli kart.
              return Container(
                margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sütun başlıkları
                    Container(
                      color: Colors.white.withValues(alpha: 0.04),
                      padding: const EdgeInsets.fromLTRB(3, 7, 10, 7),
                      child: const _StandingsHeaderRow(),
                    ),
                    for (var i = 0; i < rows.length; i++)
                      _StandingsRow(
                        index: i,
                        entry: rows[i],
                        totalCount: rows.length,
                        showZones: showZones,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeamSquadScreen(
                                teamId: rows[i].teamId,
                                tournamentId: widget.leagueId,
                                teamName: rows[i].name,
                                teamLogoUrl: rows[i].logo,
                              ),
                            ),
                          );
                        },
                      ),
                    // Açıklama
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          if (showZones) ...[
                            const _LegendDot(
                              color: accentGreen,
                              label: 'Üst tur',
                            ),
                            const _LegendDot(
                              color: Color(0xFFF59E0B),
                              label: 'Klasman',
                            ),
                          ],
                          const _LegendDot(
                            color: accentGreen,
                            label: 'Galibiyet',
                          ),
                          const _LegendDot(
                            color: Color(0xFF64748B),
                            label: 'Beraberlik',
                          ),
                          const _LegendDot(
                            color: Color(0xFFF87171),
                            label: 'Mağlubiyet',
                          ),
                          Text(
                            'O: Oynanan  G: Galibiyet  B: Beraberlik  '
                            'M: Mağlubiyet  A: Atılan  Y: Yenilen  AV: Averaj',
                            style: TextStyle(
                              color: midText.withValues(alpha: 0.8),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// Sütun genişlikleri başlık ve satırlarda ortak kullanılır.
const _kMidText = Color(0xFF94A3B8);
const _kAccent = Color(0xFF10B981);

/// Sütun genişlikleri başlık ve satırlarda ortak kullanılır. Dar ekranlarda
/// (ör. 360dp) G/B/M de görünsün diye sütunlar sıkıştırılır.
class _StandingsCols {
  const _StandingsCols({
    required this.rank,
    required this.stat,
    required this.av,
    required this.pts,
    required this.gap,
    required this.fontSize,
  });

  final double rank;
  final double stat;
  final double av;
  final double pts;
  final double gap;
  final double fontSize;

  static const wide = _StandingsCols(
    rank: 26,
    stat: 25,
    av: 30,
    pts: 30,
    gap: 6,
    fontSize: 14,
  );
  static const compact = _StandingsCols(
    rank: 22,
    stat: 21,
    av: 26,
    pts: 26,
    gap: 4,
    fontSize: 12.5,
  );

  static _StandingsCols of(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 390 ? compact : wide;
}

const _tabular = [FontFeature.tabularFigures()];

class _StandingsHeaderRow extends StatelessWidget {
  const _StandingsHeaderRow();

  @override
  Widget build(BuildContext context) {
    final c = _StandingsCols.of(context);
    Widget h(String t, double w, {bool highlight = false}) => SizedBox(
      width: w,
      child: Text(
        t,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: highlight ? _kAccent : _kMidText,
        ),
      ),
    );

    return Row(
      children: [
        h('#', c.rank),
        SizedBox(width: c.gap + 31),
        const Expanded(
          child: Text(
            'Takım',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: _kMidText,
            ),
          ),
        ),
        h('O', c.stat),
        h('G', c.stat),
        h('B', c.stat),
        h('M', c.stat),
        h('A', c.stat),
        h('Y', c.stat),
        h('AV', c.av),
        const SizedBox(width: 4),
        h('P', c.pts, highlight: true),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: _kMidText, fontSize: 10)),
      ],
    );
  }
}

class _StandingsRow extends StatelessWidget {
  const _StandingsRow({
    required this.index,
    required this.entry,
    required this.totalCount,
    required this.showZones,
    required this.onTap,
  });

  final int index;
  final StandingEntry entry;
  final int totalCount;
  final bool showZones;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const teamText = Color(0xFFF8FAFC);
    const classOrange = Color(0xFFF59E0B);
    const negative = Color(0xFFF87171);
    final c = _StandingsCols.of(context);

    Widget stat(String text, double width, {Color? color, FontWeight? w}) {
      return SizedBox(
        width: width,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: c.fontSize,
              fontWeight: w ?? FontWeight.w600,
              color: color ?? const Color(0xFFCBD5E1),
              fontFeatures: _tabular,
            ),
          ),
        ),
      );
    }

    final isLeader = index == 0 && entry.played > 0;

    Color zoneColor = Colors.transparent;
    if (showZones) {
      if (index < 4) {
        zoneColor = _kAccent;
      } else if (index >= totalCount - 4) {
        zoneColor = classOrange;
      }
    }

    final av = entry.goalDiff;
    final avText = av > 0 ? '+$av' : '$av';
    final avColor = av > 0 ? _kAccent : (av < 0 ? negative : _kMidText);

    final rowColor = isLeader
        ? _kAccent.withValues(alpha: 0.08)
        : (index.isOdd
              ? Colors.white.withValues(alpha: 0.025)
              : Colors.transparent);

    return Material(
      color: rowColor,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(0, 5, 10, 5),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 3),
              // Sıra yuvarlak içinde: üst tur dolu yeşil, klasman turuncu.
              SizedBox(
                width: c.rank,
                child: Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: zoneColor == _kAccent
                          ? _kAccent
                          : zoneColor == classOrange
                          ? classOrange.withValues(alpha: 0.18)
                          : const Color(0xFF334155),
                      border: zoneColor == classOrange
                          ? Border.all(color: classOrange, width: 1.5)
                          : null,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: zoneColor == _kAccent
                            ? const Color(0xFF052E20)
                            : zoneColor == classOrange
                            ? classOrange
                            : teamText,
                        fontSize: 11.5,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: c.gap - 2),
              WebSafeImage(
                url: entry.logo,
                width: 22,
                height: 22,
                fit: BoxFit.contain,
                fallbackIconSize: 18,
              ),
              const SizedBox(width: 8),
              // Uzun adlar küçülmek yerine 2 satıra iner.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      shortTeamName(entry.name),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: teamText,
                        fontSize: 12,
                        height: 1.15,
                      ),
                    ),
                    // Son 5 maç: yeşil galibiyet, gri beraberlik, kırmızı
                    // mağlubiyet.
                    if (entry.form.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          for (final r in entry.form)
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: r == 'G'
                                    ? _kAccent
                                    : r == 'B'
                                    ? const Color(0xFF64748B)
                                    : negative,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              stat('${entry.played}', c.stat),
              stat('${entry.won}', c.stat),
              stat('${entry.drawn}', c.stat),
              stat('${entry.lost}', c.stat),
              stat('${entry.goalsFor}', c.stat),
              stat('${entry.goalsAgainst}', c.stat),
              stat(avText, c.av, color: avColor, w: FontWeight.w700),
              const SizedBox(width: 4),
              SizedBox(
                width: c.pts,
                child: Text(
                  '${entry.points}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _kAccent,
                    fontSize: 15,
                    fontFeatures: _tabular,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
