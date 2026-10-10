import '../../models/auth_models.dart';

abstract class IAuthService {
  Stream<UserDoc?> watchUserDoc(String uid);

  Stream<List<RosterAssignment>> watchRosterAssignmentsByPhone(String phone);

  /// Giriş yapmadan çağrılır: geçici şifre talebi açar. Numarada hesap varsa
  /// talep şifre sıfırlama olur. [isReset] true ise hesabı olmayan numara
  /// için talep açılmaz ([AccountRequestOutcome.notRegistered]).
  Future<AccountRequestOutcome> requestAccountPassword({
    required String phoneRaw10,
    String? fullName,
    bool isReset = false,
  });

  /// Giriş yapmadan çağrılır: SMS doğrulama kodu gönderir (SMS doğrulama
  /// açıkken). [isReset] true ise hesabı olmayan numaraya kod gönderilmez.
  Future<SmsOtpSendOutcome> sendSmsOtp({
    required String phoneRaw10,
    bool isReset = false,
  });

  /// Giriş yapmadan çağrılır: kodu doğrular; hesabı açar ya da şifresini
  /// [password] yapar. Başarılıysa kullanıcı bu şifreyle giriş yapabilir.
  Future<SmsOtpVerifyOutcome> verifySmsOtp({
    required String phoneRaw10,
    required String code,
    required String password,
  });

  /// Admin: şifre talepleri (yeniden eskiye).
  Stream<List<AccountRequestEntry>> watchAccountRequests({
    bool includeClosed = false,
  });

  /// Admin: talebi onaylar; hesabı açar ya da şifresini sıfırlar ve geçici
  /// şifreyi döner. Onaylanmış talep için yeni şifre üretir.
  Future<TempPasswordGrant> approveAccountRequest(String id);

  /// Admin: talebi reddeder.
  Future<void> rejectAccountRequest(String id);

  /// Giriş yapmış kullanıcı kendi şifresini değiştirir ve "ilk girişte
  /// şifre değiştir" işaretini kaldırır.
  Future<void> changeOwnPassword(String newPassword);
}
