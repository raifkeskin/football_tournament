import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Afişlerin varsayılan zemin fotoğrafı (maç ve fikstür afişleri).
const kDefaultPosterPhoto = AssetImage('assets/anasayfa.jpg');

/// Turnuvanın afiş arka planı (`leagues.poster_bg_url`). Turnuva başına tek
/// görseldir; şimdilik yalnızca admin yükler (Yönetim Paneli › Afiş Arka
/// Planı).
class PosterBackgrounds {
  PosterBackgrounds._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Turnuva id → görsel adresi ('' = yüklenmemiş).
  static final Map<String, String> _byLeague = {};

  /// Sezon id → turnuva id.
  static final Map<String, String> _leagueBySeason = {};

  /// Afişi açarken okunur; hata olursa varsayılan zemin kullanılır.
  static Future<String?> resolve({String? leagueId, String? seasonId}) async {
    try {
      var lid = (leagueId ?? '').trim();
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
      // Admin başka cihazda değiştirmiş olabilir: her afişte taze okunur
      // (tek sütun, küçük sorgu).
      final row = await _sb
          .from('leagues')
          .select('poster_bg_url')
          .eq('id', lid)
          .maybeSingle();
      final url = (row?['poster_bg_url'] ?? '').toString().trim();
      _byLeague[lid] = url;
      return url.isEmpty ? null : url;
    } catch (e) {
      debugPrint('Afiş arka planı okunamadı: $e');
      final lid = (leagueId ?? '').trim();
      final cached = _byLeague[lid] ?? '';
      return cached.isEmpty ? null : cached;
    }
  }

  static void remember(String leagueId, String? url) =>
      _byLeague[leagueId] = (url ?? '').trim();
}

/// Afişin altındaki ağaca turnuvanın zemin görselini taşır.
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
