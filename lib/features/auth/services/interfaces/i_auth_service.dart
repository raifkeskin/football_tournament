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
