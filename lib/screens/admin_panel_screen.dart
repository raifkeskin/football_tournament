import 'package:flutter/material.dart';
import 'package:football_tournament/core/services/app_session.dart';
import 'package:football_tournament/core/services/app_settings.dart';
import 'package:football_tournament/features/team/screens/admin_manage_teams_screen.dart';
import 'package:football_tournament/features/team/screens/team_squad_screen.dart';
import 'package:football_tournament/features/tournament/screens/admin_manage_leagues_screen.dart';
import 'package:football_tournament/features/tournament/screens/admin_pitch_management_screen.dart';
import '../features/match/screens/admin_fixture_entry_screen.dart';
import '../features/news/screens/admin_manage_news_screen.dart';
import '../features/sponsors/admin_sponsors_screen.dart';
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
    final session = AppSession.of(context).value;
    final isAdmin = session.isAdmin;
    // Mevcut buton verilerini modern yapıya uygun şekilde listeliyoruz
    // admin_panel_screen.dart içindeki menü listeni buna göre güncelle:
    final List<_AdminMenuData> menuItems = [
      _AdminMenuData(
        baslik: 'Turnuva Yönetimi',
        renkler: const [Color(0xFFFCD34D), Color(0xFFD97706)],
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
        renkler: const [Color(0xFF2DD4BF), Color(0xFF0D9488)],
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
        renkler: const [Color(0xFF818CF8), Color(0xFF4F46E5)],
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
        renkler: const [Color(0xFF60A5FA), Color(0xFF2563EB)],
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
        renkler: const [Color(0xFFF87171), Color(0xFFDC2626)],
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
        renkler: const [Color(0xFFFB7185), Color(0xFFE11D48)],
        ikon: Icons.newspaper_rounded,
        resimYolu: 'assets/admin/news_bg.jpg',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminManageNewsScreen()),
          );
        },
      ),
      // Sponsorlar: yalnızca admin ve kurucu başkan (bölge sorumlusu değil).
      if (isAdmin || session.isLeagueOwner)
        _AdminMenuData(
          baslik: 'Sponsor Yönetimi',
          renkler: const [Color(0xFFFDE68A), Color(0xFFCA8A04)],
          ikon: Icons.handshake_rounded,
          resimYolu: 'assets/images/admin_tournament.jpg',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminSponsorsScreen()),
            );
          },
        ),
      if (isAdmin)
        _AdminMenuData(
          baslik: 'Saha Yönetimi',
          renkler: const [Color(0xFF4ADE80), Color(0xFF16A34A)],
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
                  _SettingSwitch(
                    setting: AppSettings.privateLeaguesEnabled,
                    save: AppSettings.setPrivateLeaguesEnabled,
                    title: 'Gizli Turnuva Özelliği',
                    onIcon: Icons.lock_outline_rounded,
                    offIcon: Icons.public_rounded,
                    onText:
                        'Açık · "Turnuva Kodu Gir" ve gizli turnuva seçimi '
                        'görünür',
                    offText: 'Kapalı · tüm turnuvalar herkese açık',
                  ),
                  const SizedBox(height: 8),
                  _SettingSwitch(
                    setting: AppSettings.bottomNavEnabled,
                    save: AppSettings.setBottomNavEnabled,
                    title: 'Alt Menü',
                    onIcon: Icons.space_bar_rounded,
                    offIcon: Icons.menu_rounded,
                    onText: 'Açık · ana ekranlarda alt gezinme çubuğu görünür',
                    offText: 'Kapalı · gezinme yan menü ve kaydırma ile',
                  ),
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
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
          ),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
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

/// Uygulama geneli bir ayarın açma/kapama satırı (yalnızca admin).
class _SettingSwitch extends StatefulWidget {
  const _SettingSwitch({
    required this.setting,
    required this.save,
    required this.title,
    required this.onIcon,
    required this.offIcon,
    required this.onText,
    required this.offText,
  });

  final ValueNotifier<bool> setting;
  final Future<void> Function(bool) save;
  final String title;
  final IconData onIcon;
  final IconData offIcon;
  final String onText;
  final String offText;

  @override
  State<_SettingSwitch> createState() => _SettingSwitchState();
}

class _SettingSwitchState extends State<_SettingSwitch> {
  bool _saving = false;

  Future<void> _set(bool v) async {
    setState(() => _saving = true);
    try {
      await widget.save(v);
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
      valueListenable: widget.setting,
      builder: (context, on, _) => SwitchListTile.adaptive(
        value: on,
        onChanged: _saving ? null : _set,
        secondary: Icon(
          on ? widget.onIcon : widget.offIcon,
          color: Colors.white70,
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          on ? widget.onText : widget.offText,
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

  /// İkon kutusunun renk geçişi (yan menüdeki gibi her bölümün kendi rengi).
  final List<Color> renkler;
  final String resimYolu;
  final VoidCallback onPressed;

  _AdminMenuData({
    required this.baslik,
    required this.ikon,
    required this.renkler,
    required this.resimYolu,
    required this.onPressed,
  });
}

/// Panel kartı: yeni tasarımın düz kartı (yüzey rengi, köşe 16); solda
/// bölümün kendi renginde geçişli ikon kutusu. Arka plan fotoğrafı yok.
class _ModernImageMenuCard extends StatelessWidget {
  final _AdminMenuData data;
  const _ModernImageMenuCard({required this.data});

  @override
  Widget build(BuildContext context) {
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
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: data.renkler,
                  ),
                ),
                child: Icon(data.ikon, color: Colors.white, size: 22),
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
