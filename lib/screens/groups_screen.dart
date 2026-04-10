import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/league.dart';
import '../models/match.dart'; // GroupModel burada
import '../models/team.dart';
import '../services/database_service.dart';
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Gruplar / Puan Durumu')),
      body: Column(
        children: [
          // Turnuva ve Grup Seçiciler
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
                  if (mounted) {
                    setState(() {
                      _selectedLeagueId = leagues.first.id;
                      if (widget.initialLeagueId != leagues.first.id) {
                        _selectedGroupId = null;
                      }
                    });
                  }
                });
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          value: _selectedLeagueId,
                          decoration: const InputDecoration(
                            labelText: 'Turnuva Seçin',
                            border: OutlineInputBorder(),
                          ),
                          items: leagues
                              .map(
                                (l) => DropdownMenuItem(
                                  value: l.id,
                                  child: Center(
                                    child: Text(
                                      l.name,
                                      textAlign: TextAlign.center,
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
                        if (_selectedLeagueId != null) ...[
                          const SizedBox(height: 12),
                          StreamBuilder<List<GroupModel>>(
                            stream: _databaseService.getGroups(
                              _selectedLeagueId!,
                            ),
                            builder: (context, groupSnapshot) {
                              if (!groupSnapshot.hasData ||
                                  groupSnapshot.data!.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              final groups = [...groupSnapshot.data!]
                                ..sort(
                                  (a, b) => a.name.toLowerCase().compareTo(
                                    b.name.toLowerCase(),
                                  ),
                                );
                              final groupIds = groups.map((g) => g.id).toSet();
                              if (_selectedGroupId != null &&
                                  !groupIds.contains(_selectedGroupId)) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted)
                                    setState(() => _selectedGroupId = null);
                                });
                              }

                              if (_selectedGroupId == null) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  setState(
                                    () => _selectedGroupId = groups.first.id,
                                  );
                                });
                              }

                              return DropdownButtonFormField<String>(
                                value: _selectedGroupId,
                                decoration: const InputDecoration(
                                  labelText: 'Grup Seçin',
                                  border: OutlineInputBorder(),
                                ),
                                items: groups
                                    .map(
                                      (g) => DropdownMenuItem(
                                        value: g.id,
                                        child: Center(
                                          child: Text(
                                            g.name,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) =>
                                    setState(() => _selectedGroupId = val),
                                menuMaxHeight: 360,
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Divider(color: Colors.grey.shade300, height: 1),
          Expanded(
            child: _selectedLeagueId == null
                ? const Center(child: Text('Lütfen bir turnuva seçin.'))
                : StreamBuilder<List<GroupModel>>(
                    stream: _databaseService.getGroups(_selectedLeagueId!),
                    builder: (context, groupSnapshot) {
                      if (groupSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final allGroups = (groupSnapshot.data ?? []).toList()
                        ..sort(
                          (a, b) => a.name.toLowerCase().compareTo(
                            b.name.toLowerCase(),
                          ),
                        );
                      if (allGroups.isEmpty) {
                        return const Center(
                          child: Text(
                            'Bu turnuvada henüz grup oluşturulmamış.',
                          ),
                        );
                      }

                      // Filtreleme: Eğer bir grup seçilmişse sadece onu göster, seçilmemişse hepsini göster (veya boş bırak)
                      final displayedGroups = _selectedGroupId == null
                          ? allGroups
                          : allGroups
                                .where((g) => g.id == _selectedGroupId)
                                .toList();

                      return ListView.builder(
                        itemCount: displayedGroups.length,
                        itemBuilder: (context, index) {
                          final group = displayedGroups[index];
                          return _GroupStandingsTable(
                            group: group,
                            databaseService: _databaseService,
                          );
                        },
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
  final GroupModel group;
  final DatabaseService databaseService;

  const _GroupStandingsTable({
    required this.group,
    required this.databaseService,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('teams')
                .where('groupId', isEqualTo: group.id)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Bu grupta henüz takım yok.',
                    textAlign: TextAlign.center,
                  ),
                );
              }

              final teams = snapshot.data!.docs
                  .map(
                    (doc) => Team.fromMap({
                      ...doc.data() as Map<String, dynamic>,
                      'id': doc.id,
                    }),
                  )
                  .toList();

              teams.sort((a, b) {
                final sA = a.stats ?? {};
                final sB = b.stats ?? {};
                int cmp = (sB['Puan'] ?? 0).compareTo(sA['Puan'] ?? 0);
                if (cmp == 0) cmp = (sB['AV'] ?? 0).compareTo(sA['AV'] ?? 0);
                if (cmp == 0) cmp = (sB['AG'] ?? 0).compareTo(sA['AG'] ?? 0);
                return cmp;
              });

              Widget headerCell(String text, {double width = 20}) {
                return SizedBox(
                  width: width,
                  child: Center(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.emoji_events_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'PUAN DURUMU',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 24,
                          child: Center(child: Text('#')),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Takımlar',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        headerCell('O'),
                        headerCell('G'),
                        headerCell('B'),
                        headerCell('M'),
                        headerCell('A'),
                        headerCell('Y'),
                        headerCell('AV', width: 24),
                        headerCell('P', width: 22),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < teams.length; i++)
                    _StandingsRow(
                      index: i,
                      team: teams[i],
                      primary: cs.primary,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TeamSquadScreen(
                              teamId: teams[i].id,
                              teamName: teams[i].name,
                              teamLogoUrl: teams[i].logoUrl,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StandingsRow extends StatelessWidget {
  const _StandingsRow({
    required this.index,
    required this.team,
    required this.primary,
    required this.onTap,
  });

  final int index;
  final Team team;
  final Color primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = team.stats ?? const <String, dynamic>{};
    final zebra =
        index.isEven ? Colors.white : const Color(0xFFF2F2F2);

    Widget cell(
      String text, {
      FontWeight weight = FontWeight.w700,
      Color? color,
      double width = 20,
      double fontSize = 12,
      FontStyle? fontStyle,
    }) {
      return SizedBox(
        width: width,
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: weight,
              fontStyle: fontStyle,
              color: color,
            ),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: zebra,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _TakimAmblemi(
                logoUrl: team.logoUrl,
                takimAdi: team.name,
                size: 32,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    team.name,
                    textAlign: TextAlign.left,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      height: 1.08,
                    ),
                  ),
                ),
              ),
              cell('${s['P'] ?? 0}'),
              cell('${s['G'] ?? 0}'),
              cell('${s['B'] ?? 0}'),
              cell('${s['M'] ?? 0}'),
              cell('${s['AG'] ?? 0}'),
              cell('${s['YG'] ?? 0}'),
              cell('${s['AV'] ?? 0}', width: 24),
              cell(
                '${s['Puan'] ?? 0}',
                width: 22,
                weight: FontWeight.w900,
                color: Colors.black,
                fontSize: 16,
                fontStyle: FontStyle.italic,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TakimAmblemi extends StatelessWidget {
  const _TakimAmblemi({
    required this.logoUrl,
    required this.takimAdi,
    this.size = 40,
  });
  final String logoUrl;
  final String takimAdi;
  final double size;

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = takimAdi.isNotEmpty ? takimAdi[0].toUpperCase() : '?';
    final url = _normalizeUrl(logoUrl);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.primary.withValues(alpha: 0.14),
      ),
      alignment: Alignment.center,
      child: url.isNotEmpty
          ? ClipOval(
              child: Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.sports_soccer, size: 20, color: cs.primary),
              ),
            )
          : Text(
              initial,
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
            ),
    );
  }
}
