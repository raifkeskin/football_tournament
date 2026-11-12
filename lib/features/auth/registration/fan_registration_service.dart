import 'package:supabase_flutter/supabase_flutter.dart';

import 'fan_membership_terms.dart';

class LocationOption {
  const LocationOption({required this.id, required this.name});

  final int id;
  final String name;

  factory LocationOption.fromMap(Map<String, dynamic> row) => LocationOption(
    id: (row['id'] as num).toInt(),
    name: row['name'].toString(),
  );
}

class FanRegistrationService {
  FanRegistrationService._();

  static const termsVersion = fanMembershipTermsVersion;

  static SupabaseClient get _client => Supabase.instance.client;

  static List<LocationOption>? _provinces;
  static final Map<int, List<LocationOption>> _districts = {};

  static Future<List<LocationOption>> provinces() async {
    final cached = _provinces;
    if (cached != null) return cached;
    final rows = await _client
        .from('turkey_provinces')
        .select('id, name')
        .order('name');
    final options = rows
        .map((row) => LocationOption.fromMap(row))
        .toList(growable: false);
    _provinces = options;
    return options;
  }

  static Future<List<LocationOption>> districts(int provinceId) async {
    final cached = _districts[provinceId];
    if (cached != null) return cached;
    final rows = await _client
        .from('turkey_districts')
        .select('id, name')
        .eq('province_id', provinceId)
        .order('name');
    final options = rows
        .map((row) => LocationOption.fromMap(row))
        .toList(growable: false);
    _districts[provinceId] = options;
    return options;
  }

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
    int? provinceId,
    int? districtId,
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
        'p_province_id': provinceId,
        'p_district_id': districtId,
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
    'invalid_location' => 'İl ve ilçe seçiminizi kontrol edin.',
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
