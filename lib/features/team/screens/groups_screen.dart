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
import '../services/team_directory.dart';
import '../../share/poster_background.dart';
import '../../share/poster_share.dart';
import '../../share/standings_poster.dart';
import '../../../core/utils/string_utils.dart';
import '../../tournament/models/league_format.dart';

/// Bir turnuva + sezon + grubun puan durumu. Başlık çubuğu ve grup sekmesi
/// yok; Turnuva Sayfası'nın Puan Durumu sekmesinde gösterilir.
class StandingsView extends StatefulWidget {
  const StandingsView({
    super.key,
    required this.leagueId,
    required this.seasonId,
    required this.groupId,
    this.includeLive = false,
    this.highlightTeamIds = const {},
  });

  final String leagueId;
  final String seasonId;
  final String groupId;

  /// Oynanmakta olan maçlar o anki skorla sayılır; sıra değişimi okla
  /// gösterilir (maç detayındaki canlı puan durumu).
  final bool includeLive;

  /// Vurgulanan takımlar (ör. açık olan maçın iki takımı).
  final Set<String> highlightTeamIds;

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
              includeLive: widget.includeLive,
              highlightTeamIds: widget.highlightTeamIds,
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
      ServiceLocator.teamService.watchSeasonTeams(seasonId).first,
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
      kind: PosterKind.standings,
      formats: const [PosterFormat.post, PosterFormat.story],
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
  final bool includeLive;
  final Set<String> highlightTeamIds;

  const _GroupStandingsTable({
    super.key,
    required this.leagueId,
    required this.seasonId,
    required this.groupId,
    required this.groupName,
    required this.fetchGroupId,
    this.includeLive = false,
    this.highlightTeamIds = const {},
  });

  @override
  State<_GroupStandingsTable> createState() => _GroupStandingsTableState();
}

class _GroupStandingsTableState extends State<_GroupStandingsTable> {
  Stream<List<Map<String, dynamic>>>? _matchesStream;
  Stream<List<Team>>? _teamsStream;

  /// Sezonun lig formatı (bellekte; ekran beklemeden çizilsin).
  static final Map<String, ({LeagueFormat? format, bool doubleRound})>
  _formats = {};
  late ({LeagueFormat? format, bool doubleRound})? _format =
      _formats[widget.seasonId];

  @override
  void initState() {
    super.initState();
    _initStreams();
    _loadFormat();
    if (widget.includeLive) TeamDirectory.known.addListener(_onTeamsKnown);
  }

  @override
  void dispose() {
    TeamDirectory.known.removeListener(_onTeamsKnown);
    super.dispose();
  }

  /// Kısa adlar (teams.short_name) okununca canlı tablo yeniden çizilir.
  void _onTeamsKnown() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFormat() async {
    final id = widget.seasonId;
    try {
      final row = await Supabase.instance.client
          .from('seasons')
          .select('league_format, is_double_round')
          .eq('id', id)
          .maybeSingle();
      final v = (
        format: LeagueFormat.fromJson(row?['league_format']),
        doubleRound: row?['is_double_round'] == true,
      );
      _formats[id] = v;
      if (mounted && widget.seasonId == id) setState(() => _format = v);
    } catch (_) {
      // Format okunamazsa eski görünüm.
    }
  }

  @override
  void didUpdateWidget(covariant _GroupStandingsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leagueId != widget.leagueId ||
        oldWidget.seasonId != widget.seasonId ||
        oldWidget.fetchGroupId != widget.fetchGroupId) {
      _initStreams();
    }
    if (oldWidget.seasonId != widget.seasonId) {
      _format = _formats[widget.seasonId];
      _loadFormat();
    }
  }

  void _initStreams() {
    _matchesStream = _watchLeagueMatchesRaw(
      widget.leagueId,
      widget.seasonId,
      widget.fetchGroupId,
    );
    _teamsStream = ServiceLocator.teamService.watchSeasonTeams(
      widget.seasonId,
    );
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
                includeLive: widget.includeLive,
              );

              // Canlı modda gruptaki oynanan maçlar; varsa maç öncesi
              // sıraya göre değişim (▲/▼) hesaplanır.
              final liveInGroup =
                  widget.includeLive &&
                  seasonMatches.any(
                    (m) =>
                        isLiveMatchRow(m) &&
                        ((m['group_id'] ?? '').toString().trim() ==
                                widget.groupId ||
                            (m['group_id'] ?? '').toString().trim() ==
                                widget.groupName.trim()),
                  );
              final rankBefore = <String, int>{};
              if (liveInGroup) {
                final before = computeGroupStandings(
                  leagueId: widget.leagueId,
                  groupId: widget.groupId,
                  groupName: widget.groupName,
                  seasonMatches: seasonMatches,
                  allTeams: teamsSnapshot.data ?? const <Team>[],
                );
                for (var i = 0; i < before.length; i++) {
                  rankBefore[before[i].teamId] = i;
                }
              }

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

              // Lig formatı varsa bölgeler ondan; yoksa eski görünüm (4'ten
              // az takımda bölge şeritleri anlamsız, hepsi yeşil olur).
              final format = _format?.format;
              final showZones = format != null || rows.length > 4;
              const classOrange = Color(0xFFF59E0B);
              ({String name, Color color, bool filled})? zoneAt(int i) {
                if (format != null) {
                  final z = format.zoneOf(i + 1, rows.length);
                  if (z == null) return null;
                  final first =
                      format.cups.isNotEmpty &&
                      z.color == LeagueFormat.colors.first;
                  return (name: z.name, color: z.color, filled: first);
                }
                if (!showZones) return null;
                if (i < 4) {
                  return (name: 'Üst tur', color: _kAccent, filled: true);
                }
                if (i >= rows.length - 4) {
                  return (name: 'Klasman', color: classOrange, filled: false);
                }
                return null;
              }

              final legend = <({String name, Color color})>[];
              for (var i = 0; i < rows.length; i++) {
                final z = zoneAt(i);
                if (z != null && !legend.any((l) => l.name == z.name)) {
                  legend.add((name: z.name, color: z.color));
                }
              }

              // Ardışık aynı bölgedeki sıralar tek grup.
              final groups =
                  <
                    ({
                      int start,
                      int end,
                      ({String name, Color color, bool filled})? zone,
                    })
                  >[];
              for (var i = 0; i < rows.length; i++) {
                final z = zoneAt(i);
                if (groups.isNotEmpty && groups.last.zone?.name == z?.name) {
                  final last = groups.removeLast();
                  groups.add((start: last.start, end: i + 1, zone: last.zone));
                } else {
                  groups.add((start: i, end: i + 1, zone: z));
                }
              }
              final hasBands = groups.any((g) => g.zone != null);
              // Maç detayındaki canlı tablo dar: A/Y yok, varsa kısa ad.
              final compact = widget.includeLive;
              if (compact) {
                TeamDirectory.ensure([for (final r in rows) r.teamId]);
              }

              Widget row(int i) => _StandingsRow(
                index: i,
                entry: rows[i],
                compact: compact,
                shortName: compact
                    ? TeamDirectory.known.value[rows[i].teamId]?.shortName
                    : null,
                zone: zoneAt(i),
                highlight: widget.highlightTeamIds.contains(rows[i].teamId),
                rankDelta: rankBefore.containsKey(rows[i].teamId)
                    ? rankBefore[rows[i].teamId]! - i
                    : 0,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      settings: const RouteSettings(name: 'TeamSquadScreen'),
                      builder: (_) => TeamSquadScreen(
                        teamId: rows[i].teamId,
                        tournamentId: widget.leagueId,
                        teamName: rows[i].name,
                        teamLogoUrl: rows[i].logo,
                      ),
                    ),
                  );
                },
              );

              // Kenarlardan boşluklu, yuvarlak köşeli kart.
              final table = Container(
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
                      padding: EdgeInsets.fromLTRB(
                        3 + (hasBands ? _kZoneBand : 0),
                        7,
                        10,
                        7,
                      ),
                      child: _StandingsHeaderRow(compact: compact),
                    ),
                    // Bölgeler: aynı bölgedeki satırlar bir arada, solda bölge
                    // adı 90° sola yatırılmış başlıkla.
                    for (final g in groups)
                      Stack(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              left: hasBands ? _kZoneBand : 0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = g.start; i < g.end; i++) row(i),
                              ],
                            ),
                          ),
                          if (g.zone != null)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: _kZoneBand,
                              child: _ZoneBand(
                                name: g.zone!.name,
                                color: g.zone!.color,
                              ),
                            ),
                        ],
                      ),
                    // Açıklama
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          for (final l in legend)
                            _LegendDot(color: l.color, label: l.name),
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
              final ifNow = format == null
                  ? null
                  : _ifNowPairs(format, rows, _format?.doubleRound ?? false);
              if (ifNow == null && !liveInGroup) return table;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (liveInGroup) const _LiveCaption(),
                  table,
                  if (ifNow != null) _IfNowCard(lines: ifNow),
                ],
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
  const _StandingsHeaderRow({this.compact = false});

  /// Atılan / yenilen gol sütunları gizli (maç detayındaki canlı tablo).
  final bool compact;

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
        if (!compact) ...[h('A', c.stat), h('Y', c.stat)],
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

/// "Bugün bitse" satırları (kupa adı, rengi, eşleşmeler). Kart kapalıysa,
/// geçerli kupa yoksa ya da sezonun yarısı oynanmadıysa null.
List<({String cup, Color color, String pairs})>? _ifNowPairs(
  LeagueFormat f,
  List<StandingEntry> rows,
  bool doubleRound,
) {
  final n = rows.length;
  // Anahtar açıksa hemen görünür; turnuva yetkilisi istediği hafta açar.
  if (!f.showIfNow || f.cups.isEmpty || n < 2) return null;
  String name(int rank) => shortTeamName(rows[rank - 1].name);
  final out = <({String cup, Color color, String pairs})>[];
  for (var i = 0; i < f.cups.length; i++) {
    if (f.errorsOf(i, n).isNotEmpty) continue;
    final c = f.cups[i];
    final parts = <String>[];
    final byes = <String>[];
    for (final (a, b) in c.firstRound()) {
      if (a != null && b != null) {
        parts.add('${name(a)} – ${name(b)}');
      } else if (a != null || b != null) {
        byes.add(name((a ?? b)!));
      }
    }
    out.add((
      cup: c.name,
      color: LeagueFormat.colors[i % LeagueFormat.colors.length],
      pairs: [
        parts.join(' · '),
        if (byes.isNotEmpty) '(bay: ${byes.join(', ')})',
      ].join(' '),
    ));
  }
  return out.isEmpty ? null : out;
}

/// Canlı puan durumunun üstündeki "● CANLI" yazısı (yanıp söner).
class _LiveCaption extends StatefulWidget {
  const _LiveCaption();

  @override
  State<_LiveCaption> createState() => _LiveCaptionState();
}

class _LiveCaptionState extends State<_LiveCaption>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFEF4444);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.25, end: 1).animate(_blink),
            child: const Icon(Icons.circle, size: 8, color: red),
          ),
          const SizedBox(width: 6),
          const Text(
            'CANLI',
            style: TextStyle(
              color: red,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _IfNowCard extends StatelessWidget {
  const _IfNowCard({required this.lines});

  final List<({String cup, Color color, String pairs})> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            _kAccent.withValues(alpha: 0.12),
            _kAccent.withValues(alpha: 0.03),
          ],
        ),
        border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BUGÜN BİTSE',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${l.cup}: ',
                      style: TextStyle(
                        color: l.color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(text: l.pairs),
                  ],
                ),
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bölge şeridinin genişliği (dikey başlık).
const double _kZoneBand = 20;

/// Puan tablosunda bölge başlığı (ör. "PRESTİJ KUPASI"), satırların solunda
/// 90° sola yatırılmış: aşağıdan yukarı okunur, adın ardından ince çizgi.
class _ZoneBand extends StatelessWidget {
  const _ZoneBand({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: RotatedBox(
        quarterTurns: 3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          // Ad sığdığı kadar yazılır (kısa bölgede kısaltılır), kalan yere çizgi.
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (box.maxWidth - 16).clamp(0, double.infinity),
                  ),
                  child: Text(
                    name.trUpper,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 1,
                    color: color.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StandingsRow extends StatelessWidget {
  const _StandingsRow({
    required this.index,
    required this.entry,
    required this.zone,
    required this.onTap,
    this.highlight = false,
    this.rankDelta = 0,
    this.compact = false,
    this.shortName,
  });

  final int index;
  final StandingEntry entry;

  /// Dar görünüm: A/Y sütunları yok, ad tek satır.
  final bool compact;

  /// Takımın kısa adı (teams.short_name); boşsa tam ad kısaltılarak yazılır.
  final String? shortName;

  /// Satır vurgulu (açık olan maçın takımı).
  final bool highlight;

  /// Maç öncesine göre sıra değişimi: + yukarı, − aşağı.
  final int rankDelta;

  /// Sıranın bölgesi (kupa / üst tur / klasman / lige veda); yoksa null.
  /// [filled]: sıra dairesi dolu (ilk bölge), değilse çerçeveli.
  final ({String name, Color color, bool filled})? zone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const teamText = Color(0xFFF8FAFC);
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

    final z = zone;

    final av = entry.goalDiff;
    final avText = av > 0 ? '+$av' : '$av';
    final avColor = av > 0 ? _kAccent : (av < 0 ? negative : _kMidText);

    final rowColor = highlight
        ? _kAccent.withValues(alpha: 0.16)
        : isLeader
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
                      color: z == null
                          ? const Color(0xFF334155)
                          : z.filled
                          ? z.color
                          : z.color.withValues(alpha: 0.18),
                      border: z != null && !z.filled
                          ? Border.all(color: z.color, width: 1.5)
                          : null,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: z == null
                            ? teamText
                            : z.filled
                            ? const Color(0xFF052E20)
                            : z.color,
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
                    Text.rich(
                      TextSpan(
                        text: (shortName ?? '').trim().isNotEmpty
                            ? shortName!.trim()
                            : shortTeamName(entry.name),
                        children: [
                          if (rankDelta != 0)
                            TextSpan(
                              text: rankDelta > 0
                                  ? '  ▲$rankDelta'
                                  : '  ▼${-rankDelta}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: rankDelta > 0
                                    ? const Color(0xFF22C55E)
                                    : negative,
                              ),
                            ),
                        ],
                      ),
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: highlight
                            ? FontWeight.w800
                            : FontWeight.w600,
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
              if (!compact) ...[
                stat('${entry.goalsFor}', c.stat),
                stat('${entry.goalsAgainst}', c.stat),
              ],
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
