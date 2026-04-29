import 'package:flutter/material.dart';

import 'admin_group_management_screen.dart';
import 'admin_manage_leagues_screen.dart';
import '../../team/screens/admin_manage_teams_screen.dart';
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
    final cs = Theme.of(context).colorScheme;
    final ILeagueService leagueService = ServiceLocator.leagueService;

    ButtonStyle buttonStyle({
      Color? backgroundColor,
      Color? foregroundColor,
    }) {
      return FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 56),
        backgroundColor: backgroundColor ?? cs.surfaceContainerLow,
        foregroundColor: foregroundColor ?? cs.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Turnuva Yönetimi'),
        centerTitle: true,
      ),
      body: StreamBuilder<String>(
        stream: leagueService.watchLeagueName(tournamentId),
        builder: (context, snap) {
          final name = (snap.data ?? tournamentId).trim();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminManageLeaguesScreen(),
                    ),
                  );
                },
                style: buttonStyle(),
                icon: const Icon(Icons.settings_outlined),
                label: const Text(
                  'Turnuva Yönetimi',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AdminManageTeamsScreen(
                        initialLeagueId: tournamentId,
                        lockLeagueSelection: true,
                      ),
                    ),
                  );
                },
                style: buttonStyle(),
                icon: const Icon(Icons.shield_outlined),
                label: const Text(
                  'Takım Yönetimi',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AdminGroupManagementScreen(
                        initialLeagueId: tournamentId,
                        lockLeagueSelection: true,
                      ),
                    ),
                  );
                },
                style: buttonStyle(),
                icon: const Icon(Icons.groups_outlined),
                label: const Text(
                  'Grup Yönetimi',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
