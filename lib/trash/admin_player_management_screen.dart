import 'package:flutter/material.dart';
import 'package:football_tournament/features/admin/services/approval_service.dart';

import '../../features/match/models/match.dart';
import '../../features/team/models/team.dart';
import '../../features/team/services/interfaces/i_team_service.dart';
import '../../features/tournament/models/league.dart';
import '../../features/tournament/services/interfaces/i_league_service.dart';
import '../../core/config/app_config.dart';
import '../../core/services/app_session.dart';
import '../../core/services/service_locator.dart';
import '../../core/widgets/web_safe_image.dart';
import '../../features/team/screens/team_squad_screen.dart';
import '../../features/player/widgets/player_card.dart';
import '../../features/player/services/player_service.dart';

class AdminPlayerManagementScreen extends StatefulWidget {
  const AdminPlayerManagementScreen({super.key});

  @override
  State<AdminPlayerManagementScreen> createState() => _AdminPlayerManagementScreenState();
}

class _AdminPlayerManagementScreenState extends State<AdminPlayerManagementScreen> {
  final _searchController = TextEditingController();
  String _q = '';

  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final ITeamService _teamService = ServiceLocator.teamService;
  final PlayerService _playerService = PlayerService();

  String _norm(String input) {
    return input.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().trim();
  }

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  String _positionsBirthLine(PlayerModel p) {
    final main = (p.mainPosition ?? '').trim();
    final sub = (p.position ?? '').trim();
    final pos = main.isEmpty ? (sub.isEmpty ? '-' : sub) : (sub.isEmpty ? main : '$main / $sub');
    final birth = (p.birthDate ?? '').trim();
    final birthText = birth.isEmpty ? '-' : birth;
    return '$pos - $birthText';
  }

  Future<void> _openPlayerForm({PlayerModel? editing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerFormScreen(
          standalone: true,
          editing: editing,
        ),
      ),
    );
  }

  Future<void> _openPlayerCard(PlayerModel p) async {
    final phoneOrId = ((p.phone ?? '').trim().isNotEmpty ? p.phone! : p.id).trim();
    final h = MediaQuery.of(context).size.height * 0.95;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: h),
      showDragHandle: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SizedBox(
          height: h,
          child: PlayerCard(
            playerPhone: phoneOrId,
            name: p.name,
            number: (p.number ?? '').trim(),
            photoUrl: (p.photoUrl ?? '').trim(),
            position: (p.position ?? p.mainPosition ?? '').trim(),
            birthDate: (p.birthDate ?? '').trim(),
            height: p.height,
            weight: p.weight,
            seasons: const <League>[],
            initialSeasonId: '',
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFabMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded),
              title: const Text('Futbolcu Ekle'),
              onTap: () => Navigator.pop(context, 'create'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_rounded),
              title: const Text('Toplu Yükle'),
              onTap: () => Navigator.pop(context, 'bulk'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'create':
        await _openPlayerForm();
        return;
      case 'bulk':
        await _openBulkUploadFlow();
        return;
    }
  }

  Future<void> _openCreatePlayerSheet() async {
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu işlem bu veritabanı modunda desteklenmiyor.')),
      );
      return;
    }

    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    var saving = false;

    String normalizePhone10(String input) {
      final digits = input.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) return '';
      var d = digits;
      if (d.startsWith('90') && d.length >= 12) d = d.substring(2);
      if (d.startsWith('0')) d = d.substring(1);
      if (d.length > 10) d = d.substring(d.length - 10);
      return d;
    }

    Future<void> submit(void Function(void Function()) setSheetState) async {
      final fullName = nameController.text.trim();
      final phone10 = normalizePhone10(phoneController.text);
      if (fullName.isEmpty) return;
      if (phone10.length != 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Telefon 10 hane olmalı.')),
        );
        return;
      }
      setSheetState(() => saving = true);
      try {
        await _playerService.createFootballer(fullName: fullName, phoneRaw10: phone10);
        if (!context.mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Futbolcu eklendi.')),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      } finally {
        if (context.mounted) setSheetState(() => saving = false);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
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
            return SizedBox(
              height: h,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Ad Soyad',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      enabled: !saving,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefon (10 hane)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: saving ? null : () => submit(setSheetState),
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
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
                        onPressed: saving ? null : () => Navigator.of(context).pop(),
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
    phoneController.dispose();
  }

  Future<Map<String, String>?> _pickLeagueTeamForBulkUpload() async {
    String selectedLeagueId = '';
    String selectedTeamId = '';
    String selectedTeamName = '';

    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      showDragHandle: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            Widget buildTeamList(List<Team> teams) {
              final list = teams
                  .where((t) => (t.leagueId ?? '').toString().trim() == selectedLeagueId)
                  .toList();
              list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

              if (selectedLeagueId.trim().isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Önce turnuva seçin.'),
                );
              }
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Bu turnuvada takım bulunamadı.'),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final t = list[i];
                  final selected = t.id == selectedTeamId;
                  return ListTile(
                    title: Text(t.name.trim().isEmpty ? t.id : t.name),
                    trailing: selected ? const Icon(Icons.check_rounded) : null,
                    onTap: () {
                      setSheetState(() {
                        selectedTeamId = t.id;
                        selectedTeamName = t.name.trim();
                      });
                    },
                  );
                },
              );
            }

            return StreamBuilder<List<League>>(
              stream: _leagueService.watchLeagues(),
              builder: (context, leaguesSnap) {
                final leagues = leaguesSnap.data ?? const <League>[];
                leagues.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                if (selectedLeagueId.isEmpty && leagues.isNotEmpty) {
                  selectedLeagueId = leagues.first.id;
                }

                return StreamBuilder<List<Team>>(
                  stream: _teamService.watchAllTeams(),
                  builder: (context, teamsSnap) {
                    final teams = teamsSnap.data ?? const <Team>[];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<String>(
                            value: selectedLeagueId.isEmpty ? null : selectedLeagueId,
                            decoration: const InputDecoration(
                              labelText: 'Turnuva',
                              prefixIcon: Icon(Icons.emoji_events_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final l in leagues)
                                DropdownMenuItem<String>(
                                  value: l.id,
                                  child: Text(l.name.trim().isEmpty ? l.id : l.name),
                                ),
                            ],
                            onChanged: (v) {
                              setSheetState(() {
                                selectedLeagueId = v ?? '';
                                selectedTeamId = '';
                                selectedTeamName = '';
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                              child: buildTeamList(teams),
                            ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: FilledButton(
                              onPressed: selectedLeagueId.trim().isEmpty ||
                                      selectedTeamId.trim().isEmpty
                                  ? null
                                  : () => Navigator.pop(
                                        context,
                                        {
                                          'leagueId': selectedLeagueId,
                                          'teamId': selectedTeamId,
                                          'teamName': selectedTeamName,
                                        },
                                      ),
                              child: const Text(
                                'Devam Et',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _openBulkUploadFlow() async {
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu işlem bu veritabanı modunda desteklenmiyor.')),
      );
      return;
    }

    final picked = await _pickLeagueTeamForBulkUpload();
    if (!mounted) return;
    if (picked == null) return;

    final leagueId = (picked['leagueId'] ?? '').trim();
    final teamId = (picked['teamId'] ?? '').trim();
    final teamName = (picked['teamName'] ?? '').trim();
    if (leagueId.isEmpty || teamId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Takım/turnuva bilgisi bulunamadı.')),
      );
      return;
    }

    await showSquadBulkUploadDialog(
      context: context,
      approvalService: ApprovalService(),
      leagueId: leagueId,
      teamId: teamId,
      teamName: teamName.isEmpty ? teamId : teamName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Futbolcu Lisans Yönetimi'),
        centerTitle: true,
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: _openFabMenu,
              child: const Icon(Icons.add),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Oyuncu Ara',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<PlayerModel>>(
                stream: _playerService.watchAllFootballers(caller: 'AdminPlayerManagementScreen'),
                initialData: const <PlayerModel>[],
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Hata: ${snap.error}'));
                  }
                  final list = (snap.data ?? const <PlayerModel>[])
                      .where((p) => _norm(p.name).contains(_norm(_q)))
                      .toList();
                  if (list.isEmpty) {
                    return const Center(child: Text('Futbolcu bulunamadı.'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final p = list[i];
                      final photo = _normalizeUrl((p.photoUrl ?? '').trim());
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          onTap: () => _openPlayerCard(p),
                          leading: photo.isNotEmpty
                              ? WebSafeImage(
                                  url: photo,
                                  width: 38,
                                  height: 38,
                                  isCircle: true,
                                  fit: BoxFit.cover,
                                  fallbackIconSize: 18,
                                )
                              : CircleAvatar(
                                  radius: 19,
                                  backgroundColor: cs.primary.withValues(alpha: 0.12),
                                  child: Icon(Icons.person, size: 18, color: cs.primary),
                                ),
                          title: Text(
                            p.name.trim().isEmpty ? p.id : p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _positionsBirthLine(p),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: 'Düzenle',
                            onPressed: () => _openPlayerForm(editing: p),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ),
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

