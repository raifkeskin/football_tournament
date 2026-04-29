import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/league.dart';
import '../models/season.dart';
import '../../match/models/match.dart';
import '../../team/models/team.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/app_session.dart';
import '../services/interfaces/i_league_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
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
  String? _selectedLeagueId;
  String? _selectedSeasonId;
  String? _selectedGroupId;
  String? _selectedGroupName;
  final List<String> _selectedTeamIds = [];

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
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      return const Stream<List<Season>>.empty();
    }
    return Supabase.instance.client
        .from('seasons')
        .stream(primaryKey: ['id'])
        .eq('league_id', id)
        .order('start_date', ascending: false)
        .map(
          (rows) => rows
              .cast<Map<String, dynamic>>()
              .map(Season.fromJson)
              .toList(),
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

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Grup ve Takım Atama'),
        actions: [
          if (isAdmin && (_selectedSeasonId ?? '').trim().isNotEmpty)
            IconButton(
              onPressed: _openAddGroupSheet,
              icon: const Icon(Icons.add),
              tooltip: 'Grup Ekle',
            ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // 1. Turnuva Seçimi
          StreamBuilder<List<League>>(
            stream: _leagueService.watchLeagues(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              final leagues = snapshot.data ?? const <League>[];
              if (leagues.isNotEmpty) {
                final hasSelected =
                    _selectedLeagueId != null &&
                    leagues.any((l) => l.id == _selectedLeagueId);
                if (!hasSelected) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      _selectedLeagueId = leagues.first.id;
                      _selectedGroupId = null;
                      _selectedTeamIds.clear();
                    });
                  });
                }
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedLeagueId,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Turnuva Seçin',
                        labelStyle: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
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
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: widget.lockLeagueSelection
                          ? null
                          : (val) {
                              setState(() {
                                _selectedLeagueId = val;
                                _selectedSeasonId = null;
                                _selectedGroupId = null;
                                _selectedTeamIds.clear();
                              });
                            },
                    ),
                  ),
                ),
              );
            },
          ),

          // 2. Sezon Seçimi
          if ((_selectedLeagueId ?? '').trim().isNotEmpty)
            StreamBuilder<List<Season>>(
              stream: _watchSeasonsForLeague(_selectedLeagueId!),
              builder: (context, snapshot) {
                if (AppConfig.activeDatabase != DatabaseType.supabase) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Sezon seçimi bu veritabanı modunda desteklenmiyor.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) return const SizedBox();
                final seasons = snapshot.data ?? const <Season>[];
                if (seasons.isNotEmpty) {
                  final hasSelected = _selectedSeasonId != null &&
                      seasons.any((s) => s.id == _selectedSeasonId);
                  if (!hasSelected) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        _selectedSeasonId = seasons.first.id;
                        _selectedGroupId = null;
                        _selectedTeamIds.clear();
                      });
                    });
                  }
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedSeasonId,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Sezon Seçin',
                          labelStyle: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        items: seasons
                            .map(
                              (s) => DropdownMenuItem(
                                value: s.id,
                                child: Center(
                                  child: Text(
                                    s.name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedSeasonId = val;
                            _selectedGroupId = null;
                            _selectedGroupName = null;
                            _selectedTeamIds.clear();
                          });
                        },
                        menuMaxHeight: 360,
                      ),
                    ),
                  ),
                );
              },
            ),

          // 2. Grup Seçimi (Turnuva seçildiyse)
          if ((_selectedSeasonId ?? '').trim().isNotEmpty)
            StreamBuilder<List<GroupModel>>(
              stream: _leagueService.watchGroups(_selectedSeasonId!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                final groups = [...snapshot.data!]
                  ..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );
                if (groups.isNotEmpty) {
                  final hasSelected =
                      _selectedGroupId != null &&
                      groups.any((g) => g.id == _selectedGroupId);
                  if (!hasSelected) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final first = groups.first;
                      setState(() {
                        _selectedGroupId = first.id;
                        _selectedGroupName = first.name;
                        _selectedTeamIds.clear();
                      });
                      _syncSelectedTeamsForGroup();
                    });
                  }
                }
                GroupModel? selectedGroup;
                final selectedGroupId = _selectedGroupId;
                if (selectedGroupId != null) {
                  for (final g in groups) {
                    if (g.id == selectedGroupId) {
                      selectedGroup = g;
                      break;
                    }
                  }
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedGroupId,
                                  dropdownColor: const Color(0xFF1E293B),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Grup Seçin',
                                    labelStyle: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
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
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) {
                                    final selected = groups.where((g) => g.id == val).toList();
                                    setState(() {
                                      _selectedGroupId = val;
                                      _selectedGroupName = selected.isEmpty ? null : selected.first.name;
                                      _selectedTeamIds.clear();
                                    });
                                    _syncSelectedTeamsForGroup();
                                  },
                                  menuMaxHeight: 360,
                                ),
                              ),
                              if (isAdmin && selectedGroup != null) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () async {
                                    await showModalBottomSheet<void>(
                                      context: context,
                                      showDragHandle: true,
                                      builder: (context) => SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              leading: const Icon(
                                                Icons.delete_outline,
                                              ),
                                              title: const Text('Grubu Sil'),
                                              onTap: () {
                                                Navigator.pop(context);
                                                _deleteSelectedGroup();
                                              },
                                            ),
                                            const SizedBox(height: 10),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.more_vert_rounded),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

          // 3. Takım Listesi (Checkbox)
          if (_selectedGroupId != null)
            Expanded(
              child: StreamBuilder<List<Team>>(
                stream: _teamService.watchAllTeams(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final allTeams =
                      (snapshot.data ?? const <Team>[])
                          .where((t) => t.id != 'free_agent_pool')
                          .toList();

                  final seasonId = (_selectedSeasonId ?? '').trim();
                  final groupId = (_selectedGroupId ?? '').trim();
                  final availableTeams = allTeams
                      .where((t) => (t.seasonId ?? '').trim() == seasonId)
                      .where(
                        (t) =>
                            (t.groupId ?? '').trim().isEmpty ||
                            (t.groupId ?? '').trim() == groupId,
                      )
                      .toList()
                    ..sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    );

                  return Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: availableTeams.length,
                          itemBuilder: (context, index) {
                            final team = availableTeams[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: CheckboxListTile(
                                title: Text(team.name),
                                secondary: SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: WebSafeImage(
                                    url: team.logoUrl,
                                    width: 30,
                                    height: 30,
                                    borderRadius: BorderRadius.circular(6),
                                    fallbackIconSize: 16,
                                  ),
                                ),
                                value: _selectedTeamIds.contains(team.id),
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedTeamIds.add(team.id);
                                    } else {
                                      _selectedTeamIds.remove(team.id);
                                    }
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: FilledButton(
                          onPressed: _saveGroupTeams,
                          child: const Text('KAYDET'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openAddGroupSheet() async {
    final seasonId = (_selectedSeasonId ?? '').trim();
    if (seasonId.isEmpty) return;
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu işlem bu veritabanı modunda desteklenmiyor.'),
        ),
      );
      return;
    }

    final nameController = TextEditingController();
    final selectedTeamIds = <String>{};
    var saving = false;

    Future<void> openTeamPicker(void Function(void Function()) setSheetState) async {
      final picked = await showModalBottomSheet<Set<String>>(
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
        builder: (context) {
          final viewInsets = MediaQuery.of(context).viewInsets;
          final h = MediaQuery.of(context).size.height * 0.8;
          final working = <String>{...selectedTeamIds};
          return StatefulBuilder(
            builder: (context, setPickerState) {
              return SizedBox(
                height: h,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    16 + viewInsets.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox(
                          width: 148,
                          height: 148,
                          child: ClipOval(
                            child: Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: Icon(
                                Icons.shield_outlined,
                                size: 44,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Takım Ekle/Çıkar',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: StreamBuilder<List<Team>>(
                          stream: _teamService.watchAllTeams(),
                          builder: (context, snap) {
                            final teams = (snap.data ?? const <Team>[])
                                .where((t) => t.id != 'free_agent_pool')
                                .where((t) => (t.seasonId ?? '').trim() == seasonId)
                                .toList()
                              ..sort(
                                (a, b) => a.name
                                    .toLowerCase()
                                    .compareTo(b.name.toLowerCase()),
                              );
                            if (teams.isEmpty) {
                              return const Center(child: Text('Takım bulunamadı.'));
                            }
                            return ListView.builder(
                              itemCount: teams.length,
                              itemBuilder: (context, index) {
                                final t = teams[index];
                                final checked = working.contains(t.id);
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: CheckboxListTile(
                                    value: checked,
                                    onChanged: (val) {
                                      setPickerState(() {
                                        if (val == true) {
                                          working.add(t.id);
                                        } else {
                                          working.remove(t.id);
                                        }
                                      });
                                    },
                                    title: Text(t.name),
                                    secondary: SizedBox(
                                      width: 30,
                                      height: 30,
                                      child: WebSafeImage(
                                        url: t.logoUrl,
                                        width: 30,
                                        height: 30,
                                        borderRadius: BorderRadius.circular(6),
                                        fallbackIconSize: 16,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(working),
                          child: const Text(
                            'KAYDET',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'VAZGEÇ',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      if (picked == null) return;
      setSheetState(() {
        selectedTeamIds
          ..clear()
          ..addAll(picked);
      });
    }

    Future<void> submit(void Function(void Function()) setSheetState) async {
      final name = nameController.text.trim();
      if (name.isEmpty) return;
      setSheetState(() => saving = true);
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

        final ids = selectedTeamIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
        for (final id in ids) {
          await _teamService.updateTeam(
            id,
            {'groupId': groupId, 'groupName': name},
          );
        }

        if (!mounted) return;
        setState(() {
          _selectedGroupId = groupId;
          _selectedGroupName = name;
          _selectedTeamIds
            ..clear()
            ..addAll(ids);
        });
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Grup eklendi.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      } finally {
        if (mounted) setSheetState(() => saving = false);
      }
    }

    await showModalBottomSheet<void>(
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
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        final h = MediaQuery.of(context).size.height * 0.8;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final disabled = saving;
            return SizedBox(
              height: h,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SizedBox(
                        width: 148,
                        height: 148,
                        child: ClipOval(
                          child: Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: Icon(
                              Icons.groups_outlined,
                              size: 44,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      enabled: !disabled,
                      maxLength: 10,
                      decoration: const InputDecoration(
                        labelText: 'Grup Adı',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: disabled
                          ? null
                          : () => openTeamPicker(setSheetState),
                      icon: const Icon(Icons.playlist_add_check_outlined),
                      label: Text(
                        'Takım Ekle/Çıkar'
                        '${selectedTeamIds.isEmpty ? '' : ' (${selectedTeamIds.length})'}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: disabled ? null : () => submit(setSheetState),
                        child: disabled
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(
                                'KAYDET',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: disabled
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text(
                          'VAZGEÇ',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
  }

  Future<void> _saveGroupTeams() async {
    try {
      final groupId = _selectedGroupId;
      if (groupId == null) return;
      final seasonId = (_selectedSeasonId ?? '').trim();
      if (seasonId.isEmpty) return;
      final groupName = (_selectedGroupName ?? '').trim();

      final teams = await _teamService.getTeamsCached(seasonId);
      final currentGroupTeams = teams.where((t) => (t.groupId ?? '').trim() == groupId).toList();

      final nextIds = _selectedTeamIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      final currentIds = currentGroupTeams.map((t) => t.id.trim()).where((e) => e.isNotEmpty).toSet();

      final toRemove = currentIds.difference(nextIds);
      final toAdd = nextIds.difference(currentIds);

      for (final id in toRemove) {
        await _teamService.updateTeam(id, {'groupId': null, 'groupName': null});
      }
      for (final id in toAdd) {
        await _teamService.updateTeam(
          id,
          {'groupId': groupId, 'groupName': groupName.isEmpty ? null : groupName},
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Grup takımları başarıyla güncellendi.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteSelectedGroup() async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Grup Sil'),
        content: const Text(
          'Bu grup ve altındaki tüm takımlar/bağlantılar silinecektir. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hayır'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Evet'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _leagueService.deleteGroupCascade(groupId);
      if (!mounted) return;
      setState(() {
        _selectedGroupId = null;
        _selectedTeamIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Grup silindi.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
