import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Afişlerin varsayılan zemin fotoğrafı (maç ve fikstür afişleri).
const kDefaultPosterPhoto = AssetImage('assets/anasayfa.jpg');

/// Arka plan alan afiş türleri. Kadro, esame ve diziliş afişleri takım
/// rengiyle çizilir; arka plan almaz.
enum PosterKind {
  match('match', 'Maç Afişi'),
  fixture('fixture', 'Haftalık Fikstür'),
  results('results', 'Maç Sonuçları'),
  standings('standings', 'Puan Durumu');

  const PosterKind(this.key, this.label);

  /// `leagues.poster_bgs` anahtarı.
  final String key;
  final String label;
}

/// Turnuvanın afiş arka planları: ortak görsel (`leagues.poster_bg_url`) ve
/// afiş türüne özel görseller (`leagues.poster_bgs`). Türün görseli yoksa
/// ortak görsel kullanılır; maç sonuçları önce fikstürünkine bakar. Admin ve
/// kurucu başkan değiştirir (Yönetim Paneli › Afiş Arka Planı).
class PosterBackgrounds {
  PosterBackgrounds._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Turnuva id → (ortak görsel, türe özel görseller).
  static final Map<String, ({String common, Map<String, String> byKind})>
  _byLeague = {};

  /// Sezon id → turnuva id.
  static final Map<String, String> _leagueBySeason = {};

  static Map<String, String> parseKinds(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if ('${e.value ?? ''}'.trim().isNotEmpty)
          '${e.key}': '${e.value}'.trim(),
  };

  /// [kind] türündeki afişin zemini; kayıtlar hiç yoksa null.
  static String? pick(
    PosterKind kind, {
    required String common,
    required Map<String, String> byKind,
  }) {
    final url =
        byKind[kind.key] ??
        (kind == PosterKind.results ? byKind[PosterKind.fixture.key] : null) ??
        common;
    return url.trim().isEmpty ? null : url.trim();
  }

  /// Afişi açarken okunur; hata olursa son bilinen ya da varsayılan zemin.
  static Future<String?> resolve({
    required PosterKind kind,
    String? leagueId,
    String? seasonId,
  }) async {
    var lid = (leagueId ?? '').trim();
    try {
      final sid = (seasonId ?? '').trim();
      if (lid.isEmpty && sid.isNotEmpty) {
        lid = _leagueBySeason[sid] ?? '';
        if (lid.isEmpty) {
          final row = await _sb
              .from('seasons')
              .select('league_id')
              .eq('id', sid)
              .maybeSingle();
          lid = (row?['league_id'] ?? '').toString().trim();
          if (lid.isNotEmpty) _leagueBySeason[sid] = lid;
        }
      }
      if (lid.isEmpty) return null;
      // Başka cihazda değişmiş olabilir: her afişte taze okunur (küçük sorgu).
      final row = await _sb
          .from('leagues')
          .select('poster_bg_url, poster_bgs')
          .eq('id', lid)
          .maybeSingle();
      remember(
        lid,
        common: (row?['poster_bg_url'] ?? '').toString(),
        byKind: parseKinds(row?['poster_bgs']),
      );
    } catch (e) {
      debugPrint('Afiş arka planı okunamadı: $e');
    }
    final cached = _byLeague[lid];
    if (cached == null) return null;
    return pick(kind, common: cached.common, byKind: cached.byKind);
  }

  static void remember(
    String leagueId, {
    required String common,
    required Map<String, String> byKind,
  }) => _byLeague[leagueId] = (common: common.trim(), byKind: byKind);
}

class PosterBackground extends InheritedWidget {
  const PosterBackground({
    super.key,
    required this.image,
    required super.child,
  });

  /// Yüklenmiş (ya da yönetim ekranında önizlenen) zemin; null ise afiş kendi
  /// varsayılan zeminini çizer.
  final ImageProvider? image;

  static ImageProvider? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PosterBackground>()?.image;

  /// Fotoğraf zeminli afişler için: turnuvanınki ya da stadyum fotoğrafı.
  static ImageProvider photoOf(BuildContext context) =>
      of(context) ?? kDefaultPosterPhoto;

  @override
  bool updateShouldNotify(PosterBackground old) => old.image != image;
}

/// Düz renk geçişli afişlerin (kadro, diziliş, puan durumu) zemini. Turnuvanın
/// görseli varsa onu çizer, geçişi yarı saydam olarak üstüne koyar ki yazılar
/// okunur kalsın.
class PosterBackdrop extends StatelessWidget {
  const PosterBackdrop({
    super.key,
    required this.colors,
    this.stops,
    this.padding,
    required this.child,
  });

  final List<Color> colors;
  final List<double>? stops;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final image = PosterBackground.of(context);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: image == null
          ? colors
          : [for (final c in colors) c.withValues(alpha: 0.8)],
      stops: stops,
    );
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(gradient: gradient),
      child: child,
    );
    if (image == null) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.last,
        image: DecorationImage(image: image, fit: BoxFit.cover),
      ),
      child: content,
    );
  }
}
