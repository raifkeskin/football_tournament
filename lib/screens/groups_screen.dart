import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/league.dart';
import '../services/database_service.dart';
import '../widgets/web_safe_image.dart';
import 'team_squad_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, this.initialLeagueId, this.initialGroupId});

  final String? initialLeagueId;
  final String? initialGroupId;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _databaseService = DatabaseService();
  String? _selectedLeagueId;
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _selectedLeagueId = widget.initialLeagueId;
    _selectedGroupId = widget.initialGroupId;
  }

  @override
  Widget build(BuildContext context) {
    const headerGreen = Color(0xFF064E3B);
    const bgDark = Color(0xFF0F172A);
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        title: const Text('Gruplar / Puan Durumu'),
        centerTitle: true,
        backgroundColor: headerGreen,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: _databaseService.getLeagues(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              final leagues =
                  snapshot.data!.docs
                      .map(
                        (doc) => League.fromMap({
                          ...doc.data() as Map<String, dynamic>,
                          'id': doc.id,
                        }),
                      )
                      .toList()
                    ..sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    );
              if (leagues.isEmpty) return const SizedBox();

              final leagueIds = leagues.map((l) => l.id).toSet();
              if (_selectedLeagueId == null ||
                  !leagueIds.contains(_selectedLeagueId)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _selectedLeagueId = leagues.first.id;
                    _selectedGroupId = null;
                  });
                });
              }

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

              return Container(
                color: headerGreen,
                height: 120,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                alignment: Alignment.topCenter,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedLeagueId,
                        dropdownColor: const Color(0xFF1E293B),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        iconEnabledColor: Colors.white,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                        decoration: dec('Turnuva Seçin'),
                        items: leagues
                            .map(
                              (l) => DropdownMenuItem(
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
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedLeagueId = val;
                            _selectedGroupId = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _selectedLeagueId == null
                          ? const SizedBox.shrink()
                          : StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('groups')
                                  .where(
                                    'tournamentId',
                                    isEqualTo: _selectedLeagueId,
                                  )
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const SizedBox.shrink();
                                }
                                final groupDocs = snapshot.data!.docs;

                                if (_selectedGroupId != null &&
                                    !groupDocs
                                        .map((d) => d.id)
                                        .contains(_selectedGroupId)) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (!mounted) return;
                                    setState(() => _selectedGroupId = null);
                                  });
                                }

                                return DropdownButtonFormField<String?>(
                                  initialValue: _selectedGroupId,
                                  dropdownColor: const Color(0xFF1E293B),
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                  ),
                                  iconEnabledColor: Colors.white,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  decoration: dec('Grup Seçin'),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text(
                                        'Tümü',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    for (final doc in groupDocs)
                                      DropdownMenuItem<String?>(
                                        value: doc.id,
                                        child: Text(
                                          (doc.data()
                                                  as Map<
                                                    String,
                                                    dynamic
                                                  >)['name'] ??
                                              'Grup',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                  ],
                                  onChanged: (val) =>
                                      setState(() => _selectedGroupId = val),
                                  menuMaxHeight: 360,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: _selectedLeagueId == null
                ? const Center(
                    child: Text(
                      'Lütfen bir turnuva seçin.',
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('groups')
                        .where('tournamentId', isEqualTo: _selectedLeagueId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final allGroupDocs = snapshot.data!.docs;

                      if (allGroupDocs.isEmpty) {
                        return const Center(
                          child: Text(
                            'Bu turnuvada henüz grup oluşturulmamış.',
                            style: TextStyle(color: Colors.white),
                          ),
                        );
                      }

                      final displayedGroupDocs = _selectedGroupId == null
                          ? allGroupDocs
                          : allGroupDocs
                                .where((d) => d.id == _selectedGroupId)
                                .toList();

                      return Transform.translate(
                        offset: const Offset(0, -24),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
                          itemCount: displayedGroupDocs.length,
                          itemBuilder: (context, index) {
                            final groupDoc = displayedGroupDocs[index];
                            final groupData =
                                groupDoc.data() as Map<String, dynamic>;
                            final groupName = groupData['name'] ?? 'Grup';
                            return _GroupStandingsTable(
                              leagueId: _selectedLeagueId!,
                              groupId: groupDoc.id,
                              groupName: groupName,
                              databaseService: _databaseService,
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _GroupStandingsTable extends StatelessWidget {
  final String leagueId;
  final String groupId;
  final String groupName;
  final DatabaseService databaseService;

  const _GroupStandingsTable({
    required this.leagueId,
    required this.groupId,
    required this.groupName,
    required this.databaseService,
  });

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? 0;
  }

  bool _isCompleted(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().trim();
    if (status == 'finished') return true;
    final isCompleted = data['isCompleted'];
    return isCompleted == true;
  }

  @override
  Widget build(BuildContext context) {
    const bgDark = Color(0xFF0F172A);
    const tableBg = Color(0xFF1E293B);
    const midText = Color(0xFF94A3B8);
    const accentGreen = Color(0xFF10B981);
    const trophy = Color(0xFFFBBF24);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('teams')
            .where('groupId', isEqualTo: groupId)
            .snapshots(),
        builder: (context, teamsSnapshot) {
          if (teamsSnapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final teamDocs = teamsSnapshot.data?.docs ?? [];
          final standings = <String, Map<String, dynamic>>{};
          final teamNames = <String, String>{};
          final teamLogos = <String, String>{};

          for (final teamDoc in teamDocs) {
            final teamData = teamDoc.data() as Map<String, dynamic>;
            final teamId = teamDoc.id;
            final teamName = (teamData['name'] ?? '').toString();
            final teamLogo = (teamData['logoUrl'] ?? '').toString();

            teamNames[teamId] = teamName;
            teamLogos[teamId] = teamLogo;
            standings[teamId] = {
              'P': 0,
              'G': 0,
              'B': 0,
              'M': 0,
              'AG': 0,
              'YG': 0,
              'AV': 0,
              'Puan': 0,
            };
          }

          if (standings.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  'Grup $groupName için henüz takım/maç verisi yok.',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('matches')
                .where('leagueId', isEqualTo: leagueId)
                .where('groupId', isEqualTo: groupId)
                .snapshots(),
            builder: (context, matchesSnapshot) {
              if (matchesSnapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (matchesSnapshot.hasData) {
                for (final matchDoc in matchesSnapshot.data!.docs) {
                  final m = matchDoc.data() as Map<String, dynamic>;
                  final hId = (m['homeTeamId'] ?? '').toString();
                  final aId = (m['awayTeamId'] ?? '').toString();

                  if (_isCompleted(m) &&
                      standings.containsKey(hId) &&
                      standings.containsKey(aId)) {
                    final hS = _asInt(m['homeScore']);
                    final aS = _asInt(m['awayScore']);

                    standings[hId]!['P'] = standings[hId]!['P']! + 1;
                    standings[aId]!['P'] = standings[aId]!['P']! + 1;
                    standings[hId]!['AG'] = standings[hId]!['AG']! + hS;
                    standings[hId]!['YG'] = standings[hId]!['YG']! + aS;
                    standings[aId]!['AG'] = standings[aId]!['AG']! + aS;
                    standings[aId]!['YG'] = standings[aId]!['YG']! + hS;

                    if (hS > aS) {
                      standings[hId]!['G'] = standings[hId]!['G']! + 1;
                      standings[hId]!['Puan'] =
                          standings[hId]!['Puan']! + 3;
                      standings[aId]!['M'] = standings[aId]!['M']! + 1;
                    } else if (aS > hS) {
                      standings[aId]!['G'] = standings[aId]!['G']! + 1;
                      standings[aId]!['Puan'] =
                          standings[aId]!['Puan']! + 3;
                      standings[hId]!['M'] = standings[hId]!['M']! + 1;
                    } else {
                      standings[hId]!['B'] = standings[hId]!['B']! + 1;
                      standings[aId]!['B'] = standings[aId]!['B']! + 1;
                      standings[hId]!['Puan'] =
                          standings[hId]!['Puan']! + 1;
                      standings[aId]!['Puan'] =
                          standings[aId]!['Puan']! + 1;
                    }
                  }
                }
              }

              standings.forEach((k, v) {
                v['AV'] = v['AG']! - v['YG']!;
              });

              final sortedTeamIds = standings.keys.toList()
                ..sort((a, b) {
                  final sa = standings[a]!;
                  final sb = standings[b]!;
                  final pA = _asInt(sa['Puan']);
                  final pB = _asInt(sb['Puan']);
                  if (pB != pA) return pB.compareTo(pA);
                  final avA = _asInt(sa['AV']);
                  final avB = _asInt(sb['AV']);
                  if (avB != avA) return avB.compareTo(avA);
                  final agA = _asInt(sa['AG']);
                  final agB = _asInt(sb['AG']);
                  if (agB != agA) return agB.compareTo(agA);
                  return teamNames[a]!.toLowerCase().compareTo(
                    teamNames[b]!.toLowerCase(),
                  );
                });

              Widget headerCell(
                String text, {
                required double width,
                bool highlight = false,
              }) {
                return SizedBox(
                  width: width,
                  child: Center(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: highlight ? accentGreen : midText,
                      ),
                    ),
                  ),
                );
              }

              String groupLabel() {
                final name = groupName.trim();
                if (name.isEmpty) return 'GRUP';
                final upper = name.toUpperCase();
                return upper.contains('GRUP') ? upper : '$upper GRUBU';
              }

              return Container(
                decoration: BoxDecoration(
                  color: tableBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_rounded,
                          color: trophy,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'PUAN DURUMU',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          groupLabel(),
                          style: const TextStyle(
                            color: midText,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Divider(
                        color: midText.withValues(alpha: 0.35), height: 1),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: bgDark.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: midText.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            child: Center(
                              child: Text(
                                '#',
                                style: TextStyle(
                                  color: midText,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'TAKIMLAR',
                              style: TextStyle(
                                color: midText,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          headerCell('O', width: 20),
                          headerCell('G', width: 20),
                          headerCell('B', width: 20),
                          headerCell('M', width: 20),
                          headerCell('A', width: 20),
                          headerCell('Y', width: 20),
                          headerCell('AV', width: 28),
                          headerCell('P', width: 26, highlight: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: sortedTeamIds.length,
                      separatorBuilder: (_, _) => Divider(
                        color: midText.withValues(alpha: 0.18),
                        height: 1,
                      ),
                      itemBuilder: (context, i) {
                        final tId = sortedTeamIds[i];
                        final stats = standings[tId]!;
                        final tName = teamNames[tId] ?? 'Takım';
                        final tLogo = teamLogos[tId] ?? '';
                        return _StandingsRow(
                          index: i,
                          teamId: tId,
                          teamName: tName,
                          teamLogo: tLogo,
                          stats: stats,
                          totalCount: sortedTeamIds.length,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TeamSquadScreen(
                                  teamId: tId,
                                  tournamentId: leagueId,
                                  teamName: tName,
                                  teamLogoUrl: tLogo,
                                ),
                              ),
                            );
                          },
                        );
                      },
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

class _StandingsRow extends StatelessWidget {
  const _StandingsRow({
    required this.index,
    required this.teamId,
    required this.teamName,
    required this.teamLogo,
    required this.stats,
    required this.totalCount,
    required this.onTap,
  });

  final int index;
  final String teamId;
  final String teamName;
  final String teamLogo;
  final Map<String, dynamic> stats;
  final int totalCount;
  final VoidCallback onTap;

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  String _shortenMasters(String s) {
    return s
        .replaceAll('Masterlar', 'M.')
        .replaceAll('Master', 'M.')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    const midText = Color(0xFF94A3B8);
    const teamText = Color(0xFFF8FAFC);
    const accentGreen = Color(0xFF10B981);
    const classOrange = Color(0xFFF59E0B);
    const rowBg = Color(0xFF1E293B);
    const logoBg = Color(0xFF334155);

    Widget cell(
      dynamic text, {
      FontWeight weight = FontWeight.w700,
      Color? color,
      double width = 22,
      double fontSize = 11,
      FontStyle? fontStyle,
    }) {
      return SizedBox(
        width: width,
        child: Center(
          child: Text(
            text.toString(),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: weight,
              fontStyle: fontStyle,
              color: color ?? midText,
            ),
          ),
        ),
      );
    }

    final displayName = _shortenMasters(teamName);
    final url = _normalizeUrl(teamLogo);
    final isElite = index < 4;
    final isClass = totalCount >= 4 && index >= (totalCount - 4);
    final stripeColor = isElite
        ? accentGreen
        : (isClass ? classOrange : Colors.transparent);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: rowBg,
        child: Row(
          children: [
            SizedBox(
              width: 10,
              height: 46,
              child: Center(
                child: Container(
                  width: 3,
                  height: 25,
                  decoration: BoxDecoration(
                    color: stripeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 20,
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: teamText,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: logoBg,
                    ),
                    child: WebSafeImage(
                      url: url,
                      width: 20,
                      height: 20,
                      isCircle: true,
                      fallbackIconSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: teamText,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            cell(stats['P']),
            cell(stats['G']),
            cell(stats['B']),
            cell(stats['M']),
            cell(stats['AG']),
            cell(stats['YG']),
            cell(stats['AV'], width: 28),
            cell(
              stats['Puan'],
              width: 26,
              weight: FontWeight.w900,
              color: accentGreen,
              fontSize: 14,
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
