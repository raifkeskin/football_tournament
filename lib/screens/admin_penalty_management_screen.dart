import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/match.dart';
import '../models/team.dart';
import '../services/database_service.dart';

class AdminPenaltyManagementScreen extends StatefulWidget {
  const AdminPenaltyManagementScreen({super.key});

  @override
  State<AdminPenaltyManagementScreen> createState() =>
      _AdminPenaltyManagementScreenState();
}

class _AdminPenaltyManagementScreenState
    extends State<AdminPenaltyManagementScreen> {
  final _dbService = DatabaseService();

  Future<void> _openPenaltyForm({
    required List<Team> teams,
    PlayerModel? editing,
  }) async {
    String? teamId = editing?.teamId;
    String? playerId = editing?.id;
    final suspendedController = TextEditingController(
      text: editing != null ? editing.suspendedMatches.toString() : '',
    );
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final insets = MediaQuery.of(context).viewInsets;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> saveSelectedPlayer(PlayerModel player) async {
              final raw = suspendedController.text.trim();
              final n = int.tryParse(raw);
              if (n == null || n < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ceza (maç sayısı) geçerli olmalı.'),
                  ),
                );
                return;
              }

              setSheetState(() => saving = true);
              try {
                await _dbService.setPlayerSuspendedMatches(
                  playerId: player.id,
                  suspendedMatches: n,
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Ceza kaydedildi.')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Hata: $e')));
              } finally {
                if (context.mounted) setSheetState(() => saving = false);
              }
            }

            final sortedTeams = [...teams]
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );

            if (teamId == null && sortedTeams.isNotEmpty) {
              teamId = sortedTeams.first.id;
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 6,
                bottom: insets.bottom + 16,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    editing == null ? 'Ceza Ekle' : 'Cezayı Güncelle',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: teamId,
                    decoration: const InputDecoration(
                      labelText: 'Takım',
                      border: OutlineInputBorder(),
                    ),
                    items: sortedTeams
                        .map(
                          (t) => DropdownMenuItem<String>(
                            value: t.id,
                            child: Text(
                              t.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (v) {
                            setSheetState(() {
                              teamId = v;
                              playerId = null;
                            });
                          },
                    menuMaxHeight: 420,
                  ),
                  const SizedBox(height: 12),
                  if (teamId == null)
                    const SizedBox.shrink()
                  else
                    StreamBuilder<List<PlayerModel>>(
                      stream: _dbService.getPlayers(teamId!),
                      builder: (context, snapshot) {
                        final players = snapshot.data ?? const <PlayerModel>[];
                        final sortedPlayers = [...players]
                          ..sort((a, b) {
                            final an =
                                int.tryParse((a.number ?? '').trim()) ?? 9999;
                            final bn =
                                int.tryParse((b.number ?? '').trim()) ?? 9999;
                            final c = an.compareTo(bn);
                            if (c != 0) return c;
                            return a.name
                                .toLowerCase()
                                .compareTo(b.name.toLowerCase());
                          });

                        final ids = sortedPlayers.map((p) => p.id).toSet();
                        if (playerId != null && !ids.contains(playerId)) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            setSheetState(() => playerId = null);
                          });
                        }

                        final selected = playerId == null
                            ? null
                            : sortedPlayers
                                    .where((p) => p.id == playerId)
                                    .isNotEmpty
                                ? sortedPlayers
                                    .firstWhere((p) => p.id == playerId)
                                : null;

                        return Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: playerId,
                              decoration: const InputDecoration(
                                labelText: 'Oyuncu',
                                border: OutlineInputBorder(),
                              ),
                              items: sortedPlayers
                                  .map(
                                    (p) => DropdownMenuItem<String>(
                                      value: p.id,
                                      child: Text(
                                        (p.number ?? '').trim().isEmpty
                                            ? p.name
                                            : '${p.number} • ${p.name}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: saving
                                  ? null
                                  : (v) =>
                                      setSheetState(() => playerId = v),
                              menuMaxHeight: 420,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: suspendedController,
                              enabled: !saving && selected != null,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Ceza (Maç Sayısı)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 50,
                              child: saving
                                  ? const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : FilledButton.icon(
                                      onPressed: selected == null
                                          ? null
                                          : () => saveSelectedPlayer(selected),
                                      icon: const Icon(Icons.save_outlined),
                                      label: const Text(
                                        'Kaydet',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );

    suspendedController.dispose();
  }

  Future<void> _openPenaltyActions({
    required Map<String, Team> teamById,
    required List<Team> teams,
    required PlayerModel player,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Güncelle'),
              onTap: () {
                Navigator.pop(context);
                _openPenaltyForm(teams: teams, editing: player);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Cezayı Kaldır'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await _dbService.setPlayerSuspendedMatches(
                    playerId: player.id,
                    suspendedMatches: 0,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ceza kaldırıldı.')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                }
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ceza Yönetimi')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: StreamBuilder<QuerySnapshot>(
        stream: _dbService.getTeams(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final teams = snapshot.data!.docs
              .map(
                (d) => Team.fromMap({
                  ...d.data() as Map<String, dynamic>,
                  'id': d.id,
                }),
              )
              .toList();
          return FloatingActionButton(
            onPressed: () => _openPenaltyForm(teams: teams),
            child: const Icon(Icons.add),
          );
        },
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _dbService.getTeams(),
        builder: (context, teamSnapshot) {
          final teamById = <String, Team>{};
          final teams = <Team>[];
          if (teamSnapshot.hasData) {
            for (final doc in teamSnapshot.data!.docs) {
              final t = Team.fromMap({
                ...doc.data() as Map<String, dynamic>,
                'id': doc.id,
              });
              teams.add(t);
              teamById[t.id] = t;
            }
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('players')
                .where('suspendedMatches', isGreaterThan: 0)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final suspended = snapshot.data!.docs
                  .map(
                    (d) => PlayerModel.fromMap(
                      d.data() as Map<String, dynamic>,
                      d.id,
                    ),
                  )
                  .where((p) => p.suspendedMatches > 0)
                  .toList();

              suspended.sort((a, b) {
                final at = (teamById[a.teamId]?.name ?? '').toLowerCase();
                final bt = (teamById[b.teamId]?.name ?? '').toLowerCase();
                final tc = at.compareTo(bt);
                if (tc != 0) return tc;
                final an = int.tryParse((a.number ?? '').trim()) ?? 9999;
                final bn = int.tryParse((b.number ?? '').trim()) ?? 9999;
                final nc = an.compareTo(bn);
                if (nc != 0) return nc;
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });

              if (suspended.isEmpty) {
                return Center(
                  child: Text(
                    'Cezalı oyuncu yok.',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: suspended.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final p = suspended[index];
                  final teamName = teamById[p.teamId]?.name ?? 'Takım';
                  final num = (p.number ?? '').trim();
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      onTap: () => _openPenaltyActions(
                        teamById: teamById,
                        teams: teams,
                        player: p,
                      ),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          num.isEmpty ? '—' : num,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        teamName,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          '${p.suspendedMatches} maç',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),
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
