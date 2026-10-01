import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/league.dart';
import '../models/season.dart';
import '../../match/models/match.dart';
import '../../team/models/team.dart';
import '../../../core/services/app_session.dart';
import '../services/interfaces/i_league_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/resilient_stream.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/custom_popup_selector.dart';
import '../../../core/widgets/web_safe_image.dart';

class AdminGroupManagementScreen extends StatefulWidget {
  const AdminGroupManagementScreen({
    super.key,
    this.initialLeagueId,
    this.lockLeagueSelection = false,
  });

  final String? initialLeagueId;
  final bool lockLeagueSelection;

  @override
  State<AdminGroupManagementScreen> createState() =>
      _AdminGroupManagementScreenState();
}

class _AdminGroupManagementScreenState
    extends State<AdminGroupManagementScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final ITeamService _teamService = ServiceLocator.teamService;
  late final Stream<List<League>> _leaguesStream = _leagueService
      .watchLeagues();
  late final Stream<List<Team>> _teamsStream = _teamService.watchAllTeams();
  final Map<String, Stream<List<Season>>> _seasonStreams = {};

  String? _selectedLeagueId;
  String? _selectedSeasonId;
  String? _selectedGroupId;
  String? _selectedGroupName;
  final List<String> _selectedTeamIds = [];

  // Filtre penceresi açıkken listeler güncellenince pencereyi yeniler.
  List<League> _leagues = const [];
  List<Season> _seasons = const [];
  List<GroupModel> _groups = const [];
  VoidCallback? _filterRefresh;

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialLeagueId ?? '').trim();
    if (initial.isNotEmpty) {
      _selectedLeagueId = initial;
    }
  }

  Stream<List<Season>> _watchSeasonsForLeague(String leagueId) {
    final id = leagueId.trim();
    if (id.isEmpty) return const Stream<List<Season>>.empty();
    // Aynı turnuva için tek akış: her build'de yeniden bağlanmaz.
    // Son listeyi sonradan bağlanan dinleyiciye de hemen verir.
    return _seasonStreams.putIfAbsent(
      id,
      () => resilientStream(
        () => Supabase.instance.client
            .from('seasons')
            .stream(primaryKey: ['id'])
            .eq('league_id', id)
            .order('start_date', ascending: false)
            .map(
              (rows) => rows
                  .cast<Map<String, dynamic>>()
                  .map(Season.fromJson)
                  .toList(),
            ),
      ),
    );
  }

  void _refreshFilterDialog() {
    final refresh = _filterRefresh;
    if (refresh == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : null,
      ),
    );
  }

  Future<void> _syncSelectedTeamsForGroup() async {
    final seasonId = (_selectedSeasonId ?? '').trim();
    final groupId = (_selectedGroupId ?? '').trim();
    if (seasonId.isEmpty || groupId.isEmpty) return;
    final teams = await _teamService.getTeamsCached(seasonId);
    final ids = teams
        .where((t) => (t.groupId ?? '').trim() == groupId)
        .map((t) => t.id)
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (!mounted) return;
    setState(() {
      _selectedTeamIds
        ..clear()
        ..addAll(ids);
    });
  }

  String _filterSummary() {
    String nameOf<T>(List<T> items, String? id, String Function(T) idOf,
        String Function(T) nameOf) {
      for (final i in items) {
        if (idOf(i) == id) return nameOf(i);
      }
      return '';
    }

    final parts = [
      nameOf<League>(_leagues, _selectedLeagueId, (l) => l.id, (l) => l.name),
      nameOf<Season>(_seasons, _selectedSeasonId, (s) => s.id, (s) => s.name),
      (_selectedGroupName ?? '').trim(),
    ].where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? 'Turnuva seçin' : parts.join(' • ');
  }

  Future<void> _openFilters() async {
    await showAdminFilterDialog(
      context: context,
      fieldsBuilder: (ctx, refresh) {
        _filterRefresh = refresh;
        return [
          IgnorePointer(
            ignoring: widget.lockLeagueSelection,
            child: Opacity(
              opacity: widget.lockLeagueSelection ? 0.6 : 1,
              child: CustomPopupSelector<String>(
                label: 'Turnuva',
                selectedValue: _selectedLeagueId,
                items: _leagues.map((l) => l.id).toList(),
                labelBuilder: (id) => _leagues
                    .firstWhere(
                      (l) => l.id == id,
                      orElse: () => _leagues.first,
                    )
                    .name,
                onChanged: (val) {
                  if (val == _selectedLeagueId) return;
                  setState(() {
                    _selectedLeagueId = val;
                    _selectedSeasonId = null;
                    _selectedGroupId = null;
                    _selectedGroupName = null;
                    _seasons = const [];
                    _groups = const [];
                    _selectedTeamIds.clear();
                  });
                  refresh();
                },
              ),
            ),
          ),
          CustomPopupSelector<String>(
            label: 'Sezon',
            selectedValue: _selectedSeasonId,
            items: _seasons.map((s) => s.id).toList(),
            labelBuilder: (id) => _seasons
                .firstWhere((s) => s.id == id, orElse: () => _seasons.first)
                .name,
            onChanged: (val) {
              if (val == _selectedSeasonId) return;
              setState(() {
                _selectedSeasonId = val;
                _selectedGroupId = null;
                _selectedGroupName = null;
                _groups = const [];
                _selectedTeamIds.clear();
              });
              refresh();
            },
          ),
          CustomPopupSelector<String>(
            label: 'Grup',
            selectedValue: _selectedGroupId,
            items: _groups.map((g) => g.id).toList(),
            labelBuilder: (id) => _groups
                .firstWhere((g) => g.id == id, orElse: () => _groups.first)
                .name,
            onChanged: (val) {
              final selected = _groups.where((g) => g.id == val).toList();
              setState(() {
                _selectedGroupId = val;
                _selectedGroupName = selected.isEmpty
                    ? null
                    : selected.first.name;
                _selectedTeamIds.clear();
              });
              _syncSelectedTeamsForGroup();
              refresh();
            },
          ),
        ];
      },
    );
    _filterRefresh = null;
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    final hasSeason = (_selectedSeasonId ?? '').trim().isNotEmpty;
    return AdminPageScaffold(
      title: 'Grup ve Takım Atama',
      actions: [
        if (isAdmin && _selectedGroupId != null)
          AdminBarAction(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Grubu Sil',
            onPressed: _deleteSelectedGroup,
          ),
        if (isAdmin && hasSeason)
          AdminBarAction(
            icon: Icons.add_rounded,
            tooltip: 'Grup Ekle',
            onPressed: _openAddGroupDialog,
          ),
      ],
      body: StreamBuilder<List<League>>(
        stream: _leaguesStream,
        builder: (context, leagueSnap) {
          if (!leagueSnap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: kAdminAccent),
            );
          }
          _leagues = leagueSnap.data ?? const <League>[];
          if (_leagues.isNotEmpty &&
              !_leagues.any((l) => l.id == _selectedLeagueId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _selectedLeagueId = _leagues.first.id;
                _selectedSeasonId = null;
                _selectedGroupId = null;
                _selectedGroupName = null;
                _selectedTeamIds.clear();
              });
            });
          }
          final leagueId = (_selectedLeagueId ?? '').trim();
          return StreamBuilder<List<Season>>(
            stream: _watchSeasonsForLeague(leagueId),
            builder: (context, seasonSnap) {
              _seasons = seasonSnap.data ?? const <Season>[];
              if (_seasons.isNotEmpty &&
                  !_seasons.any((s) => s.id == _selectedSeasonId)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _selectedSeasonId = _seasons.first.id;
                    _selectedGroupId = null;
                    _selectedGroupName = null;
                    _selectedTeamIds.clear();
                  });
                });
              }
              final seasonId = (_selectedSeasonId ?? '').trim();
              return StreamBuilder<List<GroupModel>>(
                stream: seasonId.isEmpty
                    ? const Stream<List<GroupModel>>.empty()
                    : _leagueService.watchGroups(seasonId),
                builder: (context, groupSnap) {
                  _groups = [...(groupSnap.data ?? const <GroupModel>[])]
                    ..sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    );
                  if (_groups.isNotEmpty &&
                      !_groups.any((g) => g.id == _selectedGroupId)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final first = _groups.first;
                      setState(() {
                        _selectedGroupId = first.id;
                        _selectedGroupName = first.name;
                        _selectedTeamIds.clear();
                      });
                      _syncSelectedTeamsForGroup();
                    });
                  }
                  _refreshFilterDialog();

                  return Column(
                    children: [
                      AdminFilterBar(
                        summary: _filterSummary(),
                        onTap: _openFilters,
                      ),
                      Expanded(child: _teamChecklist()),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _teamChecklist() {
    if (_selectedGroupId == null) {
      return Center(
        child: Text(
          (_selectedSeasonId ?? '').isEmpty
              ? 'Sezon bulunamadı.'
              : 'Bu sezonda grup yok. Sağ üstten grup ekleyebilirsiniz.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return StreamBuilder<List<Team>>(
      stream: _teamsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: kAdminAccent),
          );
        }
        final seasonId = (_selectedSeasonId ?? '').trim();
        final groupId = (_selectedGroupId ?? '').trim();
        final availableTeams =
            (snapshot.data ?? const <Team>[])
                .where((t) => t.id != 'free_agent_pool')
                .where((t) => (t.seasonId ?? '').trim() == seasonId)
                .where(
                  (t) =>
                      (t.groupId ?? '').trim().isEmpty ||
                      (t.groupId ?? '').trim() == groupId,
                )
                .toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );

        if (availableTeams.isEmpty) {
          return const Center(
            child: Text(
              'Bu sezonda gruba eklenebilecek takım yok.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        return Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                itemCount: availableTeams.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final team = availableTeams[index];
                  return _TeamCheckTile(
                    team: team,
                    checked: _selectedTeamIds.contains(team.id),
                    onChanged: (val) => setState(() {
                      if (val) {
                        _selectedTeamIds.add(team.id);
                      } else {
                        _selectedTeamIds.remove(team.id);
                      }
                    }),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAdminAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _saveGroupTeams,
                  child: const Text(
                    'KAYDET',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Sezondaki takımlardan seçim (ortada açılan popup).
  Future<Set<String>?> _pickTeams(String seasonId, Set<String> initial) {
    final working = <String>{...initial};
    return showAdminPopup<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPickerState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Takım Ekle/Çıkar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Flexible(
              child: StreamBuilder<List<Team>>(
                stream: _teamsStream,
                builder: (context, snap) {
                  final teams =
                      (snap.data ?? const <Team>[])
                          .where((t) => t.id != 'free_agent_pool')
                          .where((t) => (t.seasonId ?? '').trim() == seasonId)
                          .toList()
                        ..sort(
                          (a, b) => a.name.toLowerCase().compareTo(
                            b.name.toLowerCase(),
                          ),
                        );
                  if (teams.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Takım bulunamadı.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: teams.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final t = teams[index];
                      return _TeamCheckTile(
                        team: t,
                        checked: working.contains(t.id),
                        onChanged: (val) => setPickerState(() {
                          if (val) {
                            working.add(t.id);
                          } else {
                            working.remove(t.id);
                          }
                        }),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: _DialogButtons(
                primaryLabel: 'TAMAM',
                onPrimary: () => Navigator.pop(ctx, working),
                onCancel: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddGroupDialog() async {
    final seasonId = (_selectedSeasonId ?? '').trim();
    if (seasonId.isEmpty) return;

    final nameController = TextEditingController();
    final selectedTeamIds = <String>{};
    var saving = false;

    Future<void> submit(BuildContext ctx, StateSetter setLocal) async {
      final name = nameController.text.trim();
      if (name.isEmpty) {
        _snack('Grup adı boş olamaz.', error: true);
        return;
      }
      setLocal(() => saving = true);
      try {
        final res = await Supabase.instance.client
            .from('groups')
            .insert({'season_id': seasonId, 'name': name})
            .select('id')
            .single();
        final groupId = (res['id'] ?? '').toString().trim();
        if (groupId.isEmpty) {
          throw Exception('Grup oluşturulamadı.');
        }

        final ids = selectedTeamIds
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet();
        for (final id in ids) {
          await _teamService.updateTeam(id, {
            'groupId': groupId,
            'groupName': name,
          });
        }

        if (!mounted) return;
        setState(() {
          _selectedGroupId = groupId;
          _selectedGroupName = name;
          _selectedTeamIds
            ..clear()
            ..addAll(ids);
        });
        if (ctx.mounted) Navigator.pop(ctx);
        _snack('Grup eklendi.');
      } catch (e) {
        if (!mounted) return;
        _snack('Hata: $e', error: true);
        if (ctx.mounted) setLocal(() => saving = false);
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: adminDialogDecoration(),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.groups_outlined, color: kAdminAccent),
                      SizedBox(width: 8),
                      Text(
                        'Grup Ekle',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    enabled: !saving,
                    maxLength: 10,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Grup Adı',
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.3),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: kAdminAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      foregroundColor: kAdminAccent,
                      side: const BorderSide(color: kAdminAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            final picked = await _pickTeams(
                              seasonId,
                              selectedTeamIds,
                            );
                            if (picked == null) return;
                            setLocal(() {
                              selectedTeamIds
                                ..clear()
                                ..addAll(picked);
                            });
                          },
                    icon: const Icon(Icons.playlist_add_check_outlined),
                    label: Text(
                      'Takım Ekle/Çıkar'
                      '${selectedTeamIds.isEmpty ? '' : ' (${selectedTeamIds.length})'}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _DialogButtons(
                    primaryLabel: 'KAYDET',
                    busy: saving,
                    onPrimary: saving ? null : () => submit(ctx, setLocal),
                    onCancel: saving ? null : () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Dialog kapanış animasyonu bitene kadar alan controller'ı kullanır.
    Future<void>.delayed(
      const Duration(milliseconds: 600),
      nameController.dispose,
    );
  }

  Future<void> _saveGroupTeams() async {
    try {
      final groupId = _selectedGroupId;
      if (groupId == null) return;
      final seasonId = (_selectedSeasonId ?? '').trim();
      if (seasonId.isEmpty) return;
      final groupName = (_selectedGroupName ?? '').trim();

      final teams = await _teamService.getTeamsCached(seasonId);
      final currentGroupTeams = teams
          .where((t) => (t.groupId ?? '').trim() == groupId)
          .toList();

      final nextIds = _selectedTeamIds
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      final currentIds = currentGroupTeams
          .map((t) => t.id.trim())
          .where((e) => e.isNotEmpty)
          .toSet();

      final toRemove = currentIds.difference(nextIds);
      final toAdd = nextIds.difference(currentIds);

      for (final id in toRemove) {
        await _teamService.updateTeam(id, {'groupId': null, 'groupName': null});
      }
      for (final id in toAdd) {
        await _teamService.updateTeam(id, {
          'groupId': groupId,
          'groupName': groupName.isEmpty ? null : groupName,
        });
      }
      if (!mounted) return;
      _snack('Grup takımları güncellendi.');
    } catch (e) {
      if (!mounted) return;
      _snack('Hata: $e', error: true);
    }
  }

  Future<void> _deleteSelectedGroup() async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;

    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Grubu Sil',
      message:
          'Bu grup ve altındaki tüm takım bağlantıları silinecektir. '
          'Devam etmek istiyor musunuz?',
    );
    if (!ok) return;

    try {
      await _leagueService.deleteGroupCascade(groupId);
      if (!mounted) return;
      setState(() {
        _selectedGroupId = null;
        _selectedGroupName = null;
        _selectedTeamIds.clear();
      });
      _snack('Grup silindi.');
    } catch (e) {
      if (!mounted) return;
      _snack('Hata: $e', error: true);
    }
  }
}

/// Takım seçimi satırı (ortak koyu kart + onay kutusu).
class _TeamCheckTile extends StatelessWidget {
  const _TeamCheckTile({
    required this.team,
    required this.checked,
    required this.onChanged,
  });

  final Team team;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: adminCardDecoration(),
      child: CheckboxListTile(
        value: checked,
        onChanged: (v) => onChanged(v == true),
        activeColor: kAdminAccent,
        checkColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          team.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        secondary: SizedBox(
          width: 32,
          height: 32,
          child: WebSafeImage(
            url: team.logoUrl,
            width: 32,
            height: 32,
            borderRadius: BorderRadius.circular(8),
            fallbackIconSize: 16,
          ),
        ),
      ),
    );
  }
}

/// Popup altındaki standart buton çifti (yeşil ana buton + VAZGEÇ).
class _DialogButtons extends StatelessWidget {
  const _DialogButtons({
    required this.primaryLabel,
    required this.onPrimary,
    required this.onCancel,
    this.busy = false,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onCancel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAdminAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onPrimary,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    primaryLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 50,
          child: OutlinedButton(
            onPressed: onCancel,
            child: const Text(
              'VAZGEÇ',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}
