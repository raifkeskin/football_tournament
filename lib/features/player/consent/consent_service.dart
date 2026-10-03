import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'consent_texts.dart';

/// Oyuncunun güncel onayları (her türün en son kaydı).
class MyConsents {
  const MyConsents({required this.granted, required this.lastAt});

  /// Güncel versiyonla verilmiş onaylar.
  final Set<ConsentType> granted;
  final DateTime? lastAt;

  bool get complete => kConsentTexts
      .where((t) => t.required)
      .every((t) => granted.contains(t.type));
}

/// Kadro / lisans ekranları için oyuncu bazında durum.
class ConsentStatus {
  const ConsentStatus({required this.hasAccount, required this.complete});

  final bool hasAccount;
  final bool complete;
}

class ConsentService {
  SupabaseClient get _sb => Supabase.instance.client;

  Future<MyConsents> loadMine(String playerId) async {
    final rows = await _sb
        .from('player_consents')
        .select('consent_type, granted, version, created_at')
        .eq('player_id', playerId)
        .order('created_at', ascending: false);
    final seen = <String>{};
    final granted = <ConsentType>{};
    DateTime? lastAt;
    for (final r in rows) {
      final type = (r['consent_type'] ?? '').toString();
      lastAt ??= DateTime.tryParse((r['created_at'] ?? '').toString());
      if (!seen.add(type)) continue; // yalnızca en son kayıt
      if (r['granted'] != true || r['version'] != kConsentVersion) continue;
      for (final t in ConsentType.values) {
        if (t.db == type) granted.add(t);
      }
    }
    return MyConsents(granted: granted, lastAt: lastAt?.toLocal());
  }

  Future<void> save(String playerId, Set<ConsentType> granted) {
    return _sb.rpc(
      'give_player_consents',
      params: {
        'p_player_id': playerId,
        'p_privacy': granted.contains(ConsentType.privacyNotice),
        'p_health': granted.contains(ConsentType.healthData),
        'p_declaration': granted.contains(ConsentType.healthDeclaration),
        'p_photo': granted.contains(ConsentType.photoPublish),
        'p_version': kConsentVersion,
        'p_user_agent': kIsWeb ? 'web' : defaultTargetPlatform.name,
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
