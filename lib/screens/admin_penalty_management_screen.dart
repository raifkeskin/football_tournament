import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/match.dart';
import '../services/app_session.dart';
import '../models/team.dart';
import '../services/interfaces/i_team_service.dart';
import '../services/service_locator.dart';

class AdminPenaltyManagementScreen extends StatefulWidget {
  const AdminPenaltyManagementScreen({super.key});

  @override
  State<AdminPenaltyManagementScreen> createState() =>
      _AdminPenaltyManagementScreenState();
}

class _AdminPenaltyManagementScreenState
    extends State<AdminPenaltyManagementScreen> {
  final ITeamService _teamService = ServiceLocator.teamService;

  Future<void> _openPenaltyForm({
    required List<Team> teams,
    PlayerModel? editing,
  }) async {
    String? teamId = editing?.teamId;
    String? playerId = editing?.id;
    final reasonController = TextEditingController();
    final suspendedController = TextEditingController(
      text: editing != null ? editing.suspendedMatches.toString() : '',
    );
    var saving = false;
    if (editing != null && (editing.id).trim().isNotEmpty) {
      try {
        final data = await _teamService.getPenaltyForPlayer(editing.id);
        final reason =
            (data?['penaltyReason'] ?? data?['penalty_reason'] ?? '').toString().trim();
        if (reason.isNotEmpty) reasonController.text = reason;
      } catch (_) {}
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final insets = MediaQuery.of(context).viewInsets;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final cs = Theme.of(context).colorScheme;

            Future<void> saveSelectedPlayer(PlayerModel player) async {
              final resolvedTeamId = (teamId ?? '').trim();
              if (resolvedTeamId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lütfen takım seçin.')),
                );
                return;
              }
              final reason = reasonController.text.trim();
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
              var shouldClose = false;
              final parentMessenger = ScaffoldMessenger.of(this.context);
              final sm = ScaffoldMessenger.of(context);
              final nav = Navigator.of(context);
              try {
                await _teamService.upsertPenaltyForPlayer(
                  playerId: player.id,
                  teamId: resolvedTeamId,
                  penaltyReason: reason,
                  matchCount: n,
                );
                if (!mounted) return;
                shouldClose = true;
                nav.pop();
                parentMessenger.showSnackBar(
                  const SnackBar(content: Text('Ceza başarıyla kaydedildi.')),
                );
              } catch (e) {
                if (!mounted) return;
                sm.showSnackBar(
                  SnackBar(content: Text('Hata: $e')),
                );
              } finally {
                if (!shouldClose && mounted) {
                  try {
                    setSheetState(() => saving = false);
                  } catch (_) {}
                }
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
                  Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        onPressed: saving ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        color: cs.primary,
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: teamId,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: sortedTeams
                        .map(
                          (t) => DropdownMenuItem<String>(
                            value: t.id,
                            child: Text(
                              t.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
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
                      stream: _teamService.watchPlayers(teamId: teamId!),
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
                              initialValue: playerId,
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Oyuncu',
                                border: OutlineInputBorder(),
                                labelStyle: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
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
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
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
                              controller: reasonController,
                              enabled: !saving && selected != null,
                              decoration: const InputDecoration(
                                labelText: 'Ceza Sebebi',
                                border: OutlineInputBorder(),
                                labelStyle: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: suspendedController,
                              enabled: !saving && selected != null,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Maç Sayısı',
                                border: OutlineInputBorder(),
                                labelStyle: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 50,
                              width: double.infinity,
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
                                  : FilledButton(
                                      onPressed: () {
                                        final resolvedTeamId =
                                            (teamId ?? '').trim();
                                        if (resolvedTeamId.isEmpty) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Lütfen takım seçin.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        if (selected == null) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Lütfen oyuncu seçin.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        saveSelectedPlayer(selected);
                                      },
                                      style: FilledButton.styleFrom(
                                        minimumSize:
                                            const Size(double.infinity, 50),
                                        backgroundColor: cs.primary,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text(
                                        'KAYDET',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
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

    reasonController.dispose();
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
                  await _teamService.clearPenaltyForPlayer(playerId: player.id);
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
    final isAdmin = AppSession.of(context).value.isAdmin;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ceza Yönetimi')),
        body: const Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Ceza Yönetimi')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: StreamBuilder<List<Team>>(
        stream: _teamService.watchAllTeams(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final teams =
              (snapshot.data ?? const <Team>[])
                  .where((t) => t.id != 'free_agent_pool')
                  .toList();
          return FloatingActionButton(
            onPressed: () => _openPenaltyForm(teams: teams),
            child: const Icon(Icons.add),
          );
        },
      ),
      body: StreamBuilder<List<Team>>(
        stream: _teamService.watchAllTeams(),
        builder: (context, teamSnapshot) {
          final teamById = <String, Team>{};
          final teams = <Team>[];
          if (teamSnapshot.hasData) {
            for (final t in teamSnapshot.data!) {
              if (t.id == 'free_agent_pool') continue;
              teams.add(t);
              teamById[t.id] = t;
            }
          }

          return StreamBuilder<List<PlayerModel>>(
            stream: _teamService.watchAllPlayers(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final suspended =
                  (snapshot.data ?? const <PlayerModel>[])
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
