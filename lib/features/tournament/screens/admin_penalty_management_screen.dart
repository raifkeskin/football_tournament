import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:football_tournament/core/widgets/custom_bottom_sheet_dropdown.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../match/models/match.dart';
import '../../../core/services/app_session.dart';
import '../../team/models/team.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../services/interfaces/i_league_service.dart';
import '../../tournament/models/league.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../player/services/penalty_service.dart';

class AdminPenaltyManagementScreen extends StatefulWidget {
  const AdminPenaltyManagementScreen({super.key});

  @override
  State<AdminPenaltyManagementScreen> createState() =>
      _AdminPenaltyManagementScreenState();
}

class _AdminPenaltyManagementScreenState
    extends State<AdminPenaltyManagementScreen> {
  final ITeamService _teamService = ServiceLocator.teamService;
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final PenaltyService _penaltyService = PenaltyService();
  final SupabaseClient _sb = Supabase.instance.client;

  String _selectedLeagueId = '';
  String _selectedSeasonId = '';
  _PenaltyFilter _penaltyFilter = _PenaltyFilter.active;
  final Set<String> _hiddenPenaltyIds = <String>{};

  Future<List<Map<String, dynamic>>> _fetchSeasons(String leagueId) async {
    final lid = leagueId.trim();
    if (lid.isEmpty) return const <Map<String, dynamic>>[];
    final res = await _sb
        .from('seasons')
        .select('id, name')
        .eq('league_id', lid)
        .order('name', ascending: true);
    return res.cast<Map<String, dynamic>>();
  }

  Future<Map<String, Map<String, dynamic>>> _fetchPlayersByIds(
    Iterable<String> playerIds,
  ) async {
    String clean(dynamic v) =>
        (v ?? '').toString().replaceAll('\u0000', '').trim();
    final ids = playerIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const <String, Map<String, dynamic>>{};
    final res = await _sb.from('players').select().inFilter('id', ids);
    final out = <String, Map<String, dynamic>>{};
    for (final r in res) {
      final row = (r as Map).cast<String, dynamic>();
      final id = clean(row['id']);
      if (id.isEmpty) continue;
      final n0 = clean(row['name']);
      final n1 = clean(row['full_name']);
      final n2 = clean(row['display_name']);
      final first = clean(row['first_name']);
      final last = clean(
        row['last_name'].toString().isEmpty ? row['surname'] : row['last_name'],
      );
      final combined = [first, last].where((e) => e.isNotEmpty).join(' ');
      final name = n0.isNotEmpty
          ? n0
          : (n1.isNotEmpty ? n1 : (n2.isNotEmpty ? n2 : combined));

      final p0 = clean(row['photo_url']);
      final p1 = clean(row['logo_url']);
      final p2 = clean(row['avatar_url']);
      final p3 = clean(row['photoUrl']);
      final photoUrl = p0.isNotEmpty
          ? p0
          : (p1.isNotEmpty ? p1 : (p2.isNotEmpty ? p2 : p3));

      out[id] = <String, dynamic>{
        'id': id,
        'name': name,
        'photo_url': photoUrl,
      };
    }
    return out;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchRosterByPlayerIds({
    required String seasonId,
    required Iterable<String> playerIds,
  }) async {
    final sid = seasonId.trim();
    if (sid.isEmpty) return const <String, Map<String, dynamic>>{};
    final ids = playerIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const <String, Map<String, dynamic>>{};
    final res = await _sb
        .from('season_team_players')
        .select('player_id, team_id, jersey_number')
        .eq('season_id', sid)
        .inFilter('player_id', ids);
    final out = <String, Map<String, dynamic>>{};
    for (final r in res) {
      final row = (r as Map).cast<String, dynamic>();
      final pid = (row['player_id'] ?? '').toString().trim();
      if (pid.isEmpty) continue;
      out.putIfAbsent(pid, () => row);
    }
    return out;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchTeamsByIds(
    Iterable<String> teamIds,
  ) async {
    final ids = teamIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const <String, Map<String, dynamic>>{};
    final res = await _sb.from('teams').select('id, name').inFilter('id', ids);
    final out = <String, Map<String, dynamic>>{};
    for (final r in res) {
      final row = (r as Map).cast<String, dynamic>();
      final id = (row['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      out[id] = row;
    }
    return out;
  }

  Future<void> _openPenaltySheet({
    String? initialLeagueId,
    String? initialSeasonId,
    String? initialTeamId,
    String? initialPlayerId,
    String? penaltyId,
  }) async {
    final didSave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      showDragHandle: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PenaltyEditorSheet(
        leagueService: _leagueService,
        teamService: _teamService,
        penaltyService: _penaltyService,
        sb: _sb,
        initialLeagueId: (initialLeagueId ?? _selectedLeagueId).trim(),
        initialSeasonId: (initialSeasonId ?? _selectedSeasonId).trim(),
        initialTeamId: (initialTeamId ?? '').trim(),
        initialPlayerId: (initialPlayerId ?? '').trim(),
        penaltyId: (penaltyId ?? '').trim(),
      ),
    );
    if (!mounted) return;
    if (didSave == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (penaltyId ?? '').trim().isEmpty
                ? 'Ceza kaydedildi.'
                : 'Ceza güncellendi.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ceza Yönetimi'), centerTitle: true),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openPenaltySheet(),
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            StreamBuilder<List<League>>(
              stream: _leagueService.watchLeagues(),
              builder: (context, snap) {
                final byId = <String, League>{};
                for (final l in (snap.data ?? const <League>[])) {
                  final id = l.id.trim();
                  if (id.isEmpty) continue;
                  byId.putIfAbsent(id, () => l);
                }
                final leagues = byId.values.toList()
                  ..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );

                if (_selectedLeagueId.isEmpty && leagues.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() => _selectedLeagueId = leagues.first.id);
                  });
                }

                return DropdownButtonFormField<String>(
                  initialValue:
                      _selectedLeagueId.isEmpty ||
                          !byId.containsKey(_selectedLeagueId)
                      ? null
                      : _selectedLeagueId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Turnuva',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: cs.primary, width: 1.6),
                    ),
                    filled: true,
                    fillColor: cs.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                  items: [
                    for (final l in leagues)
                      DropdownMenuItem<String>(
                        value: l.id,
                        child: Text(l.name.trim().isEmpty ? l.id : l.name),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _selectedLeagueId = (v ?? '').trim();
                      _selectedSeasonId = '';
                      _hiddenPenaltyIds.clear();
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchSeasons(_selectedLeagueId),
              builder: (context, snap) {
                final byId = <String, Map<String, dynamic>>{};
                for (final s in (snap.data ?? const <Map<String, dynamic>>[])) {
                  final id = (s['id'] ?? '').toString().trim();
                  if (id.isEmpty) continue;
                  byId.putIfAbsent(id, () => s);
                }
                final seasons = byId.values.toList()
                  ..sort((a, b) {
                    final an = (a['name'] ?? '').toString().toLowerCase();
                    final bn = (b['name'] ?? '').toString().toLowerCase();
                    return an.compareTo(bn);
                  });

                if (_selectedSeasonId.isEmpty && seasons.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(
                      () => _selectedSeasonId = (seasons.first['id'] ?? '')
                          .toString()
                          .trim(),
                    );
                  });
                }

                return DropdownButtonFormField<String>(
                  initialValue:
                      _selectedSeasonId.isEmpty ||
                          !byId.containsKey(_selectedSeasonId)
                      ? null
                      : _selectedSeasonId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Sezon',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: cs.primary, width: 1.6),
                    ),
                    filled: true,
                    fillColor: cs.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                  items: [
                    for (final s in seasons)
                      DropdownMenuItem<String>(
                        value: (s['id'] ?? '').toString().trim(),
                        child: Text(
                          (s['name'] ?? '').toString().trim().isEmpty
                              ? (s['id'] ?? '').toString()
                              : (s['name'] ?? '').toString(),
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _selectedSeasonId = (v ?? '').trim();
                      _hiddenPenaltyIds.clear();
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            CustomBottomSheetDropdown<_PenaltyFilter>(
              labelText: 'Filtre',
              value: _penaltyFilter,
              items: const [
                _PenaltyFilter.active,
                _PenaltyFilter.passive,
                _PenaltyFilter.all,
              ],
              itemLabelBuilder: (filter) => switch (filter) {
                _PenaltyFilter.all => 'Tümü',
                _PenaltyFilter.active => 'Aktif',
                _PenaltyFilter.passive => 'Pasif',
              },
              onChanged: (v) {
                if (v != null) setState(() => _penaltyFilter = v);
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _selectedSeasonId.trim().isEmpty
                  ? Center(
                      child: Text(
                        'Liste için sezon seçin.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : StreamBuilder<Map<String, PlayerPenalty>>(
                      stream: _penaltyService.watchPenaltiesByPlayerId(
                        _selectedSeasonId,
                        isActive: switch (_penaltyFilter) {
                          _PenaltyFilter.active => true,
                          _PenaltyFilter.passive => false,
                          _PenaltyFilter.all => null,
                        },
                      ),
                      initialData: const <String, PlayerPenalty>{},
                      builder: (context, snap) {
                        final penalties =
                            snap.data ?? const <String, PlayerPenalty>{};
                        final list =
                            penalties.values
                                .where((p) => !_hiddenPenaltyIds.contains(p.id))
                                .toList()
                              ..sort(
                                (a, b) => b.matchCount.compareTo(a.matchCount),
                              );
                        if (list.isEmpty) {
                          return Center(
                            child: Text(switch (_penaltyFilter) {
                              _PenaltyFilter.active => 'Aktif ceza yok.',
                              _PenaltyFilter.passive => 'Pasif ceza yok.',
                              _PenaltyFilter.all => 'Ceza kaydı yok.',
                            }, style: TextStyle(color: cs.onSurfaceVariant)),
                          );
                        }

                        final playerIds = list.map((e) => e.playerId).toSet();
                        return FutureBuilder<Map<String, Map<String, dynamic>>>(
                          future: _fetchPlayersByIds(playerIds),
                          builder: (context, playersSnap) {
                            final playerById =
                                playersSnap.data ??
                                const <String, Map<String, dynamic>>{};
                            return FutureBuilder<
                              Map<String, Map<String, dynamic>>
                            >(
                              future: _fetchRosterByPlayerIds(
                                seasonId: _selectedSeasonId,
                                playerIds: playerIds,
                              ),
                              builder: (context, rosterSnap) {
                                final rosterByPlayerId =
                                    rosterSnap.data ??
                                    const <String, Map<String, dynamic>>{};
                                final teamIds = rosterByPlayerId.values
                                    .map(
                                      (r) => (r['team_id'] ?? '')
                                          .toString()
                                          .trim(),
                                    )
                                    .where((e) => e.isNotEmpty)
                                    .toSet();

                                return FutureBuilder<
                                  Map<String, Map<String, dynamic>>
                                >(
                                  future: _fetchTeamsByIds(teamIds),
                                  builder: (context, teamsSnap) {
                                    final teamById =
                                        teamsSnap.data ??
                                        const <String, Map<String, dynamic>>{};
                                    return ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(
                                        0,
                                        0,
                                        0,
                                        24,
                                      ),
                                      itemCount: list.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 6),
                                      itemBuilder: (context, i) {
                                        final pen = list[i];
                                        final pRow =
                                            playerById[pen.playerId] ??
                                            const <String, dynamic>{};
                                        final pName = (pRow['name'] ?? '')
                                            .toString()
                                            .trim();
                                        final pPhotoUrl =
                                            (pRow['photo_url'] ?? '')
                                                .toString()
                                                .trim();

                                        final roster =
                                            rosterByPlayerId[pen.playerId] ??
                                            const <String, dynamic>{};
                                        final pNum =
                                            (roster['jersey_number'] ?? '')
                                                .toString()
                                                .trim();
                                        final pTeamId =
                                            (roster['team_id'] ?? '')
                                                .toString()
                                                .trim();
                                        final tName =
                                            (teamById[pTeamId]?['name'] ?? '')
                                                .toString()
                                                .trim();

                                        final resolvedName = pName.isEmpty
                                            ? pen.playerId
                                            : pName;
                                        final resolvedTeam = tName.isEmpty
                                            ? pTeamId
                                            : tName;

                                        return Card(
                                          margin: EdgeInsets.zero,
                                          child: ListTile(
                                            leading: pPhotoUrl.isEmpty
                                                ? Container(
                                                    width: 38,
                                                    height: 38,
                                                    decoration: BoxDecoration(
                                                      color: cs.primary
                                                          .withValues(
                                                            alpha: 0.10,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: Text(
                                                      pNum.isEmpty ? '—' : pNum,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color: cs.primary,
                                                      ),
                                                    ),
                                                  )
                                                : WebSafeImage(
                                                    url: pPhotoUrl,
                                                    width: 38,
                                                    height: 38,
                                                    fit: BoxFit.cover,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    fallbackIconSize: 18,
                                                  ),
                                            title: Text(
                                              resolvedName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 14,
                                              ),
                                            ),
                                            subtitle: Text(
                                              resolvedTeam,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: cs.onSurfaceVariant
                                                    .withValues(alpha: 0.72),
                                                fontWeight: FontWeight.w500,
                                                fontSize: 12,
                                              ),
                                            ),
                                            dense: true,
                                            visualDensity:
                                                VisualDensity.compact,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 6,
                                                ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red
                                                        .withValues(
                                                          alpha: 0.10,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.red
                                                          .withValues(
                                                            alpha: 0.25,
                                                          ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '${pen.matchCount} maç',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: Colors.red,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                PopupMenuButton<
                                                  _PenaltyMenuAction
                                                >(
                                                  tooltip: 'İşlemler',
                                                  icon: Icon(
                                                    Icons.more_vert,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                  onSelected: (action) async {
                                                    if (action ==
                                                        _PenaltyMenuAction
                                                            .edit) {
                                                      await _openPenaltySheet(
                                                        initialLeagueId:
                                                            _selectedLeagueId,
                                                        initialSeasonId:
                                                            _selectedSeasonId,
                                                        initialTeamId: pTeamId,
                                                        initialPlayerId:
                                                            pen.playerId,
                                                        penaltyId: pen.id,
                                                      );
                                                      return;
                                                    }
                                                    var displayName =
                                                        resolvedName.trim();
                                                    if (displayName.isEmpty ||
                                                        displayName ==
                                                            pen.playerId) {
                                                      try {
                                                        final m =
                                                            await _fetchPlayersByIds(
                                                              [pen.playerId],
                                                            );
                                                        final row =
                                                            m[pen.playerId];
                                                        final n =
                                                            (row?['name'] ?? '')
                                                                .toString()
                                                                .trim();
                                                        if (n.isNotEmpty) {
                                                          displayName = n;
                                                        }
                                                      } catch (_) {}
                                                    }
                                                    final ok = await showDialog<bool>(
                                                      context: context,
                                                      builder: (ctx) {
                                                        final n =
                                                            displayName.isEmpty
                                                            ? pen.playerId
                                                            : displayName;
                                                        return AlertDialog(
                                                          title: const Text(
                                                            'Cezayı sil?',
                                                          ),
                                                          content: Text(
                                                            '$n oyuncusunun ceza kaydı silinecek.',
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                    ctx,
                                                                  ).pop(false),
                                                              child: const Text(
                                                                'Vazgeç',
                                                              ),
                                                            ),
                                                            FilledButton(
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                    ctx,
                                                                  ).pop(true),
                                                              child: const Text(
                                                                'Sil',
                                                              ),
                                                            ),
                                                          ],
                                                        );
                                                      },
                                                    );
                                                    if (ok != true) return;
                                                    try {
                                                      await _penaltyService
                                                          .deletePenaltyById(
                                                            pen.id,
                                                          );
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      setState(
                                                        () => _hiddenPenaltyIds
                                                            .add(pen.id),
                                                      );
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Ceza silindi.',
                                                          ),
                                                        ),
                                                      );
                                                    } catch (e) {
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Hata: $e',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  itemBuilder: (context) => [
                                                    const PopupMenuItem(
                                                      value: _PenaltyMenuAction
                                                          .edit,
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.edit_outlined,
                                                            size: 18,
                                                          ),
                                                          SizedBox(width: 10),
                                                          Text('Düzenle'),
                                                        ],
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: _PenaltyMenuAction
                                                          .delete,
                                                      child: Row(
                                                        children: const [
                                                          Icon(
                                                            Icons
                                                                .delete_outline,
                                                            size: 18,
                                                            color: Colors.red,
                                                          ),
                                                          SizedBox(width: 10),
                                                          Text(
                                                            'Sil',
                                                            style: TextStyle(
                                                              color: Colors.red,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            onTap: () => _openPenaltySheet(
                                              initialLeagueId:
                                                  _selectedLeagueId,
                                              initialSeasonId:
                                                  _selectedSeasonId,
                                              initialTeamId: pTeamId,
                                              initialPlayerId: pen.playerId,
                                              penaltyId: pen.id,
                                            ),
                                          ),
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
            ),
          ],
        ),
      ),
    );
  }
}

class _PenaltyEditorSheet extends StatefulWidget {
  const _PenaltyEditorSheet({
    required this.leagueService,
    required this.teamService,
    required this.penaltyService,
    required this.sb,
    required this.initialLeagueId,
    required this.initialSeasonId,
    required this.initialTeamId,
    required this.initialPlayerId,
    required this.penaltyId,
  });

  final ILeagueService leagueService;
  final ITeamService teamService;
  final PenaltyService penaltyService;
  final SupabaseClient sb;

  final String initialLeagueId;
  final String initialSeasonId;
  final String initialTeamId;
  final String initialPlayerId;
  final String penaltyId;

  @override
  State<_PenaltyEditorSheet> createState() => _PenaltyEditorSheetState();
}

class _PenaltyEditorSheetState extends State<_PenaltyEditorSheet> {
  late String _leagueId;
  late String _seasonId;
  late String _teamId;
  late String _playerId;
  late String _penaltyId;

  final TextEditingController _matchCountController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  bool _saving = false;
  bool _loadingExisting = false;

  bool get _isEdit => _penaltyId.trim().isNotEmpty;

  InputDecoration _deco(String label) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: cs.primary, width: 1.6),
      ),
      filled: true,
      fillColor: cs.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchSeasons(String leagueId) async {
    final lid = leagueId.trim();
    if (lid.isEmpty) return const <Map<String, dynamic>>[];
    final res = await widget.sb
        .from('seasons')
        .select('id, name')
        .eq('league_id', lid)
        .order('name', ascending: true);
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> _loadExistingFromPenaltyId() async {
    final id = _penaltyId.trim();
    if (id.isEmpty) return;
    setState(() => _loadingExisting = true);
    try {
      final existing = await widget.penaltyService.getPenaltyById(id);
      if (!mounted) return;
      if (existing == null) return;
      setState(() {
        _playerId = existing.playerId.trim();
        _seasonId = existing.seasonId.trim();
      });
      _matchCountController.text = '${existing.matchCount}';
      _descController.text = existing.reason;

      if (_leagueId.trim().isEmpty && _seasonId.trim().isNotEmpty) {
        try {
          final res = await widget.sb
              .from('seasons')
              .select('league_id')
              .eq('id', _seasonId.trim())
              .limit(1);
          if (!mounted) return;
          if (res.isNotEmpty) {
            final row = (res.first as Map).cast<String, dynamic>();
            final lid = (row['league_id'] ?? '').toString().trim();
            if (lid.isNotEmpty) setState(() => _leagueId = lid);
          }
        } catch (_) {}
      }

      if (_teamId.trim().isEmpty &&
          _playerId.trim().isNotEmpty &&
          _seasonId.trim().isNotEmpty) {
        try {
          final res = await widget.sb
              .from('season_team_players')
              .select('team_id')
              .eq('season_id', _seasonId.trim())
              .eq('player_id', _playerId.trim())
              .eq('is_active', true)
              .limit(1);
          if (!mounted) return;
          if (res.isNotEmpty) {
            final row = (res.first as Map).cast<String, dynamic>();
            final tid = (row['team_id'] ?? '').toString().trim();
            if (tid.isNotEmpty) setState(() => _teamId = tid);
          }
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  Future<void> _loadExistingForPlayerSeason() async {
    final pid = _playerId.trim();
    final sid = _seasonId.trim();
    if (pid.isEmpty || sid.isEmpty) return;
    setState(() => _loadingExisting = true);
    try {
      final existing = await widget.penaltyService.getPenaltyOnce(
        playerId: pid,
        seasonId: sid,
      );
      if (!mounted) return;
      _matchCountController.text = existing == null
          ? ''
          : '${existing.matchCount}';
      _descController.text = existing == null ? '' : existing.reason;
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _leagueId = widget.initialLeagueId.trim();
    _seasonId = widget.initialSeasonId.trim();
    _teamId = widget.initialTeamId.trim();
    _playerId = widget.initialPlayerId.trim();
    _penaltyId = widget.penaltyId.trim();

    if (_penaltyId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadExistingFromPenaltyId(),
      );
    } else if (_playerId.isNotEmpty && _seasonId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadExistingForPlayerSeason(),
      );
    }
  }

  @override
  void dispose() {
    _matchCountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pid = _playerId.trim();
    final sid = _seasonId.trim();
    if (pid.isEmpty || sid.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lütfen futbolcu seçin.')));
      return;
    }
    final raw = _matchCountController.text.replaceAll(RegExp(r'\D'), '').trim();
    final n = raw.isEmpty ? 0 : int.tryParse(raw);
    if (n == null || n < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ceza maç sayısı geçerli olmalı.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await widget.penaltyService.updatePenaltyById(
          penaltyId: _penaltyId,
          matchCount: n,
          description: _descController.text,
        );
      } else {
        await widget.penaltyService.upsertPlayerPenalty(
          playerId: pid,
          seasonId: sid,
          matchCount: n,
          description: _descController.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets.bottom),
child: ListView(
        children: [
          StreamBuilder<List<League>>(
            stream: widget.leagueService.watchLeagues(),
            builder: (context, snap) {
              final byId = <String, League>{};
              for (final l in (snap.data ?? const <League>[])) {
                final id = l.id.trim();
                if (id.isEmpty) continue;
                byId.putIfAbsent(id, () => l);
              }
              final leagues = byId.values.toList()
                ..sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );

              // YENİ DİNAMİK YAPI BURADAN BAŞLIYOR (return kelimesine dikkat)
              return IgnorePointer(
                ignoring: _saving || _isEdit,
                child: CustomBottomSheetDropdown<League>(
                  labelText: 'Turnuva',
                  items: leagues,
                  // Eğer ID boşsa veya listede yoksa null, varsa objenin kendisini ver
                  value: _leagueId.isEmpty || !byId.containsKey(_leagueId)
                      ? null
                      : leagues.where((l) => l.id == _leagueId).firstOrNull,
                  itemLabelBuilder: (l) => l.name.trim().isEmpty ? l.id : l.name,
                  onChanged: (League? selectedLeague) {
                    setState(() {
                      _leagueId = selectedLeague?.id ?? '';
                      _seasonId = '';
                      _teamId = '';
                      _playerId = '';
                      if (!_isEdit) {
                        _matchCountController.text = '';
                        _descController.text = '';
                      }
                    });
                  },
                ),
              );
              // YENİ DİNAMİK YAPI BURADA BİTİYOR
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _fetchSeasons(_leagueId),
            builder: (context, snap) {
              final byId = <String, Map<String, dynamic>>{};
              for (final s in (snap.data ?? const <Map<String, dynamic>>[])) {
                final id = (s['id'] ?? '').toString().trim();
                if (id.isEmpty) continue;
                byId.putIfAbsent(id, () => s);
              }
              final seasons = byId.values.toList()
                ..sort((a, b) {
                  final an = (a['name'] ?? '').toString().toLowerCase();
                  final bn = (b['name'] ?? '').toString().toLowerCase();
                  return an.compareTo(bn);
                });

              return DropdownButtonFormField<String>(
                initialValue: _seasonId.isEmpty || !byId.containsKey(_seasonId)
                    ? null
                    : _seasonId,
                isExpanded: true,
                decoration: _deco('Sezon'),
                items: [
                  for (final s in seasons)
                    DropdownMenuItem<String>(
                      value: (s['id'] ?? '').toString().trim(),
                      child: Text(
                        (s['name'] ?? '').toString().trim().isEmpty
                            ? (s['id'] ?? '').toString()
                            : (s['name'] ?? '').toString(),
                      ),
                    ),
                ],
                onChanged: _saving || _isEdit
                    ? null
                    : (v) {
                        setState(() {
                          _seasonId = (v ?? '').trim();
                          _teamId = '';
                          _playerId = '';
                          if (!_isEdit) {
                            _matchCountController.text = '';
                            _descController.text = '';
                          }
                        });
                      },
              );
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Team>>(
            future: () async {
              final sid = _seasonId.trim();
              if (sid.isEmpty) return const <Team>[];
              try {
                return await widget.teamService.getTeamsCached(
                  sid,
                  caller: 'AdminPenalty',
                );
              } catch (_) {
                return const <Team>[];
              }
            }(),
            builder: (context, snap) {
              final byId = <String, Team>{};
              for (final t in (snap.data ?? const <Team>[])) {
                final id = t.id.trim();
                if (id.isEmpty) continue;
                byId.putIfAbsent(id, () => t);
              }
              final teams = byId.values.toList()
                ..sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );

              return DropdownButtonFormField<String>(
                initialValue: _teamId.isEmpty || !byId.containsKey(_teamId)
                    ? null
                    : _teamId,
                isExpanded: true,
                decoration: _deco('Takım'),
                items: [
                  for (final t in teams)
                    DropdownMenuItem<String>(
                      value: t.id,
                      child: Text(t.name.trim().isEmpty ? t.id : t.name),
                    ),
                ],
                onChanged: _saving || _isEdit || _seasonId.trim().isEmpty
                    ? null
                    : (v) {
                        setState(() {
                          _teamId = (v ?? '').trim();
                          _playerId = '';
                          if (!_isEdit) {
                            _matchCountController.text = '';
                            _descController.text = '';
                          }
                        });
                      },
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<PlayerModel>>(
            stream: () {
              final tid = _teamId.trim();
              final sid = _seasonId.trim();
              if (tid.isEmpty || sid.isEmpty) {
                return Stream.value(const <PlayerModel>[]);
              }
              return widget.teamService.watchPlayers(
                teamId: tid,
                tournamentId: sid,
              );
            }(),
            builder: (context, snap) {
              final byId = <String, PlayerModel>{};
              for (final p in (snap.data ?? const <PlayerModel>[])) {
                final id = p.id.trim();
                if (id.isEmpty) continue;
                byId.putIfAbsent(id, () => p);
              }
              final players =
                  byId.values
                      .where(
                        (p) => p.role == 'Futbolcu' || p.role == 'Her İkisi',
                      )
                      .toList()
                    ..sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    );

              return DropdownButtonFormField<String>(
                initialValue: _playerId.isEmpty || !byId.containsKey(_playerId)
                    ? null
                    : _playerId,
                isExpanded: true,
                decoration: _deco('Futbolcu'),
                items: [
                  for (final p in players)
                    DropdownMenuItem<String>(
                      value: p.id,
                      child: Text(p.name.trim().isEmpty ? p.id : p.name),
                    ),
                ],
                onChanged: _saving || _isEdit || _teamId.trim().isEmpty
                    ? null
                    : (v) async {
                        setState(() {
                          _playerId = (v ?? '').trim();
                          if (!_isEdit) {
                            _matchCountController.text = '';
                            _descController.text = '';
                          }
                        });
                        if (!_isEdit) await _loadExistingForPlayerSeason();
                      },
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _matchCountController,
            enabled:
                !_saving &&
                _playerId.trim().isNotEmpty &&
                _seasonId.trim().isNotEmpty &&
                !_loadingExisting,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: _deco('Ceza Maç Sayısı'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descController,
            enabled:
                !_saving &&
                _playerId.trim().isNotEmpty &&
                _seasonId.trim().isNotEmpty &&
                !_loadingExisting,
            maxLines: 4,
            decoration: _deco('Açıklama'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: _saving || _loadingExisting ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _isEdit ? 'GÜNCELLE' : 'KAYDET',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text(
                'VAZGEÇ',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PenaltyFilter { active, passive, all }

enum _PenaltyMenuAction { edit, delete }
