import 'package:supabase_flutter/supabase_flutter.dart';

import 'fan_membership_terms.dart';

class FanRegistrationService {
  FanRegistrationService._();

  static const termsVersion = fanMembershipTermsVersion;

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<String> sendCode({
    required String phone,
    required String fullName,
  }) async {
    final result = await _client.rpc(
      'fan_register_otp_send',
      params: {'p_phone': phone, 'p_name': fullName},
    );
    return (result ?? '').toString();
  }

  static Future<String> verifyCode({
    required String phone,
    required String code,
  }) async {
    final result = await _client.rpc(
      'register_otp_check',
      params: {'p_phone': phone, 'p_code': code},
    );
    return (result ?? '').toString();
  }

  static Future<String> register({
    required String phone,
    required String code,
    required String password,
    required String firstName,
    required String lastName,
    required bool termsAccepted,
  }) async {
    final result = await _client.rpc(
      'register_fan',
      params: {
        'p_phone': phone,
        'p_code': code,
        'p_password': password,
        'p_first': firstName,
        'p_last': lastName,
        // İl/ilçe artık alınmıyor (2026-11-12); RPC imzası aynı kalır.
        'p_province_id': null,
        'p_district_id': null,
        'p_terms_version': termsVersion,
        'p_terms_accepted': termsAccepted,
      },
    );
    return (result ?? '').toString();
  }

  static String message(String result) => switch (result) {
    'disabled' => 'Taraftar kaydı şu an kapalı. Lütfen daha sonra deneyin.',
    'invalid_phone' => 'Geçerli bir cep telefonu numarası girin.',
    'invalid_name' => 'Adınızı ve soyadınızı kontrol edin.',
    'terms_required' => 'Üyelik sözleşmesini kabul etmeniz gerekiyor.',
    'has_account' =>
      'Bu numarayla zaten hesap var. Giriş yapın veya şifrenizi yenileyin.',
    'too_soon' => 'Yeni kod istemeden önce lütfen biraz bekleyin.',
    'too_many' =>
      'Bu numaraya çok fazla kod istendi. Lütfen daha sonra tekrar deneyin.',
    'not_configured' =>
      'Kod gönderimi şu an yapılandırılmamış. Lütfen daha sonra deneyin.',
    'expired' => 'Kodun süresi doldu. Yeni kod isteyin.',
    'too_many_attempts' => 'Çok fazla hatalı deneme yapıldı. Yeni kod isteyin.',
    'wrong_code' => 'Kod hatalı. Lütfen kontrol edin.',
    'weak_password' =>
      'Şifre 6-10 karakter olmalı ve en az bir rakam veya özel karakter içermeli.',
    _ => 'İşlem tamamlanamadı. Lütfen tekrar deneyin.',
  };
}
