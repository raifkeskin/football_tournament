import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/league.dart';
import '../models/match.dart';
import '../services/database_service.dart';
import '../widgets/web_safe_image.dart';
import 'match_details_screen.dart';

class FixtureScreen extends StatefulWidget {
  const FixtureScreen({super.key});

  @override
  State<FixtureScreen> createState() => _FixtureScreenState();
}

class _FixtureScreenState extends State<FixtureScreen> {
  final _db = DatabaseService();
  String? _leagueId;
  String? _groupId;
  int? _week;

  DateTime? _parseYyyyMmDd(String yyyyMmDd) {
    final s = yyyyMmDd.trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final y = int.tryParse(m.group(1) ?? '');
    final mo = int.tryParse(m.group(2) ?? '');
    final d = int.tryParse(m.group(3) ?? '');
    if (y == null || mo == null || d == null) return null;
    return DateTime(y, mo, d);
  }

  String _dateStripText(String yyyyMmDd) {
    final s = yyyyMmDd.trim();
    final dt = _parseYyyyMmDd(s);
    if (dt == null) return s;
    return DateFormat('dd.MM.yyyy EEEE', 'tr_TR').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    const headerForest = Color(0xFF064E3B);
    const bgDark = Color(0xFF0F172A);
    const cardBg = Color(0xFF1E293B);
    const outline = Color(0xFF334155);
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.calendar_month_outlined),
            SizedBox(width: 8),
            Text('Fikstür'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('teams').snapshots(),
        builder: (context, teamsSnap) {
          final teamLogoById = <String, String>{};
          if (teamsSnap.hasData) {
            for (final doc in teamsSnap.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              teamLogoById[doc.id] = data['logoUrl']?.toString() ?? '';
            }
          }

          return StreamBuilder<QuerySnapshot>(
            stream: _db.getLeagues(),
            builder: (context, leaguesSnap) {
              if (!leaguesSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final leagues =
                  leaguesSnap.data!.docs
                      .map(
                        (d) => League.fromMap({
                          ...d.data() as Map<String, dynamic>,
                          'id': d.id,
                        }),
                      )
                      .toList()
                    ..sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    );

              if (leagues.isEmpty) {
                return const Center(child: Text('Turnuva bulunamadı.'));
              }
              _leagueId ??= leagues.any((l) => l.isDefault)
                  ? (leagues.where((l) => l.isDefault).first.id)
                  : leagues.first.id;
              final leagueId = _leagueId!;

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('groups')
                    .where('tournamentId', isEqualTo: leagueId)
                    .snapshots(),
                builder: (context, snapshot) {
                  final groups = snapshot.hasData
                      ? snapshot.data!.docs.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          // Grup adını 'name' alanından veya döküman ID'sinden alıyoruz
                          return (d['name'] ?? doc.id).toString();
                        }).toList()
                      : <String>[];

                  if (groups.isNotEmpty &&
                      _groupId != null &&
                      !groups.contains(_groupId)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() => _groupId = null);
                    });
                  }

                  final selectedGroupId = groups.isEmpty ? null : _groupId;
                  final groupNameById = {for (final g in groups) g: '$g Grubu'};

                  InputDecoration dec(String label) {
                    return InputDecoration(
                      labelText: label,
                      labelStyle: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white54),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    );
                  }

                  return FutureBuilder<int?>(
                    key: ValueKey('$leagueId|$selectedGroupId'),
                    future: _db.getFixtureMaxWeek(
                      leagueId,
                      groupId: selectedGroupId,
                    ),
                    builder: (context, maxWeekSnap) {
                      final maxWeekErr = maxWeekSnap.error?.toString() ?? '';
                      final maxWeekNeedsIndex =
                          maxWeekErr.contains('requires an index') ||
                          maxWeekErr.contains('FAILED_PRECONDITION');
                      final useWeekFallback =
                          maxWeekSnap.hasError && maxWeekNeedsIndex;

                      final maxWeek = useWeekFallback
                          ? 30
                          : (maxWeekSnap.data ?? 0);
                      final weeks = <int>[for (var i = 1; i <= maxWeek; i++) i];
                      if (_week != null && _week! > maxWeek) {
                        weeks.insert(0, _week!);
                      }

                      if (_week == null && maxWeek > 0) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() => _week = useWeekFallback ? 1 : maxWeek);
                        });
                      }

                      final effectiveWeek = _week;

                      return StreamBuilder<List<MatchModel>>(
                        stream: effectiveWeek == null
                            ? Stream<List<MatchModel>>.empty()
                            : _db.watchFixtureMatches(
                                leagueId,
                                effectiveWeek,
                                groupId: selectedGroupId,
                              ),
                        builder: (context, matchesSnap) {
                          if ((!useWeekFallback &&
                                  maxWeekSnap.connectionState ==
                                      ConnectionState.waiting) ||
                              matchesSnap.connectionState ==
                                  ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if ((maxWeekSnap.hasError && !useWeekFallback) ||
                              matchesSnap.hasError) {
                            final raw = (matchesSnap.error ?? maxWeekSnap.error)
                                .toString();
                            final needsIndex =
                                raw.contains('requires an index') ||
                                raw.contains('FAILED_PRECONDITION');
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  needsIndex
                                      ? 'Fikstür sorgusu için Firestore index gerekiyor. firestore.indexes.json deploy edildiyse, indexlerin Firebase Console’da “Building” sürecinin bitmesini bekleyin ve uygulamayı yeniden başlatın.'
                                      : 'Fikstür verisi alınamadı.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            );
                          }

                          final matches =
                              (matchesSnap.data ?? const <MatchModel>[])..sort((
                                a,
                                b,
                              ) {
                                final ad = (a.matchDate ?? '').trim();
                                final bd = (b.matchDate ?? '').trim();
                                final dcmp = ad.compareTo(bd);
                                if (dcmp != 0) return dcmp;
                                final at = (a.matchTime ?? '').trim();
                                final bt = (b.matchTime ?? '').trim();
                                if (at.isEmpty && bt.isEmpty) {
                                  return a.homeTeamName.toLowerCase().compareTo(
                                    b.homeTeamName.toLowerCase(),
                                  );
                                }
                                if (at.isEmpty) return 1;
                                if (bt.isEmpty) return -1;
                                final cmp = at.compareTo(bt);
                                if (cmp != 0) return cmp;
                                return a.homeTeamName.toLowerCase().compareTo(
                                  b.homeTeamName.toLowerCase(),
                                );
                              });

                          return Column(
                            children: [
                              Container(
                                color: headerForest,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  16,
                                  32,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      initialValue: leagueId,
                                      isExpanded: true,
                                      dropdownColor: cardBg,
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Colors.white,
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                      decoration: dec('Turnuva Seçin'),
                                      items: [
                                        for (final l in leagues)
                                          DropdownMenuItem(
                                            value: l.id,
                                            child: Text(
                                              l.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                      ],
                                      onChanged: (v) {
                                        setState(() {
                                          _leagueId = v;
                                          _groupId = null;
                                          _week = null;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String?>(
                                            initialValue: selectedGroupId,
                                            isExpanded: true,
                                            dropdownColor: cardBg,
                                            icon: const Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color: Colors.white,
                                            ),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                            ),
                                            decoration: dec('Grup Seçin'),
                                            items: groups.isEmpty
                                                ? const [
                                                    DropdownMenuItem<String?>(
                                                      value: null,
                                                      child: Text('-'),
                                                    ),
                                                  ]
                                                : [
                                                    const DropdownMenuItem<
                                                      String?
                                                    >(
                                                      value: null,
                                                      child: Text(
                                                        'Tümü',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w900,
                                                        ),
                                                      ),
                                                    ),
                                                    for (final g in groups)
                                                      DropdownMenuItem<String?>(
                                                        value: g,
                                                        child: Text(
                                                          '$g Grubu',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                              ),
                                                        ),
                                                      ),
                                                  ],
                                            onChanged: groups.isEmpty
                                                ? null
                                                : (v) => setState(
                                                    () => _groupId = v,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: DropdownButtonFormField<int?>(
                                            initialValue: _week,
                                            isExpanded: true,
                                            dropdownColor: cardBg,
                                            icon: const Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color: Colors.white,
                                            ),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                            ),
                                            decoration: dec('Hafta Seçin'),
                                            items: [
                                              if (weeks.isEmpty)
                                                const DropdownMenuItem<int?>(
                                                  value: null,
                                                  child: Text('-'),
                                                ),
                                              for (final w in weeks)
                                                DropdownMenuItem<int?>(
                                                  value: w,
                                                  child: Text(
                                                    '$w. Hafta',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                            onChanged: weeks.isEmpty
                                                ? null
                                                : (v) =>
                                                      setState(() => _week = v),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Transform.translate(
                                  offset: const Offset(0, -24),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: bgDark,
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(24),
                                      ),
                                    ),
                                    padding: const EdgeInsets.only(top: 18),
                                    child: matches.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'Maç bulunamadı.',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          )
                                        : _FixtureList(
                                            matches: matches,
                                            dateStripText: _dateStripText,
                                            groupNameById: groupNameById,
                                            showGroupInHeader:
                                                selectedGroupId == null,
                                            teamLogoById: teamLogoById,
                                            onMatchTap: (m) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      MatchDetailsScreen(
                                                        match: m,
                                                      ),
                                                ),
                                              );
                                            },
                                            surfaceContainerLow: cardBg,
                                            outlineVariant: outline,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
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

class _FixtureList extends StatelessWidget {
  const _FixtureList({
    required this.matches,
    required this.dateStripText,
    required this.groupNameById,
    required this.showGroupInHeader,
    required this.teamLogoById,
    required this.onMatchTap,
    required this.surfaceContainerLow,
    required this.outlineVariant,
  });

  final List<MatchModel> matches;
  final String Function(String yyyyMmDd) dateStripText;
  final Map<String, String> groupNameById;
  final bool showGroupInHeader;
  final Map<String, String> teamLogoById;
  final void Function(MatchModel match) onMatchTap;
  final Color surfaceContainerLow;
  final Color outlineVariant;

  @override
  Widget build(BuildContext context) {
    String groupLabel(String groupId) {
      final raw = (groupNameById[groupId] ?? '').trim();
      if (raw.isEmpty) return 'Grup';
      final base = raw.length <= 2 ? raw.toUpperCase() : raw;
      final hasGrup = RegExp(r'grup', caseSensitive: false).hasMatch(base);
      return hasGrup ? base : '$base Grubu';
    }

    final bySection = <String, List<MatchModel>>{};
    for (final m in matches) {
      final dateKey = (m.matchDate ?? '').trim().isEmpty
          ? '__NO_DATE__'
          : (m.matchDate ?? '').trim();
      final sectionKey = showGroupInHeader
          ? '$dateKey|${(m.groupId ?? '').trim()}'
          : dateKey;
      (bySection[sectionKey] ??= []).add(m);
    }

    final sectionKeys = bySection.keys.toList()
      ..sort((a, b) {
        String da(String key) => showGroupInHeader ? key.split('|').first : key;
        String ga(String key) => showGroupInHeader
            ? (key.split('|').length > 1 ? key.split('|')[1] : '')
            : '';

        final ad = da(a);
        final bd = da(b);
        if (ad == '__NO_DATE__' && bd == '__NO_DATE__') return 0;
        if (ad == '__NO_DATE__') return 1;
        if (bd == '__NO_DATE__') return -1;
        final dcmp = ad.compareTo(bd);
        if (dcmp != 0) return dcmp;
        if (!showGroupInHeader) return 0;
        return groupLabel(ga(a)).compareTo(groupLabel(ga(b)));
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        for (final k in sectionKeys)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  () {
                    final parts = showGroupInHeader ? k.split('|') : [k];
                    final dateKey = parts.first;
                    final dateText = dateKey == '__NO_DATE__'
                        ? 'Tarih Belirlenmedi'
                        : dateStripText(dateKey);
                    if (!showGroupInHeader) return dateText;
                    final groupId = parts.length > 1 ? parts[1] : '';
                    final grp = groupLabel(groupId);
                    return '$dateText - $grp';
                  }(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < bySection[k]!.length; i++) ...[
                  _MatchCard(
                    match: bySection[k]![i],
                    teamLogoById: teamLogoById,
                    onTap: () => onMatchTap(bySection[k]![i]),
                  ),
                  if (i != bySection[k]!.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.teamLogoById,
    required this.onTap,
  });

  final MatchModel match;
  final Map<String, String> teamLogoById;
  final VoidCallback onTap;

  Widget _logo(String url) {
    return SizedBox(
      width: 28,
      height: 28,
      child: WebSafeImage(
        url: url,
        width: 28,
        height: 28,
        isCircle: true,
        fallbackIconSize: 18,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFinished = match.status == MatchStatus.finished;
    final timeText = (match.matchTime ?? '').trim();
    final leftText = isFinished
        ? 'MS'
        : (timeText.isEmpty ? '--:--' : timeText);
    const fg = Color(0xFFF8FAFC);
    const mid = Color(0xFF94A3B8);
    const accent = Color(0xFF10B981);

    final homeLogo = match.homeTeamLogoUrl.trim().isNotEmpty
        ? match.homeTeamLogoUrl
        : (teamLogoById[match.homeTeamId] ?? '');
    final awayLogo = match.awayTeamLogoUrl.trim().isNotEmpty
        ? match.awayTeamLogoUrl
        : (teamLogoById[match.awayTeamId] ?? '');

    final showScore =
        isFinished || match.homeScore != 0 || match.awayScore != 0;
    final hs = match.homeScore;
    final as = match.awayScore;
    final homeWin = showScore && hs > as;
    final awayWin = showScore && as > hs;

    Widget scoreBox({required int score, required bool highlight}) {
      return SizedBox(
        width: 25,
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            showScore ? '$score' : '-',
            style: TextStyle(
              color: highlight ? fg : mid,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 46,
                child: Center(
                  child: Text(
                    leftText,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: isFinished ? accent : mid,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _logo(homeLogo),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            match.homeTeamName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: fg,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            scoreBox(
                              score: hs,
                              highlight: homeWin || !showScore,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _logo(awayLogo),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            match.awayTeamName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: fg,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            scoreBox(
                              score: as,
                              highlight: awayWin || !showScore,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
