import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Puan Durumu Hesaplama Testleri', () {
    // Mock: _asInt fonksiyonu
    int _asInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString().trim()) ?? 0;
    }

    // Mock: _isCompleted fonksiyonu
    bool _isCompleted(Map<String, dynamic> data) {
      return data['status'] == 'finished' ||
          (data['homeScore'] != null && data['awayScore'] != null);
    }

    // Puan hesaplama fonksiyonu (standalone test için)
    Map<String, Map<String, int>> calculateStandings(
      List<String> teamIds,
      List<Map<String, dynamic>> matches,
    ) {
      final standings = <String, Map<String, int>>{};

      // Initialize standings
      for (final teamId in teamIds) {
        standings[teamId] = {
          'P': 0, // Oynanılan
          'G': 0, // Galibiyetler
          'B': 0, // Beraberlikler
          'M': 0, // Mağlubiyetler
          'AG': 0, // Açılan Gol
          'YG': 0, // Yediği Gol
          'AV': 0, // Averaj
          'Puan': 0, // Toplam Puan
        };
      }

      // Process matches
      for (final m in matches) {
        final hId = (m['homeTeamId'] ?? '').toString();
        final aId = (m['awayTeamId'] ?? '').toString();

        if (_isCompleted(m) &&
            standings.containsKey(hId) &&
            standings.containsKey(aId)) {
          final hS = _asInt(m['homeScore']);
          final aS = _asInt(m['awayScore']);

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

      standings.forEach((k, v) {
        v['AV'] = v['AG']! - v['YG']!;
      });

      return standings;
    }

    test('Boş maç listesi - tüm takımlar 0 puan', () {
      final teamIds = ['team1', 'team2', 'team3'];
      final matches = <Map<String, dynamic>>[];

      final standings = calculateStandings(teamIds, matches);

      expect(standings['team1']!['Puan'], 0);
      expect(standings['team2']!['Puan'], 0);
      expect(standings['team3']!['Puan'], 0);
      print('✓ Test 1 GEÇTI: Boş maç listesi');
    });

    test('Ev sahibi galibiyeti - 2-0', () {
      final teamIds = ['home_team', 'away_team'];
      final matches = [
        {
          'homeTeamId': 'home_team',
          'awayTeamId': 'away_team',
          'homeScore': 2,
          'awayScore': 0,
          'status': 'finished',
        },
      ];

      final standings = calculateStandings(teamIds, matches);

      expect(standings['home_team']!['Puan'], 3);
      expect(standings['home_team']!['G'], 1);
      expect(standings['home_team']!['AG'], 2);
      expect(standings['home_team']!['YG'], 0);
      expect(standings['away_team']!['Puan'], 0);
      expect(standings['away_team']!['M'], 1);
      print('✓ Test 2 GEÇTI: Ev sahibi galibiyeti 2-0');
    });

    test('Deplasman galibiyeti - 1-3', () {
      final teamIds = ['home_team', 'away_team'];
      final matches = [
        {
          'homeTeamId': 'home_team',
          'awayTeamId': 'away_team',
          'homeScore': 1,
          'awayScore': 3,
          'status': 'finished',
        },
      ];

      final standings = calculateStandings(teamIds, matches);

      expect(standings['away_team']!['Puan'], 3);
      expect(standings['away_team']!['G'], 1);
      expect(standings['away_team']!['AG'], 3);
      expect(standings['home_team']!['Puan'], 0);
      expect(standings['home_team']!['M'], 1);
      print('✓ Test 3 GEÇTI: Deplasman galibiyeti 1-3');
    });

    test('Beraberlik - 1-1', () {
      final teamIds = ['home_team', 'away_team'];
      final matches = [
        {
          'homeTeamId': 'home_team',
          'awayTeamId': 'away_team',
          'homeScore': 1,
          'awayScore': 1,
          'status': 'finished',
        },
      ];

      final standings = calculateStandings(teamIds, matches);

      expect(standings['home_team']!['Puan'], 1);
      expect(standings['away_team']!['Puan'], 1);
      expect(standings['home_team']!['B'], 1);
      expect(standings['away_team']!['B'], 1);
      print('✓ Test 4 GEÇTI: Beraberlik 1-1');
    });

    test('Birden fazla maç - karmaşık senaryo', () {
      final teamIds = ['team_a', 'team_b', 'team_c'];
      final matches = [
        // Team A 2-1 Team B (A 3 puan)
        {
          'homeTeamId': 'team_a',
          'awayTeamId': 'team_b',
          'homeScore': 2,
          'awayScore': 1,
          'status': 'finished',
        },
        // Team C 1-1 Team A (A 1 puan, C 1 puan)
        {
          'homeTeamId': 'team_c',
          'awayTeamId': 'team_a',
          'homeScore': 1,
          'awayScore': 1,
          'status': 'finished',
        },
        // Team B 3-0 Team C (B 3 puan)
        {
          'homeTeamId': 'team_b',
          'awayTeamId': 'team_c',
          'homeScore': 3,
          'awayScore': 0,
          'status': 'finished',
        },
      ];

      final standings = calculateStandings(teamIds, matches);

      // Team A: 2 maç, 1G+1B = 4 puan, 3 açtı 2 yedi
      expect(standings['team_a']!['Puan'], 4);
      expect(standings['team_a']!['P'], 2);
      expect(standings['team_a']!['AG'], 3);
      expect(standings['team_a']!['YG'], 2);

      // Team B: 2 maç, 1G+1M = 3 puan, 4 açtı 3 yedi
      expect(standings['team_b']!['Puan'], 3);
      expect(standings['team_b']!['P'], 2);
      expect(standings['team_b']!['AG'], 4);

      // Team C: 2 maç, 1B+1M = 1 puan, 1 açtı 4 yedi
      expect(standings['team_c']!['Puan'], 1);
      expect(standings['team_c']!['P'], 2);

      print('✓ Test 5 GEÇTI: Birden fazla maç - karmaşık senaryo');
      print('  Team A: ${standings['team_a']!['Puan']} puan (2P, 1G, 1B)');
      print('  Team B: ${standings['team_b']!['Puan']} puan (2P, 1G, 1M)');
      print('  Team C: ${standings['team_c']!['Puan']} puan (2P, 1B, 1M)');
    });

    test(
      'Status finished ve homeScore/awayScore null - _isCompleted kontrol',
      () {
        final data1 = {
          'status': 'finished',
          'homeScore': null,
          'awayScore': null,
        };
        expect(_isCompleted(data1), true); // finished status yeterli

        final data2 = {'status': 'pending', 'homeScore': 2, 'awayScore': 1};
        expect(_isCompleted(data2), true); // scorelar yeterli

        final data3 = {'status': 'pending', 'homeScore': null, 'awayScore': 1};
        expect(_isCompleted(data3), false); // ikisi de gerekli

        print('✓ Test 6 GEÇTI: _isCompleted fonksiyonu doğru çalışıyor');
      },
    );
  });
}
