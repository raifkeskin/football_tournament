import 'dart:async';
import 'package:flutter/material.dart';
import 'package:football_tournament/screens/admin_panel_screen.dart';
import '../../home/screens/main_navigator.dart';
import '../../../core/services/app_session.dart';
import '../../auth/services/interfaces/i_auth_service.dart';
import '../../../core/services/service_locator.dart';
import '../../auth/screens/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onRequestHomeTab});

  final VoidCallback onRequestHomeTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final IAuthService _authService = ServiceLocator.authService;

  bool _isLoading = false;
  int _tapCount = 0;
  Timer? _tapTimer;

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  /// Admin paneli geçişi için başlığa tıklama mantığı (Backdoor)
  void _onProfileTitleTap(dynamic session) {
    if (session == null) return;
    final user = session.value.user;
    if (user == null && !session.value.isAdmin) return;

    _tapTimer?.cancel();
    _tapCount++;
    if (_tapCount >= 3) {
      _tapCount = 0;
      if (session.value.isAdmin) {
        // Zaten adminse direkt kapatabiliriz
        session.setAdmin(false);
      } else {
        // Admin değilse şifre soralım
        _showAdminPasswordDialog(session);
      }
    } else {
      _tapTimer = Timer(const Duration(seconds: 2), () => _tapCount = 0);
    }
  }

  /// Super Admin şifre popup'ı
  Future<void> _showAdminPasswordDialog(dynamic session) async {
    final controller = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yönetici Girişi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Lütfen devam etmek için yönetici şifresini girin.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Şifre',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
              onSubmitted: (_) {
                if (controller.text == 'masterclass') {
                  // Buraya kendi şifreni yazabilirsin
                  session.setAdmin(true);
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () {
              // Not: Şifreyi projenizdeki orijinal şifreyle değiştirmeyi unutmayın
              if (controller.text == 'masterclass') {
                session.setAdmin(true);
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Hatalı şifre!')));
              }
            },
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
  }

  /// Güvenli çıkış yapma fonksiyonu
  Future<void> _logout(dynamic session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Oturumunuzu kapatmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      await session.signOut();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dynamic session = AppSession.of(context);
    final sessionData = session.value;
    final user = sessionData.user;
    final isRealUser = user != null && !(user.isAnonymous ?? false);
    final isAdminPanelVisible = sessionData.isAdmin;
    final isSuperAdminMode = isAdminPanelVisible && !isRealUser;

    return StreamBuilder<dynamic>(
      stream: isSuperAdminMode ? const Stream.empty() : (_authService as dynamic).watchUserDoc(user?.id ?? ''),
      builder: (context, snapshot) {
        final dynamic doc = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        
        final state = doc == null
            ? ProfileState(
                phone: sessionData.phone,
                role: sessionData.role,
                isAdmin: sessionData.isAdmin,
                isLoading: isLoading,
              )
            : ProfileState(
                displayName: doc.displayName,
                phone: doc.phone ?? sessionData.phone,
                role: doc.role ?? sessionData.role,
                isAdmin: doc.isAdmin ?? sessionData.isAdmin,
                isLoading: false,
              );

        final showAppBar = isRealUser || isAdminPanelVisible;

        return PopScope(
          canPop: !isAdminPanelVisible,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (isAdminPanelVisible) {
              widget.onRequestHomeTab();
            }
          },
          child: Scaffold(
            appBar: !showAppBar ? null : AppBar(
              centerTitle: true,
              leading: isAdminPanelVisible
                  ? IconButton(
                      icon: const Icon(Icons.home_rounded),
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const MainNavigator(initialTabIndex: 0),
                          ),
                          (route) => false,
                        );
                      },
                    )
                  : null,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isAdminPanelVisible
                        ? Icons.admin_panel_settings_outlined
                        : Icons.person_outline,
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isLoading
                        ? null
                        : () => _onProfileTitleTap(session),
                    child: Text(isAdminPanelVisible ? 'Admin Panel' : 'Profil'),
                  ),
                ],
              ),
            ),
            body: isAdminPanelVisible
                ? Column(
                    children: [
                      Expanded(
                        child: AdminPanelWidget(
                          onLogout: () => _logout(session),
                        ),
                      ),
                    ],
                  )
                : (isRealUser
                      ? _buildLoggedInProfileBody(context, state, session)
                      : const LoginScreen()),
          ),
        );
      },
    );
  }

  Widget _buildLoggedInProfileBody(
    BuildContext context,
    ProfileState state,
    dynamic session,
  ) {
    final cs = Theme.of(context).colorScheme;
    final phone = state.phone ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  context,
                  'İsim Soyisim',
                  state.displayName ?? (state.isLoading ? 'Yükleniyor...' : 'Belirtilmemiş'),
                  Icons.badge_outlined,
                ),
                const Divider(height: 24),
                _buildInfoRow(
                  context,
                  'Telefon',
                  phone.isEmpty ? 'Girilmemiş' : phone,
                  Icons.phone_android_outlined,
                ),
                const Divider(height: 24),
                _buildInfoRow(
                  context,
                  'Rol',
                  state.isAdmin
                      ? 'Sistem Yöneticisi'
                      : (state.role == 'manager'
                            ? 'Takım Sorumlusu'
                            : 'Oyuncu'),
                  Icons.workspace_premium_outlined,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : () => _logout(session),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text(
              'ÇIKIŞ YAP',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary.withValues(alpha: 0.7)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}

/// Profil durumunu temsil eden model sınıfı.
class ProfileState {
  final String? displayName;
  final String? phone;
  final String? role;
  final bool isAdmin;
  final bool isLoading;

  const ProfileState({
    this.displayName,
    this.phone,
    this.role,
    this.isAdmin = false,
    this.isLoading = false,
  });

  ProfileState copyWith({
    String? displayName,
    String? phone,
    String? role,
    bool? isAdmin,
    bool? isLoading,
  }) {
    return ProfileState(
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      isAdmin: isAdmin ?? this.isAdmin,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
