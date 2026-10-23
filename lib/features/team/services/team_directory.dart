import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Takım adı / logosu: yalnız ekranda gösterilen maçların takımları okunur
/// (tüm takımlar indirilmez; turnuva sayısı arttıkça liste büyümez).
/// Okunanlar uygulama açık kaldıkça bellekte tutulur.
class TeamBrief {
  const TeamBrief({
    required this.id,
    required this.name,
    required this.shortName,
    required this.logoUrl,
  });

  final String id;
  final String name;
  final String shortName;
  final String logoUrl;
}

class TeamDirectory {
  TeamDirectory._();

  /// Bilinen takımlar; yenileri gelince dinleyenler yeniden çizilir.
  static final ValueNotifier<Map<String, TeamBrief>> known = ValueNotifier(
    const {},
  );

  /// Okunmuş ama bulunamamış (silinmiş / yetkisiz) takımlar: tekrar sorulmaz.
  static final Set<String> _absent = {};
  static final Set<String> _inFlight = {};

  /// [ids] içinden henüz okunmamış olanlar.
  static List<String> missing(Iterable<String> ids) => [
    for (final id in {...ids})
      if (id.isNotEmpty &&
          !known.value.containsKey(id) &&
          !_absent.contains(id))
        id,
  ];

  /// Eksik takımları okur (150'şer); tamamlanınca [known] güncellenir.
  static Future<void> ensure(Iterable<String> ids) async {
    final todo = [
      for (final id in missing(ids))
        if (!_inFlight.contains(id)) id,
    ];
    if (todo.isEmpty) return;
    _inFlight.addAll(todo);
    try {
      final next = {...known.value};
      for (var i = 0; i < todo.length; i += 150) {
        final part = todo.sublist(
          i,
          i + 150 > todo.length ? todo.length : i + 150,
        );
        final rows = await Supabase.instance.client
            .from('teams')
            .select('id, name, short_name, logo_url')
            .inFilter('id', part);
        final got = <String>{};
        for (final r in rows) {
          final id = (r['id'] ?? '').toString();
          got.add(id);
          next[id] = TeamBrief(
            id: id,
            name: (r['name'] ?? '').toString(),
            shortName: (r['short_name'] ?? '').toString(),
            logoUrl: (r['logo_url'] ?? '').toString(),
          );
        }
        _absent.addAll(part.where((id) => !got.contains(id)));
      }
      known.value = next;
    } catch (e) {
      debugPrint('Takım bilgisi okunamadı: $e');
      // Bağlantı yoksa bekletmeyelim: ad yerine yedek metin gösterilir.
      _absent.addAll(todo);
      known.value = {...known.value};
    } finally {
      _inFlight.removeAll(todo);
    }
  }
}
