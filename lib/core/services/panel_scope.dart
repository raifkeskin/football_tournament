import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session.dart';

/// Yönetim panelinde kullanıcının kapsamı: kurucu başkan kendi turnuvalarının,
/// bölge sorumlusu kendi bölgelerinin takımlarını ve oyuncularını görür.
/// Pasif (ya da silinmiş) turnuvalar kapsama girmez; etkin kadroda
/// olmayanlar admin listesinde "Boşta" filtresiyle görünür.
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

/// Etkin sezonlardaki üyelikler (panel_memberships): filtreler için.
class PanelMemberships {
  PanelMemberships._(this.leagues, this.seasons, this.teams, this.players);

  /// league id → ad
  final Map<String, String> leagues;

  /// season id → (ad, league id)
  final Map<String, ({String name, String league})> seasons;

  /// team / player id → etkin sezon id'leri (yoksa boşta).
  final Map<String, Set<String>> teams;
  final Map<String, Set<String>> players;

  Set<String> leaguesOf(Set<String>? seasonIds) => {
    for (final s in seasonIds ?? const <String>{})
      if (seasons[s] != null) seasons[s]!.league,
  };

  static Future<PanelMemberships> load() async {
    final r = await Supabase.instance.client.rpc('panel_memberships');
    final m = r is Map ? r : const {};
    Map<String, Set<String>> sets(Object? v) => {
      if (v is Map)
        for (final e in v.entries)
          e.key.toString(): {
            for (final s in (e.value is List ? e.value as List : const []))
              s.toString(),
          },
    };
    final rawSeasons = m['seasons'];
    return PanelMemberships._(
      {
        if (m['leagues'] is Map)
          for (final e in (m['leagues'] as Map).entries)
            e.key.toString(): e.value.toString(),
      },
      {
        if (rawSeasons is Map)
          for (final e in rawSeasons.entries)
            e.key.toString(): (
              name: ((e.value as Map?)?['name'] ?? '').toString(),
              league: ((e.value as Map?)?['league'] ?? '').toString(),
            ),
      },
      sets(m['teams']),
      sets(m['players']),
    );
  }
}
