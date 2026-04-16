import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_panel_screen.dart';
import 'forgot_password_screen.dart';
import 'online_registration_screen.dart';
import '../main.dart';
import 'main_navigator.dart';
import '../services/app_session.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onRequestHomeTab});

  final VoidCallback onRequestHomeTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;
  int _backdoorTapCount = 0;
  DateTime? _backdoorLastTapAt;
  Timer? _backdoorResetTimer;

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
    final imageUrl = (state.user?.photoURL ?? '').trim();
    final heroHeight = MediaQuery.of(context).size.height / 3;
    final uid = state.user?.uid;

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
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: uid == null
                        ? null
                        : FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .snapshots(),
                    builder: (context, snap) {
                      final data = snap.data?.data();
                      final role = (data?['accessRole'] ?? data?['role'] ?? state.role)
                          .toString()
                          .trim();
                      final phone =
                          (data?['phone'] ?? state.phone).toString().trim();
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
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: phone.isEmpty
                                ? null
                                : FirebaseFirestore.instance
                                    .collection('rosters')
                                    .where('playerPhone', isEqualTo: phone)
                                    .snapshots(),
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
                              final rosters = rosterSnap.data!.docs;
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
                                children: rosters.map((doc) {
                                  final r = doc.data();
                                  final tournamentId =
                                      (r['tournamentId'] ?? '').toString().trim();
                                  final teamId = (r['teamId'] ?? '').toString().trim();
                                  final roleName = _displayAssignmentRoleTr(
                                    (r['role'] ?? '').toString(),
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
                                    return StreamBuilder<
                                        DocumentSnapshot<Map<String, dynamic>>>(
                                      stream: FirebaseFirestore.instance
                                          .collection('teams')
                                          .doc(teamId)
                                          .snapshots(),
                                      builder: (context, teamSnap) {
                                        final teamName =
                                            (teamSnap.data?.data()?['name'] as String?)
                                                    ?.trim() ??
                                                teamId;
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
                                  return StreamBuilder<
                                      DocumentSnapshot<Map<String, dynamic>>>(
                                    stream: FirebaseFirestore.instance
                                        .collection('tournaments')
                                        .doc(tournamentId)
                                        .snapshots(),
                                    builder: (context, tSnap) {
                                      final tName =
                                          (tSnap.data?.data()?['name'] as String?)
                                                  ?.trim() ??
                                              tournamentId;
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
                ? AdminPanelWidget(onLogout: () => _logout(session))
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
