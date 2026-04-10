import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/league.dart';
import '../models/match.dart';
import '../models/team.dart';
import '../services/app_session.dart';
import '../services/database_service.dart';

class AdminGroupManagementScreen extends StatefulWidget {
  const AdminGroupManagementScreen({super.key});

  @override
  State<AdminGroupManagementScreen> createState() =>
      _AdminGroupManagementScreenState();
}

class _AdminGroupManagementScreenState
    extends State<AdminGroupManagementScreen> {
  final _dbService = DatabaseService();
  String? _selectedLeagueId;
  String? _selectedGroupId;
  final List<String> _selectedTeamIds = [];

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('Grup ve Takım Atama')),
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
          StreamBuilder<QuerySnapshot>(
            stream: _dbService.getLeagues(),
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
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedLeagueId,
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
              stream: _dbService.getGroups(_selectedLeagueId!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                final groups = [...snapshot.data!]
                  ..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );
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
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedGroupId = val;
                                      final group = groups.firstWhere(
                                        (g) => g.id == val,
                                      );
                                      _selectedTeamIds.clear();
                                      _selectedTeamIds.addAll(group.teamIds);
                                    });
                                  },
                                  menuMaxHeight: 360,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (isAdmin && selectedGroup != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            title: Text(
                              'Seçili Grup: ${selectedGroup.name}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await showModalBottomSheet<void>(
                                context: context,
                                showDragHandle: true,
                                builder: (context) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(Icons.delete_outline),
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
              child: StreamBuilder<QuerySnapshot>(
                stream: _dbService.getTeams(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final allTeams = snapshot.data!.docs
                      .map(
                        (doc) => Team.fromMap({
                          ...doc.data() as Map<String, dynamic>,
                          'id': doc.id,
                        }),
                      )
                      .toList();

                  // Filtreleme Mantığı:
                  // 1. Sadece bu turnuvaya (League) ait olan takımları göster.
                  // 2. Takımın bir grubu yoksa (null) göster.
                  // 3. Takım zaten BAŞKA bir gruptaysa (ve o grup bizim seçtiğimiz grup DEĞİLSE) listede gösterme.
                  final availableTeams =
                      allTeams.where((t) {
                        if (t.leagueId != _selectedLeagueId) return false;
                        if (t.groupId != null && t.groupId != _selectedGroupId)
                          return false;
                        return true;
                      }).toList()..sort(
                        (a, b) => a.name.toLowerCase().compareTo(
                          b.name.toLowerCase(),
                        ),
                      );

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                            child: Text(
                              'Takımları Seçin',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ),
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
                                secondary: team.logoUrl.isNotEmpty
                                    ? Image.network(team.logoUrl, width: 30)
                                    : null,
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
                          child: const Text('Grubu Güncelle / Kaydet'),
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
                        _selectedLeagueId == null)
                      return;
                    await _dbService.addGroup(
                      GroupModel(
                        id: '',
                        leagueId: _selectedLeagueId!,
                        name: controller.text.trim(),
                        teamIds: [],
                      ),
                    );
                    if (!mounted) return;
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Ekle'),
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
      // 1. Grubu güncelle (teamIds listesi)
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(_selectedGroupId)
          .update({'teamIds': _selectedTeamIds});

      // 2. Takımları güncelle (groupId ve groupName ata)
      final groupSnap = await FirebaseFirestore.instance
          .collection('groups')
          .doc(_selectedGroupId)
          .get();
      final groupName = groupSnap.data()?['name'] ?? '';

      final batch = FirebaseFirestore.instance.batch();

      // Önce bu gruptan çıkarılan takımların groupId'sini temizle
      final oldTeams = await FirebaseFirestore.instance
          .collection('teams')
          .where('groupId', isEqualTo: _selectedGroupId)
          .get();
      for (var doc in oldTeams.docs) {
        batch.update(doc.reference, {'groupId': null, 'groupName': null});
      }

      // Seçilen yeni takımlara ata
      for (var tId in _selectedTeamIds) {
        batch.update(FirebaseFirestore.instance.collection('teams').doc(tId), {
          'groupId': _selectedGroupId,
          'groupName': groupName,
        });
      }

      await batch.commit();
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
      await _dbService.deleteGroupCascade(groupId);
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
