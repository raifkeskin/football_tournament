import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'consent_texts.dart';

/// Oyuncunun onay durumu ve yürürlükteki metinler.
class MyConsents {
  const MyConsents({
    required this.doc,
    required this.granted,
    required this.complete,
    required this.lastAt,
  });

  /// Yürürlükteki metin sürümü ve kutuları (sunucudan).
  final ConsentDoc doc;

  /// Ekranda işaretli gelecek kutular: bu sürümle verilmiş onaylar; isteğe
  /// bağlı kutularda önceki sürümle verilmiş izin de korunur (kaydet'e basınca
  /// fotoğraf yanlışlıkla gizlenmesin).
  final Set<String> granted;

  /// Zorunlu onaylar tamam mı (sunucu kuralı: eski sürüm eski sezonlar için
  /// geçerli, yeni sürümden sonra açılan sezon yeni metni ister).
  final bool complete;
  final DateTime? lastAt;
}

/// Kadro / lisans ekranları için oyuncu bazında durum.
class ConsentStatus {
  const ConsentStatus({required this.hasAccount, required this.complete});

  final bool hasAccount;
  final bool complete;
}

class ConsentService {
  SupabaseClient get _sb => Supabase.instance.client;

  static ConsentDoc? _docCache;

  /// Yürürlükteki metinler. Sunucuya ulaşılamazsa uygulamadaki ilk sürüm.
  Future<ConsentDoc> loadDoc({bool refresh = false}) async {
    final cached = _docCache;
    if (cached != null && !refresh) return cached;
    try {
      final version = (await _sb.rpc('current_consent_version')).toString();
      final rows = await _sb
          .from('consent_items')
          .select('key, title, checkbox, body, required')
          .eq('version', version)
          .order('sort_order');
      final items = [for (final r in rows) ConsentItem.fromRow(r)];
      if (items.isEmpty) return cached ?? kFallbackConsentDoc;
      return _docCache = ConsentDoc(version: version, items: items);
    } catch (_) {
      return cached ?? kFallbackConsentDoc;
    }
  }

  Future<MyConsents> loadMine(String playerId) async {
    final results = await Future.wait<Object?>([
      loadDoc(refresh: true),
      _sb
          .from('player_consents')
          .select('consent_type, granted, version, created_at')
          .eq('player_id', playerId)
          .order('created_at', ascending: false)
          .then<Object?>((r) => r),
      _sb
          .rpc(
            'player_consent_status',
            params: {
              'p_player_ids': [playerId],
            },
          )
          .then<Object?>((r) => r),
    ]);
    final doc = results[0] as ConsentDoc;
    final rows = results[1] as List;
    final status = results[2] as List;

    final seen = <String>{};
    final granted = <String>{};
    DateTime? lastAt;
    for (final r in rows.cast<Map>()) {
      final key = (r['consent_type'] ?? '').toString();
      lastAt ??= DateTime.tryParse((r['created_at'] ?? '').toString());
      if (!seen.add(key)) continue; // yalnızca en son kayıt
      if (r['granted'] != true) continue;
      final item = doc.item(key);
      if (item == null) continue;
      if (r['version'] == doc.version || !item.required) granted.add(key);
    }
    final complete = status.isNotEmpty && status.first['complete'] == true;
    return MyConsents(
      doc: doc,
      granted: granted,
      complete: complete,
      lastAt: lastAt?.toLocal(),
    );
  }

  Future<void> save(String playerId, ConsentDoc doc, Set<String> granted) {
    final agent = kIsWeb ? 'web' : defaultTargetPlatform.name;
    if (doc.version == kFallbackConsentVersion) {
      // Sunucu metinleri okunamadıysa ilk sürümün kutuları gösterildi.
      return _sb.rpc(
        'give_player_consents',
        params: {
          'p_player_id': playerId,
          'p_privacy': granted.contains('privacy_notice'),
          'p_health': granted.contains('health_data'),
          'p_declaration': granted.contains('health_declaration'),
          'p_photo': granted.contains('photo_publish'),
          'p_version': doc.version,
          'p_user_agent': agent,
        },
      );
    }
    return _sb.rpc(
      'give_player_consents_v2',
      params: {
        'p_player_id': playerId,
        'p_version': doc.version,
        'p_choices': {
          for (final i in doc.items) i.key: granted.contains(i.key),
        },
        'p_user_agent': agent,
      },
    );
  }

  /// Yetkisi olmayan oyuncular için satır dönmez; onlar sonuçta yer almaz.
  Future<Map<String, ConsentStatus>> statusOf(
    Iterable<String> playerIds,
  ) async {
    final ids = playerIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await _sb.rpc(
      'player_consent_status',
      params: {'p_player_ids': ids},
    );
    return {
      for (final r in (rows as List))
        (r['player_id'] ?? '').toString(): ConsentStatus(
          hasAccount: r['has_account'] == true,
          complete: r['complete'] == true,
        ),
    };
  }
}
