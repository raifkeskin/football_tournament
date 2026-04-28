import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/season.dart';
import '../../team/models/team.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../team/screens/team_squad_screen.dart';

class SeasonManagementScreen extends StatelessWidget {
  const SeasonManagementScreen({
    super.key,
    required this.leagueId,
    required this.leagueName,
    required this.leagueLogoUrl,
  });

  final String leagueId;
  final String leagueName;
  final String leagueLogoUrl;

  SupabaseClient get _sb => Supabase.instance.client;

  Stream<List<Season>> _watchSeasons() {
    return _sb
        .from('seasons')
        .stream(primaryKey: ['id'])
        .eq('league_id', leagueId)
        .order('start_date', ascending: false)
        .map(
          (rows) => rows
              .cast<Map<String, dynamic>>()
              .map(Season.fromJson)
              .toList(),
        );
  }

  static String _fmt(DateTime? date) {
    if (date == null) return '-';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('$leagueName Sezonları'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const SizedBox(height: 12),
          StreamBuilder<List<Season>>(
            stream: _watchSeasons(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final seasons = snapshot.data ?? const <Season>[];
              if (seasons.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Sezon bulunamadı.')),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: seasons.length,
                itemBuilder: (context, index) {
                  final s = seasons[index];
                  final dateRange = '${_fmt(s.startDate)} - ${_fmt(s.endDate)}';
                  final location = [
                    if ((s.city ?? '').trim().isNotEmpty) s.city!.trim(),
                    s.country.trim(),
                  ].join(' • ');
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      leading: Icon(
                        Icons.calendar_month_outlined,
                        color: cs.onSurfaceVariant,
                      ),
                      title: Text(
                        s.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        location.trim().isEmpty ? dateRange : '$dateRange\n$location',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TeamListScreen(
                              seasonId: s.id,
                              seasonName: s.name,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class TeamListScreen extends StatelessWidget {
  TeamListScreen({
    super.key,
    required this.seasonId,
    required this.seasonName,
  });

  final String seasonId;
  final String seasonName;
  final ITeamService _teamService = ServiceLocator.teamService;

  Stream<List<Team>> _watchTeams() {
    final sid = seasonId.trim();
    if (sid.isEmpty) return Stream.value(const <Team>[]);
    return _teamService.watchAllTeams(caller: 'TeamListScreen').map((all) {
      final filtered =
          all.where((t) => (t.seasonId ?? '').trim() == sid).toList();
      filtered.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(seasonName.trim().isEmpty ? 'Takımlar' : seasonName)),
      body: StreamBuilder<List<Team>>(
        stream: _watchTeams(),
        initialData: const <Team>[],
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }
          final teams = snapshot.data ?? const <Team>[];
          if (teams.isEmpty) {
            return const Center(child: Text('Takım bulunamadı.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: teams.length,
            itemBuilder: (context, index) {
              final t = teams[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  leading: t.logoUrl.trim().isNotEmpty
                      ? WebSafeImage(
                          url: t.logoUrl,
                          width: 36,
                          height: 36,
                          borderRadius: BorderRadius.circular(10),
                          fallbackIconSize: 18,
                        )
                      : Icon(
                          Icons.shield_outlined,
                          color: cs.onSurfaceVariant,
                        ),
                  title: Text(
                    t.name.trim().isEmpty ? t.id : t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TeamSquadScreen(
                          teamId: t.id,
                          tournamentId: seasonId,
                          teamName: t.name.trim().isEmpty ? t.id : t.name,
                          teamLogoUrl: t.logoUrl,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
