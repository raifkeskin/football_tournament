import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tournament/models/league.dart';
import '../../../core/services/service_locator.dart';
import '../../match/services/interfaces/i_match_service.dart';
import '../models/player_stats.dart';
import '../../../core/widgets/web_safe_image.dart';

class PlayerCard extends StatefulWidget {
  const PlayerCard({
    super.key,
    required this.playerPhone,
    required this.name,
    required this.number,
    required this.photoUrl,
    required this.position,
    required this.birthDate,
    required this.height,
    required this.weight,
    required this.seasons,
    required this.initialSeasonId,
  });

  final String playerPhone;
  final String name;
  final String number;
  final String photoUrl;
  final String position;
  final String birthDate;
  final int? height;
  final int? weight;
  final List<League> seasons;
  final String initialSeasonId;

  @override
  State<PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<PlayerCard> {
  final IMatchService _matchService = ServiceLocator.matchService;
  late String _selectedSeasonId;
  late final Future<_PlayerCardData> _future;

  final Set<String> _expandedTournamentIds = <String>{};
  final Set<String> _expandedSeasonIds = <String>{};

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSeasonId.trim();
    _selectedSeasonId = initial;
    _future = _load();
  }

  int? _ageFromBirthDate(String? birthDate) {
    final s = (birthDate ?? '').trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(s);
    if (m == null) return null;
    final dd = int.tryParse(m.group(1)!) ?? 0;
    final mm = int.tryParse(m.group(2)!) ?? 0;
    final yyyy = int.tryParse(m.group(3)!) ?? 0;
    if (dd < 1 || dd > 31 || mm < 1 || mm > 12 || yyyy < 1900 || yyyy > 2100) {
      return null;
    }
    final now = DateTime.now();
    var age = now.year - yyyy;
    final hadBirthday = (now.month > mm) || (now.month == mm && now.day >= dd);
    if (!hadBirthday) age -= 1;
    return age < 0 ? null : age;
  }

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  Stream<PlayerStats> _watchSelectedStats() {
    final seasonId = _selectedSeasonId.trim();
    if (seasonId.isEmpty) {
      return Stream<PlayerStats>.value(
        const PlayerStats(
          id: '',
          playerPhone: '',
          tournamentId: '',
          teamId: '',
        ),
      );
    }
    final phone = widget.playerPhone.trim();
    return _matchService.watchPlayerStats(tournamentId: seasonId).map((all) {
      for (final s in all) {
        if (s.playerPhone.trim() == phone) return s;
      }
      return PlayerStats(
        id: PlayerStats.docId(playerPhone: phone, tournamentId: seasonId),
        playerPhone: phone,
        tournamentId: seasonId,
        teamId: '',
        matchesPlayed: 0,
        goals: 0,
        assists: 0,
        yellowCards: 0,
        redCards: 0,
        manOfTheMatch: 0,
      );
    });
  }

  SupabaseClient get _sb => Supabase.instance.client;

  int _readInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    final s = v.toString().replaceAll('\u0000', '').trim();
    return int.tryParse(s) ??
        double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
        0;
  }

  Future<_PlayerCardData> _load() async {
    final playerKey = widget.playerPhone.trim();
    if (playerKey.isEmpty) {
      return _PlayerCardData.empty();
    }

    final statsRows = <Map<String, dynamic>>[];
    try {
      final res = await _sb
          .from('player_statistics')
          .select()
          .or('player_id.eq.$playerKey,player_phone.eq.$playerKey');
      statsRows.addAll(res.cast<Map<String, dynamic>>());
    } catch (_) {}

    final seasonIds = <String>{};
    for (final r in statsRows) {
      final sid = (r['season_id'] ?? r['seasonId'] ?? '').toString().trim();
      if (sid.isNotEmpty) seasonIds.add(sid);
    }

    final seasonById = <String, Map<String, dynamic>>{};
    final leagueById = <String, Map<String, dynamic>>{};
    if (seasonIds.isNotEmpty) {
      try {
        final res = await _sb
            .from('seasons')
            .select('id, name, league_id')
            .inFilter('id', seasonIds.toList());
        for (final any in res) {
          final row = (any as Map).cast<String, dynamic>();
          final id = (row['id'] ?? '').toString().trim();
          if (id.isNotEmpty) seasonById[id] = row;
        }
      } catch (_) {}

      final leagueIds = <String>{};
      for (final s in seasonById.values) {
        final lid = (s['league_id'] ?? '').toString().trim();
        if (lid.isNotEmpty) leagueIds.add(lid);
      }
      if (leagueIds.isNotEmpty) {
        try {
          final res = await _sb
              .from('leagues')
              .select('id, name')
              .inFilter('id', leagueIds.toList());
          for (final any in res) {
            final row = (any as Map).cast<String, dynamic>();
            final id = (row['id'] ?? '').toString().trim();
            if (id.isNotEmpty) leagueById[id] = row;
          }
        } catch (_) {}
      }
    }

    final byLeague = <String, _TournamentNode>{};
    _StatTotals overall = const _StatTotals();

    for (final r in statsRows) {
      final seasonId = (r['season_id'] ?? r['seasonId'] ?? '').toString().trim();
      if (seasonId.isEmpty) continue;

      final matches = _readInt(r['matches_played'] ?? r['matchesPlayed'] ?? r['matches']);
      final goals = _readInt(r['goals'] ?? r['goal']);
      final assists = _readInt(r['assists'] ?? r['assist']);
      final yellow = _readInt(r['yellow_cards'] ?? r['yellowCards']);
      final red = _readInt(r['red_cards'] ?? r['redCards']);
      final totals = _StatTotals(
        matches: matches,
        goals: goals,
        assists: assists,
        yellow: yellow,
        red: red,
      );

      overall = overall + totals;

      final seasonRow = seasonById[seasonId];
      final leagueId =
          (seasonRow?['league_id'] ?? r['league_id'] ?? r['tournament_id'] ?? '')
              .toString()
              .trim();
      final leagueName = (leagueById[leagueId]?['name'] ?? '').toString().trim();
      final seasonName = (seasonRow?['name'] ?? '').toString().trim();

      final tKey = leagueId.isEmpty ? '__UNKNOWN_TOURNAMENT__' : leagueId;
      final tNode = byLeague.putIfAbsent(
        tKey,
        () => _TournamentNode(
          tournamentId: tKey,
          tournamentName: leagueName.isEmpty ? 'Turnuva' : leagueName,
          seasons: <String, _SeasonNode>{},
        ),
      );
      final sNode = tNode.seasons.putIfAbsent(
        seasonId,
        () => _SeasonNode(
          seasonId: seasonId,
          seasonName: seasonName.isEmpty ? seasonId : seasonName,
          totals: const _StatTotals(),
        ),
      );
      tNode.seasons[seasonId] = sNode.copyWith(totals: sNode.totals + totals);
    }

    final tournaments = byLeague.values.toList()
      ..sort((a, b) => a.tournamentName.toLowerCase().compareTo(b.tournamentName.toLowerCase()));
    for (final t in tournaments) {
      final seasonList = t.seasons.values.toList()
        ..sort((a, b) => a.seasonName.toLowerCase().compareTo(b.seasonName.toLowerCase()));
      t.sortedSeasons = seasonList;
    }

    return _PlayerCardData(
      overall: overall,
      tournaments: tournaments,
    );
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0B1B3A);
    const muted = Color(0xFF64748B);
    const green = Color(0xFF10B981);
    const border = Color(0xFFE2E8F0);
    const chipBg = Color(0xFFF8FAFC);

    final name = widget.name.trim().isEmpty ? '-' : widget.name.trim();
    final number = widget.number.trim();
    final pos = widget.position.trim().isEmpty ? '-' : widget.position.trim();
    final age = _ageFromBirthDate(widget.birthDate);
    final seasons = widget.seasons.where((e) => e.id.trim().isNotEmpty).toList();
    final hasSelected =
        seasons.any((s) => s.id.trim() == _selectedSeasonId.trim());
    final effectiveSeasonId = hasSelected
        ? _selectedSeasonId.trim()
        : (seasons.isEmpty ? '' : seasons.first.id.trim());
    if (effectiveSeasonId != _selectedSeasonId.trim()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedSeasonId = effectiveSeasonId);
      });
    }

    Widget infoChip(String label) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: navy,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      );
    }

    Widget miniStatItem({
      required Widget icon,
      required String value,
      required String label,
    }) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: navy,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    final coverUrl = _normalizeUrl(widget.photoUrl);

    return Material(
      color: Colors.black,
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: coverUrl.isEmpty
                  ? Container(
                      color: const Color(0xFF0B1B3A),
                      child: const Center(
                        child: Icon(
                          Icons.person,
                          size: 120,
                          color: Colors.white54,
                        ),
                      ),
                    )
                  : WebSafeImage(
                      url: coverUrl,
                      width: double.infinity,
                      height: double.infinity,
                      isCircle: false,
                      fit: BoxFit.cover,
                      fallbackIconSize: 120,
                    ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: Material(
                color: Colors.white.withValues(alpha: 0.18),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.white,
                  tooltip: 'Kapat',
                ),
              ),
            ),
            Positioned.fill(
              top: MediaQuery.of(context).size.height * 0.40,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                child: Container(
                  color: Colors.white,
                  child: FutureBuilder<_PlayerCardData>(
                    future: _future,
                    builder: (context, snapshot) {
                      final data = snapshot.data ?? _PlayerCardData.empty();
                      return CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: navy,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 24,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        number.isEmpty ? 'No: -' : 'No: $number',
                                        style: const TextStyle(
                                          color: navy,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      infoChip('MEVKİ: $pos'),
                                      infoChip(age == null ? 'YAŞ: -' : 'YAŞ: $age'),
                                      infoChip(
                                        widget.height == null
                                            ? 'BOY: -'
                                            : 'BOY: ${widget.height} cm',
                                      ),
                                      infoChip(
                                        widget.weight == null
                                            ? 'KİLO: -'
                                            : 'KİLO: ${widget.weight} kg',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _PinnedHeaderDelegate(
                              minHeight: 98,
                              maxHeight: 98,
                              child: Container(
                                color: Colors.white,
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: chipBg,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: border),
                                  ),
                                  child: Row(
                                    children: [
                                      miniStatItem(
                                        icon: const Icon(
                                          Icons.sports_soccer_outlined,
                                          color: green,
                                          size: 20,
                                        ),
                                        value: '${data.overall.matches}',
                                        label: 'TOPLAM MAÇ',
                                      ),
                                      miniStatItem(
                                        icon: const Icon(
                                          Icons.gps_fixed_rounded,
                                          color: green,
                                          size: 20,
                                        ),
                                        value: '${data.overall.goals}',
                                        label: 'GOL',
                                      ),
                                      miniStatItem(
                                        icon: const Icon(
                                          Icons.group_outlined,
                                          color: green,
                                          size: 20,
                                        ),
                                        value: '${data.overall.assists}',
                                        label: 'ASİST',
                                      ),
                                      miniStatItem(
                                        icon: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFBBF24),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                        value: '${data.overall.yellow}',
                                        label: 'SARI',
                                      ),
                                      miniStatItem(
                                        icon: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEF4444),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                        value: '${data.overall.red}',
                                        label: 'KIRMIZI',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                              child: const Text(
                                'Turnuva ve Sezon Kırılımları',
                                style: TextStyle(
                                  color: navy,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: ExpansionPanelList(
                                expansionCallback: (index, isExpanded) {
                                  final id = data.tournaments[index].tournamentId;
                                  setState(() {
                                    if (isExpanded) {
                                      _expandedTournamentIds.remove(id);
                                    } else {
                                      _expandedTournamentIds.add(id);
                                    }
                                  });
                                },
                                children: [
                                  for (final t in data.tournaments)
                                    ExpansionPanel(
                                      canTapOnHeader: true,
                                      isExpanded: _expandedTournamentIds.contains(t.tournamentId),
                                      headerBuilder: (context, isExpanded) {
                                        return ListTile(
                                          title: Text(
                                            t.tournamentName,
                                            style: const TextStyle(
                                              color: navy,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        );
                                      },
                                      body: Column(
                                        children: [
                                          for (final s in t.sortedSeasons)
                                            ExpansionTile(
                                              initiallyExpanded: false,
                                              onExpansionChanged: (open) {
                                                setState(() {
                                                  final key = '${t.tournamentId}::${s.seasonId}';
                                                  if (open) {
                                                    _expandedSeasonIds.add(key);
                                                  } else {
                                                    _expandedSeasonIds.remove(key);
                                                  }
                                                });
                                              },
                                              title: Text(
                                                s.seasonName,
                                                style: const TextStyle(
                                                  color: navy,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                                              children: [
                                                _StatRow(label: 'Maç', value: '${s.totals.matches}'),
                                                _StatRow(label: 'Gol', value: '${s.totals.goals}'),
                                                _StatRow(label: 'Asist', value: '${s.totals.assists}'),
                                                _StatRow(
                                                  label: 'Sarı Kart',
                                                  value: '${s.totals.yellow}',
                                                ),
                                                _StatRow(
                                                  label: 'Kırmızı Kart',
                                                  value: '${s.totals.red}',
                                                ),
                                              ],
                                            ),
                                          const SizedBox(height: 6),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Turnuva İstatistikleri',
                                    style: TextStyle(
                                      color: navy,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    value: effectiveSeasonId.isEmpty ? null : effectiveSeasonId,
                                    isExpanded: true,
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: navy),
                                    decoration: InputDecoration(
                                      labelText: 'Sezon Seçin',
                                      labelStyle: const TextStyle(
                                        color: muted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: border),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: border),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: green, width: 1.6),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                    dropdownColor: Colors.white,
                                    items: [
                                      for (final s in seasons)
                                        DropdownMenuItem<String>(
                                          value: s.id,
                                          child: Text(
                                            s.name.trim().isEmpty ? s.id : s.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: navy,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                    ],
                                    onChanged: seasons.isEmpty
                                        ? null
                                        : (v) => setState(() => _selectedSeasonId = (v ?? '').trim()),
                                  ),
                                  const SizedBox(height: 14),
                                  StreamBuilder<PlayerStats>(
                                    stream: _watchSelectedStats(),
                                    builder: (context, snapshot) {
                                      final s = snapshot.data ??
                                          const PlayerStats(
                                            id: '',
                                            playerPhone: '',
                                            tournamentId: '',
                                            teamId: '',
                                          );
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: chipBg,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: border),
                                        ),
                                        child: Row(
                                          children: [
                                            miniStatItem(
                                              icon: const Icon(Icons.sports_soccer_outlined, color: green, size: 20),
                                              value: '${s.matchesPlayed}',
                                              label: 'MAÇ',
                                            ),
                                            miniStatItem(
                                              icon: const Icon(Icons.gps_fixed_rounded, color: green, size: 20),
                                              value: '${s.goals}',
                                              label: 'GOL',
                                            ),
                                            miniStatItem(
                                              icon: const Icon(Icons.group_outlined, color: green, size: 20),
                                              value: '${s.assists}',
                                              label: 'ASİST',
                                            ),
                                            miniStatItem(
                                              icon: Container(
                                                width: 18,
                                                height: 18,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFBBF24),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                              ),
                                              value: '${s.yellowCards}',
                                              label: 'SARI',
                                            ),
                                            miniStatItem(
                                              icon: Container(
                                                width: 18,
                                                height: 18,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFEF4444),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                              ),
                                              value: '${s.redCards}',
                                              label: 'KIRMIZI',
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return minHeight != oldDelegate.minHeight ||
        maxHeight != oldDelegate.maxHeight ||
        child != oldDelegate.child;
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0B1B3A);
    const muted = Color(0xFF64748B);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: navy,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerCardData {
  const _PlayerCardData({
    required this.overall,
    required this.tournaments,
  });

  final _StatTotals overall;
  final List<_TournamentNode> tournaments;

  factory _PlayerCardData.empty() =>
      const _PlayerCardData(overall: _StatTotals(), tournaments: <_TournamentNode>[]);
}

class _TournamentNode {
  _TournamentNode({
    required this.tournamentId,
    required this.tournamentName,
    required this.seasons,
  });

  final String tournamentId;
  final String tournamentName;
  final Map<String, _SeasonNode> seasons;
  List<_SeasonNode> sortedSeasons = const <_SeasonNode>[];
}

class _SeasonNode {
  const _SeasonNode({
    required this.seasonId,
    required this.seasonName,
    required this.totals,
  });

  final String seasonId;
  final String seasonName;
  final _StatTotals totals;

  _SeasonNode copyWith({_StatTotals? totals}) {
    return _SeasonNode(
      seasonId: seasonId,
      seasonName: seasonName,
      totals: totals ?? this.totals,
    );
  }
}

class _StatTotals {
  const _StatTotals({
    this.matches = 0,
    this.goals = 0,
    this.assists = 0,
    this.yellow = 0,
    this.red = 0,
  });

  final int matches;
  final int goals;
  final int assists;
  final int yellow;
  final int red;

  _StatTotals operator +(_StatTotals other) {
    return _StatTotals(
      matches: matches + other.matches,
      goals: goals + other.goals,
      assists: assists + other.assists,
      yellow: yellow + other.yellow,
      red: red + other.red,
    );
  }
}
