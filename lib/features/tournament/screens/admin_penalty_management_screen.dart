import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../services/interfaces/i_league_service.dart';
import '../../tournament/models/league.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/custom_popup_selector.dart';
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

  late final Stream<List<League>> _leaguesStream = _leagueService
      .watchLeagues();
  List<League> _leagues = const <League>[];
  final Map<String, List<Map<String, dynamic>>> _seasonsByLeague = {};
  final Set<String> _loadingSeasons = <String>{};

  /// Turnuvanın sezonlarını bir kez okur; sezon seçili değilse ilkini seçer.
  Future<void> _ensureSeasons(String leagueId, {VoidCallback? onLoaded}) async {
    final lid = leagueId.trim();
    if (lid.isEmpty ||
        _seasonsByLeague.containsKey(lid) ||
        _loadingSeasons.contains(lid)) {
      return;
    }
    _loadingSeasons.add(lid);
    try {
      final rows = await _fetchSeasons(lid);
      if (!mounted) return;
      setState(() {
        _seasonsByLeague[lid] = rows;
        if (_selectedLeagueId == lid &&
            _selectedSeasonId.isEmpty &&
            rows.isNotEmpty) {
          _selectedSeasonId = (rows.first['id'] ?? '').toString().trim();
        }
      });
      onLoaded?.call();
    } catch (_) {
      // Sezonlar okunamazsa filtre "Seçiniz" gösterir; liste boş kalır.
    } finally {
      _loadingSeasons.remove(lid);
    }
  }

  String _seasonName(String seasonId) {
    final id = seasonId.trim();
    if (id.isEmpty) return '';
    for (final s in _seasonsByLeague[_selectedLeagueId] ?? const []) {
      if ((s['id'] ?? '').toString().trim() == id) {
        final name = (s['name'] ?? '').toString().trim();
        return name.isEmpty ? id : name;
      }
    }
    return '';
  }

  String _filterLabel(_PenaltyFilter filter) => switch (filter) {
    _PenaltyFilter.all => 'Tümü',
    _PenaltyFilter.active => 'Aktif',
    _PenaltyFilter.passive => 'Pasif',
  };

  Future<void> _openFilters() {
    return showAdminFilterDialog(
      context: context,
      fieldsBuilder: (ctx, refresh) {
        final seasons =
            _seasonsByLeague[_selectedLeagueId] ??
            const <Map<String, dynamic>>[];
        return [
          CustomPopupSelector<String>(
            label: 'Turnuva',
            selectedValue: _selectedLeagueId.isEmpty ? null : _selectedLeagueId,
            items: _leagues.map((l) => l.id).toList(),
            labelBuilder: (id) {
              for (final l in _leagues) {
                if (l.id == id) return l.name.trim().isEmpty ? l.id : l.name;
              }
              return '';
            },
            onChanged: (v) {
              final lid = (v ?? '').trim();
              if (lid == _selectedLeagueId) return;
              final cached = _seasonsByLeague[lid];
              setState(() {
                _selectedLeagueId = lid;
                _selectedSeasonId = cached == null || cached.isEmpty
                    ? ''
                    : (cached.first['id'] ?? '').toString().trim();
                _hiddenPenaltyIds.clear();
              });
              _ensureSeasons(lid, onLoaded: refresh);
              refresh();
            },
          ),
          CustomPopupSelector<String>(
            label: 'Sezon',
            selectedValue: _selectedSeasonId.isEmpty ? null : _selectedSeasonId,
            items: [for (final s in seasons) (s['id'] ?? '').toString().trim()],
            labelBuilder: (id) => _seasonName(id ?? ''),
            onChanged: (v) {
              setState(() {
                _selectedSeasonId = (v ?? '').trim();
                _hiddenPenaltyIds.clear();
              });
              refresh();
            },
          ),
          CustomPopupSelector<_PenaltyFilter>(
            label: 'Filtre',
            selectedValue: _penaltyFilter,
            items: _PenaltyFilter.values,
            labelBuilder: (f) => _filterLabel(f ?? _PenaltyFilter.active),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _penaltyFilter = v);
              refresh();
            },
          ),
        ];
      },
    );
  }

  /// Bölge sorumlusunun bu sezonda görebileceği oyuncular (bölgesindeki
  /// takımların kadroları). Kurucu / admin için null (hepsi).
  final Map<String, Future<Set<String>?>> _allowedBySeason = {};

  Future<Set<String>?> _allowedPlayers(String seasonId) {
    final session = AppSession.of(context).value;
    if (session.canManageLeague(_selectedLeagueId)) return Future.value(null);
    final regions = {for (final r in session.regionsInSeason(seasonId)) r.id};
    return _allowedBySeason[seasonId] ??= () async {
      final teams = await _sb
          .from('season_teams')
          .select('team_id, groups(region_id)')
          .eq('season_id', seasonId);
      final teamIds = [
        for (final t in teams)
          if (regions.contains(
            ((t['groups'] as Map?)?['region_id'] ?? '').toString(),
          ))
            (t['team_id'] ?? '').toString(),
      ];
      if (teamIds.isEmpty) return <String>{};
      final rows = await _sb
          .from('season_team_players')
          .select('player_id')
          .eq('season_id', seasonId)
          .inFilter('team_id', teamIds);
      return {for (final r in rows) (r['player_id'] ?? '').toString()};
    }();
  }

  Future<List<Map<String, dynamic>>> _fetchSeasons(String leagueId) async {
    final lid = leagueId.trim();
    if (lid.isEmpty) return const <Map<String, dynamic>>[];
    final res = await _sb
        .from('seasons')
        .select('id, name')
        .eq('league_id', lid)
        .order('name', ascending: true);
    // Bölge sorumlusu yalnızca bölgesinin bulunduğu sezonları görür.
    if (!mounted) return const <Map<String, dynamic>>[];
    final session = AppSession.of(context).value;
    if (session.canManageLeague(lid)) return res.cast<Map<String, dynamic>>();
    final mine = {for (final r in session.ownedRegions) r.seasonId};
    return [
      for (final r in res.cast<Map<String, dynamic>>())
        if (mine.contains((r['id'] ?? '').toString())) r,
    ];
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
    final didSave = await showDialog<bool>(
      context: context,
      builder: (dctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: AdminDialogCloseOverlay(
          onClose: () => Navigator.pop(dctx, false),
          child: Container(
            height: MediaQuery.of(dctx).size.height * 0.8,
            clipBehavior: Clip.antiAlias,
            decoration: adminDialogDecoration(),
            child: _PenaltyEditorSheet(
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
          ),
        ),
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

  Future<void> _deletePenalty({
    required String penaltyId,
    required String playerId,
    required String resolvedName,
  }) async {
    var displayName = resolvedName.trim();
    if (displayName.isEmpty || displayName == playerId) {
      try {
        final m = await _fetchPlayersByIds([playerId]);
        final n = (m[playerId]?['name'] ?? '').toString().trim();
        if (n.isNotEmpty) displayName = n;
      } catch (_) {}
    }
    if (!mounted) return;
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Cezayı Sil',
      message:
          '${displayName.isEmpty ? playerId : displayName} oyuncusunun ceza '
          'kaydı silinecek.',
    );
    if (!ok) return;
    try {
      await _penaltyService.deletePenaltyById(penaltyId);
      if (!mounted) return;
      setState(() => _hiddenPenaltyIds.add(penaltyId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ceza silindi.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    if (!session.hasManagementPanel) {
      return const AdminPageScaffold(
        title: 'Ceza Yönetimi',
        body: Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return AdminPageScaffold(
      title: 'Ceza Yönetimi',
      actions: [
        AdminBarAction(
          icon: Icons.gavel_rounded,
          tooltip: 'Ceza Ekle',
          onPressed: () => _openPenaltySheet(),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            StreamBuilder<List<League>>(
              stream: _leaguesStream,
              builder: (context, snap) {
                final byId = <String, League>{};
                for (final l in (snap.data ?? const <League>[])) {
                  final id = l.id.trim();
                  if (id.isEmpty) continue;
                  final allowedLeagues = session.panelLeagueIds;
                  if (allowedLeagues != null && !allowedLeagues.contains(id)) {
                    continue;
                  }
                  byId.putIfAbsent(id, () => l);
                }
                _leagues = byId.values.toList()
                  ..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );

                if (_selectedLeagueId.isEmpty && _leagues.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() => _selectedLeagueId = _leagues.first.id);
                    _ensureSeasons(_selectedLeagueId);
                  });
                } else if (_selectedLeagueId.isNotEmpty) {
                  _ensureSeasons(_selectedLeagueId);
                }

                final parts = [
                  byId[_selectedLeagueId]?.name ?? 'Turnuva seçin',
                  _seasonName(_selectedSeasonId),
                  _filterLabel(_penaltyFilter),
                ].where((s) => s.trim().isNotEmpty);
                return AdminFilterBar(
                  padding: const EdgeInsets.only(bottom: 12),
                  summary: parts.join(' • '),
                  onTap: _openFilters,
                );
              },
            ),
            if (_selectedSeasonId.trim().isNotEmpty)
              FutureBuilder<Set<String>?>(
                future: _allowedPlayers(_selectedSeasonId),
                builder: (context, allowedSnap) {
                  if (allowedSnap.connectionState != ConnectionState.done) {
                    return const SizedBox.shrink();
                  }
                  return _PendingPenaltiesCard(
                    key: ValueKey('pending_$_selectedSeasonId'),
                    seasonId: _selectedSeasonId,
                    penaltyService: _penaltyService,
                    allowedPlayerIds: allowedSnap.data,
                  );
                },
              ),
            Expanded(
              child: _selectedSeasonId.trim().isEmpty
                  ? Center(
                      child: Text(
                        'Liste için sezon seçin.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : FutureBuilder<Set<String>?>(
                      future: _allowedPlayers(_selectedSeasonId),
                      builder: (context, allowedSnap) {
                        if (allowedSnap.connectionState !=
                            ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: kAdminAccent,
                            ),
                          );
                        }
                        final allowed = allowedSnap.data;
                        return StreamBuilder<Map<String, PlayerPenalty>>(
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
                                    .where(
                                      (p) =>
                                          !_hiddenPenaltyIds.contains(p.id) &&
                                          (allowed == null ||
                                              allowed.contains(p.playerId)),
                                    )
                                    .toList()
                                  ..sort(
                                    (a, b) =>
                                        b.matchCount.compareTo(a.matchCount),
                                  );
                            if (list.isEmpty) {
                              return Center(
                                child: Text(
                                  switch (_penaltyFilter) {
                                    _PenaltyFilter.active => 'Aktif ceza yok.',
                                    _PenaltyFilter.passive => 'Pasif ceza yok.',
                                    _PenaltyFilter.all => 'Ceza kaydı yok.',
                                  },
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              );
                            }

                            final playerIds = list
                                .map((e) => e.playerId)
                                .toSet();
                            return FutureBuilder<
                              Map<String, Map<String, dynamic>>
                            >(
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
                                            const <
                                              String,
                                              Map<String, dynamic>
                                            >{};
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
                                                rosterByPlayerId[pen
                                                    .playerId] ??
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
                                                (teamById[pTeamId]?['name'] ??
                                                        '')
                                                    .toString()
                                                    .trim();

                                            final resolvedName = pName.isEmpty
                                                ? pen.playerId
                                                : pName;
                                            final resolvedTeam = tName.isEmpty
                                                ? pTeamId
                                                : tName;

                                            return Container(
                                              decoration: adminCardDecoration(),
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
                                                        alignment:
                                                            Alignment.center,
                                                        child: Text(
                                                          pNum.isEmpty
                                                              ? '—'
                                                              : pNum,
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  resolvedTeam,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: cs.onSurfaceVariant
                                                        .withValues(
                                                          alpha: 0.72,
                                                        ),
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
                                                  mainAxisSize:
                                                      MainAxisSize.min,
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
                                                    AdminSmallAction(
                                                      icon: Icons.edit_outlined,
                                                      tooltip: 'Düzenle',
                                                      color: Colors.white70,
                                                      onTap: () =>
                                                          _openPenaltySheet(
                                                            initialLeagueId:
                                                                _selectedLeagueId,
                                                            initialSeasonId:
                                                                _selectedSeasonId,
                                                            initialTeamId:
                                                                pTeamId,
                                                            initialPlayerId:
                                                                pen.playerId,
                                                            penaltyId: pen.id,
                                                          ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    AdminSmallAction(
                                                      icon: Icons
                                                          .delete_outline_rounded,
                                                      tooltip: 'Sil',
                                                      color: kAdminDanger,
                                                      onTap: () =>
                                                          _deletePenalty(
                                                            penaltyId: pen.id,
                                                            playerId:
                                                                pen.playerId,
                                                            resolvedName:
                                                                resolvedName,
                                                          ),
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

  late final Stream<List<League>> _leaguesStream = widget.leagueService
      .watchLeagues();
  List<AdminOption> _leagues = const [];
  List<AdminOption> _seasons = const [];
  List<AdminOption> _teams = const [];
  List<AdminOption> _players = const [];
  bool _loadingSeasons = false;
  bool _loadingTeams = false;
  bool _loadingPlayers = false;

  bool _saving = false;
  bool _loadingExisting = false;

  bool get _isEdit => _penaltyId.trim().isNotEmpty;

  // Turnuva → Sezon → Takım → Futbolcu listeleri. Sezon tekse ya da varsayılan
  // işaretliyse otomatik seçilir.

  Future<void> _loadSeasons({bool autoPick = true}) async {
    final lid = _leagueId.trim();
    if (lid.isEmpty) return;
    setState(() => _loadingSeasons = true);
    try {
      final res = await widget.sb
          .from('seasons')
          .select('id, name, is_default')
          .eq('league_id', lid)
          .order('start_date', ascending: false);
      if (!mounted || _leagueId != lid) return;
      final seasons = [
        for (final r in res)
          (
            id: (r['id'] ?? '').toString().trim(),
            name: (r['name'] ?? '').toString().trim(),
            isDefault: r['is_default'] == true,
          ),
      ];
      setState(() {
        _seasons = seasons;
        _loadingSeasons = false;
      });
      if (autoPick && _seasonId.isEmpty) {
        final auto = autoPickOption(seasons);
        if (auto != null) _selectSeason(auto);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSeasons = false);
    }
  }

  Future<void> _loadTeams() async {
    final sid = _seasonId.trim();
    if (sid.isEmpty) return;
    setState(() => _loadingTeams = true);
    try {
      final teams = await widget.teamService.getTeamsCached(
        sid,
        caller: 'AdminPenalty',
      );
      if (!mounted || _seasonId != sid) return;
      final byId = <String, AdminOption>{};
      for (final t in teams) {
        final id = t.id.trim();
        if (id.isEmpty) continue;
        // Sezona bağlı ama hiçbir gruba atanmamış takımlar sezonda oynamaz.
        if ((t.groupId ?? '').trim().isEmpty) continue;
        byId.putIfAbsent(
          id,
          () => (
            id: id,
            name: t.name.trim().isEmpty ? id : t.name.trim(),
            isDefault: false,
          ),
        );
      }
      setState(() {
        _teams = byId.values.toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _loadingTeams = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingTeams = false);
    }
  }

  Future<void> _loadPlayers() async {
    final tid = _teamId.trim();
    final sid = _seasonId.trim();
    if (tid.isEmpty || sid.isEmpty) return;
    setState(() => _loadingPlayers = true);
    try {
      final players = await widget.teamService
          .watchPlayers(teamId: tid, tournamentId: sid)
          .first;
      if (!mounted || _teamId != tid) return;
      final byId = <String, AdminOption>{};
      for (final p in players) {
        final id = p.id.trim();
        if (id.isEmpty) continue;
        byId.putIfAbsent(
          id,
          () => (
            id: id,
            name: p.name.trim().isEmpty ? id : p.name.trim(),
            isDefault: false,
          ),
        );
      }
      setState(() {
        _players = byId.values.toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _loadingPlayers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPlayers = false);
    }
  }

  void _clearForm() {
    if (_isEdit) return;
    _matchCountController.text = '';
    _descController.text = '';
  }

  void _selectLeague(String id) {
    setState(() {
      _leagueId = id;
      _seasonId = '';
      _teamId = '';
      _playerId = '';
      _seasons = const [];
      _teams = const [];
      _players = const [];
      _clearForm();
    });
    _loadSeasons();
  }

  void _selectSeason(String id) {
    setState(() {
      _seasonId = id;
      _teamId = '';
      _playerId = '';
      _teams = const [];
      _players = const [];
      _clearForm();
    });
    _loadTeams();
  }

  void _selectTeam(String id) {
    setState(() {
      _teamId = id;
      _playerId = '';
      _players = const [];
      _clearForm();
    });
    _loadPlayers();
  }

  Future<void> _selectPlayer(String id) async {
    setState(() {
      _playerId = id;
      _clearForm();
    });
    if (!_isEdit) await _loadExistingForPlayerSeason();
  }

  static String? _nameOf(List<AdminOption> options, String id) {
    for (final o in options) {
      if (o.id == id) return o.name;
    }
    return null;
  }

  Future<void> _pick({
    required String title,
    required List<AdminOption> options,
    required String selected,
    required void Function(String id) onPicked,
  }) async {
    final picked = await showAdminOptionPicker<String>(
      context: context,
      title: title,
      items: options.map((o) => o.id).toList(),
      labelBuilder: (id) => _nameOf(options, id) ?? id,
      selected: selected.isEmpty ? null : selected,
    );
    if (picked != null && picked != selected) onPicked(picked);
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
      // Kilitli alanlarda adların görünmesi için listeleri yükle.
      _loadSeasons(autoPick: false);
      _loadTeams();
      _loadPlayers();
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_penaltyId.isNotEmpty) {
        _loadExistingFromPenaltyId();
        return;
      }
      _loadSeasons();
      _loadTeams();
      _loadPlayers();
      if (_playerId.isNotEmpty && _seasonId.isNotEmpty) {
        _loadExistingForPlayerSeason();
      }
    });
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
    final locked = _saving || _isEdit;
    final formEnabled =
        !_saving &&
        _playerId.trim().isNotEmpty &&
        _seasonId.trim().isNotEmpty &&
        !_loadingExisting;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminDialogHeader(
            icon: Icons.gavel_rounded,
            title: _isEdit ? 'Cezayı Düzenle' : 'Ceza Ekle',
            subtitle: _isEdit
                ? 'Futbolcu bilgileri değiştirilemez'
                : 'Önce turnuva, sezon ve futbolcuyu seçin',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                AdminFormSection(
                  title: 'Turnuva',
                  child: StreamBuilder<List<League>>(
                    stream: _leaguesStream,
                    builder: (context, snap) {
                      if (snap.hasData) {
                        final byId = <String, AdminOption>{};
                        for (final l in snap.data!) {
                          final id = l.id.trim();
                          if (id.isEmpty) continue;
                          byId.putIfAbsent(
                            id,
                            () => (
                              id: id,
                              name: l.name.trim().isEmpty ? id : l.name.trim(),
                              isDefault: false,
                            ),
                          );
                        }
                        _leagues = byId.values.toList()
                          ..sort(
                            (a, b) => a.name.toLowerCase().compareTo(
                              b.name.toLowerCase(),
                            ),
                          );
                      }
                      final leagueChosen = _leagueId.isNotEmpty;
                      return AdminFieldGroup(
                        children: [
                          AdminSelectRow(
                            icon: Icons.emoji_events_outlined,
                            label: 'Turnuva',
                            value: _nameOf(_leagues, _leagueId),
                            placeholder: 'Turnuva seçin',
                            locked: _isEdit,
                            loading: !snap.hasData,
                            onTap: locked
                                ? null
                                : () => _pick(
                                    title: 'Turnuva Seçin',
                                    options: _leagues,
                                    selected: _leagueId,
                                    onPicked: _selectLeague,
                                  ),
                          ),
                          AdminSelectRow(
                            icon: Icons.calendar_month_outlined,
                            label: 'Sezon',
                            value: _nameOf(_seasons, _seasonId),
                            placeholder: leagueChosen
                                ? 'Sezon seçin'
                                : 'Önce turnuva seçin',
                            locked: _isEdit,
                            loading: _loadingSeasons,
                            onTap: locked || !leagueChosen
                                ? null
                                : () => _pick(
                                    title: 'Sezon Seçin',
                                    options: _seasons,
                                    selected: _seasonId,
                                    onPicked: _selectSeason,
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                AdminFormSection(
                  title: 'Futbolcu',
                  child: AdminFieldGroup(
                    children: [
                      AdminSelectRow(
                        icon: Icons.shield_outlined,
                        label: 'Takım',
                        value: _nameOf(_teams, _teamId),
                        placeholder: _seasonId.isEmpty
                            ? 'Önce sezon seçin'
                            : 'Takım seçin',
                        locked: _isEdit,
                        loading: _loadingTeams,
                        onTap: locked || _seasonId.isEmpty
                            ? null
                            : () => _pick(
                                title: 'Takım Seçin',
                                options: _teams,
                                selected: _teamId,
                                onPicked: _selectTeam,
                              ),
                      ),
                      AdminSelectRow(
                        icon: Icons.person_outline_rounded,
                        label: 'Futbolcu',
                        value: _nameOf(_players, _playerId),
                        placeholder: _teamId.isEmpty
                            ? 'Önce takım seçin'
                            : 'Futbolcu seçin',
                        locked: _isEdit,
                        loading: _loadingPlayers,
                        onTap: locked || _teamId.isEmpty
                            ? null
                            : () => _pick(
                                title: 'Futbolcu Seçin',
                                options: _players,
                                selected: _playerId,
                                onPicked: _selectPlayer,
                              ),
                      ),
                    ],
                  ),
                ),
                AdminFormSection(
                  title: 'Ceza',
                  child: Column(
                    children: [
                      TextField(
                        controller: _matchCountController,
                        enabled: formEnabled,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        cursorColor: kAdminAccent,
                        decoration: adminInputDecoration(
                          label: 'Ceza Maç Sayısı',
                          icon: Icons.block_rounded,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descController,
                        enabled: formEnabled,
                        minLines: 3,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: kAdminAccent,
                        decoration: adminInputDecoration(
                          label: 'Açıklama',
                          hint: 'Cezanın nedeni (isteğe bağlı)',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AdminPrimaryButton(
            label: _isEdit ? 'GÜNCELLE' : 'KAYDET',
            busy: _saving,
            onPressed: _loadingExisting ? null : _submit,
          ),
        ],
      ),
    );
  }
}

enum _PenaltyFilter { active, passive, all }

/// Kırmızı kart / ikinci sarıdan otomatik açılan, turnuva sahibinin onayını
/// bekleyen cezalar. Onayda maç sayısı değiştirilebilir; onaylanan ceza
/// yalnızca bu sezonun maçlarında geçerlidir.
class _PendingPenaltiesCard extends StatefulWidget {
  const _PendingPenaltiesCard({
    super.key,
    required this.seasonId,
    required this.penaltyService,
    this.allowedPlayerIds,
  });

  final String seasonId;
  final PenaltyService penaltyService;

  /// Bölge sorumlusu: yalnızca bölgesindeki oyuncular (null = hepsi).
  final Set<String>? allowedPlayerIds;

  @override
  State<_PendingPenaltiesCard> createState() => _PendingPenaltiesCardState();
}

class _PendingPenaltiesCardState extends State<_PendingPenaltiesCard> {
  late final Stream<List<PlayerPenalty>> _pending = widget.penaltyService
      .watchPendingPenalties(widget.seasonId);
  final Map<String, int> _counts = {};
  final Set<String> _busy = {};
  final Map<String, String> _nameById = {};
  final Map<String, String> _teamByPlayer = {};
  Set<String> _loadedFor = {};

  Future<void> _loadNames(Set<String> ids) async {
    if (ids.isEmpty || _loadedFor.containsAll(ids)) return;
    _loadedFor = {..._loadedFor, ...ids};
    try {
      final sb = Supabase.instance.client;
      final players = await sb
          .from('players')
          .select('id, name, surname')
          .inFilter('id', ids.toList());
      final rosters = await sb
          .from('season_team_players')
          .select('player_id, teams(name)')
          .eq('season_id', widget.seasonId)
          .inFilter('player_id', ids.toList());
      if (!mounted) return;
      setState(() {
        for (final p in players) {
          _nameById[p['id'].toString()] =
              '${p['name'] ?? ''} ${p['surname'] ?? ''}'.trim();
        }
        for (final r in rosters) {
          final t = (r['teams'] as Map?)?['name'];
          if (t != null) _teamByPlayer[r['player_id'].toString()] = '$t';
        }
      });
    } catch (_) {}
  }

  Future<void> _review(PlayerPenalty p, bool approve) async {
    setState(() => _busy.add(p.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.penaltyService.reviewPenalty(
        p.id,
        approve: approve,
        matchCount: approve ? (_counts[p.id] ?? p.matchCount) : null,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(approve ? 'Ceza onaylandı.' : 'Ceza reddedildi.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PlayerPenalty>>(
      stream: _pending,
      builder: (context, snap) {
        final allowed = widget.allowedPlayerIds;
        final list = [
          for (final p in snap.data ?? const <PlayerPenalty>[])
            if (allowed == null || allowed.contains(p.playerId)) p,
        ];
        if (list.isEmpty) return const SizedBox.shrink();
        final ids = list.map((p) => p.playerId).toSet();
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadNames(ids));
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AdminFormSection(
            title: 'Onay bekleyen cezalar (${list.length})',
            child: AdminFieldGroup(children: [for (final p in list) _row(p)]),
          ),
        );
      },
    );
  }

  Widget _row(PlayerPenalty p) {
    final count = _counts[p.id] ?? p.matchCount;
    final busy = _busy.contains(p.id);
    final name = _nameById[p.playerId] ?? '…';
    final team = _teamByPlayer[p.playerId];
    final isRed = p.kind == 'red_card';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 19,
                decoration: BoxDecoration(
                  color: isRed
                      ? const Color(0xFFDC2626)
                      : const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      [
                        if (team != null) team,
                        isRed ? 'Kırmızı kart' : 'İkinci sarı kart',
                      ].join(' · '),
                      style: const TextStyle(
                        color: kAdminMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: busy || count <= 1
                    ? null
                    : () => setState(() => _counts[p.id] = count - 1),
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: Colors.white70,
              ),
              Text(
                '$count maç',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                onPressed: busy
                    ? null
                    : () => setState(() => _counts[p.id] = count + 1),
                icon: const Icon(Icons.add_circle_outline_rounded),
                color: Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _review(p, false),
                  child: const Text('Reddet'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kAdminAccent),
                  onPressed: busy ? null : () => _review(p, true),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Onayla'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
