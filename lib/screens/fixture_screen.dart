import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // TextInputFormatter için gerekli
import 'package:intl/intl.dart';

import '../models/league.dart';
import '../models/match.dart';
import '../models/team.dart';
import '../services/app_session.dart';
import '../services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../services/interfaces/i_team_service.dart';
import '../services/service_locator.dart';
import '../widgets/web_safe_image.dart';
import 'match_details_screen.dart';

class FixtureScreen extends StatefulWidget {
  const FixtureScreen({super.key});

  @override
  State<FixtureScreen> createState() => _FixtureScreenState();
}

class _FixtureScreenState extends State<FixtureScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final IMatchService _matchService = ServiceLocator.matchService;
  final ITeamService _teamService = ServiceLocator.teamService;
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
    final bool isAdmin = AppSession.of(context).value.isAdmin;

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
      body: StreamBuilder<List<Team>>(
        stream: _teamService.watchAllTeams(),
        builder: (context, teamsSnap) {
          final teamLogoById = <String, String>{};
          final teamNameById = <String, String>{};
          if (teamsSnap.hasData) {
            for (final t in teamsSnap.data!) {
              teamLogoById[t.id] = t.logoUrl;
              teamNameById[t.id] = t.name;
            }
          }

          return StreamBuilder<List<League>>(
            stream: _leagueService.watchLeagues(),
            builder: (context, leaguesSnap) {
              if (!leaguesSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final leagues = [...(leaguesSnap.data ?? const <League>[])];

              if (leagues.isEmpty) {
                return const Center(child: Text('Turnuva bulunamadı.'));
              }

              _leagueId ??= leagues.any((l) => l.isDefault)
                  ? (leagues.where((l) => l.isDefault).first.id)
                  : leagues.first.id;

              return StreamBuilder<List<GroupModel>>(
                stream: _leagueId == null
                    ? const Stream<List<GroupModel>>.empty()
                    : _leagueService.watchGroups(_leagueId!),
                builder: (context, snapshot) {
                  final groupsRaw = snapshot.data ?? const <GroupModel>[];
                  final groups = [...groupsRaw]
                    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                  String groupDisplayName(GroupModel g, int index) {
                    final name = g.name.trim();
                    if (name.isNotEmpty) return name;
                    return 'Grup ${index + 1}';
                  }

                  final groupNameById = <String, String>{
                    for (final e in groups.indexed) e.$2.id: groupDisplayName(e.$2, e.$1),
                  };

                  final selectedGroupId =
                      (_groupId != null && groupNameById.containsKey(_groupId)) ? _groupId : null;
                  final showGroupInHeader = selectedGroupId == null && groups.length > 1;

                  return FutureBuilder<int?>(
                    key: ValueKey('$_leagueId|$selectedGroupId'),
                    future: _matchService.getFixtureMaxWeek(
                      _leagueId!,
                      groupId: selectedGroupId,
                    ),
                    builder: (context, maxWeekSnap) {
                      final maxWeek = maxWeekSnap.data ?? 30;
                      final weeks = <int>[for (var i = 1; i <= maxWeek; i++) i];

                      if (_week == null && maxWeek > 0) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _week = 1);
                        });
                      }

                      return StreamBuilder<List<MatchModel>>(
                        stream: _week == null
                            ? Stream.empty()
                            : _matchService.watchFixtureMatches(
                                _leagueId!,
                                _week!,
                                groupId: selectedGroupId,
                              ),
                        builder: (context, matchesSnap) {
                          if (matchesSnap.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final matches = (matchesSnap.data ?? [])
                            ..sort((a, b) {
                              // Önce tarihe göre sırala (2026-04-18, 2026-04-19 gibi)
                              int dateComp = (a.matchDate ?? '').compareTo(
                                b.matchDate ?? '',
                              );
                              if (dateComp != 0) return dateComp;

                              // Eğer tarihler aynıysa, saate göre sırala (18:00, 19:00 gibi)
                              return (a.matchTime ?? '').compareTo(
                                b.matchTime ?? '',
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
                                  children: [
                                    _buildDropdown(
                                      'Turnuva Seçin',
                                      _leagueId,
                                      leagues
                                          .map(
                                            (l) => DropdownMenuItem(
                                              value: l.id,
                                              child: Text(l.name),
                                            ),
                                          )
                                          .toList(),
                                      (v) => setState(() {
                                        _leagueId = v;
                                        _groupId = null;
                                        _week = null;
                                      }),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildDropdown(
                                            'Grup Seçin',
                                            selectedGroupId,
                                            [
                                              const DropdownMenuItem(
                                                value: null,
                                                child: Text('Tümü'),
                                              ),
                                              ...groups.indexed.map((e) {
                                                final g = e.$2;
                                                final label = groupNameById[g.id] ?? '';
                                                return DropdownMenuItem(
                                                  value: g.id,
                                                  child: Text(label),
                                                );
                                              }),
                                            ],
                                            (v) => setState(() => _groupId = v),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildDropdown(
                                            'Hafta Seçin',
                                            _week,
                                            weeks
                                                .map(
                                                  (w) => DropdownMenuItem(
                                                    value: w,
                                                    child: Text('$w. Hafta'),
                                                  ),
                                                )
                                                .toList(),
                                            (v) => setState(() => _week = v),
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
                                            showGroupInHeader: showGroupInHeader,
                                            teamLogoById: teamLogoById,
                                          teamNameById: teamNameById,
                                            isAdmin: isAdmin,
                                            onMatchTap: (m) => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    MatchDetailsScreen(
                                                      match: m,
                                                    ),
                                              ),
                                            ),
                                            cardColor: cardBg,
                                            outlineColor: outline,
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

  Widget _buildDropdown(
    String label,
    dynamic value,
    List<DropdownMenuItem<dynamic>> items,
    Function(dynamic) onChanged,
  ) {
    return DropdownButtonFormField(
      initialValue: value,
      isExpanded: true,
      dropdownColor: const Color(0xFF1E293B),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      items: items,
      onChanged: onChanged,
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
    required this.teamNameById,
    required this.onMatchTap,
    required this.cardColor,
    required this.outlineColor,
    required this.isAdmin,
  });

  final List<MatchModel> matches;
  final String Function(String yyyyMmDd) dateStripText;
  final Map<String, String> groupNameById;
  final bool showGroupInHeader;
  final Map<String, String> teamLogoById;
  final Map<String, String> teamNameById;
  final void Function(MatchModel match) onMatchTap;
  final Color cardColor;
  final Color outlineColor;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    String groupLabel(String groupId) {
      final name = groupNameById[groupId] ?? 'Grup';
      return name.toLowerCase().contains('grup') ? name : '$name Grubu';
    }

    // 1. AŞAMA: Maçları Tarihe Göre Grupla
    final byDate = <String, List<MatchModel>>{};
    for (final m in matches) {
      final dateKey = (m.matchDate ?? '').trim().isEmpty
          ? '__NO_DATE__'
          : m.matchDate!.trim();
      (byDate[dateKey] ??= []).add(m);
    }

    final sortedDates = byDate.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        for (final dKey in sortedDates)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: outlineColor.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ANA TARİH BAŞLIĞI (Panelin en üstünde tek sefer)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 4),
                  child: Text(
                    dKey == '__NO_DATE__'
                        ? 'Tarih Belirlenmedi'
                        : dateStripText(dKey),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 12),

                // 2. AŞAMA: O Günkü Maçları Gruplara Bölerek Listele
                ..._buildGroupedSection(byDate[dKey]!, groupLabel),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _buildGroupedSection(
    List<MatchModel> matchesInDate,
    String Function(String) groupLabel,
  ) {
    // O tarihteki maçları kendi içinde gruplara ayır
    final groupedByGroup = <String, List<MatchModel>>{};
    for (var m in matchesInDate) {
      final gId = m.groupId ?? '';
      (groupedByGroup[gId] ??= []).add(m);
    }

    final sortedGroupIds = groupedByGroup.keys.toList()..sort();
    final List<Widget> items = [];

    for (var gId in sortedGroupIds) {
      // Eğer "Tümü" seçiliyse (showGroupInHeader true) grup başlıklarını göster
      if (showGroupInHeader && gId.isNotEmpty) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              groupLabel(gId).toUpperCase(),
              style: TextStyle(
                color: Colors.amberAccent.withOpacity(0.8),
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ),
        );
      }

      // Grubun maçlarını ekle
      for (var m in groupedByGroup[gId]!) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MatchCard(
              match: m,
              teamLogoById: teamLogoById,
              teamNameById: teamNameById,
              isAdmin: isAdmin,
              onTap: () => onMatchTap(m),
            ),
          ),
        );
      }
    }
    return items;
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.teamLogoById,
    required this.teamNameById,
    required this.onTap,
    required this.isAdmin,
  });

  static final IMatchService _matchService = ServiceLocator.matchService;
  static final ILeagueService _leagueService = ServiceLocator.leagueService;

  final MatchModel match;
  final Map<String, String> teamLogoById;
  final Map<String, String> teamNameById;
  final VoidCallback onTap;
  final bool isAdmin;

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

    final homeLogo = (teamLogoById[match.homeTeamId] ?? '').trim();
    final awayLogo = (teamLogoById[match.awayTeamId] ?? '').trim();
    final homeName = (teamNameById[match.homeTeamId] ?? '').trim();
    final awayName = (teamNameById[match.awayTeamId] ?? '').trim();

    final hs = match.homeScore;
    final as = match.awayScore;
    final showScore = isFinished || hs != 0 || as != 0;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: () {
          final role = AppSession.of(context).value.role;
          if (role != 'super_admin') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bu işlem için Super Admin yetkisi gereklidir.'),
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }
          _showQuickScoreDialog(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 50,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isAdmin)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          Icons.edit_calendar,
                          size: 22,
                          color: Colors.white,
                        ),
                        onPressed: () => _showEditPopup(context),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      leftText,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: isFinished ? accent : mid,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _teamRow(
                      homeName.isEmpty ? 'Ev Sahibi' : homeName,
                      homeLogo,
                      hs,
                      showScore,
                      hs >= as,
                    ),
                    const SizedBox(height: 12),
                    _teamRow(
                      awayName.isEmpty ? 'Deplasman' : awayName,
                      awayLogo,
                      as,
                      showScore,
                      as >= hs,
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

  Widget _teamRow(
    String name,
    String logo,
    int score,
    bool showScore,
    bool highlight,
  ) {
    return Row(
      children: [
        _logo(logo),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: highlight ? Colors.white : Colors.white70,
              fontSize: 13,
            ),
          ),
        ),
        SizedBox(
          width: 25,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              showScore ? '$score' : '-',
              style: TextStyle(
                color: highlight ? Colors.white : Colors.white38,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showQuickScoreDialog(BuildContext context) {
    final homeName = (teamNameById[match.homeTeamId] ?? '').trim();
    final awayName = (teamNameById[match.awayTeamId] ?? '').trim();
    final homeScoreCtrl = TextEditingController(
      text: match.homeScore.toString(),
    );
    final awayScoreCtrl = TextEditingController(
      text: match.awayScore.toString(),
    );

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        title: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            color: Color(0xFF064E3B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: const Text(
            'Hızlı Skor Girişi',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${homeName.isEmpty ? 'Ev Sahibi' : homeName} - ${awayName.isEmpty ? 'Deplasman' : awayName}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: homeScoreCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF10B981),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  '-',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: awayScoreCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF10B981),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('İptal', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final homeScore = int.tryParse(homeScoreCtrl.text) ?? 0;
              final awayScore = int.tryParse(awayScoreCtrl.text) ?? 0;

              await _matchService.completeMatchWithScoreAndDefaultEvents(
                matchId: match.id,
                homeScore: homeScore,
                awayScore: awayScore,
              );

              if (c.mounted) Navigator.pop(c);
            },
            child: const Text(
              'KAYDET',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditPopup(BuildContext context) async {
    // DB Formatını (YYYY-MM-DD) -> GG/AA/YYYY'ye Çevir
    String initialDate = '';
    if (match.matchDate != null && match.matchDate!.contains('-')) {
      final p = match.matchDate!.split('-');
      if (p.length == 3) initialDate = '${p[2]}/${p[1]}/${p[0]}';
    } else {
      initialDate = match.matchDate ?? '';
    }

    final dCtrl = TextEditingController(text: initialDate);
    final tCtrl = TextEditingController(text: match.matchTime ?? '');
    final dateFocus = FocusNode();
    final timeFocus = FocusNode();

    String? selectedPitch = match.pitchName;

    final pitches = await _leagueService.listPitchesOnce();

    // Tek bir stad varsa otomatik seç
    if (pitches.length == 1) {
      selectedPitch = pitches.first;
    }

    // Tarih tamam olduğunda otomatik saat field'ine geç
    dCtrl.addListener(() {
      if (dCtrl.text.length == 10) {
        // DD/MM/YYYY = 10 karakter
        timeFocus.requestFocus();
      }
    });

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Maçı Düzenle',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // TARİH INPUT
                TextField(
                  controller: dCtrl,
                  focusNode: dateFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_DateInputFormatter()],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Tarih (GG/AA/YYYY)',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
                const SizedBox(
                  height: 25,
                ), // Üst üste binmeyi engellemek için boşluk artırıldı
                // SAAT INPUT
                TextField(
                  controller: tCtrl,
                  focusNode: timeFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_TimeInputFormatter()],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Saat (SS:DD)',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                DropdownButtonFormField<String>(
                  initialValue: pitches.contains(selectedPitch) ? selectedPitch : null,
                  dropdownColor: const Color(0xFF0F172A),
                  decoration: const InputDecoration(
                    labelText: 'Stad Seçin',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                  ),
                  items: pitches
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            p,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedPitch = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text(
                'İptal',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
              ),
              onPressed: () async {
                final dateText = dCtrl.text;
                final timeText = tCtrl.text;

                // VALIDATION (Doğrulama)
                if (dateText.length != 10) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tarih formatı hatalı! (GG/AA/YYYY)'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }
                if (timeText.length != 5) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Saat formatı hatalı! (SS:DD)'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                // Tekrar DB Formatına Çevir (GG/AA/YYYY -> YYYY-MM-DD)
                final parts = dateText.split('/');
                final dbDate = '${parts[2]}-${parts[1]}-${parts[0]}';

                await _matchService.updateMatchSchedule(
                  matchId: match.id,
                  matchDateDb: dbDate,
                  matchTime: timeText,
                  pitchName: selectedPitch,
                );
                if (context.mounted) {
                  dateFocus.dispose();
                  timeFocus.dispose();
                  dCtrl.dispose();
                  tCtrl.dispose();
                  Navigator.pop(c);
                }
              },
              child: const Text(
                'GÜNCELLE',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- OTOMATİK FORMATLAYICILAR ---

class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Silme işlemini izin ver
    if (newValue.text.isEmpty) return newValue;
    if (newValue.text.length < oldValue.text.length) return newValue;

    // Sadece rakamları al
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // Max 8 rakam (DD/MM/YYYY)
    if (digitsOnly.length > 8) {
      digitsOnly = digitsOnly.substring(0, 8);
    }

    // Formatla
    String formatted = '';
    for (int i = 0; i < digitsOnly.length; i++) {
      formatted += digitsOnly[i];
      // 2. ve 4. rakamdan sonra / ekle
      if (i == 1 || i == 3) {
        formatted += '/';
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _TimeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length < oldValue.text.length) {
      return newValue; // Silme işlemi
    }

    String cleanText = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanText.length > 4) {
      cleanText = cleanText.substring(0, 4); // Max 4 rakam
    }

    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < cleanText.length; i++) {
      buffer.write(cleanText[i]);
      if (i == 1) buffer.write(':'); // 2. rakamdan sonra anında : ekle
    }

    String finalString = buffer.toString();
    return TextEditingValue(
      text: finalString,
      selection: TextSelection.collapsed(offset: finalString.length),
    );
  }
}
