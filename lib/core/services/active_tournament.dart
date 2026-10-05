import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uygulamanın büründüğü turnuva kimliği (logo, ad, renkler).
@immutable
class TournamentTheme {
  const TournamentTheme({
    required this.leagueId,
    required this.name,
    required this.logoUrl,
    required this.primary,
    required this.secondary,
  });

  final String leagueId;

  /// Bantta görünen ad (kısa ad varsa o).
  final String name;
  final String logoUrl;
  final Color primary;
  final Color secondary;

  /// Bant gradyanının koyu kenarları.
  Color get primaryDark => Color.lerp(primary, Colors.black, 0.45)!;

  static Color? _hex(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(s)) return null;
    return Color(int.parse('FF${s.substring(1)}', radix: 16));
  }

  static String _toHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// `leagues` satırından; tema rengi tanımlı değilse null.
  static TournamentTheme? fromRow(Map<String, dynamic> r) {
    final p = _hex(r['theme_primary']);
    if (p == null) return null;
    final short = (r['short_name'] ?? '').toString().trim();
    return TournamentTheme(
      leagueId: (r['id'] ?? '').toString(),
      name: short.isNotEmpty ? short : (r['name'] ?? '').toString().trim(),
      logoUrl: (r['logo_url'] ?? '').toString().trim(),
      primary: p,
      secondary: _hex(r['theme_secondary']) ?? Colors.white,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': leagueId,
    'short_name': name,
    'logo_url': logoUrl,
    'theme_primary': _toHex(primary),
    'theme_secondary': _toHex(secondary),
  };
}

/// Uygulama hangi turnuvanın kimliğiyle açılsın? Soru sorulmadan:
/// 1. Giriş yapmış kişi: kendi turnuvası (`my_preferred_league`: oyuncu,
///    takım sorumlusu, kurucu başkan, takipçi).
/// 2. Misafir: en son seçip baktığı turnuva (cihazda saklanır).
/// 3. Hiçbiri yoksa ya da turnuvanın teması yoksa: genel TVL görünümü.
/// Son tema cihazda saklanır; açılış ekranı beklemeden boyanır.
class ActiveTournament {
  ActiveTournament._();

  static final theme = ValueNotifier<TournamentTheme?>(null);

  static const _kTheme = 'active_tournament_theme';
  static const _kGuestLeague = 'guest_last_league';

  /// Misafir modu seçildi mi (GuestMode ile aynı anahtar).
  static const _kGuestChosen = 'guest_mode_chosen';

  /// Üst üste gelen refresh çağrılarında yalnızca sonuncusu uygulanır.
  static int _generation = 0;

  static SupabaseClient get _sb => Supabase.instance.client;

  static bool get _isRealUser {
    final u = _sb.auth.currentUser;
    return u != null && !u.isAnonymous;
  }

  /// Saklanan son temayı yükler (main'de, runApp'ten önce). Giriş yapılmamış
  /// ve misafir seçimi de yapılmamışsa (açılışta giriş kapısı çıkacak) uygulama
  /// TVL kimliğiyle açılır; eski tema temizlenir.
  static Future<void> init({required bool guestChosen}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_isRealUser && !guestChosen) {
        theme.value = null;
        await prefs.remove(_kTheme);
        return;
      }
      final raw = prefs.getString(_kTheme);
      if (raw == null) return;
      theme.value = TournamentTheme.fromRow(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {}
  }

  /// Kişiye göre turnuvayı belirler (açılışta ve giriş/çıkışta).
  /// Giriş yapılmamış ve misafir modu seçilmemişse (giriş kapısı) tema
  /// boştur: kapıda hiçbir turnuvanın adı görünmez.
  static Future<void> refresh() async {
    final gen = ++_generation;
    try {
      String? leagueId;
      if (_isRealUser) {
        final res = await _sb.rpc('my_preferred_league');
        leagueId = res?.toString();
      } else {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_kGuestChosen) ?? false) {
          leagueId = prefs.getString(_kGuestLeague);
        }
      }
      await _apply(leagueId, gen: gen);
    } catch (e) {
      debugPrint('Turnuva teması belirlenemedi: $e');
    }
  }

  /// Misafir bir turnuvayı seçip baktığında: uygulama o turnuvaya bürünür.
  /// Giriş yapmış kişide tema kendi turnuvasında kalır.
  static Future<void> noteViewed(String? leagueId) async {
    if (_isRealUser || (leagueId ?? '').isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kGuestLeague) == leagueId) return;
      await prefs.setString(_kGuestLeague, leagueId!);
      await _apply(leagueId);
    } catch (_) {}
  }

  static Future<void> _apply(String? leagueId, {int? gen}) async {
    TournamentTheme? next;
    if ((leagueId ?? '').isNotEmpty) {
      final row = await _sb
          .from('leagues')
          .select(
            'id, name, short_name, logo_url, theme_primary, theme_secondary',
          )
          .eq('id', leagueId!)
          .maybeSingle();
      if (row != null) next = TournamentTheme.fromRow(row);
    }
    // Bu arada daha yeni bir refresh başladıysa onun sonucu geçerli.
    if (gen != null && gen != _generation) return;
    theme.value = next;
    final prefs = await SharedPreferences.getInstance();
    if (next == null) {
      await prefs.remove(_kTheme);
    } else {
      await prefs.setString(_kTheme, jsonEncode(next.toJson()));
    }
  }
}
