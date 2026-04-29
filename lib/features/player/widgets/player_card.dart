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
  String _selectedTournamentId = '';
  late final Future<_PlayerCardData> _future;

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
    const badgeBlue = Color(0xFF0EA5E9);
    const border = Color(0xFFE2E8F0);
    const chipBg = Color(0xFFF8FAFC);

    final name = widget.name.trim().isEmpty ? '-' : widget.name.trim();
    final number = widget.number.trim();
    final pos = widget.position.trim().isEmpty ? '-' : widget.position.trim();
    final age = _ageFromBirthDate(widget.birthDate);

    String birthYear() {
      final s = widget.birthDate.trim();
      if (s.isEmpty) return '-';
      final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(s);
      if (m != null) return m.group(3) ?? '-';
      final anyYear = RegExp(r'(\d{4})').firstMatch(s);
      return anyYear?.group(1) ?? '-';
    }

    Widget infoTile({
      required String label,
      required String value,
      required double labelSize,
      required double valueSize,
      required EdgeInsets padding,
    }) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: muted,
                  fontWeight: FontWeight.w900,
                  fontSize: labelSize,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: navy,
                  fontWeight: FontWeight.w900,
                  fontSize: valueSize,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final coverUrl = _normalizeUrl(widget.photoUrl);

    return Material(
      color: const Color(0xFFF8FAFC),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final safeTop = MediaQuery.of(context).padding.top;
          final h = constraints.maxHeight;
          final heroH = (h * 0.25).clamp(160.0, 240.0);
          const overlap = 22.0;
          final isNarrow = constraints.maxWidth < 360;
          final infoAspect = isNarrow ? 1.25 : 1.35;
          final statAspect = isNarrow ? 1.75 : 1.95;

          Widget statCard({
            required String title,
            required String value,
            required Widget icon,
            Color? valueColor,
          }) {
            return Container(
              padding: EdgeInsets.all(isNarrow ? 12 : 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w700,
                            fontSize: isNarrow ? 11 : 12,
                          ),
                        ),
                        SizedBox(height: isNarrow ? 6 : 8),
                        Text(
                          value,
                          style: TextStyle(
                            color: valueColor ?? navy,
                            fontWeight: FontWeight.w900,
                            fontSize: isNarrow ? 20 : 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  icon,
                ],
              ),
            );
          }

          Widget iconBadge(IconData icon) {
            return Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: green, size: 20),
            );
          }

          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: heroH,
                child: coverUrl.isEmpty
                    ? Container(
                        color: const Color(0xFFE2E8F0),
                        child: const Center(
                          child: Icon(
                            Icons.person,
                            size: 70,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      )
                    : WebSafeImage(
                        url: coverUrl,
                        width: double.infinity,
                        height: heroH,
                        isCircle: false,
                        fit: BoxFit.cover,
                        fallbackIconSize: 70,
                      ),
              ),
              Positioned(
                top: safeTop + 10,
                right: 12,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.30),
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white,
                    tooltip: 'Kapat',
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: heroH - overlap,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  child: Container(
                    color: Colors.white,
                    child: FutureBuilder<_PlayerCardData>(
                      future: _future,
                      builder: (context, snapshot) {
                        final data = snapshot.data ?? _PlayerCardData.empty();
                        final tournaments = data.tournaments;

                        String? findTournamentIdForSeason(String seasonId) {
                          final sid = seasonId.trim();
                          if (sid.isEmpty) return null;
                          for (final t in tournaments) {
                            for (final s in t.sortedSeasons) {
                              if (s.seasonId.trim() == sid) return t.tournamentId;
                            }
                          }
                          return null;
                        }

                        String? ensureTournament() {
                          final current = _selectedTournamentId.trim();
                          if (current.isNotEmpty &&
                              tournaments.any((t) => t.tournamentId == current)) {
                            return current;
                          }
                          final inferred = findTournamentIdForSeason(_selectedSeasonId);
                          if (inferred != null) return inferred;
                          if (tournaments.isNotEmpty) return tournaments.first.tournamentId;
                          return null;
                        }

                        final effectiveTournamentId = ensureTournament() ?? '';

                        final selectedTournament = tournaments
                            .where((t) => t.tournamentId == effectiveTournamentId)
                            .toList(growable: false);

                        final seasonsInTournament = selectedTournament.isEmpty
                            ? const <_SeasonNode>[]
                            : selectedTournament.first.sortedSeasons;

                        final effectiveSeasonId = seasonsInTournament.any(
                          (s) => s.seasonId.trim() == _selectedSeasonId.trim(),
                        )
                            ? _selectedSeasonId.trim()
                            : (seasonsInTournament.isEmpty
                                ? ''
                                : seasonsInTournament.first.seasonId.trim());

                        if (effectiveTournamentId != _selectedTournamentId.trim() ||
                            effectiveSeasonId != _selectedSeasonId.trim()) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() {
                              _selectedTournamentId = effectiveTournamentId;
                              _selectedSeasonId = effectiveSeasonId;
                            });
                          });
                        }

                        Widget numberBadge() {
                          final text = number.isEmpty ? '-' : number;
                          return Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              color: badgeBlue,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.10),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    text,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 22,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: navy,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 26,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                numberBadge(),
                              ],
                            ),
                            const SizedBox(height: 16),
                            GridView.count(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: infoAspect,
                              children: [
                                infoTile(
                                  label: 'Mevki',
                                  value: pos,
                                  labelSize: isNarrow ? 10 : 11,
                                  valueSize: isNarrow ? 14 : 16,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isNarrow ? 10 : 12,
                                    vertical: isNarrow ? 10 : 12,
                                  ),
                                ),
                                infoTile(
                                  label: 'Yaş',
                                  value: age == null ? '-' : '$age',
                                  labelSize: isNarrow ? 10 : 11,
                                  valueSize: isNarrow ? 14 : 16,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isNarrow ? 10 : 12,
                                    vertical: isNarrow ? 10 : 12,
                                  ),
                                ),
                                infoTile(
                                  label: 'Boy',
                                  value: widget.height == null ? '-' : '${widget.height} cm',
                                  labelSize: isNarrow ? 10 : 11,
                                  valueSize: isNarrow ? 14 : 16,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isNarrow ? 10 : 12,
                                    vertical: isNarrow ? 10 : 12,
                                  ),
                                ),
                                infoTile(
                                  label: 'Kilo',
                                  value: widget.weight == null ? '-' : '${widget.weight} kg',
                                  labelSize: isNarrow ? 10 : 11,
                                  valueSize: isNarrow ? 14 : 16,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isNarrow ? 10 : 12,
                                    vertical: isNarrow ? 10 : 12,
                                  ),
                                ),
                                infoTile(
                                  label: 'Doğum',
                                  value: birthYear(),
                                  labelSize: isNarrow ? 10 : 11,
                                  valueSize: isNarrow ? 14 : 16,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isNarrow ? 10 : 12,
                                    vertical: isNarrow ? 10 : 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: const [
                                Icon(Icons.insights_outlined, color: green, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Genel istatistikler',
                                  style: TextStyle(
                                    color: navy,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            GridView.count(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: statAspect,
                              children: [
                                statCard(
                                  title: 'Oynanan Maç',
                                  value: '${data.overall.matches}',
                                  icon: iconBadge(Icons.sports_soccer_outlined),
                                ),
                                statCard(
                                  title: 'Gol',
                                  value: '${data.overall.goals}',
                                  valueColor: green,
                                  icon: iconBadge(Icons.gps_fixed_rounded),
                                ),
                                statCard(
                                  title: 'Asist',
                                  value: '${data.overall.assists}',
                                  valueColor: const Color(0xFF7C3AED),
                                  icon: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(
                                      Icons.group_outlined,
                                      color: Color(0xFF7C3AED),
                                      size: 20,
                                    ),
                                  ),
                                ),
                                statCard(
                                  title: 'Kartlar (S/K)',
                                  value: '${data.overall.yellow} / ${data.overall.red}',
                                  icon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFBBF24),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        width: 10,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: const [
                                Icon(Icons.bar_chart_outlined, color: green, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Turnuva istatistikleri',
                                  style: TextStyle(
                                    color: navy,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (tournaments.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Center(child: Text('Turnuva verisi bulunamadı.')),
                              )
                            else
                              Theme(
                                data: Theme.of(context).copyWith(
                                  dividerColor: Colors.transparent,
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                ),
                                child: Column(
                                  children: [
                                    for (final t in tournaments)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        decoration: BoxDecoration(
                                          color: chipBg,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: border),
                                        ),
                                        child: ExpansionTile(
                                          key: PageStorageKey<String>('t_${t.tournamentId}'),
                                          initiallyExpanded:
                                              t.tournamentId.trim() == effectiveTournamentId,
                                          tilePadding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          childrenPadding:
                                              const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                          title: Text(
                                            t.tournamentName.trim().isEmpty
                                                ? 'Turnuva'
                                                : t.tournamentName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: navy,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          children: [
                                            for (final ss in t.sortedSeasons)
                                              InkWell(
                                                borderRadius: BorderRadius.circular(14),
                                                onTap: () {
                                                  setState(() {
                                                    _selectedTournamentId = t.tournamentId;
                                                    _selectedSeasonId = ss.seasonId;
                                                  });
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                                  margin: const EdgeInsets.only(top: 8),
                                                  decoration: BoxDecoration(
                                                    color: ss.seasonId.trim() == effectiveSeasonId
                                                        ? Colors.white
                                                        : Colors.transparent,
                                                    borderRadius: BorderRadius.circular(14),
                                                    border: Border.all(
                                                      color: ss.seasonId.trim() == effectiveSeasonId
                                                          ? green
                                                          : border,
                                                      width: ss.seasonId.trim() == effectiveSeasonId
                                                          ? 1.4
                                                          : 1.0,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          ss.seasonName.trim().isEmpty
                                                              ? ss.seasonId
                                                              : ss.seasonName,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: TextStyle(
                                                            color: navy,
                                                            fontWeight:
                                                                ss.seasonId.trim() ==
                                                                        effectiveSeasonId
                                                                    ? FontWeight.w900
                                                                    : FontWeight.w800,
                                                          ),
                                                        ),
                                                      ),
                                                      if (ss.seasonId.trim() == effectiveSeasonId)
                                                        const Icon(
                                                          Icons.check_circle_rounded,
                                                          color: green,
                                                          size: 20,
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 14),
                            StreamBuilder<PlayerStats>(
                              stream: _watchSelectedStats(),
                              builder: (context, snap) {
                                final s = snap.data ??
                                    const PlayerStats(
                                      id: '',
                                      playerPhone: '',
                                      tournamentId: '',
                                      teamId: '',
                                    );
                                final cardsValue = '${s.yellowCards} / ${s.redCards}';
                                return GridView.count(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: statAspect,
                                  children: [
                                    statCard(
                                      title: 'Oynanan Maç',
                                      value: '${s.matchesPlayed}',
                                      icon: iconBadge(Icons.sports_soccer_outlined),
                                    ),
                                    statCard(
                                      title: 'Gol',
                                      value: '${s.goals}',
                                      valueColor: green,
                                      icon: iconBadge(Icons.gps_fixed_rounded),
                                    ),
                                    statCard(
                                      title: 'Asist',
                                      value: '${s.assists}',
                                      valueColor: const Color(0xFF7C3AED),
                                      icon: Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: const Icon(
                                          Icons.group_outlined,
                                          color: Color(0xFF7C3AED),
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                    statCard(
                                      title: 'Kartlar (S/K)',
                                      value: cardsValue,
                                      icon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFBBF24),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            width: 10,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEF4444),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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
