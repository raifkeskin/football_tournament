import 'package:flutter/material.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
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
  ConsentSummaryBanner({
    super.key,
    required Map<String, ConsentStatus> statuses,
  }) : _missing = statuses.values.where((s) => !s.complete).length,
       _noAccount = statuses.values
           .where((s) => !s.complete && !s.hasAccount)
           .length;

  /// Sayılar sunucudan geldiğinde (Lisans Yönetimi).
  const ConsentSummaryBanner.counts({
    super.key,
    required int missing,
    required int noAccount,
  }) : _missing = missing,
       _noAccount = noAccount;

  final int _missing;
  final int _noAccount;

  @override
  Widget build(BuildContext context) {
    final missingCount = _missing;
    if (missingCount == 0) return const SizedBox.shrink();
    final noAccount = _noAccount;
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
              '• $missingCount oyuncudan KVKK / sağlık onayı alınmadı.'
              '${noAccount > 0 ? '\n• $noAccount oyuncunun hesabı yok.' : ''}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.4,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: kAdminAmber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        s.hasAccount ? 'Onay yok' : 'Hesap yok',
        style: const TextStyle(
          color: kAdminAmber,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Onay metni gövdesi: "## " ile başlayan satır başlık, "• " ile başlayan
/// satır madde olarak gösterilir; gerisi paragraf.
class ConsentBodyText extends StatelessWidget {
  const ConsentBodyText(
    this.body, {
    super.key,
    this.color = Colors.white70,
    this.fontSize = 13,
  });

  final String body;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final lines = body.trim().split('\n');
    final children = <Widget>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        children.add(const SizedBox(height: 8));
      } else if (line.startsWith('## ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text(
              line.substring(3),
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize + 0.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      } else if (line.startsWith('• ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•  ',
                  style: TextStyle(color: kAdminAccent, fontSize: fontSize),
                ),
                Expanded(
                  child: Text(
                    line.substring(2),
                    style: TextStyle(
                      color: color,
                      fontSize: fontSize,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              line,
              style: TextStyle(color: color, fontSize: fontSize, height: 1.4),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
