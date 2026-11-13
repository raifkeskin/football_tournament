import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_settings.dart';
import '../../../core/services/data_versions.dart';
import '../../player/player_columns.dart';

/// Maç detayı tek istekte (bkz. 20261113130000_match_detail_bundle.sql).
///
/// Ekran açılırken [start] çağrılır. Servislerin ilk okumaları (olaylar,
/// esame, medya, gol kesitleri, iki takımın kadrosu, sezon ayarları, maç
/// durumu) ağa gitmeden önce bu cevabı bekler ve kullanır; ~12 istek yerine
/// tek istek gider. Her parça bir kez kullanılır: sonraki okumalar (canlı
/// güncelleme, yenileme) yine sunucudan yapılır. Paket kısa süre geçerlidir
/// ve bu cihaz maça yazınca unutulur. Paket alınamazsa servisler eskisi gibi
/// kendi sorgularını atar.
///
/// Bitmiş maçın paketi cihazda saklanır ve sonraki açılışta beklemeden
/// gösterilir; maç değiştiyse (`match:<id>` sürümü, bkz.
/// 20261113140000_match_version.sql) arkadan yenilenir.
///
/// Cihaza yazılanlar (kişisel veri): yalnız ekranda herkesin gördüğü ad,
/// soyad, forma numarası, fotoğraf linki ve mevki. Doğum tarihi, hesap
/// bağlantısı vb. yazılmaz ([playerDetails] ile okunur, bellekte kalır).
/// Kopya hesaba özeldir, yetkisi değişen hesaba gösterilmez, çıkışta silinir
/// (bkz. [VersionedCache.personalPrefix]) ve en fazla [_maxStored] maç
/// tutulur.
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

  /// Cihazda en fazla bu kadar bitmiş maç saklanır (en eskisi silinir).
  static const _maxStored = 15;

  /// Bundan büyük paket saklanmaz (ör. çok fotoğraflı maç). Bugünkü
  /// maçlarda kopya ortalama 25 KB, en büyüğü 71 KB.
  static const _maxStoredChars = 80 * 1024;

  /// Cihaza yazılan oyuncu alanları (forma numarası satırın kendisinde).
  static const _storedPlayerFields = [
    'id',
    'name',
    'surname',
    'photo_url',
    'main_position',
  ];

  /// Cihaza yazılmayan oyuncu sütunları ([playerDetails]).
  static final String _detailColumns = kPlayerColumns
      .split(',')
      .map((c) => c.trim())
      .where((c) => c == 'id' || !_storedPlayerFields.contains(c))
      .join(', ');

  /// Paket cihazdaki kopyadan geldi (yalnız bellekte; cihaza yazılmaz).
  static const _kDisk = '_disk';

  static const _indexKey = '${VersionedCache.personalPrefix}match_index';

  static String _diskKey(String id) =>
      '${VersionedCache.personalPrefix}match:$id';

  /// Saklanan kopyayı geçersiz kılan sürümler: maçın kendisi (olay, esame,
  /// medya, kesit), oyuncu kayıtları (ad düzeltme, fotoğrafın kaldırılması),
  /// sezon ayarları ve sezon kadroları.
  static List<String> _scopes(String id) => [
    'match:$id',
    'players',
    'seasons',
    'season_team_players',
  ];

  static final Map<String, _Entry> _entries = {};
  static final List<void Function(String matchId, String seasonId)>
  _onRefreshed = [];

  static SupabaseClient get _db => Supabase.instance.client;
  static String get _uid => _db.auth.currentUser?.id ?? 'guest';

  /// Kapı: herkese açık değilse yalnız admin (bkz.
  /// [AppSettings.matchBundleEnabled]).
  static bool enabled({required bool isAdmin}) =>
      isAdmin || AppSettings.matchBundleEnabled.value;

  /// Cihazdaki kopya gösterildikten sonra maçın değiştiği anlaşıldı ve taze
  /// paket alındı: servisler bu maç için belleklerindeki veriyi bırakıp
  /// yeniden okur (taze paketten).
  static void addRefreshListener(
    void Function(String matchId, String seasonId) listener,
  ) => _onRefreshed.add(listener);

  /// Maçın paketini istemeye başlar (zaten yükleniyorsa bir şey yapmaz).
  static void start(String matchId, String seasonId) {
    final id = matchId.trim();
    if (id.isEmpty) return;
    final uid = _uid;
    final e = _entries[id];
    if (e != null && !e.expired && e.uid == uid) return;
    _entries.removeWhere((_, v) => v.expired);
    _entries[id] = _Entry(_load(id, uid), seasonId.trim(), uid);
  }

  /// Bu cihaz maça yazdı: paket ve cihazdaki kopya artık eski.
  static void forget(String matchId) {
    final id = matchId.trim();
    if (id.isEmpty) return;
    _entries.remove(id);
    unawaited(_unstore(id, _uid));
  }

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
    if (e == null || e.expired || e.uid != _uid || e.used.contains(slot)) {
      return null;
    }
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
    if (e == null || e.uid != _uid) return null;
    if (DateTime.now().difference(e.at) > _statusFor) return null;
    final data = await e.data.timeout(_wait, onTimeout: () => null);
    return data == null ? null : _statusOf(data);
  }

  /// Paket cihazdaki kopyadan geldiyse oyuncuların cihaza yazılmayan
  /// sütunları (oyuncu kimliği → satır): iki takım için tek istek, yalnız
  /// bellekte. Paket sunucudan geldiyse (satırlar zaten tam) ya da
  /// okunamadıysa `null`.
  static Future<Map<String, Map<String, dynamic>>?> playerDetails(
    String matchId,
  ) async {
    final e = _entries[matchId.trim()];
    if (e == null || e.uid != _uid) return null;
    final data = await e.data.timeout(_wait, onTimeout: () => null);
    if (data == null || data[_kDisk] != true) return null;
    return e.details ??= _readPlayerDetails(data);
  }

  static Future<Map<String, Map<String, dynamic>>?> _readPlayerDetails(
    Map<String, dynamic> data,
  ) async {
    final ids = <String>{};
    final teams = data['players'];
    if (teams is Map) {
      for (final team in teams.values) {
        if (team is! Map) continue;
        for (final rows in team.values) {
          if (rows is! List) continue;
          for (final r in rows) {
            final p = r is Map ? r['players'] : null;
            final pid = p is Map ? (p['id'] ?? '').toString() : '';
            if (pid.isNotEmpty) ids.add(pid);
          }
        }
      }
    }
    if (ids.isEmpty) return const {};
    try {
      final rows = await _db
          .from('players')
          .select(_detailColumns)
          .inFilter('id', ids.toList());
      return {
        for (final r in rows)
          (r['id'] ?? '').toString(): Map<String, dynamic>.from(r),
      };
    } catch (_) {
      return null;
    }
  }

  static String _statusOf(Map<String, dynamic> data) {
    final m = data['match'];
    return m is Map ? (m['status'] ?? '').toString().trim() : '';
  }

  /// Önce cihazdaki kopya (bitmiş maç), yoksa sunucu.
  static Future<Map<String, dynamic>?> _load(String id, String uid) async {
    final key = _diskKey(id);
    final cached = await VersionedCache.peek(key);
    if (uid != _uid) return null;
    if (cached is Map) {
      final copy = Map<String, dynamic>.from(cached)..[_kDisk] = true;
      if (VersionedCache.servable(key)) {
        // Beklemeden gösterilir; maç değiştiyse arkadan yenilenir.
        unawaited(_revalidate(id, uid));
        return copy;
      }
      // Yetki özeti henüz bilinmiyor ya da kopya eski: önce doğrulanır.
      if (await VersionedCache.unchanged(key, _scopes(id))) return copy;
    }
    return (await _fetch(id, uid)).data;
  }

  /// Paketi sunucudan okur; bitmiş maçsa cihaza kaydeder. `ok` false:
  /// okunamadı (ör. bağlantı yok).
  static Future<({bool ok, Map<String, dynamic>? data})> _fetch(
    String id,
    String uid,
  ) async {
    // Sürüm, veriyle aynı anda istenir (fazladan tur yok).
    final stampF = DataVersions.stamp(_scopes(id));
    Map<String, dynamic>? data;
    try {
      final v = await _db.rpc(
        'match_detail_bundle',
        params: {'p_match_id': id},
      );
      data = v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return (ok: false, data: null);
    }
    final stamp = await stampF;
    if (data != null && stamp != null && _statusOf(data) == 'finished') {
      unawaited(_store(id, uid, data, stamp));
    } else {
      // Görünmüyor, bitmemiş ya da sürümü okunamadı: kopya tutulmaz.
      unawaited(_unstore(id, uid));
    }
    return (ok: true, data: data);
  }

  /// Cihazdaki kopya gösterildi; sürüm değiştiyse taze paket alınır ve
  /// servislere haber verilir.
  static Future<void> _revalidate(String id, String uid) async {
    if (await VersionedCache.unchanged(_diskKey(id), _scopes(id))) return;
    final fresh = await _fetch(id, uid);
    // Okunamadıysa (bağlantı yok) kopya gösterilmeye devam eder.
    if (!fresh.ok || uid != _uid) return;
    final old = _entries[id];
    if (old != null) {
      _entries[id] = _Entry(Future.value(fresh.data), old.seasonId, uid);
    }
    for (final listener in List.of(_onRefreshed)) {
      try {
        listener(id, old?.seasonId ?? '');
      } catch (_) {}
    }
  }

  /// Cihaza yazılan hâl: maçın yalnız durumu, oyuncuların yalnız görünen
  /// alanları; inceleyen hesabın kimliği yazılmaz.
  static Map<String, dynamic> _forDisk(Map<String, dynamic> b) {
    List<Map<String, dynamic>> slim(Object? rows) => [
      if (rows is List)
        for (final r in rows)
          if (r is Map && r['players'] is Map)
            {
              'jersey_number': r['jersey_number'],
              'players': {
                for (final f in _storedPlayerFields)
                  f: (r['players'] as Map)[f],
              },
            },
    ];
    final teams = b['players'];
    final highlights = b['highlights'];
    return {
      'match': {'status': _statusOf(b)},
      'events': b['events'],
      'rosters': b['rosters'],
      'media': b['media'],
      'highlights': [
        if (highlights is List)
          for (final h in highlights)
            if (h is Map) Map<String, dynamic>.from(h)..remove('reviewed_by'),
      ],
      'settings': b['settings'],
      'players': {
        if (teams is Map)
          for (final t in teams.entries)
            if (t.value is Map)
              t.key.toString(): {
                'squad': slim((t.value as Map)['squad']),
                'played': slim((t.value as Map)['played']),
              },
      },
    };
  }

  // Saklama işlemleri sırayla yürür (dizin okuma-yazması çakışmasın).
  static Future<void> _queue = Future.value();

  static Future<void> _serial(Future<void> Function() job) {
    final next = _queue.then((_) => job()).catchError((Object _) {});
    _queue = next;
    return next;
  }

  /// Saklanan maçların kimlikleri, eskiden yeniye.
  static Future<List<String>> _index() async {
    final v = await VersionedCache.peek(_indexKey);
    return [
      if (v is List)
        for (final x in v) x.toString(),
    ];
  }

  static Future<void> _store(
    String id,
    String uid,
    Map<String, dynamic> data,
    String stamp,
  ) => _serial(() async {
    if (uid != _uid) return;
    final slim = _forDisk(data);
    final ids = await _index();
    if (uid != _uid) return;
    ids.remove(id);
    if (jsonEncode(slim).length > _maxStoredChars) {
      await VersionedCache.remove(_diskKey(id));
    } else {
      await VersionedCache.save(_diskKey(id), slim, stamp);
      ids.add(id);
    }
    while (ids.length > _maxStored) {
      await VersionedCache.remove(_diskKey(ids.removeAt(0)));
    }
    await VersionedCache.save(_indexKey, ids, null);
  });

  static Future<void> _unstore(String id, String uid) => _serial(() async {
    if (uid != _uid) return;
    final ids = await _index();
    if (uid != _uid || !ids.remove(id)) return;
    await VersionedCache.remove(_diskKey(id));
    await VersionedCache.save(_indexKey, ids, null);
  });
}

class _Entry {
  _Entry(this.data, this.seasonId, this.uid);

  final Future<Map<String, dynamic>?> data;
  final String seasonId;

  /// Paketi isteyen hesap; başka hesaba verilmez.
  final String uid;
  final DateTime at = DateTime.now();
  final Set<String> used = {};

  /// Cihazdaki kopyada olmayan oyuncu sütunları (bir kez okunur).
  Future<Map<String, Map<String, dynamic>>?>? details;

  bool get expired =>
      DateTime.now().difference(at) > MatchDetailBundle._validFor;
}
