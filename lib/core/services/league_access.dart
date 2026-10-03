import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/admin_form.dart';
import '../widgets/admin_page.dart';
import 'global_filter.dart';

/// Gizli turnuvaları erişim koduyla takip etme.
///
/// Kod veritabanında `league_followers`'a yazılır (bkz. migration
/// 20261006110000_private_leagues). Giriş yapmamış kişi için isimsiz
/// (anonymous) oturum açılır; kişi kayıt olmaz. Girilen kodlar cihazda da
/// saklanır: çıkış yapınca ya da gerçek hesapla girince takip yenilenir.
class LeagueAccess {
  LeagueAccess._();

  static const _kCodesKey = 'followed_league_codes';

  /// Görülebilen turnuvalar değişince (giriş/çıkış, kod girildi) artar;
  /// ana ekranlar bu değerle yeniden kurulur ve verilerini baştan okur.
  static final dataEpoch = ValueNotifier<int>(0);

  static void bump() => dataEpoch.value++;

  static SupabaseClient get _sb => Supabase.instance.client;

  static Future<List<String>> _storedCodes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_kCodesKey) ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<void> _saveCodes(List<String> codes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kCodesKey, codes.toSet().toList());
    } catch (_) {}
  }

  static Future<bool> _ensureSession() async {
    if (_sb.auth.currentSession != null) return true;
    try {
      await _sb.auth.signInAnonymously();
      return true;
    } catch (e) {
      debugPrint('İsimsiz oturum açılamadı: $e');
      return false;
    }
  }

  /// Kodu doğrular ve turnuvayı takip eder. Döner: (turnuva id, ad).
  static Future<({String id, String name})> followByCode(String code) async {
    final clean = code.trim();
    if (!await _ensureSession()) {
      throw Exception(
        'Şu an kod ile turnuva açılamıyor. Lütfen daha sonra tekrar deneyin.',
      );
    }
    final res = await _sb.rpc(
      'follow_league_by_code',
      params: {'p_code': clean},
    );
    final map = Map<String, dynamic>.from(res as Map);
    await _saveCodes([...await _storedCodes(), clean]);
    return (
      id: (map['league_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
    );
  }

  /// Cihazdaki kodlarla takibi yeniler; geçersizleşen kodlar silinir.
  /// Oturum yoksa ve kod varsa isimsiz oturum açar. Değişiklik olduysa true.
  static Future<bool> restoreFollows() async {
    final codes = await _storedCodes();
    if (codes.isEmpty) return false;
    if (!await _ensureSession()) return false;
    final valid = <String>[];
    for (final c in codes) {
      try {
        await _sb.rpc('follow_league_by_code', params: {'p_code': c});
        valid.add(c);
      } on PostgrestException catch (e) {
        // Kod yenilenmiş / turnuva kaldırılmış: cihazdan da sil.
        if (e.code != 'P0002') valid.add(c);
      } catch (_) {
        valid.add(c);
      }
    }
    if (valid.length != codes.length) await _saveCodes(valid);
    return valid.isNotEmpty;
  }
}

/// "Turnuva Kodu Gir" penceresi: kod doğruysa turnuva açılır ve seçilir.
Future<void> showLeagueCodeDialog(BuildContext context) async {
  String? leagueName;
  String? leagueId;
  final code = await showAdminTextInputDialog(
    context: context,
    title: 'Turnuva Kodu Gir',
    icon: Icons.key_rounded,
    subtitle:
        'Gizli bir turnuvayı takip etmek için turnuva sorumlusunun '
        'paylaştığı kodu girin.',
    label: 'Erişim Kodu',
    fieldIcon: Icons.lock_open_rounded,
    hint: 'Örn. 482913',
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')),
      LengthLimitingTextInputFormatter(12),
    ],
    confirmLabel: 'AÇ',
    validator: (v) => v.trim().isEmpty ? 'Kodu girin.' : null,
  );
  if (code == null || !context.mounted) return;

  try {
    final r = await LeagueAccess.followByCode(code);
    leagueId = r.id;
    leagueName = r.name;
  } on PostgrestException catch (e) {
    if (!context.mounted) return;
    await showAdminInfoDialog(
      context: context,
      title: 'Turnuva açılamadı',
      message: e.message,
    );
    return;
  } catch (e) {
    if (!context.mounted) return;
    await showAdminInfoDialog(
      context: context,
      title: 'Turnuva açılamadı',
      message: e.toString().replaceFirst('Exception: ', ''),
    );
    return;
  }

  GlobalFilter.setLeague(leagueId);
  LeagueAccess.bump();
  if (!context.mounted) return;
  await showAdminInfoDialog(
    context: context,
    title: '$leagueName açıldı',
    message:
        'Turnuvanın maçlarını, puan durumunu ve haberlerini artık '
        'uygulamada görebilirsiniz.',
    icon: Icons.lock_open_rounded,
    iconColor: kAdminAccent,
  );
}
