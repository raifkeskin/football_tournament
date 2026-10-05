import 'package:flutter/material.dart';
import 'package:football_tournament/core/services/app_session.dart';
import 'package:football_tournament/core/services/app_settings.dart';
import 'package:football_tournament/core/services/active_tournament.dart';
import 'package:football_tournament/features/team/screens/admin_manage_teams_screen.dart';
import 'package:football_tournament/features/team/screens/team_squad_screen.dart';
import 'package:football_tournament/features/tournament/screens/admin_manage_leagues_screen.dart';
import 'package:football_tournament/features/tournament/screens/admin_pitch_management_screen.dart';
import '../features/match/screens/admin_fixture_entry_screen.dart';
import '../features/news/screens/admin_manage_news_screen.dart';
import '../features/tournament/screens/admin_penalty_management_screen.dart';
import 'admin_pending_actions_screen.dart';
import '../features/auth/screens/admin_otp_monitor_screen.dart';

/// Yönetim paneli. Admin tüm kartları görür; kurucu başkan ve bölge
/// sorumlusu yalnızca yetkili oldukları kartları (veriler ekranlarda kendi
/// turnuva/bölgeleriyle süzülür). [header] profil bilgi kartı içindir.
class AdminPanelWidget extends StatelessWidget {
  const AdminPanelWidget({super.key, this.header});

  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
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
            MaterialPageRoute(
              builder: (_) => const AdminPenaltyManagementScreen(),
            ),
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
      if (isAdmin)
        _AdminMenuData(
          baslik: 'Saha Yönetimi',
          ikon: Icons.stadium_rounded,
          resimYolu: 'assets/admin/pitch_bg.jpg',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminPitchManagementScreen(),
              ),
            );
          },
        ),
    ];

    return CustomScrollView(
      slivers: [
        if (header != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            sliver: SliverToBoxAdapter(child: header),
          ),
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
                  height: 68,
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
                if (isAdmin) ...[
                  _buildSmallActionTile(
                    context,
                    'Şifre Talepleri',
                    Icons.key_rounded,
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AdminOtpMonitorScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
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
                if (isAdmin) ...[
                  const SizedBox(height: 8),
                  const _PrivateLeaguesSwitch(),
                ],
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
      tileColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

/// Gizli turnuva özelliği: kapalıyken "Turnuva Kodu Gir" ve turnuva
/// formundaki "Gizli turnuva" alanı gizlenir, tüm turnuvalar herkese açılır.
class _PrivateLeaguesSwitch extends StatefulWidget {
  const _PrivateLeaguesSwitch();

  @override
  State<_PrivateLeaguesSwitch> createState() => _PrivateLeaguesSwitchState();
}

class _PrivateLeaguesSwitchState extends State<_PrivateLeaguesSwitch> {
  bool _saving = false;

  Future<void> _set(bool v) async {
    setState(() => _saving = true);
    try {
      await AppSettings.setPrivateLeaguesEnabled(v);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ayar kaydedilemedi: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.privateLeaguesEnabled,
      builder: (context, on, _) => SwitchListTile.adaptive(
        value: on,
        onChanged: _saving ? null : _set,
        secondary: Icon(
          on ? Icons.lock_outline_rounded : Icons.public_rounded,
          color: Colors.white70,
        ),
        title: const Text(
          'Gizli Turnuva Özelliği',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          on
              ? 'Açık · "Turnuva Kodu Gir" ve gizli turnuva seçimi görünür'
              : 'Kapalı · tüm turnuvalar herkese açık',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        activeTrackColor: const Color(0xFF10B981),
        tileColor: Colors.white.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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

/// Panel kartı: yeni tasarımın düz kartı (yüzey rengi, köşe 16); solda
/// turnuva vurgu renginde ikon kutusu. Arka plan fotoğrafı yok.
class _ModernImageMenuCard extends StatelessWidget {
  final _AdminMenuData data;
  const _ModernImageMenuCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final accent =
        ActiveTournament.theme.value?.secondary ?? const Color(0xFF10B981);
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: data.onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(data.ikon, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  data.baslik,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white38,
                size: 24,
              ),
            ],
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
        actions: [
          IconButton(
            tooltip: 'Çıkış Yap',
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFF87171)),
            onPressed: () async {
              await onLogout();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: const AdminPanelWidget(),
    );
  }
}
