import 'package:flutter/material.dart';
import 'admin_group_management_screen.dart';
import 'package:football_tournament/features/tournament/screens/admin_manage_leagues_screen.dart';
import '../../team/screens/admin_manage_teams_screen.dart';
import '../../team/screens/team_squad_screen.dart';
import '../services/interfaces/i_league_service.dart';
import '../../../core/services/service_locator.dart';

class TournamentAdminDashboardScreen extends StatelessWidget {
  const TournamentAdminDashboardScreen({
    super.key,
    required this.tournamentId,
  });

  final String tournamentId;

  @override
  Widget build(BuildContext context) {
    final ILeagueService leagueService = ServiceLocator.leagueService;

    return Scaffold(
      // Arka planı tamamen Dashboard lacivertine çektik
      backgroundColor: const Color(0xFF0F172A),
      body: StreamBuilder<String>(
        stream: leagueService.watchLeagueName(tournamentId),
        builder: (context, snap) {
          final name = (snap.data ?? tournamentId).trim();
          
          return CustomScrollView(
            slivers: [
              // MODERN HEADER: Yeşil bar yerine kupa görseli ve lacivert tonları
              SliverAppBar(
                expandedHeight: 200.0,
                pinned: true,
                stretch: true,
                backgroundColor: const Color(0xFF0F172A),
                leading: const BackButton(color: Colors.white),
                actions: [
                  // İstediğin Kalın ve Beyaz "+" Butonu
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: IconButton(
                      icon: const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 32,
                        weight: 900,
                      ),
                      onPressed: () {
                        // Yeni işlem/sezon ekleme fonksiyonu buraya
                      },
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: true,
                  title: Text(
                    name, // Dinamik gelen turnuva ismi
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: -0.5,
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Butondaki görselin aynısı (Tasarım Devamlılığı)
                      Image.asset(
                        'assets/admin/tournament_bg.jpg',
                        fit: BoxFit.cover,
                      ),
                      // Derin lacivert gradyan
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.2),
                              const Color(0xFF0F172A).withOpacity(0.8),
                              const Color(0xFF0F172A),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // YÖNETİM BUTONLARI (Kart Yapısı)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildModernMenuTile(
                      context,
                      title: 'Turnuva Ayarları',
                      subtitle: 'Genel yapılandırma ve lig işlemleri',
                      icon: Icons.settings_outlined,
                      onTap: () => Navigator.of(context).push(
                        // HATA BURADAYDI: const kelimesi tamamen kaldırıldı!
                        MaterialPageRoute(builder: (_) => AdminManageLeaguesScreen()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildModernMenuTile(
                      context,
                      title: 'Futbolcu Lisans Yönetimi',
                      subtitle: 'Oyuncu kayıt ve onay işlemleri',
                      icon: Icons.badge_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FootballerLicenseScreen()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildModernMenuTile(
                      context,
                      title: 'Takım Yönetimi',
                      subtitle: 'Kadrolar ve takım bilgileri',
                      icon: Icons.shield_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => AdminManageTeamsScreen(
                          initialLeagueId: tournamentId,
                          lockLeagueSelection: true,
                        )),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildModernMenuTile(
                      context,
                      title: 'Grup Yönetimi',
                      subtitle: 'Puan durumu ve grup eşleşmeleri',
                      icon: Icons.groups_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => AdminGroupManagementScreen(
                          initialLeagueId: tournamentId,
                          lockLeagueSelection: true,
                        )),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildModernMenuTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      ),
    );
  }
}