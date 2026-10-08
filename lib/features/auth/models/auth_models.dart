class UserDoc {
  const UserDoc({
    required this.uid,
    required this.role,
    required this.phone,
    this.displayName,
    this.isAdmin = false,
  });

  final String uid;
  final String? role;
  final String phone;
  final String? displayName;
  final bool isAdmin;
}

class RosterAssignment {
  const RosterAssignment({
    required this.id,
    required this.tournamentId,
    required this.teamId,
    required this.role,
  });

  final String id;
  final String tournamentId;
  final String teamId;
  final String role;
}

/// Admin "Şifre Talepleri" listesindeki satır.
class AccountRequestEntry {
  const AccountRequestEntry({
    required this.id,
    required this.phoneRaw10,
    required this.isReset,
    required this.status,
    this.fullName,
    this.playerName,
    this.createdAt,
    this.reviewedAt,
  });

  final String id;
  final String phoneRaw10;

  /// true: hesabı olan kullanıcı yeni şifre istedi; false: yeni kayıt.
  final bool isReset;

  /// pending | approved | rejected
  final String status;

  /// Kullanıcının formda yazdığı ad soyad.
  final String? fullName;

  /// Aynı telefonlu oyuncu kaydının adı (varsa).
  final String? playerName;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  String? get displayName => playerName ?? fullName;
}

/// `request_account_password` sonucu.
enum AccountRequestOutcome {
  requested,
  resetRequested,
  alreadyPending,
  notRegistered,

  /// Numara hiçbir oyuncu kaydında yok (kadroya eklenmemiş).
  unknownPhone,
  invalidPhone,
}

/// SMS doğrulama kodu gönderme sonucu (`sms_otp_send`).
enum SmsOtpSendOutcome {
  /// Yeni hesap için kod gönderildi.
  sent,

  /// Numarada hesap var; şifre sıfırlama kodu gönderildi.
  sentReset,

  /// SMS doğrulama kapalı (eski akış kullanılmalı).
  disabled,
  invalidPhone,
  notRegistered,
  unknownPhone,

  /// Son koddan bu yana 60 sn geçmedi.
  tooSoon,

  /// Saatlik kod sınırı doldu.
  tooMany,

  /// SMS sağlayıcı bilgileri girilmemiş.
  notConfigured,
}

/// SMS kodunu doğrulayıp şifre belirleme sonucu (`sms_otp_verify`).
enum SmsOtpVerifyOutcome {
  ok,
  disabled,
  invalidPhone,
  weakPassword,
  expired,
  wrongCode,
  tooManyAttempts,
}

/// Onaylanan talebin geçici şifresi (yalnızca onay anında döner).
class TempPasswordGrant {
  const TempPasswordGrant({
    required this.phoneRaw10,
    required this.password,
    required this.isReset,
    this.fullName,
  });

  final String phoneRaw10;
  final String password;
  final bool isReset;
  final String? fullName;
}
