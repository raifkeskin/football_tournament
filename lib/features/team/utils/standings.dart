import '../models/team.dart';

/// Puan tablosunda bir takımın satırı.
class StandingEntry {
  StandingEntry({required this.teamId, required this.name, required this.logo});

  final String teamId;
  final String name;
  final String logo;
  int played = 0;
  int won = 0;
  int drawn = 0;
  int lost = 0;
  int goalsFor = 0;
  int goalsAgainst = 0;
  int points = 0;

  int get goalDiff => goalsFor - goalsAgainst;
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? 0;
}

int _score(Map<String, dynamic> m, String side) {
  final score = m['score'] ?? m['score_json'] ?? m['scoreJson'];
  if (score is Map) {
    final fullTime = score['fullTime'];
    if (fullTime is Map && fullTime[side] != null) {
      return _asInt(fullTime[side]);
    }
  }
  return side == 'home'
      ? _asInt(m['homeScore'] ?? m['home_score'])
      : _asInt(m['awayScore'] ?? m['away_score']);
}

String _homeId(Map<String, dynamic> m) =>
    (m['home_team_id'] ?? m['homeTeamId'] ?? '').toString().trim();
String _awayId(Map<String, dynamic> m) =>
    (m['away_team_id'] ?? m['awayTeamId'] ?? '').toString().trim();

bool _isCompleted(Map<String, dynamic> m) {
  final status = (m['status'] ?? '').toString().trim().toLowerCase();
  return m['is_completed'] == true ||
      m['isCompleted'] == true ||
      status == 'finished' ||
      status == 'completed';
}

/// Bir grubun puan tablosu (ekran ve paylaşım afişi aynı hesabı kullanır).
///
/// Takımlar: grupta maçı olanlar ve gruba atanmış olanlar. Sıralama: puan,
/// ikili averaj (puan, gol farkı), genel averaj, atılan gol, ad.
List<StandingEntry> computeGroupStandings({
  required String leagueId,
  required String groupId,
  required String groupName,
  required List<Map<String, dynamic>> seasonMatches,
  required List<Team> allTeams,
}) {
  final groupMatches = seasonMatches.where((m) {
    final g = (m['group_id'] ?? m['groupId'] ?? m['groupName'] ?? '')
        .toString()
        .trim();
    if (g.isEmpty) return false;
    return g == groupId || g == groupName.trim();
  }).toList();

  final playedIds = <String>{
    for (final m in groupMatches) ...[_homeId(m), _awayId(m)],
  }..remove('');

  final table = <String, StandingEntry>{
    for (final t in allTeams)
      // Fikstürü henüz çekilmemiş grupta da gruba atanmış takımlar 0
      // puanla listelenir (grup kimliği benzersiz; sezon/turnuva ayrıca
      // karşılaştırılmaz).
      if (playedIds.contains(t.id) ||
          (groupId.trim().isNotEmpty &&
              (t.groupId ?? '').toString().trim() == groupId.trim()))
        t.id: StandingEntry(teamId: t.id, name: t.name, logo: t.logoUrl),
  };

  for (final m in groupMatches) {
    final h = table[_homeId(m)];
    final a = table[_awayId(m)];
    if (!_isCompleted(m) || h == null || a == null) continue;
    final hs = _score(m, 'home');
    final as = _score(m, 'away');
    h
      ..played += 1
      ..goalsFor += hs
      ..goalsAgainst += as;
    a
      ..played += 1
      ..goalsFor += as
      ..goalsAgainst += hs;
    if (hs > as) {
      h
        ..won += 1
        ..points += 3;
      a.lost += 1;
    } else if (as > hs) {
      a
        ..won += 1
        ..points += 3;
      h.lost += 1;
    } else {
      h
        ..drawn += 1
        ..points += 1;
      a
        ..drawn += 1
        ..points += 1;
    }
  }

  final list = table.values.toList()
    ..sort((x, y) {
      if (y.points != x.points) return y.points.compareTo(x.points);

      // İkili averaj
      var ptsX = 0, ptsY = 0, gdX = 0, gdY = 0;
      for (final m in groupMatches) {
        final hId = _homeId(m), aId = _awayId(m);
        if (!_isCompleted(m)) continue;
        final xHome = hId == x.teamId && aId == y.teamId;
        final yHome = hId == y.teamId && aId == x.teamId;
        if (!xHome && !yHome) continue;
        final hs = _score(m, 'home'), as = _score(m, 'away');
        final xGoals = xHome ? hs : as;
        final yGoals = xHome ? as : hs;
        gdX += xGoals - yGoals;
        gdY += yGoals - xGoals;
        if (xGoals > yGoals) {
          ptsX += 3;
        } else if (yGoals > xGoals) {
          ptsY += 3;
        } else {
          ptsX += 1;
          ptsY += 1;
        }
      }
      if (ptsY != ptsX) return ptsY.compareTo(ptsX);
      if (gdY != gdX) return gdY.compareTo(gdX);

      if (y.goalDiff != x.goalDiff) return y.goalDiff.compareTo(x.goalDiff);
      if (y.goalsFor != x.goalsFor) return y.goalsFor.compareTo(x.goalsFor);
      return x.name.toLowerCase().compareTo(y.name.toLowerCase());
    });
  return list;
}
