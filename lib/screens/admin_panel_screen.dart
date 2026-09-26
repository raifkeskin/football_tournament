import 'package:flutter/material.dart';
import 'package:football_tournament/features/team/screens/admin_manage_teams_screen.dart';
import 'package:football_tournament/features/team/screens/team_squad_screen.dart';
import 'package:football_tournament/features/tournament/screens/admin_manage_leagues_screen.dart';
import 'package:football_tournament/features/tournament/screens/admin_pitch_management_screen.dart';
import '../features/match/screens/admin_fixture_entry_screen.dart';
import '../features/news/screens/admin_manage_news_screen.dart';
import '../features/tournament/screens/admin_penalty_management_screen.dart';
import 'admin_pending_actions_screen.dart';
import '../features/auth/screens/admin_otp_monitor_screen.dart';

class AdminPanelWidget extends StatelessWidget {
  const AdminPanelWidget({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    // Mevcut buton verilerini modern yapıya uygun şekilde listeliyoruz
    // admin_panel_screen.dart içindeki menü listeni buna göre güncelle:
    final List<_AdminMenuData> menuItems = [
      _AdminMenuData(
        baslik: 'Turnuva Yönetimi',
        ikon: Icons.emoji_events_rounded,
        resimYolu: 'assets/images/admin_tournament.jpg',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminManageLeaguesScreen()),
          );
        },
      ),
      _AdminMenuData(
        baslik: 'Futbolcu Lisans',
        ikon: Icons.assignment_ind_rounded,
        resimYolu: 'assets/images/admin_license.jpg',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FootballerLicenseScreen()),
          );
        },
      ),
      _AdminMenuData(
        baslik: 'Fikstür Planlama',
        ikon: Icons.calendar_month_rounded,
        resimYolu: 'assets/images/admin_fixture.jpg',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminFixtureEntryScreen()),
          );
        },
      ),
      _AdminMenuData(
        baslik: 'Ceza Yönetimi',
        ikon: Icons.gavel_rounded,
        resimYolu: 'assets/images/admin_penalty.jpg',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminPenaltyManagementScreen()),
          );
        },
      ),
      _AdminMenuData(
        baslik: 'Takım Yönetimi',
        ikon: Icons.shield_rounded,
        resimYolu: 'assets/images/admin_team.jpg',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminManageTeamsScreen()),
          );
        },
      ),
      _AdminMenuData(
        baslik: 'Haber Yönetimi',
        ikon: Icons.newspaper_rounded,
        resimYolu: 'assets/admin/news_bg.jpg',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminManageNewsScreen()),
          );
        },
      ),
      _AdminMenuData(
        baslik: 'Saha Yönetimi',
        ikon: Icons.stadium_rounded,
        resimYolu: 'assets/admin/pitch_bg.jpg',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminPitchManagementScreen()),
          );
        },
      ),
    ];

    return CustomScrollView(
      slivers: [
        // Grid Menü
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => Padding(
                padding: const EdgeInsets.only(
                  bottom: 10.0,
                ), // Kartlar arası boşluk 12'den 10'a düştü
                child: SizedBox(
                  height: 80, // KİLİT NOKTA: Yükseklik 100'den 80'e düşürüldü
                  child: _ModernImageMenuCard(data: menuItems[index]),
                ),
              ),
              childCount: menuItems.length,
            ),
          ),
        ),

        // Diğer araçlar (Liste şeklinde devam edebilir)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _buildSmallActionTile(
                  context,
                  'OTP Takip',
                  Icons.sms_outlined,
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AdminOtpMonitorScreen()),
                  ),
                ),
                const SizedBox(height: 8),
                _buildSmallActionTile(
                  context,
                  'Bekleyen Onaylar',
                  Icons.rule_folder_outlined,
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AdminPendingActionsScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Çıkış Butonu
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.tonalIcon(
                    onPressed: onLogout,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFEBEE),
                      foregroundColor: const Color(0xFFC62828),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text(
                      'Çıkış Yap',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSmallActionTile(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      tileColor: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

class _AdminMenuData {
  final String baslik;
  final IconData ikon;
  final String resimYolu;
  final VoidCallback onPressed;

  _AdminMenuData({
    required this.baslik,
    required this.ikon,
    required this.resimYolu,
    required this.onPressed,
  });
}

class _ModernImageMenuCard extends StatelessWidget {
  final _AdminMenuData data;
  const _ModernImageMenuCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16), // Daha zarif bir kavis
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4)),
        ],
        image: DecorationImage(
          image: AssetImage(data.resimYolu),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(
              0.75,
            ), // Resmi biraz daha karartarak yazıyı patlattık
            BlendMode.darken,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: data.onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ), // Padding ufaldı
            child: Row(
              children: [
                // Sol taraftaki şeffaf arka planlı ikon kutusu
                Container(
                  padding: const EdgeInsets.all(10), // Padding ufaldı
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Icon(
                    data.ikon,
                    color: Colors.white,
                    size: 22,
                  ), // İkon 28'den 22'ye düştü
                ),
                const SizedBox(width: 14),
                // Orta alan: Menü Başlığı
                Expanded(
                  child: Text(
                    data.baslik,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16, // Font 18'den 16'ya düştü
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                // Sağ alan: Ok İkonu
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white70,
                    size: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Modern koyu arka plan
      appBar: AppBar(
        title: const Text('Admin Panel'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AdminPanelWidget(
        onLogout: () {
          () async {
            await onLogout();
            if (!context.mounted) return;
            Navigator.of(context).pop();
          }();
        },
      ),
    );
  }
}
