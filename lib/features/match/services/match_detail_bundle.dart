import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_settings.dart';

/// Maç detayı tek istekte (bkz. 20261113130000_match_detail_bundle.sql).
///
/// Ekran açılırken [start] çağrılır. Servislerin ilk okumaları (olaylar,
/// esame, medya, gol kesitleri, iki takımın kadrosu, sezon ayarları, maç
/// durumu) ağa gitmeden önce bu cevabı bekler ve kullanır; ~12 istek yerine
/// tek istek gider. Her parça bir kez kullanılır: sonraki okumalar (canlı
/// güncelleme, yenileme) yine sunucudan yapılır. Paket kısa süre geçerlidir
/// ve bu cihaz maça yazınca unutulur. Paket alınamazsa servisler eskisi gibi
/// kendi sorgularını atar.
class MatchDetailBundle {
  MatchDetailBundle._();

  /// Bu süreden sonra paket kullanılmaz (servisler sunucudan okur).
  static const _validFor = Duration(seconds: 20);

  /// Paket bundan uzun sürerse servisler beklemeden kendi sorgularını atar.
  static const _wait = Duration(seconds: 6);

  /// Paketteki maç durumu yalnız ekran açılırken kullanılır (akışların ilk
  /// bağlanışı); sonrasında durum sunucudan okunur (maç bu arada
  /// başlatılmış / bitirilmiş olabilir).
  static const _statusFor = Duration(seconds: 8);

  static final Map<String, _Entry> _entries = {};

  /// Kapı: herkese açık değilse yalnız admin (bkz.
  /// [AppSettings.matchBundleEnabled]).
  static bool enabled({required bool isAdmin}) =>
      isAdmin || AppSettings.matchBundleEnabled.value;

  /// Maçın paketini istemeye başlar (zaten yükleniyorsa bir şey yapmaz).
  static void start(String matchId, String seasonId) {
    final id = matchId.trim();
    if (id.isEmpty) return;
    final e = _entries[id];
    if (e != null && !e.expired) return;
    _entries.removeWhere((_, v) => v.expired);
    final data = Supabase.instance.client
        .rpc('match_detail_bundle', params: {'p_match_id': id})
        .then<Map<String, dynamic>?>(
          (v) => v is Map ? Map<String, dynamic>.from(v) : null,
        )
        .catchError((Object _) => null);
    _entries[id] = _Entry(data, seasonId.trim());
  }

  /// Bu cihaz maça yazdı: paket artık eski.
  static void forget(String matchId) => _entries.remove(matchId.trim());

  /// Paketin [part] parçası (bir kez); paket yoksa, süresi geçtiyse ya da
  /// parça daha önce kullanıldıysa `null` (çağıran sunucudan okur).
  /// [key] verilirse parçanın içindeki o anahtar (ör. takım kimliği).
  /// [seasonId] verilirse paketin sezonu da tutmalı.
  static Future<Object?> take(
    String matchId,
    String part, {
    String? key,
    String? seasonId,
  }) async {
    final e = _entries[matchId.trim()];
    final slot = key == null ? part : '$part:$key';
    if (e == null || e.expired || e.used.contains(slot)) return null;
    if (seasonId != null && seasonId.trim() != e.seasonId) return null;
    e.used.add(slot);
    final data = await e.data.timeout(_wait, onTimeout: () => null);
    final v = data?[part];
    if (key == null) return v;
    return v is Map ? v[key] : null;
  }

  /// Sezona ait yüklenen paketin [part] parçası (bir kez; ör. sezon
  /// ayarları, maç kimliği bilinmeden istenir).
  static Future<Object?> takeForSeason(String seasonId, String part) async {
    final sid = seasonId.trim();
    if (sid.isEmpty) return null;
    for (final m in _entries.entries) {
      final e = m.value;
      if (e.seasonId == sid && !e.expired && !e.used.contains(part)) {
        return take(m.key, part);
      }
    }
    return null;
  }

  /// Paketteki maç durumu (birden çok akış kullanabilir); paket yoksa
  /// `null`.
  static Future<String?> status(String matchId) async {
    final e = _entries[matchId.trim()];
    if (e == null || DateTime.now().difference(e.at) > _statusFor) return null;
    final data = await e.data.timeout(_wait, onTimeout: () => null);
    final m = data?['match'];
    if (m is! Map) return null;
    return (m['status'] ?? '').toString().trim();
  }
}

class _Entry {
  _Entry(this.data, this.seasonId);

  final Future<Map<String, dynamic>?> data;
  final String seasonId;
  final DateTime at = DateTime.now();
  final Set<String> used = {};

  bool get expired =>
      DateTime.now().difference(at) > MatchDetailBundle._validFor;
}
