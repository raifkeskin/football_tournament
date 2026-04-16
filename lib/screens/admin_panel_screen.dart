import 'package:flutter/material.dart';
import 'admin_manage_leagues_screen.dart';
import 'admin_manage_news_screen.dart';
import 'admin_data_tools_screen.dart';
import 'admin_pending_actions_screen.dart';
import 'admin_pitch_management_screen.dart';

class AdminPanelWidget extends StatelessWidget {
  const AdminPanelWidget({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _PanelButonu(
          baslik: 'Turnuva Ayarları / Yönetimi',
          ikon: Icons.settings_outlined,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminManageLeaguesScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _PanelButonu(
          baslik: 'Haber Yönetimi',
          ikon: Icons.newspaper_outlined,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminManageNewsScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _PanelButonu(
          baslik: 'Saha Yönetimi',
          ikon: Icons.location_on_outlined,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminPitchManagementScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _PanelButonu(
          baslik: 'Veri Araçları',
          ikon: Icons.construction_outlined,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminDataToolsScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _PanelButonu(
          baslik: 'Bekleyen Onaylar',
          ikon: Icons.rule_folder_outlined,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminPendingActionsScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: onLogout,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            backgroundColor: const Color(0xFFFFEBEE),
            foregroundColor: const Color(0xFFC62828),
          ),
          icon: const Icon(Icons.logout_rounded),
          label: const Text(
            'Çıkış Yap',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _PanelButonu extends StatelessWidget {
  const _PanelButonu({
    required this.baslik,
    required this.ikon,
    required this.onPressed,
  });

  final String baslik;
  final IconData ikon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 56),
        elevation: 0,
        backgroundColor: cs.surfaceContainerLow,
        foregroundColor: cs.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      icon: Icon(ikon),
      label: Text(baslik, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
