import 'package:flutter/foundation.dart';

/// Giriş yapan kişinin görebileceği turnuvalar (`my_league_ids`). Admin,
/// misafir ve henüz hiçbir turnuvada olmayan kullanıcı için null: hepsi.
/// Turnuva listesi (watchLeagues) ve haber akışı bu kapsama göre süzülür.
class LeagueScope {
  LeagueScope._();

  static final ids = ValueNotifier<Set<String>?>(null);

  static bool allows(String? leagueId) {
    final s = ids.value;
    return s == null || (leagueId != null && s.contains(leagueId));
  }
}
