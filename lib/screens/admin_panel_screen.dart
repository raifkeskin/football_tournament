import 'package:flutter/material.dart';
import 'package:football_tournament/features/team/screens/admin_manage_teams_screen.dart';
import 'package:football_tournament/features/team/screens/team_squad_screen.dart';
import 'package:football_tournament/features/tournament/screens/admin_manage_leagues_screen.dart';
import '../features/match/screens/admin_fixture_entry_screen.dart';
import '../features/news/screens/admin_manage_news_screen.dart';
import 'admin_data_tools_screen.dart';
import 'admin_pending_actions_screen.dart';
import '../features/tournament/screens/admin_penalty_management_screen.dart';
import 'package:football_tournament/features/tournament/screens/admin_pitch_management_screen.dart';
import '../features/auth/screens/admin_otp_monitor_screen.dart';

class AdminPanelWidget extends StatelessWidget {
  const AdminPanelWidget({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    // Mevcut buton verilerini modern yapıya uygun şekilde listeliyoruz
    final menuItems = [
      _AdminMenuData(
        baslik: 'Turnuva Yönetimi',
        ikon: Icons.emoji_events_outlined,
        resimYolu: 'assets/admin/tournament_bg.jpg',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminManageLeaguesScreen())),
      ),
      _AdminMenuData(
        baslik: 'Futbolcu Lisans', // İsim kısaltıldı (UI uyumu için)
        ikon: Icons.badge_outlined,
        resimYolu: 'assets/admin/news_bg.jpg', // Uygun bir görselle değiştirilebilir
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FootballerLicenseScreen())),
      ),
      _AdminMenuData(
        baslik: 'Fikstür Planlama',
        ikon: Icons.calendar_month_outlined,
        resimYolu: 'assets/admin/fixture_bg.jpg',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminFixtureEntryScreen())),
      ),
      _AdminMenuData(
        baslik: 'Ceza Yönetimi',
        ikon: Icons.gavel_outlined,
        resimYolu: 'assets/admin/penalty_bg.jpg',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPenaltyManagementScreen())),
      ),
      _AdminMenuData(
        baslik: 'Takım Yönetimi',
        ikon: Icons.shield_outlined, // İkon kalkan olarak güncellendi
        resimYolu: 'assets/admin/teams_bg.jpg',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminManageTeamsScreen())),
      ),
      _AdminMenuData(
        baslik: 'Haber Yönetimi',
        ikon: Icons.newspaper_outlined,
        resimYolu: 'assets/admin/news_bg.jpg',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminManageNewsScreen())),
      ),
      _AdminMenuData(
        baslik: 'Saha Yönetimi',
        ikon: Icons.location_on_outlined,
        resimYolu: 'assets/admin/pitch_bg.jpg',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPitchManagementScreen())),
      ),
      _AdminMenuData(
        baslik: 'Veri Araçları',
        ikon: Icons.construction_outlined,
        resimYolu: 'assets/admin/penalty_bg.jpg', // Mevcut görsellerden biri atandı
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminDataToolsScreen())),
      ),
    ];

    return CustomScrollView(
      slivers: [
        // Grid Menü
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _ModernImageMenuCard(data: menuItems[index]),
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
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminOtpMonitorScreen())),
                ),
                const SizedBox(height: 8),
                _buildSmallActionTile(
                  context,
                  'Bekleyen Onaylar',
                  Icons.rule_folder_outlined,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPendingActionsScreen())),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Çıkış Yap', style: TextStyle(fontWeight: FontWeight.w900)),
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

  Widget _buildSmallActionTile(BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
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
        borderRadius: BorderRadius.circular(20),
        image: DecorationImage(
          image: AssetImage(data.resimYolu),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.6), // Görseli karartarak yazıyı ön plana çıkarır
            BlendMode.darken,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: data.onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(data.ikon, color: Colors.white, size: 24),
                ),
                Text(
                  data.baslik,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: -0.5,
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