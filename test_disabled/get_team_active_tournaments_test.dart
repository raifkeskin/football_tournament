import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:football_tournament/config/app_config.dart';
import 'package:football_tournament/services/database_service.dart';

void main() {
  group('getTeamActiveTournaments Tests', () {
    late DatabaseService dbService;
    late FakeFirebaseFirestore firestore;
    late DatabaseType _prevDb;
    const testTeamId = 'OnbHjgCmq5MrMgqyiN0R';
    const expectedTournamentId = 'qAzYxC579QhxDDgsorgX';
    const inactiveTournamentId = 'inactive_tournament_123';

    setUp(() async {
      _prevDb = AppConfig.activeDatabase;
      AppConfig.activeDatabase = DatabaseType.firebase;
      firestore = FakeFirebaseFirestore();

      await firestore.collection('leagues').doc(expectedTournamentId).set({
        'name': 'Active Tournament',
        'logoUrl': '',
        'country': 'TR',
        'isActive': true,
      });
      await firestore.collection('leagues').doc(inactiveTournamentId).set({
        'name': 'Inactive Tournament',
        'logoUrl': '',
        'country': 'TR',
        'isActive': false,
      });

      await firestore.collection('groups').doc('g1').set({
        'leagueId': expectedTournamentId,
        'name': 'A',
        'teamIds': [testTeamId],
      });
      await firestore.collection('groups').doc('g2').set({
        'leagueId': inactiveTournamentId,
        'name': 'B',
        'teamIds': [testTeamId],
      });

      dbService = DatabaseService(firestore: firestore);
    });

    tearDown(() {
      AppConfig.activeDatabase = _prevDb;
    });

    test(
      'getTeamActiveTournaments should return tournament for team',
      () async {
        print('🔍 Testing getTeamActiveTournaments for teamId: $testTeamId');

        final tournaments = await dbService.getTeamActiveTournaments(
          testTeamId,
        );

        print('📊 Returned tournaments: ${tournaments.length}');
        for (final t in tournaments) {
          print('  - ID: ${t.id}, Name: ${t.name}, isActive: ${t.isActive}');
        }

        expect(
          tournaments,
          isNotEmpty,
          reason: 'Should return at least one tournament',
        );

        final hasExpectedTournament = tournaments.any(
          (t) => t.id == expectedTournamentId,
        );

        expect(
          hasExpectedTournament,
          isTrue,
          reason: 'Should contain tournament with ID: $expectedTournamentId',
        );

        print(
          '✅ Test passed! Found expected tournament: $expectedTournamentId',
        );
      },
    );

    test('getTeamActiveTournaments should filter by isActive flag', () async {
      print('🔍 Checking isActive filtering for teamId: $testTeamId');

      final tournaments = await dbService.getTeamActiveTournaments(testTeamId);

      for (final t in tournaments) {
        expect(
          t.isActive,
          isTrue,
          reason: 'All returned tournaments should have isActive: true',
        );
      }

      print('✅ All tournaments have isActive: true');
    });

    test(
      'getTeamActiveTournaments with non-existent teamId should return empty',
      () async {
        const nonExistentTeamId = 'non_existent_team_xyz';
        print('🔍 Testing with non-existent teamId: $nonExistentTeamId');

        final tournaments = await dbService.getTeamActiveTournaments(
          nonExistentTeamId,
        );

        expect(
          tournaments,
          isEmpty,
          reason: 'Should return empty list for non-existent team',
        );

        print('✅ Correctly returned empty list');
      },
    );
  });
}
