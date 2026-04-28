import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:football_tournament/features/admin/services/approval_service.dart';

import '../../../screens/admin_panel_screen.dart';
import '../../auth/screens/forgot_password_screen.dart';
import '../../auth/screens/online_registration_screen.dart';
import '../../team/screens/team_squad_screen.dart';
import '../../../main.dart';
import '../../home/screens/main_navigator.dart';
import '../../../core/services/app_session.dart';
import '../../auth/models/auth_models.dart';
import '../../tournament/models/league.dart'; 
import '../../team/models/team.dart';
import '../../auth/services/interfaces/i_auth_service.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onRequestHomeTab});

  final VoidCallback onRequestHomeTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final IAuthService _authService = ServiceLocator.authService;
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final ITeamService _teamService = ServiceLocator.teamService;
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;
  int _backdoorTapCount = 0;
  DateTime? _backdoorLastTapAt;
  Timer? _backdoorResetTimer;

  Future<RosterAssignment?> _pickRosterAssignmentForPlayerActions(
    String phone,
  ) async {
    final p = phone.trim();
    if (p.isEmpty) return null;

    return showModalBottomSheet<RosterAssignment>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: StreamBuilder<List<RosterAssignment>>(
              stream: _authService.watchRosterAssignmentsByPhone(p),
              builder: (context, snap) {
                final list = snap.data ?? const <RosterAssignment>[];
                if (!snap.hasData) {
                  return const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (list.isEmpty) {
                  return const Center(
                    child: Text('Takım kaydınız bulunamadı.'),
                  );
                }

                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = list[i];
                    final lid = r.tournamentId.trim();
                    final tid = r.teamId.trim();
                    return StreamBuilder<String>(
                      stream: lid.isEmpty
                          ? const Stream<String>.empty()
                          : _leagueService.watchLeagueName(lid),
                      builder: (context, leagueSnap) {
                        final leagueName = (leagueSnap.data ?? lid).trim();
                        return StreamBuilder<String>(
                          stream: tid.isEmpty
                              ? const Stream<String>.empty()
                              : _teamService.watchTeamName(tid),
                          builder: (context, teamSnap) {
                            final teamName = (teamSnap.data ?? tid).trim();
                            return ListTile(
                              onTap: () => Navigator.pop(context, r),
                              title: Text(teamName.isEmpty ? '-' : teamName),
                              subtitle: Text(leagueName.isEmpty ? '-' : leagueName),
                              trailing: const Icon(Icons.chevron_right_rounded),
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
        ),
      ),
    );
  }

  Future<String?> _pickLeagueIdForAdmin() {
    return showDialog<String>(
      context: context,
      builder: (context) => StreamBuilder<List<League>>(
        stream: _leagueService.watchLeagues(),
        builder: (context, snap) {
          final leagues = snap.data ?? const <League>[];
          return SimpleDialog(
            title: const Text('Turnuva seçin'),
            children: leagues.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Turnuva bulunamadı.'),
                    ),
                  ]
                : leagues
                    .map(
                      (l) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, l.id),
                        child: Text(l.name.trim().isEmpty ? l.id : l.name),
                      ),
                    )
                    .toList(),
          );
        },
      ),
    );
  }

  Future<String?> _pickTeamIdForAdmin(String leagueId) {
    final lid = leagueId.trim();
    if (lid.isEmpty) return Future.value(null);
    return showDialog<String>(
      context: context,
      builder: (context) => StreamBuilder<List<Team>>(
        stream: _teamService.watchAllTeams(),
        builder: (context, snap) {
          final all = snap.data ?? const <Team>[];
          final teams = all
              .where((t) => (t.leagueId ?? '').toString().trim() == lid)
              .toList();
          teams.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return SimpleDialog(
            title: const Text('Takım seçin'),
            children: teams.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Takım bulunamadı.'),
                    ),
                  ]
                : teams
                    .map(
                      (t) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, t.id),
                        child: Text(t.name.trim().isEmpty ? t.id : t.name),
                      ),
                    )
                    .toList(),
          );
        },
      ),
    );
  }

  Future<RosterAssignment?> _pickTeamTournamentForAdmin() async {
    final leagueId = (await _pickLeagueIdForAdmin())?.trim() ?? '';
    if (!mounted || leagueId.isEmpty) return null;
    final teamId = (await _pickTeamIdForAdmin(leagueId))?.trim() ?? '';
    if (!mounted || teamId.isEmpty) return null;
    return RosterAssignment(
      id: '${leagueId}_$teamId',
      tournamentId: leagueId,
      teamId: teamId,
      role: 'Admin',
    );
  }

  Future<void> _openPlayerLicenseMenu({
    required String phone,
    required bool isAdmin,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded),
              title: const Text('Yeni Futbolcu Oluştur'),
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
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlayerFormScreen(
              standalone: true,
            ),
          ),
        );
        return;
      case 'bulk':
        final picked = await _pickLeagueTeamForBulkUpload(
          isAdmin: isAdmin,
          phone: phone,
        );
        if (!mounted) return;
        if (picked == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Takım seçimi iptal edildi.')),
          );
          return;
        }
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
        return;
    }
  }

  Future<Map<String, String>?> _pickLeagueTeamForBulkUpload({
    required bool isAdmin,
    required String phone,
  }) async {
    String selectedLeagueId = '';
    String selectedTeamId = '';
    String selectedTeamName = '';

    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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

            Widget buildAdminContent() {
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
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedLeagueId.isEmpty ? null : selectedLeagueId,
                              decoration: const InputDecoration(
                                labelText: 'Turnuva',
                                prefixIcon: Icon(Icons.emoji_events_outlined),
                              ),
                              items: leagues
                                  .map(
                                    (l) => DropdownMenuItem<String>(
                                      value: l.id,
                                      child: Text(l.name.trim().isEmpty ? l.id : l.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                setSheetState(() {
                                  selectedLeagueId = v ?? '';
                                  selectedTeamId = '';
                                  selectedTeamName = '';
                                });
                              },
                            ),
                          ),
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                              child: buildTeamList(teams),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: SizedBox(
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
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            }

            Widget buildNonAdminContent() {
              final p = phone.trim();
              if (p.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Telefon bilgisi bulunamadı.'),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.tonal(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Kapat'),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return StreamBuilder<List<RosterAssignment>>(
                stream: _authService.watchRosterAssignmentsByPhone(p),
                builder: (context, rosterSnap) {
                  final rosters = rosterSnap.data ?? const <RosterAssignment>[];
                  final leagueIds = rosters
                      .map((r) => r.tournamentId.trim())
                      .where((id) => id.isNotEmpty)
                      .toSet()
                      .toList();
                  leagueIds.sort();
                  if (selectedLeagueId.isEmpty && leagueIds.isNotEmpty) {
                    selectedLeagueId = leagueIds.first;
                  }

                  final teamsForSelected = rosters
                      .where((r) => r.tournamentId.trim() == selectedLeagueId)
                      .map((r) => r.teamId.trim())
                      .where((id) => id.isNotEmpty)
                      .toSet()
                      .toList();
                  teamsForSelected.sort();

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedLeagueId.isEmpty ? null : selectedLeagueId,
                          decoration: const InputDecoration(
                            labelText: 'Turnuva',
                            prefixIcon: Icon(Icons.emoji_events_outlined),
                          ),
                          items: leagueIds
                              .map(
                                (id) => DropdownMenuItem<String>(
                                  value: id,
                                  child: StreamBuilder<String>(
                                    stream: _leagueService.watchLeagueName(id),
                                    builder: (context, snap) {
                                      final name = (snap.data ?? id).trim();
                                      return Text(name.isEmpty ? id : name);
                                    },
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setSheetState(() {
                              selectedLeagueId = v ?? '';
                              selectedTeamId = '';
                              selectedTeamName = '';
                            });
                          },
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                          child: selectedLeagueId.trim().isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text('Önce turnuva seçin.'),
                                )
                              : teamsForSelected.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                      child: Text('Bu turnuvada takım bulunamadı.'),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: teamsForSelected.length,
                                      separatorBuilder: (_, _) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, i) {
                                        final tid = teamsForSelected[i];
                                        final selected = tid == selectedTeamId;
                                        return StreamBuilder<String>(
                                          stream: _teamService.watchTeamName(tid),
                                          builder: (context, snap) {
                                            final name = (snap.data ?? tid).trim();
                                            return ListTile(
                                              title: Text(name.isEmpty ? tid : name),
                                              trailing: selected
                                                  ? const Icon(Icons.check_rounded)
                                                  : null,
                                              onTap: () {
                                                setSheetState(() {
                                                  selectedTeamId = tid;
                                                  selectedTeamName = name;
                                                });
                                              },
                                            );
                                          },
                                        );
                                      },
                                    ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SizedBox(
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
                      ),
                    ],
                  );
                },
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: isAdmin ? buildAdminContent() : buildNonAdminContent(),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _backdoorResetTimer?.cancel();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login(AppSessionController session) async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    if (phone.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen telefon ve şifre girin.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await session.signInWithPhonePassword(
        phoneInput: phone,
        password: password,
        rememberMe: _rememberMe,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Giriş başarısız: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout(AppSessionController session) async {
    debugPrint('DEBUG LOGOUT: tapped');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Çıkış yapılıyor...')),
      );
    }
    setState(() => _isLoading = true);
    _phoneController.clear();
    _passwordController.clear();
    setState(() => _rememberMe = false);
    try {
      debugPrint('DEBUG LOGOUT: calling Firebase signOut');
      await session.signOut();
      debugPrint('DEBUG LOGOUT: signOut done');

      if (!context.mounted) {
        debugPrint('DEBUG: Context lost after signOut. Cannot navigate.');
        return;
      }

      final rootNav = appNavigatorKey.currentState;
      debugPrint('DEBUG LOGOUT: root navigator available = ${rootNav != null}');
      if (rootNav != null) {
        rootNav.pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => MainNavigator(initialTabIndex: 4),
          ),
          (Route<dynamic> route) => false,
        );
        return;
      }

      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => MainNavigator(initialTabIndex: 4),
        ),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      debugPrint('DEBUG LOGOUT ERROR: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleBackdoorTap(AppSessionController session) async {
    final now = DateTime.now();
    final last = _backdoorLastTapAt;
    final within = last != null && now.difference(last) < const Duration(milliseconds: 700);
    _backdoorLastTapAt = now;
    _backdoorTapCount = within ? _backdoorTapCount + 1 : 1;

    _backdoorResetTimer?.cancel();
    _backdoorResetTimer = Timer(const Duration(milliseconds: 900), () {
      _backdoorTapCount = 0;
      _backdoorLastTapAt = null;
    });

    if (_backdoorTapCount != 3) return;
    _backdoorTapCount = 0;

    var password = '';
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Sistem Girişi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Kullanıcı: masterclass',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Şifre'),
              onChanged: (v) => password = v,
              onSubmitted: (_) => Navigator.pop(context, password),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, password),
            child: const Text('Giriş'),
          ),
        ],
      ),
    );
    final pwd = (result ?? '').trim();
    if (pwd.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final success = await session.signInSuperAdminBackdoor(password: pwd);
      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şifre hatalı.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sistem girişi başarılı.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _displayRoleTr(String role) {
    final r = role.trim();
    switch (r) {
      case 'player':
        return 'Futbolcu';
      case 'manager':
        return 'Takım Sorumlusu';
      case 'tournament_admin':
        return 'Turnuva Yöneticisi';
      case 'admin':
        return 'Admin';
      case 'super_admin':
        return 'Süper Admin';
      case 'user':
        return 'Kullanıcı';
      case 'Futbolcu':
      case 'Takım Sorumlusu':
      case 'Turnuva Yöneticisi':
      case 'Admin':
      case 'Süper Admin':
      case 'Kullanıcı':
        return r;
      default:
        return r.isEmpty ? 'Kullanıcı' : r;
    }
  }

  String _displayAssignmentRoleTr(String role) {
    final r = role.trim().toLowerCase();
    switch (r) {
      case 'futbolcu':
        return 'Futbolcu';
      case 'takım sorumlusu':
      case 'takim sorumlusu':
        return 'Takım Sorumlusu';
      case 'turnuva yöneticisi':
      case 'turnuva yoneticisi':
        return 'Turnuva Yöneticisi';
      default:
        return role.trim().isEmpty ? '-' : role.trim();
    }
  }

  Widget _buildLoggedInProfileBody(
    BuildContext context,
    AppSessionState state,
    AppSessionController session,
  ) {
    final cs = Theme.of(context).colorScheme;
    final imageUrl = (state.user?.userMetadata?['avatar_url']?.toString() ?? '')
        .trim();
    final heroHeight = MediaQuery.of(context).size.height / 3;
    final uid = state.user?.id;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: heroHeight,
          child: imageUrl.isNotEmpty
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: cs.primary.withValues(alpha: 0.22),
                    child: Icon(
                      Icons.person,
                      size: 84,
                      color: cs.primary,
                    ),
                  ),
                )
              : Container(
                  color: cs.primary.withValues(alpha: 0.22),
                  child: Icon(
                    Icons.person,
                    size: 84,
                    color: cs.primary,
                  ),
                ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: StreamBuilder<UserDoc?>(
                    stream: uid == null
                        ? const Stream<UserDoc?>.empty()
                        : _authService.watchUserDoc(uid),
                    builder: (context, snap) {
                      final u = snap.data;
                      final role = (u?.role ?? state.role).toString().trim();
                      final phone =
                          (u?.phone ?? state.phone).toString().trim();
                      final displayRole = _displayRoleTr(role);
                      final displayPhone = phone.isEmpty ? '-' : phone;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Profil Bilgileri',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 50,
                            child: FilledButton.tonalIcon(
                              onPressed: state.isLoading
                                  ? null
                                  : (state.isAdmin || phone.isNotEmpty)
                                      ? () => _openPlayerLicenseMenu(
                                            phone: phone,
                                            isAdmin: state.isAdmin,
                                          )
                                      : null,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              icon: const Icon(Icons.badge_outlined),
                              label: const Text(
                                'Futbolcu Lisans Yönetimi',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Rol: $displayRole',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Telefon: $displayPhone',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Takımlarım ve Görevlerim',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 10),
                          StreamBuilder<List<RosterAssignment>>(
                            stream: phone.isEmpty
                                ? const Stream<List<RosterAssignment>>.empty()
                                : _authService.watchRosterAssignmentsByPhone(phone),
                            builder: (context, rosterSnap) {
                              if (phone.isEmpty) {
                                return Text(
                                  '-',
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                );
                              }
                              if (!rosterSnap.hasData) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }
                              final rosters =
                                  rosterSnap.data ?? const <RosterAssignment>[];
                              if (rosters.isEmpty) {
                                return Text(
                                  '-',
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                );
                              }

                              return Column(
                                children: rosters.map((r) {
                                  final tournamentId = r.tournamentId.trim();
                                  final teamId = r.teamId.trim();
                                  final roleName = _displayAssignmentRoleTr(
                                    r.role,
                                  );

                                  Widget card({
                                    required String tournamentName,
                                    required String teamName,
                                  }) {
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              tournamentName.isEmpty ? '-' : tournamentName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              teamName.isEmpty ? '-' : teamName,
                                              style: TextStyle(
                                                color: cs.onSurfaceVariant,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              roleName,
                                              style: TextStyle(
                                                color: cs.primary,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }

                                  Widget resolveTeam(String tournamentName) {
                                    if (teamId.isEmpty) {
                                      return card(
                                        tournamentName: tournamentName,
                                        teamName: '-',
                                      );
                                    }
                                    return StreamBuilder<String>(
                                      stream: _teamService.watchTeamName(teamId),
                                      builder: (context, teamSnap) {
                                        final teamName =
                                            (teamSnap.data ?? teamId).trim();
                                        return card(
                                          tournamentName: tournamentName,
                                          teamName: teamName,
                                        );
                                      },
                                    );
                                  }

                                  if (tournamentId.isEmpty) {
                                    return resolveTeam('-');
                                  }
                                  return StreamBuilder<String>(
                                    stream: _leagueService.watchLeagueName(tournamentId),
                                    builder: (context, tSnap) {
                                      final tName =
                                          (tSnap.data ?? tournamentId).trim();
                                      return resolveTeam(tName);
                                    },
                                  );
                                }).toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 50,
                            child: FilledButton.tonalIcon(
                              onPressed: state.isLoading ? null : () => _logout(session),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                                backgroundColor: const Color(0xFFFFEBEE),
                                foregroundColor: const Color(0xFFC62828),
                              ),
                              icon: const Icon(Icons.logout_rounded),
                              label: const Text(
                                'Çıkış Yap',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final session = AppSession.of(context);

    return ValueListenableBuilder<AppSessionState>(
      valueListenable: session,
      builder: (context, state, _) {
        final user = state.user;
        final isAdminPanelVisible = user != null && !state.isLoading && state.isAdmin;

        return PopScope(
          canPop: !isAdminPanelVisible,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (isAdminPanelVisible) {
              widget.onRequestHomeTab();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              centerTitle: true,
              title: GestureDetector(
                onTap: _isLoading ? null : () => _handleBackdoorTap(session),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.person_outline),
                    SizedBox(width: 8),
                    Text('Profil'),
                  ],
                ),
              ),
            ),
            body: isAdminPanelVisible
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: SizedBox(
                          height: 50,
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: state.isLoading
                                ? null
                                : () => _openPlayerLicenseMenu(
                                      phone: state.phone,
                                      isAdmin: state.isAdmin,
                                    ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                            ),
                            icon: const Icon(Icons.badge_outlined),
                            label: const Text(
                              'Futbolcu Lisans Yönetimi',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: AdminPanelWidget(
                          onLogout: () => _logout(session),
                        ),
                      ),
                    ],
                  )
                : (user != null
                    ? _buildLoggedInProfileBody(context, state, session)
                    : Transform.translate(
                        offset: const Offset(0, -20),
                        child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F172A),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      padding: const EdgeInsets.only(top: 20),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                            children: [
                              Theme(
                                data: Theme.of(context).copyWith(
                                  inputDecorationTheme:
                                      Theme.of(context).inputDecorationTheme.copyWith(
                                            labelStyle: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                            ),
                                            hintStyle: const TextStyle(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            prefixStyle: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                  textTheme: Theme.of(context)
                                      .textTheme
                                      .apply(bodyColor: Colors.white),
                                ),
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color:
                                                  cs.primary.withValues(alpha: 0.10),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: cs.outlineVariant
                                                    .withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: Icon(
                                              user == null
                                                  ? Icons.login_outlined
                                                  : Icons.person_outline,
                                              color: cs.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              user == null
                                                  ? 'Giriş'
                                                  : 'Profil Bilgileri',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      if (user == null) ...[
                                        TextField(
                                          controller: _phoneController,
                                          textInputAction: TextInputAction.next,
                                          keyboardType: TextInputType.phone,
                                          inputFormatters: [
                                            _PhoneMaskFormatter(),
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: 'Telefon Numarası',
                                            prefixText: '0 ',
                                            prefixIcon: Icon(Icons.phone_outlined),
                                            hintText: '(5XX) XXX XX XX',
                                          ),
                                          enabled: !_isLoading,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _passwordController,
                                          obscureText: true,
                                          onSubmitted: _isLoading
                                              ? null
                                              : (_) => _login(session),
                                          decoration: const InputDecoration(
                                            labelText: 'Şifre',
                                            prefixIcon: Icon(Icons.lock_outline),
                                          ),
                                          enabled: !_isLoading,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Checkbox(
                                                  value: _rememberMe,
                                                  onChanged: _isLoading
                                                      ? null
                                                      : (v) => setState(
                                                            () => _rememberMe =
                                                                v ?? false,
                                                          ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Beni Hatırla',
                                                  style: TextStyle(
                                                    color: cs.onSurfaceVariant,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            TextButton(
                                              onPressed: _isLoading
                                                  ? null
                                                  : () {
                                                      Navigator.of(context).push(
                                                        MaterialPageRoute<void>(
                                                          builder: (_) =>
                                                              const ForgotPasswordScreen(),
                                                        ),
                                                      );
                                                    },
                                              child: Text(
                                                'Şifremi Unuttum',
                                                style: TextStyle(
                                                  color: cs.primary,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          height: 50,
                                          child: _isLoading
                                              ? const Center(
                                                  child: SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  ),
                                                )
                                              : FilledButton(
                                                  onPressed: () => _login(session),
                                                  child: const Text(
                                                    'Giriş Yap',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                        const SizedBox(height: 12),
                                        Center(
                                          child: TextButton(
                                          onPressed: _isLoading
                                              ? null
                                              : () {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) =>
                                                          const OnlineRegistrationScreen(),
                                                    ),
                                                  );
                                                },
                                          child: Text(
                                            'Online Kayıt Formu',
                                            style: TextStyle(
                                              color: cs.primary,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          ),
                                        ),
                                      ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )),
          ),
        );
      },
    );
  }
}

class _PhoneMaskFormatter extends TextInputFormatter {
  static String _formatFromRaw10(String raw10) {
    final clipped = raw10.length > 10 ? raw10.substring(0, 10) : raw10;
    final a = clipped.length >= 3 ? clipped.substring(0, 3) : clipped;
    final b = clipped.length > 3
        ? clipped.substring(3, clipped.length >= 6 ? 6 : clipped.length)
        : '';
    final c = clipped.length > 6
        ? clipped.substring(6, clipped.length >= 8 ? 8 : clipped.length)
        : '';
    final d = clipped.length > 8 ? clipped.substring(8) : '';
    final sb = StringBuffer();
    if (a.isNotEmpty) {
      sb.write('(');
      sb.write(a);
      if (a.length == 3) sb.write(') ');
    }
    if (b.isNotEmpty) {
      sb.write(b);
      if (b.length == 3) sb.write(' ');
    }
    if (c.isNotEmpty) {
      sb.write(c);
      if (c.length == 2) sb.write(' ');
    }
    if (d.isNotEmpty) sb.write(d);
    return sb.toString().trimRight();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('90')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length > 10) digits = digits.substring(digits.length - 10);
    final formatted = _formatFromRaw10(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
