import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/features/match/models/match.dart';
import 'package:football_tournament/features/match/widgets/match_score_line.dart';

MatchModel _match({required String status}) => MatchModel.fromMap({
  'home_team_id': 'home',
  'away_team_id': 'away',
  'home_score': 2,
  'away_score': 1,
  'match_date': '2026-10-09',
  'match_time': '18:30',
  'status': status,
}, 'match-1');

void main() {
  testWidgets('finished match shows MS instead of kickoff time', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchScoreLine(
            match: _match(status: 'finished'),
            homeName: 'Home FC',
            awayName: 'Away FC',
            homeLogo: '',
            awayLogo: '',
            showLogos: false,
          ),
        ),
      ),
    );

    expect(find.text('MS'), findsOneWidget);
    expect(find.text('18:30'), findsNothing);
    expect(find.text('2 - 1'), findsOneWidget);
  });
}
