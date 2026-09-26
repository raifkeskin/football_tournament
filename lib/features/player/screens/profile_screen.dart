import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Supabase kontrolü için
import '../../../core/config/app_config.dart'; // AppConfig için
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

  Future<void> _logout(dynamic session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Çıkış Yap', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Oturumunuzu kapatmak istediğinize emin misiniz?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Çıkış Yap',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
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

    // YENİ VE GÜVENLİ GİRİŞ KONTROLÜ
    // Önce User objesinin ID'sinin gerçekten var olup olmadığına bakıyoruz
    final String uid = user != null ? (user.id?.toString().trim() ?? '') : '';
    bool isRealUser =
        uid.isNotEmpty && uid != 'guest' && uid != 'anonymous' && uid != '0';

    // Eğer Supabase kullanılıyorsa, "Sahte Giriş" hatasını önlemek için kesin kontrolü oradan yapıyoruz
    if (AppConfig.activeDatabase == DatabaseType.supabase) {
      final su = Supabase.instance.client.auth.currentUser;
      if (su == null || (su.isAnonymous ?? false)) {
        isRealUser =
            false; // Supabase oturumu yoksa kesinlikle Login Ekranı çıkmalı
      } else {
        isRealUser = true;
      }
    }

    final isAdminPanelVisible = sessionData.isAdmin;
    final isSuperAdminMode = isAdminPanelVisible && !isRealUser;

    const bgDark = Color(0xFF0F172A);

    return StreamBuilder<dynamic>(
      stream: isSuperAdminMode
          ? const Stream.empty()
          : (_authService as dynamic).watchUserDoc(user?.id ?? ''),
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
            backgroundColor: bgDark,
            extendBodyBehindAppBar:
                true, // KİLİT NOKTA: Arka planı AppBar'ın altına iter
            appBar: !showAppBar
                ? null
                : AppBar(
                    centerTitle: true,
                    backgroundColor:
                        Colors.transparent, // Yeşil renk iptal, tamamen şeffaf
                    elevation: 0,
                    iconTheme: const IconThemeData(color: Colors.white),
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
                              ? Icons.admin_panel_settings_rounded
                              : Icons.person_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isAdminPanelVisible ? 'Admin Panel' : 'Profil',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
            body: Stack(
              // ... geri kalanı aynı
              children: [
                // Fikstür/Gruplar ekranlarındaki ortak top görselli arka plan
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.15,
                    child: Image.asset(
                      'assets/images/background_ball.jpg',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                ),
                SafeArea(
                  child: isAdminPanelVisible
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
                            : const LoginScreen()), // Doğrulanmamışsa şifre ekranını (LoginScreen) çağır
                ),
              ],
            ),
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
    final phone = state.phone ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withOpacity(0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 15,
                offset: Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow(
                'İsim Soyisim',
                state.displayName ??
                    (state.isLoading ? 'Yükleniyor...' : 'Belirtilmemiş'),
                Icons.badge_rounded,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Colors.white12, height: 1),
              ),
              _buildInfoRow(
                'Telefon',
                phone.isEmpty ? 'Girilmemiş' : phone,
                Icons.phone_iphone_rounded,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Colors.white12, height: 1),
              ),
              _buildInfoRow(
                'Rol',
                state.isAdmin
                    ? 'Sistem Yöneticisi'
                    : (state.role == 'manager' ? 'Takım Sorumlusu' : 'Oyuncu'),
                Icons.workspace_premium_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : () => _logout(session),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              backgroundColor: Colors.redAccent.withOpacity(0.08),
              side: BorderSide(
                color: Colors.redAccent.withOpacity(0.5),
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.logout_rounded, size: 22),
            label: const Text(
              'ÇIKIŞ YAP',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF064E3B).withOpacity(0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
          ),
          child: Icon(icon, size: 24, color: const Color(0xFF10B981)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white60,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 17,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
}
