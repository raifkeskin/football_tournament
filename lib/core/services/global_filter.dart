import 'package:flutter/foundation.dart';

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
