import 'package:flutter/material.dart';

import '../../../core/widgets/admin_form.dart';
import 'consent_service.dart';

/// Oyuncu listelerinde (kadro, lisans) onay durumunu bir kez yükler; aynı
/// oyuncu kümesi için tekrar sorgu atmaz.
class ConsentStatusCache {
  final _service = ConsentService();
  String? _key;
  Future<Map<String, ConsentStatus>>? _future;

  Future<Map<String, ConsentStatus>> of(Iterable<String> playerIds) {
    final ids = playerIds.toSet().toList()..sort();
    final key = ids.join(',');
    if (key != _key || _future == null) {
      _key = key;
      _future = _service
          .statusOf(ids)
          .catchError((_) => const <String, ConsentStatus>{});
    }
    return _future!;
  }
}

/// "X oyuncudan onay alınmadı" bilgisi. Yetkisi olmayan kullanıcıya durum
/// dönmediği için hiçbir şey göstermez.
class ConsentSummaryBanner extends StatelessWidget {
  const ConsentSummaryBanner({super.key, required this.statuses});

  final Map<String, ConsentStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final missing = statuses.values.where((s) => !s.complete).toList();
    if (missing.isEmpty) return const SizedBox.shrink();
    final noAccount = missing.where((s) => !s.hasAccount).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: kAdminAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kAdminAmber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.privacy_tip_outlined, color: kAdminAmber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${missing.length} oyuncudan KVKK / sağlık onayı alınmadı'
              '${noAccount > 0 ? ' ($noAccount oyuncunun hesabı yok)' : ''}.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Oyuncu kartındaki küçük etiket: onay yoksa "Onay yok" / "Hesap yok".
class ConsentChip extends StatelessWidget {
  const ConsentChip({super.key, required this.status});

  final ConsentStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null || s.complete) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: kAdminAmber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        s.hasAccount ? 'Onay yok' : 'Hesap yok',
        style: const TextStyle(
          color: kAdminAmber,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
