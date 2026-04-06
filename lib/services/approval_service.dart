/// Bekleyen yönetim işlemlerinin durumları.
enum PendingActionStatus {
  pending,
  approved,
  rejected,
}

/// Firestore `pending_actions` koleksiyonu için veri modeli.
///
/// Örnek belge alanları:
/// - actionId: benzersiz istek kimliği
/// - actionType: team_update, squad_upload, transfer_edit vb.
/// - leagueId: ilgili lig
/// - teamId: ilgili takım (opsiyonel)
/// - submittedBy: işlemi başlatan kullanıcı uid
/// - payload: değişiklik verisi
/// - status: pending, approved, rejected
/// - submittedAt: istek zamanı
/// - reviewedBy: admin uid (onay/red anında)
/// - reviewedAt: inceleme zamanı
/// - reviewNote: admin notu
class PendingAction {
  const PendingAction({
    required this.actionId,
    required this.actionType,
    required this.leagueId,
    this.teamId,
    required this.submittedBy,
    required this.payload,
    this.status = PendingActionStatus.pending,
    this.submittedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
  });

  final String actionId;
  final String actionType;
  final String leagueId;
  final String? teamId;
  final String submittedBy;
  final Map<String, dynamic> payload;
  final PendingActionStatus status;
  final DateTime? submittedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;

  Map<String, dynamic> toMap() {
    return {
      'actionId': actionId,
      'actionType': actionType,
      'leagueId': leagueId,
      'teamId': teamId,
      'submittedBy': submittedBy,
      'payload': payload,
      'status': status.name,
      'submittedAt': submittedAt?.toIso8601String(),
      'reviewedBy': reviewedBy,
      'reviewedAt': reviewedAt?.toIso8601String(),
      'reviewNote': reviewNote,
    };
  }
}

/// TeamManager değişikliklerini Admin onayına düşüren servis iskeleti.
///
/// Not: Bu sınıf Firestore bağlantı kodunu bilinçli olarak içermez.
/// Projede `cloud_firestore` eklendiğinde metot içleri bağlanmalıdır.
class ApprovalService {
  const ApprovalService();

  /// Koleksiyon adı sabit tutulur.
  static const String pendingActionsCollection = 'pending_actions';

  /// TeamManager tarafından gelen bir işlemi bekleyen onaya yollar.
  Future<void> submitPendingAction(PendingAction action) async {
    // TODO(approval): Firestore'a `pending_actions/{actionId}` olarak yaz.
    // await FirebaseFirestore.instance
    //   .collection(pendingActionsCollection)
    //   .doc(action.actionId)
    //   .set(action.toMap());
  }

  /// Admin panelinde listelenecek bekleyen işlemleri çeker.
  Future<List<PendingAction>> fetchPendingActions({
    String? leagueId,
  }) async {
    // TODO(approval): status=pending filtreli sorgu kur.
    // Not: Gerekirse leagueId ile ek filtre uygula.
    return const [];
  }

  /// Admin onayı.
  Future<void> approveAction({
    required String actionId,
    required String adminUserId,
    String? reviewNote,
  }) async {
    // TODO(approval): status=approved, reviewedBy, reviewedAt alanlarını güncelle.
  }

  /// Admin reddi.
  Future<void> rejectAction({
    required String actionId,
    required String adminUserId,
    String? reviewNote,
  }) async {
    // TODO(approval): status=rejected, reviewedBy, reviewedAt, reviewNote güncelle.
  }
}
