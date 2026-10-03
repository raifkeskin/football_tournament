import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Supabase kontrolü için
import 'package:football_tournament/screens/admin_panel_screen.dart';
import '../../home/screens/main_navigator.dart';
import '../../../core/services/app_session.dart';
import '../../auth/screens/login_screen.dart';
import '../../../core/widgets/admin_page.dart';
import 'my_profile_view.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onRequestHomeTab});

  final VoidCallback onRequestHomeTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = false;

  Future<void> _logout(dynamic session) async {
    final confirmed = await showAdminConfirmDialog(
      context: context,
      title: 'Çıkış Yap',
      message: 'Oturumunuzu kapatmak istediğinize emin misiniz?',
      confirmLabel: 'ÇIKIŞ YAP',
      icon: Icons.logout_rounded,
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
    final su = Supabase.instance.client.auth.currentUser;
    if (su == null || (su.isAnonymous ?? false)) {
      isRealUser =
          false; // Supabase oturumu yoksa kesinlikle Login Ekranı çıkmalı
    } else {
      isRealUser = true;
    }

    final isAdminPanelVisible = sessionData.isAdmin;

    const bgDark = Color(0xFF0F172A);

    // Profil bilgisi oturumdan gelir (app_users + players üzerinden
    // AppSessionController tarafından yüklenir).
    return Builder(
      builder: (context) {
        final state = ProfileState(
          displayName: sessionData.displayName,
          phone: sessionData.phone,
          role: sessionData.role,
          isAdmin: sessionData.isAdmin,
          isLoading: sessionData.isLoading,
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
                    // Ana sayfa: admin için yeni gezinme yığını; diğer
                    // kullanıcılar için ana sekmeye geçiş (menü oradan açılır).
                    leading: IconButton(
                      icon: const Icon(Icons.home_rounded),
                      tooltip: 'Ana Sayfa',
                      onPressed: () {
                        if (!isAdminPanelVisible) {
                          widget.onRequestHomeTab();
                          return;
                        }
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const MainNavigator(initialTabIndex: 0),
                          ),
                          (route) => false,
                        );
                      },
                    ),
                    // Çıkış: başlığın sağında kırmızı ikon (admin paneli ve
                    // profil için ortak).
                    actions: [
                      IconButton(
                        tooltip: 'Çıkış Yap',
                        onPressed: _isLoading ? null : () => _logout(session),
                        icon: const Icon(
                          Icons.logout_rounded,
                          color: Color(0xFFF87171),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
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
                      ? Column(children: [Expanded(child: AdminPanelWidget())])
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

    final sessionValue = session.value as AppSessionState;
    // Futbolcu (ya da oyuncu kaydı olan herkes): kart, maçlar, talepler.
    // Oyuncu kaydı olmayan turnuva sahibi / takım sorumlusu: bilgi kartı.
    final isStaffOnly =
        sessionValue.playerId == null &&
        (state.role == 'owner' || state.role == 'manager');
    if (!isStaffOnly) {
      return MyProfileView(
        playerId: sessionValue.playerId,
        displayName: state.displayName,
        phone: phone,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                    : state.role == 'owner'
                    ? 'Turnuva Sahibi'
                    : (state.role == 'manager'
                          ? 'Takım Sorumlusu'
                          : 'Futbolcu'),
                Icons.workspace_premium_rounded,
              ),
            ],
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
            color: const Color(0xFF064E3B).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.3),
            ),
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
