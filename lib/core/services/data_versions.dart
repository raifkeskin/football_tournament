import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sunucudaki veri sürümleri (bkz. 20261018180000_data_versions.sql).
///
/// Kapsamlar: sezona bağlı veriler için `season:<id>`, genel tablolar için
/// tablo adı (`teams`, `players`, `leagues`, `seasons`, `pitches` ...).
/// Satır değişince sayaç artar; uygulama sayacı değişmeyen veriyi yeniden
/// indirmez.
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

  /// Kapsamların şu anki sürümlerinden oluşan damga; okunamazsa `null`.
  static Future<String?> stamp(Iterable<String> scopes) async {
    final list = scopes.toSet().toList()..sort();
    if (list.isEmpty) return null;
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
    return list.map((s) => '$s=${_known[s]?.version ?? 0}').join('|');
  }

  static Future<void> _flush() async {
    final scopes = _pending;
    final batch = _batch!;
    _pending = {};
    _batch = null;
    try {
      final rows = await Supabase.instance.client
          .from('data_versions')
          .select('scope, version')
          .inFilter('scope', scopes.toList());
      final now = DateTime.now();
      // Hiç değişmemiş kapsamın satırı yoktur: sürüm 0.
      for (final s in scopes) {
        _known[s] = (version: 0, at: now);
      }
      for (final r in rows) {
        _known[r['scope'].toString()] = (
          version: (r['version'] as num).toInt(),
          at: now,
        );
      }
      batch.complete();
    } catch (e) {
      batch.completeError(e);
    }
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
/// kullanıcıya göre ayrılır; yetki değişikliği sürümü artırmadığı için
/// saklanan veri en fazla [maxAge] kullanılır.
class VersionedCache {
  VersionedCache._();

  static const maxAge = Duration(hours: 12);
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
