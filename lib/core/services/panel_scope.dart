import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session.dart';

/// Yönetim panelinde kullanıcının kapsamı: kurucu başkan kendi turnuvalarının,
/// bölge sorumlusu kendi bölgelerinin takımlarını ve oyuncularını görür.
/// Pasif (ya da silinmiş) turnuvalar kapsama girmez; yalnız pasif
/// turnuvalarda yer alan takım ve oyuncular admin dahil kimseye listelenmez.
/// Yetkinin asıl kontrolü veritabanındadır (RLS); bu süzme yalnızca
/// listeleri sadeleştirir.
class PanelScope {
  PanelScope._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Sezon etkin mi: silinmemiş ve turnuvası pasif değil.
  static bool _activeSeason(Map? season) {
    if (season == null || season['deleted_at'] != null) return false;
    final league = season['leagues'] as Map?;
    if (league == null) return false;
    return league['status']?.toString() != 'passive' &&
        league['is_active'] != false;
  }

  static const _seasonCols =
      'seasons(league_id, deleted_at, '
      'leagues(status, is_active))';

  /// Listede gösterilecek takımlar. Admin: null (hepsi; yalnız pasif
  /// turnuvalardakiler [hiddenTeamIds] ile ayrıca çıkarılır).
  static Future<Set<String>?> teamIds(AppSessionState s) async {
    if (s.isAdmin) return null;
    final regions = {for (final r in s.ownedRegions) r.id};
    final rows = await _sb
        .from('season_teams')
        .select('team_id, group_id, groups(region_id), $_seasonCols');
    return {
      for (final r in rows)
        // Silinen (gizlenen) grup okunamaz: o gruptaki kayıt sayılmaz.
        if (r['group_id'] == null || r['groups'] != null)
          if (_activeSeason(r['seasons'] as Map?))
            if (s.ownedLeagueIds.contains(
                  ((r['seasons'] as Map?)?['league_id'] ?? '').toString(),
                ) ||
                regions.contains(
                  ((r['groups'] as Map?)?['region_id'] ?? '').toString(),
                ))
              (r['team_id'] ?? '').toString(),
    };
  }

  /// Yalnız pasif / silinmiş turnuvalarda yer alan takım ve oyuncular
  /// (hiç sezonu / kadrosu olmayanlar gizlenmez). Sunucuda hesaplanır.
  static Future<({Set<String> teams, Set<String> players})> _hidden() async {
    final r = await _sb.rpc('panel_hidden_ids');
    Set<String> ids(Object? v) => {
      for (final e in (v is List ? v : const [])) e.toString(),
    };
    final m = r is Map ? r : const {};
    return (teams: ids(m['teams']), players: ids(m['players']));
  }

  static Future<Set<String>> hiddenTeamIds() async => (await _hidden()).teams;

  static Future<Set<String>> hiddenPlayerIds() async =>
      (await _hidden()).players;

  /// Listede gösterilecek oyuncular: yönetebildiği takımların etkin
  /// sezon kadrolarındakiler. Admin: null.
  static Future<Set<String>?> playerIds(AppSessionState s) async {
    final teams = await teamIds(s);
    if (teams == null) return null;
    if (teams.isEmpty) return <String>{};
    final r = await _sb.rpc(
      'panel_players_of_teams',
      params: {'p_team_ids': teams.toList()},
    );
    return {for (final e in (r is List ? r : const [])) e.toString()};
  }
}
