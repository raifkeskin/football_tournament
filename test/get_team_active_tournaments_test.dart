import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:football_tournament/services/database_service.dart';

void main() {
  group('getTeamActiveTournaments Tests', () {
    late DatabaseService dbService;
    const testTeamId = 'OnbHjgCmq5MrMgqyiN0R';
    const expectedTournamentId = 'qAzYxC579QhxDDgsorgX';

    setUpAll(() async {
      // Firebase initialize
      try {
        await Firebase.initializeApp();
      } catch (e) {
        // Already initialized
      }
      dbService = DatabaseService();
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
