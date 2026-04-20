import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Test: Veritabanındaki maçları kontrol et
  await checkDatabaseMatches();
}

Future<void> checkDatabaseMatches() async {
  final db = FirebaseFirestore.instance;

  print('\n═════════════════════════════════════════════════');
  print('Firestore Maç Verileri Kontrol');
  print('═════════════════════════════════════════════════\n');

  try {
    // Tüm maçları çek
    final allMatches = await db.collection('matches').get();
    print('✓ Toplam maç sayısı: ${allMatches.docs.length}');

    if (allMatches.docs.isEmpty) {
      print('⚠️  UYARI: Veritabanında hiç maç yok!');
      return;
    }

    // Status 'finished' olan maçları çek
    final finishedMatches = await db
        .collection('matches')
        .where('status', isEqualTo: 'finished')
        .get();

    print(
      '✓ Status = "finished" olan maç sayısı: ${finishedMatches.docs.length}',
    );

    if (finishedMatches.docs.isEmpty) {
      print('⚠️  UYARI: Status "finished" olan maç yok!');
      print('   → Maçları "finished" yapmalısınız');
    }

    // İlk 5 maçı detaylı kontrol et
    print('\n📊 İlk 5 Maç Detayları:');
    print('─────────────────────────────────────────────');

    for (int i = 0; i < allMatches.docs.take(5).length; i++) {
      final doc = allMatches.docs[i];
      final data = doc.data();

      print('\nMaç ${i + 1} (ID: ${doc.id})');
      print('  Status: ${data['status'] ?? "UYARI: YOK"}');
      print('  LeagueId: ${data['leagueId'] ?? "UYARI: YOK"}');
      print('  GroupId: ${data['groupId'] ?? "UYARI: YOK"}');
      print('  HomeTeamId: ${data['homeTeamId'] ?? "UYARI: YOK"}');
      print('  AwayTeamId: ${data['awayTeamId'] ?? "UYARI: YOK"}');
      print('  HomeScore: ${data['homeScore'] ?? "UYARI: YOK"}');
      print('  AwayScore: ${data['awayScore'] ?? "UYARI: YOK"}');
      print(
        '  Score.fullTime.home: ${data['score']?['fullTime']?['home'] ?? "YOK"}',
      );
      print(
        '  Score.fullTime.away: ${data['score']?['fullTime']?['away'] ?? "YOK"}',
      );
    }

    // Grup ve League'ye göre maçları çek
    print('\n📍 Grup Özelinde Maçlar:');
    print('─────────────────────────────────────────────');

    final leagues = await db.collection('leagues').get();
    print('✓ Toplam League sayısı: ${leagues.docs.length}');

    for (final leagueDoc in leagues.docs.take(1)) {
      final leagueId = leagueDoc.id;
      final leagueName = leagueDoc.data()['name'] ?? 'Bilinmiyor';

      print('\nLiga: $leagueName (ID: $leagueId)');

      final groups = await db
          .collection('groups')
          .where('leagueId', isEqualTo: leagueId)
          .get();

      print('  Grup sayısı: ${groups.docs.length}');

      for (final groupDoc in groups.docs.take(2)) {
        final groupId = groupDoc.id;
        final groupName = groupDoc.data()['name'] ?? 'Bilinmiyor';

        final groupMatches = await db
            .collection('matches')
            .where('leagueId', isEqualTo: leagueId)
            .where('groupId', isEqualTo: groupId)
            .get();

        print('\n  Grup: $groupName (ID: $groupId)');
        print('    Maç sayısı: ${groupMatches.docs.length}');

        if (groupMatches.docs.isNotEmpty) {
          final firstMatch = groupMatches.docs.first.data();
          print('    İlk maç status: ${firstMatch['status']}');
          print(
            '    İlk maç skor: ${firstMatch['homeScore']} - ${firstMatch['awayScore']}',
          );
        }
      }
    }

    print('\n═════════════════════════════════════════════════');
    print('Kontrol Tamamlandı');
    print('═════════════════════════════════════════════════\n');
  } catch (e) {
    print('❌ Hata: $e');
  }
}
