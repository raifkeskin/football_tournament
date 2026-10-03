import 'package:flutter/foundation.dart';

import '../../features/tournament/models/season.dart';

class GlobalFilter {
  static final ValueNotifier<String?> leagueId = ValueNotifier(null);
  static final ValueNotifier<String?> seasonId = ValueNotifier(null);
  static final ValueNotifier<String?> groupId = ValueNotifier(null);

  static void setLeague(String? id) {
    if (leagueId.value != id) {
      leagueId.value = id;
      seasonId.value = null; // reset season when league changes
      groupId.value = null;
    }
  }

  static void setSeason(String? id) {
    if (seasonId.value != id) {
      seasonId.value = id;
      groupId.value = null;
    }
  }

  static void setGroup(String? id) {
    if (groupId.value != id) {
      groupId.value = id;
    }
  }
}

/// Fikstür, puan durumu ve istatistik aynı varsayılan sezonu seçsin diye ortak
/// kural: "varsayılan" işaretli → aktif → listedeki ilk (en yeni) sezon.
String pickDefaultSeasonId(List<Season> seasons) {
  for (final s in seasons) {
    if (s.isDefault) return s.id;
  }
  for (final s in seasons) {
    if (s.isActive) return s.id;
  }
  return seasons.first.id;
}
