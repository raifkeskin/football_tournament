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
        homeTeamName: 'Ev2',
        homeTeamLogoUrl: '',
        awayTeamId: 'A2',
        awayTeamName: 'Dep2',
        awayTeamLogoUrl: '',
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
}
