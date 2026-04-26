import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:football_tournament/models/match.dart';
import 'package:football_tournament/services/database_service.dart';

void main() {
  test(
    'getMatchesByDate gün/ay/yıl bazında maçları döndürür ve legacy alanları matchDate/matchTime alanlarına taşır',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = DatabaseService(firestore: firestore);

      await firestore.collection('matches').add({
        'leagueId': 'L1',
        'groupId': 'G1',
        'homeTeamId': 'H1',
        'homeTeamName': 'Ev',
        'homeTeamLogoUrl': '',
        'awayTeamId': 'A1',
        'awayTeamName': 'Dep',
        'awayTeamLogoUrl': '',
        'homeScore': 0,
        'awayScore': 0,
        'dateString': '2026-04-07',
        'time': '20:00',
        'status': MatchStatus.notStarted.name,
      });

      final m2 = MatchModel(
        id: '',
        leagueId: 'L2',
        groupId: 'G2',
        homeTeamId: 'H2',
        awayTeamId: 'A2',
        homeScore: 1,
        awayScore: 2,
        matchDate: '2026-04-07',
        matchTime: '20:00',
        status: MatchStatus.finished,
      );

      await firestore.collection('matches').add(m2.toMap());

      final selectedDay = DateTime(2026, 4, 7);

      final onlyL1 = await service
          .getMatchesByDate(leagueId: 'L1', date: selectedDay)
          .firstWhere((list) => list.length == 1);

      expect(onlyL1.single.leagueId, 'L1');
      expect(onlyL1.single.matchDate, '2026-04-07');
      expect(onlyL1.single.matchTime, '20:00');

      final updatedSnap = await firestore
          .collection('matches')
          .where('leagueId', isEqualTo: 'L1')
          .get();
      expect(updatedSnap.docs.length, 1);
      final updated = updatedSnap.docs.single.data();
      expect(updated['matchDate'], '2026-04-07');
      expect(updated['matchTime'], '20:00');
      expect(updated.containsKey('dateString'), false);
      expect(updated.containsKey('time'), false);

      final all = await service
          .getMatchesByDate(date: selectedDay)
          .firstWhere((list) => list.length == 2);
      final leagues = all.map((m) => m.leagueId).toSet();
      expect(leagues, {'L1', 'L2'});
    },
  );

  test('normalizeMatchesDocIdsByLeagueWeekHomeTeam maç idlerini normalize eder', () async {
    final firestore = FakeFirebaseFirestore();
    final service = DatabaseService(firestore: firestore);

    final auto1 = firestore.collection('matches').doc('auto1');
    await auto1.set({
      'leagueId': 'L1',
      'week': 5,
      'homeTeamId': 'H1',
      'awayTeamId': 'A1',
      'homeScore': 3,
      'awayScore': 1,
      'status': 'finished',
      'isCompleted': true,
    });
    await auto1.collection('events').doc('e1').set({'minute': 0, 'title': 'X'});

    final auto2 = firestore.collection('matches').doc('auto2');
    await auto2.set({
      'leagueId': 'L1',
      'week': 5,
      'homeTeamId': 'H1',
      'awayTeamId': 'A1',
      'homeScore': 3,
      'awayScore': 1,
      'score': {
        'fullTime': {'home': 3, 'away': 1},
      },
      'status': 'finished',
      'isCompleted': true,
    });

    await firestore.collection('match_events').doc('me1').set({
      'matchId': 'auto1',
      'minute': 10,
      'type': 'goal',
      'teamId': 'H1',
      'playerPhone': '5550000000',
    });

    final result = await service.normalizeMatchesDocIdsByLeagueWeekHomeTeam();
    expect((result['scanned'] ?? 0) >= 2, true);
    expect((result['deleted'] ?? 0) >= 1, true);

    final normalizedId = 'L1_week5_H1';
    final normalizedSnap =
        await firestore.collection('matches').doc(normalizedId).get();
    expect(normalizedSnap.exists, true);

    final stillAuto1 = await firestore.collection('matches').doc('auto1').get();
    final stillAuto2 = await firestore.collection('matches').doc('auto2').get();
    expect(stillAuto1.exists, false);
    expect(stillAuto2.exists, false);

    final evSnap = await firestore
        .collection('matches')
        .doc(normalizedId)
        .collection('events')
        .get();
    expect(evSnap.docs.any((d) => d.id == 'e1'), true);

    final matchEventsSnap = await firestore.collection('match_events').get();
    expect(
      matchEventsSnap.docs.any((d) => d.data()['matchId'] == normalizedId),
      true,
    );
  });
}
