import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/models/match.dart';
import 'package:football_tournament/services/database_service.dart';

void main() {
  group('Standings Calculation Tests', () {
    late FakeFirebaseFirestore firestore;
    late DatabaseService service;

    const testTournamentId = 'tour123';
    const testGroupId = 'grp123';
    const team1Id = 'team1';
    const team2Id = 'team2';
    const team3Id = 'team3';

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      service = DatabaseService(firestore: firestore);
    });

    test('Teams should initialize with zero standings', () async {
      // Add teams
      await firestore.collection('teams').doc(team1Id).set({
        'groupId': testGroupId,
        'name': 'Team 1',
        'logoUrl': '',
      });

      await firestore.collection('teams').doc(team2Id).set({
        'groupId': testGroupId,
        'name': 'Team 2',
        'logoUrl': '',
      });

      // Query teams (by groupId only, not tournamentId)
      final teamsSnapshot = await firestore
          .collection('teams')
          .where('groupId', isEqualTo: testGroupId)
          .get();

      print('\n✅ Teams Query Result:');
      print('Teams count: ${teamsSnapshot.docs.length}');
      expect(teamsSnapshot.docs.length, 2);

      final standings = <String, Map<String, dynamic>>{};
      for (final teamDoc in teamsSnapshot.docs) {
        final teamData = teamDoc.data();
        final teamId = teamDoc.id;
        standings[teamId] = {
          'P': 0,
          'G': 0,
          'B': 0,
          'M': 0,
          'AG': 0,
          'YG': 0,
          'AV': 0,
          'Puan': 0,
        };
      }

      print('✅ Standings initialized for ${standings.length} teams');
      standings.forEach((id, stats) {
        print('   Team $id: P=${stats['P']}, Puan=${stats['Puan']}');
      });

      expect(standings[team1Id]!['Puan'], 0);
      expect(standings[team2Id]!['Puan'], 0);
    });

    test('Standings should update correctly with completed matches', () async {
      // Add teams
      await firestore.collection('teams').doc(team1Id).set({
        'groupId': testGroupId,
        'name': 'Team 1',
        'logoUrl': '',
      });

      await firestore.collection('teams').doc(team2Id).set({
        'groupId': testGroupId,
        'name': 'Team 2',
        'logoUrl': '',
      });

      // Add a completed match (Team 1 wins 3-1)
      await firestore.collection('matches').add({
        'leagueId': testTournamentId,
        'groupId': testGroupId,
        'homeTeamId': team1Id,
        'awayTeamId': team2Id,
        'homeScore': 3,
        'awayScore': 1,
        'status': 'finished',
        'isCompleted': true,
      });

      // Query teams (by groupId only)
      final teamsSnapshot = await firestore
          .collection('teams')
          .where('groupId', isEqualTo: testGroupId)
          .get();

      // Initialize standings
      final standings = <String, Map<String, dynamic>>{};
      final teamNames = <String, String>{};
      for (final teamDoc in teamsSnapshot.docs) {
        final teamData = teamDoc.data();
        final teamId = teamDoc.id;
        teamNames[teamId] = teamData['name'] ?? 'Team';
        standings[teamId] = {
          'P': 0,
          'G': 0,
          'B': 0,
          'M': 0,
          'AG': 0,
          'YG': 0,
          'AV': 0,
          'Puan': 0,
        };
      }

      print('\n✅ Initial Standings:');
      standings.forEach((id, stats) {
        print('   ${teamNames[id]}: Puan=${stats['Puan']}, P=${stats['P']}');
      });

      // Query matches (by leagueId and groupId)
      final matchesSnapshot = await firestore
          .collection('matches')
          .where('leagueId', isEqualTo: testTournamentId)
          .where('groupId', isEqualTo: testGroupId)
          .get();

      print('\n✅ Matches Query Result:');
      print('Matches count: ${matchesSnapshot.docs.length}');

      // Update standings from matches
      for (final matchDoc in matchesSnapshot.docs) {
        final m = matchDoc.data();
        final hId = (m['homeTeamId'] ?? '').toString();
        final aId = (m['awayTeamId'] ?? '').toString();
        final status = (m['status'] ?? '').toString();
        final isCompleted = m['isCompleted'] == true;

        print(
          '   Match: $hId (${m['homeScore']}) vs $aId (${m['awayScore']}) - status: $status, isCompleted: $isCompleted',
        );

        if (isCompleted &&
            standings.containsKey(hId) &&
            standings.containsKey(aId)) {
          final hS = (m['homeScore'] as num?)?.toInt() ?? 0;
          final aS = (m['awayScore'] as num?)?.toInt() ?? 0;

          standings[hId]!['P'] = standings[hId]!['P']! + 1;
          standings[aId]!['P'] = standings[aId]!['P']! + 1;
          standings[hId]!['AG'] = standings[hId]!['AG']! + hS;
          standings[hId]!['YG'] = standings[hId]!['YG']! + aS;
          standings[aId]!['AG'] = standings[aId]!['AG']! + aS;
          standings[aId]!['YG'] = standings[aId]!['YG']! + hS;

          if (hS > aS) {
            standings[hId]!['G'] = standings[hId]!['G']! + 1;
            standings[hId]!['Puan'] = standings[hId]!['Puan']! + 3;
            standings[aId]!['M'] = standings[aId]!['M']! + 1;
          } else if (aS > hS) {
            standings[aId]!['G'] = standings[aId]!['G']! + 1;
            standings[aId]!['Puan'] = standings[aId]!['Puan']! + 3;
            standings[hId]!['M'] = standings[hId]!['M']! + 1;
          } else {
            standings[hId]!['B'] = standings[hId]!['B']! + 1;
            standings[aId]!['B'] = standings[aId]!['B']! + 1;
            standings[hId]!['Puan'] = standings[hId]!['Puan']! + 1;
            standings[aId]!['Puan'] = standings[aId]!['Puan']! + 1;
          }
        }
      }

      // Calculate averages
      standings.forEach((k, v) {
        v['AV'] = v['AG']! - v['YG']!;
      });

      print('\n✅ Final Standings:');
      standings.forEach((id, stats) {
        print(
          '   ${teamNames[id]}: P=${stats['P']}, G=${stats['G']}, B=${stats['B']}, M=${stats['M']}, AG=${stats['AG']}, YG=${stats['YG']}, AV=${stats['AV']}, Puan=${stats['Puan']}',
        );
      });

      // Verify results
      expect(standings[team1Id]!['P'], 1); // Played 1 match
      expect(standings[team1Id]!['G'], 1); // Won 1
      expect(standings[team1Id]!['Puan'], 3); // 3 points
      expect(standings[team1Id]!['AG'], 3); // Scored 3
      expect(standings[team1Id]!['YG'], 1); // Conceded 1
      expect(standings[team1Id]!['AV'], 2); // Goal average 2

      expect(standings[team2Id]!['P'], 1); // Played 1 match
      expect(standings[team2Id]!['M'], 1); // Lost 1
      expect(standings[team2Id]!['Puan'], 0); // 0 points
      expect(standings[team2Id]!['AG'], 1); // Scored 1
      expect(standings[team2Id]!['YG'], 3); // Conceded 3
      expect(standings[team2Id]!['AV'], -2); // Goal average -2
    });

    test('Groups should be queryable with tournamentId filter', () async {
      // Add a group
      await firestore.collection('groups').doc(testGroupId).set({
        'tournamentId': testTournamentId,
        'name': 'Grup A',
        'teamIds': [team1Id, team2Id],
      });

      // Query groups
      final groupsSnapshot = await firestore
          .collection('groups')
          .where('tournamentId', isEqualTo: testTournamentId)
          .get();

      print('\n✅ Groups Query Result:');
      print('Groups count: ${groupsSnapshot.docs.length}');

      expect(groupsSnapshot.docs.length, 1);
      expect((groupsSnapshot.docs.first.data()['name'] ?? ''), 'Grup A');
    });
  });
}
