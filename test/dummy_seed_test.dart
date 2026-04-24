import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:football_tournament/config/app_config.dart';
import 'package:football_tournament/services/database_service.dart';

void main() {
  test(
    'seedDummyFixtureOneWeek maç üretir ve puan durumunu günceller',
    () async {
      final prevDb = AppConfig.activeDatabase;
      AppConfig.activeDatabase = DatabaseType.firebase;
      final firestore = FakeFirebaseFirestore();
      final service = DatabaseService(firestore: firestore);

      final groupRef = await firestore.collection('groups').add({
        'leagueId': 'L1',
        'name': 'A Grubu',
        'teamIds': [],
      });
      final groupId = groupRef.id;

      final team1Ref = await firestore.collection('teams').add({
        'leagueId': 'L1',
        'name': 'Takım 1',
        'logoUrl': '',
        'groupId': groupId,
        'stats': {
          'P': 0,
          'G': 0,
          'B': 0,
          'M': 0,
          'AG': 0,
          'YG': 0,
          'AV': 0,
          'Puan': 0,
        },
      });
      final team2Ref = await firestore.collection('teams').add({
        'leagueId': 'L1',
        'name': 'Takım 2',
        'logoUrl': '',
        'groupId': groupId,
        'stats': {
          'P': 0,
          'G': 0,
          'B': 0,
          'M': 0,
          'AG': 0,
          'YG': 0,
          'AV': 0,
          'Puan': 0,
        },
      });

      final created = await service.seedDummyFixtureOneWeek(randomSeed: 7);
      expect(created, greaterThan(0));

      final matchesSnap = await firestore
          .collection('matches')
          .where('groupId', isEqualTo: groupId)
          .where('status', isEqualTo: 'finished')
          .get();

      final expected = <String, Map<String, int>>{
        team1Ref.id: {
          'P': 0,
          'G': 0,
          'B': 0,
          'M': 0,
          'AG': 0,
          'YG': 0,
          'AV': 0,
          'Puan': 0,
        },
        team2Ref.id: {
          'P': 0,
          'G': 0,
          'B': 0,
          'M': 0,
          'AG': 0,
          'YG': 0,
          'AV': 0,
          'Puan': 0,
        },
      };

      for (final doc in matchesSnap.docs) {
        final m = doc.data();
        final hId = m['homeTeamId'] as String;
        final aId = m['awayTeamId'] as String;
        final hS = (m['homeScore'] as num).toInt();
        final aS = (m['awayScore'] as num).toInt();

        expected[hId]!['P'] = expected[hId]!['P']! + 1;
        expected[aId]!['P'] = expected[aId]!['P']! + 1;
        expected[hId]!['AG'] = expected[hId]!['AG']! + hS;
        expected[hId]!['YG'] = expected[hId]!['YG']! + aS;
        expected[aId]!['AG'] = expected[aId]!['AG']! + aS;
        expected[aId]!['YG'] = expected[aId]!['YG']! + hS;

        if (hS > aS) {
          expected[hId]!['G'] = expected[hId]!['G']! + 1;
          expected[hId]!['Puan'] = expected[hId]!['Puan']! + 3;
          expected[aId]!['M'] = expected[aId]!['M']! + 1;
        } else if (aS > hS) {
          expected[aId]!['G'] = expected[aId]!['G']! + 1;
          expected[aId]!['Puan'] = expected[aId]!['Puan']! + 3;
          expected[hId]!['M'] = expected[hId]!['M']! + 1;
        } else {
          expected[hId]!['B'] = expected[hId]!['B']! + 1;
          expected[aId]!['B'] = expected[aId]!['B']! + 1;
          expected[hId]!['Puan'] = expected[hId]!['Puan']! + 1;
          expected[aId]!['Puan'] = expected[aId]!['Puan']! + 1;
        }
      }

      expected.forEach((id, stats) {
        stats['AV'] = stats['AG']! - stats['YG']!;
      });

      final teamsSnap = await firestore
          .collection('teams')
          .where('groupId', isEqualTo: groupId)
          .get();
      for (final tDoc in teamsSnap.docs) {
        final stats = Map<String, dynamic>.from(tDoc.data()['stats'] as Map);
        final e = expected[tDoc.id]!;
        expect(stats['P'], e['P']);
        expect(stats['G'], e['G']);
        expect(stats['B'], e['B']);
        expect(stats['M'], e['M']);
        expect(stats['AG'], e['AG']);
        expect(stats['YG'], e['YG']);
        expect(stats['AV'], e['AV']);
        expect(stats['Puan'], e['Puan']);
      }
      AppConfig.activeDatabase = prevDb;
    },
  );

  test(
    'gruptaki teamIds üzerinden takım listesi oluşturulabilir (2026 grubu)',
    () async {
      final prevDb = AppConfig.activeDatabase;
      AppConfig.activeDatabase = DatabaseType.firebase;
      final firestore = FakeFirebaseFirestore();
      final service = DatabaseService(firestore: firestore);

      await firestore.collection('groups').doc('g2026').set({
        'leagueId': 'L2026',
        'name': '2026',
        'teamIds': ['t1', 't2'],
      });
      await firestore.collection('teams').doc('t1').set({
        'leagueId': 'L2026',
        'name': 'Takım 1',
        'logoUrl': '',
      });
      await firestore.collection('teams').doc('t2').set({
        'leagueId': 'L2026',
        'name': 'Takım 2',
        'logoUrl': '',
      });

      final groups = await service.getGroups('L2026').first;
      expect(groups, hasLength(1));
      expect(groups.first.name, '2026');
      expect(groups.first.teamIds.toSet(), {'t1', 't2'});

      final teamIds = groups.first.teamIds.toSet();
      final teamsSnap = await firestore.collection('teams').orderBy('name').get();
      final listedTeamIds = teamsSnap.docs
          .map((d) => d.id)
          .where(teamIds.contains)
          .toSet();

      expect(listedTeamIds, {'t1', 't2'});
      AppConfig.activeDatabase = prevDb;
    },
  );
}
