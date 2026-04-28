import 'package:flutter/material.dart';
import '../models/league.dart';
import '../../match/models/match.dart';
import '../../team/models/team.dart';
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

  Future<void> _syncSelectedTeamsForGroup() async {
    final leagueId = (_selectedLeagueId ?? '').trim();
    final groupId = (_selectedGroupId ?? '').trim();
    if (leagueId.isEmpty || groupId.isEmpty) return;
    final teams = await _teamService.getTeamsCached(leagueId);
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
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: !isAdmin || _selectedLeagueId == null
          ? null
          : FloatingActionButton(
              onPressed: _showAddGroupDialog,
              child: const Icon(Icons.add),
            ),
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

          // 2. Grup Seçimi (Turnuva seçildiyse)
          if (_selectedLeagueId != null)
            StreamBuilder<List<GroupModel>>(
              stream: _leagueService.watchGroups(_selectedLeagueId!),
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

                  final leagueId = (_selectedLeagueId ?? '').trim();
                  final groupId = (_selectedGroupId ?? '').trim();
                  final availableTeams = allTeams
                      .where((t) => (t.leagueId ?? '').trim() == leagueId)
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

  void _showAddGroupDialog() {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 4,
            bottom: viewInsets.bottom + 16,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'Yeni Grup',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Grup Adı',
                  hintText: 'Örn: A Grubu',
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: () async {
                    if (controller.text.trim().isEmpty ||
                        _selectedLeagueId == null) {
                      return;
                    }
                    await _leagueService.addGroup(
                      GroupModel(
                        id: '',
                        leagueId: _selectedLeagueId!,
                        name: controller.text.trim(),
                      ),
                    );
                    if (!mounted) return;
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('KAYDET'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveGroupTeams() async {
    try {
      final groupId = _selectedGroupId;
      if (groupId == null) return;
      final leagueId = (_selectedLeagueId ?? '').trim();
      if (leagueId.isEmpty) return;
      final groupName = (_selectedGroupName ?? '').trim();

      final teams = await _teamService.getTeamsCached(leagueId);
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
