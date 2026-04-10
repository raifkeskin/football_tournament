import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:football_tournament/models/match.dart';
import 'package:football_tournament/services/database_service.dart';

void main() {
  test(
    'getMatchesByDate gün/ay/yıl bazında maçları döndürür ve dateString alanını sağlamlaştırır',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = DatabaseService(firestore: firestore);

      final matchDate = DateTime(2026, 4, 7, 20, 0);
      final m1 = MatchModel(
        id: '',
        leagueId: 'L1',
        groupId: 'G1',
        homeTeamId: 'H1',
        homeTeamName: 'Ev',
        homeTeamLogoUrl: '',
        awayTeamId: 'A1',
        awayTeamName: 'Dep',
        awayTeamLogoUrl: '',
        homeScore: 0,
        awayScore: 0,
        matchDate: matchDate,
        dateString: '2026-04-07',
        status: MatchStatus.notStarted,
      );

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
        matchDate: matchDate,
        dateString: '2026-04-07',
        status: MatchStatus.finished,
      );

      final oldDocData = {...m1.toMap()}..remove('dateString');
      await firestore.collection('matches').add(oldDocData);
      await firestore.collection('matches').add(m2.toMap());

      final selectedDay = DateTime(2026, 4, 7);

      final onlyL1 = await service
          .getMatchesByDate(leagueId: 'L1', date: selectedDay)
          .firstWhere((list) => list.length == 1);

      expect(onlyL1.single.leagueId, 'L1');
      expect(onlyL1.single.dateString, '2026-04-07');
      expect(onlyL1.single.matchDate.year, 2026);
      expect(onlyL1.single.matchDate.month, 4);
      expect(onlyL1.single.matchDate.day, 7);

      final updatedSnap = await firestore
          .collection('matches')
          .where('leagueId', isEqualTo: 'L1')
          .get();
      expect(updatedSnap.docs.length, 1);
      expect(updatedSnap.docs.single.data()['dateString'], '2026-04-07');

      final all = await service
          .getMatchesByDate(date: selectedDay)
          .firstWhere((list) => list.length == 2);
      final leagues = all.map((m) => m.leagueId).toSet();
      expect(leagues, {'L1', 'L2'});
    },
  );
}
