import 'package:firebase_core/firebase_core.dart';
import 'package:football_tournament/core/services/database_service.dart';

void main() async {
  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    print('✅ Firebase initialized');
  } catch (e) {
    print('⚠️ Firebase initialization: $e');
  }

  final dbService = DatabaseService();
  const testTeamId = 'OnbHjgCmq5MrMgqyiN0R';
  const expectedTournamentId = 'qAzYxC579QhxDDgsorgX';

  print('\n🔍 Testing getTeamActiveTournaments with teamId: $testTeamId');
  print('📌 Expected tournament ID: $expectedTournamentId\n');

  try {
    final tournaments = await dbService.getTeamActiveTournaments(testTeamId);

    print('\n${'=' * 60}');
    print('📊 TEST RESULTS:');
    print('=' * 60);
    print('Total tournaments found: ${tournaments.length}');

    if (tournaments.isEmpty) {
      print('\n❌ ERROR: No tournaments returned!');
      print('Debugging steps:');
      print('1. Check if groups exist with teamIds containing this teamId');
      print('2. Check if those groups have tournamentId field');
      print('3. Check if those tournaments have isActive: true');
    } else {
      print('\n✅ Tournaments returned successfully!');
      print('\nTournament details:');
      print('-' * 60);

      for (int i = 0; i < tournaments.length; i++) {
        final t = tournaments[i];
        final match = t.id == expectedTournamentId ? '✅ EXPECTED' : '  ';
        print('${i + 1}. $match');
        print('   ID: ${t.id}');
        print('   Name: ${t.name}');
        print('   IsActive: ${t.isActive}');
        print('-' * 60);
      }

      final hasExpected = tournaments.any((t) => t.id == expectedTournamentId);
      if (hasExpected) {
        print(
          '\n🎉 SUCCESS: Found expected tournament ID: $expectedTournamentId',
        );
      } else {
        print(
          '\n⚠️ WARNING: Expected tournament ID not found: $expectedTournamentId',
        );
        print('Found IDs: ${tournaments.map((t) => t.id).toList()}');
      }
    }
  } catch (e, stackTrace) {
    print('❌ Error during test: $e');
    print('Stack trace: $stackTrace');
  }

  print('\n✔️ Test completed.\n');
}
