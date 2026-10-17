import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/features/team/models/team.dart';
import 'package:football_tournament/features/team/utils/standings.dart';

void main() {
  const teams = [
    Team(id: 'a', name: 'A', logoUrl: ''),
    Team(id: 'b', name: 'B', logoUrl: ''),
  ];
  final matches = [
    {
      'group_id': 'g',
      'home_team_id': 'a',
      'away_team_id': 'b',
      'home_score': 0,
      'away_score': 2,
      'status': 'live',
    },
  ];

  List<StandingEntry> run({required bool live}) => computeGroupStandings(
    leagueId: 'l',
    groupId: 'g',
    groupName: 'Grup A',
    seasonMatches: matches,
    allTeams: teams,
    includeLive: live,
  );

  test('oynanan maç normal puan durumunda sayılmaz', () {
    expect(run(live: false).every((e) => e.played == 0), isTrue);
  });

  test('canlı puan durumunda o anki skorla sayılır', () {
    final rows = run(live: true);
    expect(rows.first.teamId, 'b');
    expect(rows.first.points, 3);
    expect(rows.last.played, 1);
  });
}
