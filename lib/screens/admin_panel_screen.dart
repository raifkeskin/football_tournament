import 'package:flutter/material.dart';
import 'admin_add_league_screen.dart';
import 'admin_add_team_screen.dart';

/// Admin paneli — ilgili yönetim formlarına yönlendirir.
class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Admin Panel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PanelButonu(
            baslik: 'Turnuva Ekle',
            ikon: Icons.emoji_events_outlined,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminAddLeagueScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _PanelButonu(
            baslik: 'Takım Ekle',
            ikon: Icons.groups_2_outlined,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminAddTeamScreen(),
                ),
              );
            },
          ),
        ],
      ),
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
