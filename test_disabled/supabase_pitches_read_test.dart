import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:football_tournament/config/app_config.dart';
import 'package:football_tournament/services/league_service.dart';

void main() {
  test('pitches Supabase üzerinden okunuyor (Firebase seed görmezden gelinir)', () async {
    AppConfig.activeDatabase = DatabaseType.supabase;
    AppConfig.dbLogEnabled = false;

    final firestore = FakeFirebaseFirestore();
    await firestore.collection('pitches').add({'name': 'FIREBASE_PITCH'});

    final svc = FirebaseLeagueService(
      firestore: firestore,
      supabaseSelectPitches: () async {
        return const [
          {'name': 'SUPABASE_PITCH'},
        ];
      },
    );

    final names = await svc.listPitchesOnce();
    expect(names, equals(const ['SUPABASE_PITCH']));
  });
}
