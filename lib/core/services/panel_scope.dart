import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session.dart';

/// Yönetim panelinde kullanıcının kapsamı: kurucu başkan kendi turnuvalarının,
/// bölge sorumlusu kendi bölgelerinin takımlarını ve oyuncularını görür.
/// Admin için null (hepsi). Yetkinin asıl kontrolü veritabanındadır (RLS);
/// bu süzme yalnızca listeleri sadeleştirir.
class PanelScope {
  PanelScope._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Yönetebildiği takımlar (herhangi bir sezonda).
  static Future<Set<String>?> teamIds(AppSessionState s) async {
    if (s.isAdmin) return null;
    final regions = {for (final r in s.ownedRegions) r.id};
    final rows = await _sb
        .from('season_teams')
        .select('team_id, groups(region_id), seasons(league_id)');
    return {
      for (final r in rows)
        if (s.ownedLeagueIds.contains(
              ((r['seasons'] as Map?)?['league_id'] ?? '').toString(),
            ) ||
            regions.contains(
              ((r['groups'] as Map?)?['region_id'] ?? '').toString(),
            ))
          (r['team_id'] ?? '').toString(),
    };
  }

  /// Yönetebildiği takımların kadrolarındaki oyuncular.
  static Future<Set<String>?> playerIds(AppSessionState s) async {
    final teams = await teamIds(s);
    if (teams == null) return null;
    if (teams.isEmpty) return <String>{};
    final rows = await _sb
        .from('season_team_players')
        .select('player_id')
        .inFilter('team_id', teams.toList());
    return {for (final r in rows) (r['player_id'] ?? '').toString()};
  }
}
