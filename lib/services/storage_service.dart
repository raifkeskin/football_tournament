import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

/// Firebase Storage yükleme işlemleri için servis iskeleti.
class StorageService {
  StorageService({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Turnuva logosunu `league_logos/` altında saklar.
  Future<String> uploadLeagueLogo({
    required String leagueId,
    required File file,
  }) async {
    final ref = _storage.ref().child(
      'league_logos/$leagueId-${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final task = await ref.putFile(file);
    return task.ref.getDownloadURL();
  }

  /// Takım logosunu `team_logos/` altında saklar.
  Future<String> uploadTeamLogo({
    required String teamId,
    required File file,
  }) async {
    final ref = _storage.ref().child(
      'team_logos/$teamId-${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final task = await ref.putFile(file);
    return task.ref.getDownloadURL();
  }
}
