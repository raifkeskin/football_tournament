import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../home/screens/main_navigator.dart';

/// Yeni Kayıt Ol akışının sunucu çağrıları. Doğrulama kodu sunucudaki
/// `sms_otp_provider` ayarına göre gider (test modunda adminler WhatsApp'tan
/// iletir, açıkken SMS).
class RegistrationService {
  RegistrationService._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// [kind]: 'player' ya da 'organizer'. Dönüş: sunucu sonuç kodu.
  static Future<String> sendCode({
    required String raw10,
    required String kind,
    String? name,
  }) async {
    final r = await _sb.rpc(
      'register_otp_send',
      params: {'p_phone': raw10, 'p_kind': kind, 'p_name': name},
    );
    return (r ?? '').toString();
  }

  static Future<String> checkCode({
    required String raw10,
    required String code,
  }) async {
    final r = await _sb.rpc(
      'register_otp_check',
      params: {'p_phone': raw10, 'p_code': code},
    );
    return (r ?? '').toString();
  }

  /// Kimlik okununca: bu kişinin hesabı olan bir profili var mı.
  static Future<String> precheckPlayer({
    required String firstName,
    required String lastName,
    required DateTime birthDate,
    required String tc,
  }) async {
    String two(int v) => v.toString().padLeft(2, '0');
    final r = await _sb.rpc(
      'register_player_precheck',
      params: {
        'p_first': firstName,
        'p_last': lastName,
        'p_birth':
            '${birthDate.year}-${two(birthDate.month)}-${two(birthDate.day)}',
        'p_tc': tc,
      },
    );
    return (r ?? '').toString();
  }

  static Future<String> registerOrganizer({
    required String raw10,
    required String code,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    final r = await _sb.rpc(
      'register_organizer',
      params: {
        'p_phone': raw10,
        'p_code': code,
        'p_password': password,
        'p_first': firstName,
        'p_last': lastName,
      },
    );
    return (r ?? '').toString();
  }

  static Future<String> registerPlayer({
    required String raw10,
    required String code,
    required String password,
    required String firstName,
    required String lastName,
    required DateTime birthDate,
    required String tc,
    required String mainPosition,
    String? subPosition,
    String? foot,
    int? height,
    int? weight,
  }) async {
    String two(int v) => v.toString().padLeft(2, '0');
    final r = await _sb.rpc(
      'register_player',
      params: {
        'p_phone': raw10,
        'p_code': code,
        'p_password': password,
        'p_first': firstName,
        'p_last': lastName,
        'p_birth':
            '${birthDate.year}-${two(birthDate.month)}-${two(birthDate.day)}',
        'p_tc': tc,
        'p_main': mainPosition,
        'p_sub': subPosition,
        'p_foot': foot,
        'p_height': height,
        'p_weight': weight,
      },
    );
    return (r ?? '').toString();
  }

  /// Sunucu sonuç kodunun kullanıcıya gösterilecek metni (ok için null).
  static String? message(String code) => switch (code) {
    'ok' || 'sent' => null,
    'disabled' => 'Kayıt şu an kapalı. Lütfen daha sonra tekrar deneyin.',
    'invalid_phone' => 'Geçerli bir cep telefonu numarası girin.',
    'has_account' =>
      'Bu numarayla bir hesap zaten var. Giriş yapın ya da "Şifremi '
          'Unuttum" ile yeni şifre alın.',
    'too_soon' => 'Yeni kod için biraz bekleyin.',
    'too_many' =>
      'Bu numaraya çok fazla kod istendi. Lütfen bir saat sonra tekrar '
          'deneyin.',
    'not_configured' =>
      'Kod gönderimi şu an yapılamıyor. Lütfen daha sonra tekrar deneyin.',
    'expired' => 'Kodun süresi doldu. Yeni kod isteyin.',
    'too_many_attempts' => 'Çok fazla hatalı deneme. Yeni kod isteyin.',
    'wrong_code' => 'Kod hatalı. Lütfen kontrol edin.',
    'weak_password' =>
      'Şifre 6-10 karakter olmalı ve en az bir rakam veya özel karakter '
          'içermeli.',
    'invalid_name' => 'Adınızı ve soyadınızı yazın.',
    'invalid_tc' => 'Kimlik numarası okunamadı. Kimliği tekrar okutun.',
    'invalid_data' => 'Bilgileri kontrol edin (mevki, boy, kilo).',
    'profile_has_account' =>
      'Bu kimlikle bağlı bir hesap zaten var. O hesabın telefon numarasıyla '
          'giriş yapın ya da "Şifremi Unuttum"u kullanın.',
    'ambiguous' =>
      'Bu bilgilerle birden fazla profil bulundu. Takım ya da turnuva '
          'sorumlunuza başvurun.',
    'not_verified' => 'Profilin kimlikle onaylı değil.',
    'identity_mismatch' => 'Okutulan kimlik bu profile ait değil.',
    'phone_taken' => 'Bu numara başka bir hesapta kayıtlı.',
    'same_phone' => 'Bu numara zaten hesabında kayıtlı.',
    _ => 'İşlem tamamlanamadı. Lütfen tekrar deneyin.',
  };

  /// Hesap açıldıktan sonra giriş yapılır ve ana sayfa açılır; [then] ana
  /// sayfanın üstünde açılacak ekran (ör. turnuva talebi).
  static Future<void> signInAndOpenHome(
    BuildContext context, {
    required String raw10,
    required String password,
    required String message,
    void Function(BuildContext context)? then,
  }) async {
    final session = AppSession.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    await session.signInWithPhonePassword(
      phoneInput: raw10,
      password: password,
      rememberMe: true,
    );
    final uid = _sb.auth.currentUser?.id ?? '';
    await Future.wait([
      ActiveTournament.refresh(),
      if (uid.isNotEmpty) session.waitForProfile(uid),
    ]);
    rootNav.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'MainNavigator'),
        builder: (_) => const MainNavigator(initialTabIndex: 0),
      ),
      (Route<dynamic> route) => false,
    );
    messenger.showSnackBar(SnackBar(content: Text(message)));
    if (then != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => then(rootNav.context),
      );
    }
  }
}

/// Kimlik çipindeki büyük harfli adı Türkçe kurala göre düzeltir
/// ("AHMET İLKER ÖZ" → "Ahmet İlker Öz").
String trTitleCase(String s) {
  String lower(String x) =>
      x.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
  String upper(String x) =>
      x.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
  return s
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) {
        final l = lower(w);
        return upper(l.substring(0, 1)) + l.substring(1);
      })
      .join(' ');
}
