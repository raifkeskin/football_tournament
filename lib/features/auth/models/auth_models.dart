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
  invalidPhone,
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
