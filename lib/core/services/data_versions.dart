import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sunucudaki veri sürümleri (bkz. 20261018180000_data_versions.sql).
///
/// Kapsamlar: sezona bağlı veriler için `season:<id>`, genel tablolar için
/// tablo adı (`teams`, `players`, `leagues`, `seasons`, `pitches` ...).
/// Satır değişince sayaç artar; uygulama sayacı değişmeyen veriyi yeniden
/// indirmez.
///
/// Sürümlerle aynı istekte hesabın yetki özeti de gelir (bkz.
/// 20261113120000_access_stamp.sql): sorumlu ataması, gizli turnuvaya kod,
/// kadroya eklenme gibi görünen veriyi değiştiren her şey özeti değiştirir.
/// Özet damgaya girer; değişince saklanan veri geçersiz olur.
///
/// Aynı anda istenen kapsamlar tek sorguda birleşir (açılışta başlayan
/// onlarca akış tek istek atar); sonuç birkaç saniye paylaşılır.
class DataVersions {
  DataVersions._();

  static const _shareFor = Duration(seconds: 5);
  static const _batchWindow = Duration(milliseconds: 30);

  static final Map<String, ({int version, DateTime at})> _known = {};
  static Set<String> _pending = {};
  static Completer<void>? _batch;

  /// Son okunan yetki özeti ve ait olduğu hesap.
  static String? _access;
  static String? _accessUid;

  /// Aynı hesapta yetki özeti değişti (rol, gizli turnuva, kadro): açık
  /// listeler ve hesap bilgisi yeniden okunur. Giriş/çıkışta artmaz (hesap
  /// değişimi ayrıca ele alınıyor).
  static final accessEpoch = ValueNotifier<int>(0);

  static String get _uid =>
      Supabase.instance.client.auth.currentUser?.id ?? 'guest';

  /// Bu cihaz veri yazdı: paylaşılan sürümler unutulur, sonraki damga
  /// sunucudan okunur.
  static void forget() => _known.clear();

  /// Kapsamların şu anki sürümlerinden ve yetki özetinden oluşan damga;
  /// okunamazsa `null`.
  static Future<String?> stamp(Iterable<String> scopes) async {
    final list = scopes.toSet().toList()..sort();
    if (list.isEmpty) return null;
    // Hesap değişti: özet bu hesap için yeniden okunur.
    if (_accessUid != _uid) _known.clear();
    final now = DateTime.now();
    final stale = list.where((s) {
      final k = _known[s];
      return k == null || now.difference(k.at) > _shareFor;
    });
    if (stale.isNotEmpty) {
      _pending.addAll(stale);
      var batch = _batch;
      if (batch == null) {
        batch = _batch = Completer<void>();
        Timer(_batchWindow, _flush);
      }
      try {
        await batch.future;
      } catch (_) {
        return null;
      }
    }
    final versions = list.map((s) => '$s=${_known[s]?.version ?? 0}');
    return '${versions.join('|')}|@=${_access ?? ''}';
  }

  static Future<void> _flush() async {
    final scopes = _pending;
    final batch = _batch!;
    _pending = {};
    _batch = null;
    final uid = _uid;
    final client = Supabase.instance.client;
    try {
      Map<String, dynamic> versions;
      String? access;
      try {
        final res = await client.rpc(
          'data_versions_for',
          params: {'p_scopes': scopes.toList()},
        );
        final m = Map<String, dynamic>.from(res as Map);
        versions = Map<String, dynamic>.from(m['v'] as Map? ?? const {});
        access = m['a']?.toString();
      } on PostgrestException {
        // Sunucuda fonksiyon yoksa (eski veritabanı) yalnız sürümler.
        final rows = await client
            .from('data_versions')
            .select('scope, version')
            .inFilter('scope', scopes.toList());
        versions = {for (final r in rows) r['scope'].toString(): r['version']};
      }
      final now = DateTime.now();
      // Hiç değişmemiş kapsamın satırı yoktur: sürüm 0.
      for (final s in scopes) {
        _known[s] = (version: (versions[s] as num?)?.toInt() ?? 0, at: now);
      }
      _setAccess(uid, access);
      batch.complete();
    } catch (e) {
      batch.completeError(e);
    }
  }

  static void _setAccess(String uid, String? access) {
    final changed =
        _accessUid == uid &&
        _access != null &&
        access != null &&
        _access != access;
    _accessUid = uid;
    _access = access;
    if (changed) accessEpoch.value++;
  }
}

/// Cihazda saklanan, sürüm damgasıyla doğrulanan sorgu sonucu.
///
/// Kullanım: saklanan veri hemen gösterilir ([peek]); [unchanged] true ise
/// sunucuya sorgu atılmaz. Okuma gerekiyorsa damga ([DataVersions.stamp])
/// veriyle aynı anda istenir ve birlikte kaydedilir ([save]). İkisi arasına
/// denk gelen nadir bir değişiklik, sezondaki bir sonraki değişiklikte ya da
/// en geç [maxAge] sonra yakalanır.
///
/// Veri görünürlüğü hesaba bağlı olduğundan (gizli turnuva vb.) anahtar
/// kullanıcıya göre ayrılır; yetki değişikliği damgadaki yetki özetiyle
/// yakalanır. [maxAge] yalnızca damga ile veri arasına denk gelen nadir
/// değişikliğe karşı üst sınırdır.
class VersionedCache {
  VersionedCache._();

  static const maxAge = Duration(days: 3);
  static final Map<String, ({String? stamp, DateTime at})> _meta = {};

  static String _key(String key) {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
    return 'vc1:$uid:$key';
  }

  /// Saklanan veri (sürümüne bakılmaksızın); yoksa `null`.
  static Future<Object?> peek(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(key));
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _meta[_key(key)] = (
        stamp: m['s'] as String?,
        at: DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt()),
      );
      return m['d'];
    } catch (_) {
      return null;
    }
  }

  /// Saklanan verinin sunucudaki sürümle aynı (ve yeterince yeni) olup
  /// olmadığı. Bellekte tutulan son okumanın damgası da kullanılır.
  static Future<bool> unchanged(String key, Iterable<String> scopes) async {
    if (!_meta.containsKey(_key(key))) await peek(key);
    final meta = _meta[_key(key)];
    if (meta == null || meta.stamp == null) return false;
    if (DateTime.now().difference(meta.at) > maxAge) return false;
    final now = await DataVersions.stamp(scopes);
    return now != null && now == meta.stamp;
  }

  /// [stamp] veriyle birlikte alınmış damga. [persist] false ise yalnızca
  /// bellekte tutulur (kişisel veri cihaza yazılmaz).
  static Future<void> save(
    String key,
    Object data,
    String? stamp, {
    bool persist = true,
  }) async {
    final at = DateTime.now();
    _meta[_key(key)] = (stamp: stamp, at: at);
    if (!persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(key),
        jsonEncode({'s': stamp, 't': at.millisecondsSinceEpoch, 'd': data}),
      );
    } catch (_) {}
  }
}
