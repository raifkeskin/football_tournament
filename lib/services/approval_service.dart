import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Bekleyen yönetim işlemlerinin durumları.
enum PendingActionStatus { pending, approved, rejected }

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

  factory PendingAction.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? const <String, dynamic>{};
    final statusStr =
        (map['status'] as String?) ?? PendingActionStatus.pending.name;
    final submittedAt = map['submittedAt'];
    final reviewedAt = map['reviewedAt'];
    return PendingAction(
      actionId: (map['actionId'] as String?) ?? doc.id,
      actionType: (map['actionType'] as String?) ?? '',
      leagueId: (map['leagueId'] as String?) ?? '',
      teamId: map['teamId'] as String?,
      submittedBy: (map['submittedBy'] as String?) ?? '',
      payload:
          (map['payload'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
      status: PendingActionStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => PendingActionStatus.pending,
      ),
      submittedAt: submittedAt is Timestamp ? submittedAt.toDate() : null,
      reviewedBy: map['reviewedBy'] as String?,
      reviewedAt: reviewedAt is Timestamp ? reviewedAt.toDate() : null,
      reviewNote: map['reviewNote'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'actionId': actionId,
      'actionType': actionType,
      'leagueId': leagueId,
      'teamId': teamId,
      'submittedBy': submittedBy,
      'payload': payload,
      'status': status.name,
      'submittedAt': submittedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(submittedAt!),
      'reviewedBy': reviewedBy,
      'reviewedAt': reviewedAt == null ? null : Timestamp.fromDate(reviewedAt!),
      'reviewNote': reviewNote,
    };
  }
}

/// TeamManager değişikliklerini Admin onayına düşüren servis iskeleti.
///
/// Not: Bu sınıf Firestore bağlantı kodunu bilinçli olarak içermez.
/// Projede `cloud_firestore` eklendiğinde metot içleri bağlanmalıdır.
class ApprovalService {
  ApprovalService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Koleksiyon adı sabit tutulur.
  static const String pendingActionsCollection = 'pending_actions';

  /// TeamManager tarafından gelen bir işlemi bekleyen onaya yollar.
  Future<void> submitPendingAction(PendingAction action) async {
    await _db
        .collection(pendingActionsCollection)
        .doc(action.actionId)
        .set(action.toMap());
  }

  /// Admin panelinde listelenecek bekleyen işlemleri çeker.
  Future<List<PendingAction>> fetchPendingActions({String? leagueId}) async {
    Query<Map<String, dynamic>> q = _db
        .collection(pendingActionsCollection)
        .where('status', isEqualTo: PendingActionStatus.pending.name);
    if (leagueId != null) {
      q = q.where('leagueId', isEqualTo: leagueId);
    }
    final snap = await q.get();
    final list = snap.docs.map((d) => PendingAction.fromDoc(d)).toList();
    list.sort((a, b) {
      final aa = a.submittedAt?.millisecondsSinceEpoch;
      final bb = b.submittedAt?.millisecondsSinceEpoch;
      if (aa == null && bb == null) return 0;
      if (aa == null) return 1;
      if (bb == null) return -1;
      return bb.compareTo(aa);
    });
    return list;
  }

  /// Admin onayı.
  Future<void> approveAction({
    required String actionId,
    required String adminUserId,
    String? reviewNote,
  }) async {
    final ref = _db.collection(pendingActionsCollection).doc(actionId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final action = PendingAction.fromDoc(snap);

    if (action.actionType == 'squad_upload') {
      final payloadPlayers = action.payload['players'];
      if (payloadPlayers is List) {
        await _applySquadUpload(teamId: action.teamId, players: payloadPlayers);
      }
    }

    await ref.update({
      'status': PendingActionStatus.approved.name,
      'reviewedBy': adminUserId,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewNote': reviewNote,
    });
  }

  /// Admin reddi.
  Future<void> rejectAction({
    required String actionId,
    required String adminUserId,
    String? reviewNote,
  }) async {
    await _db.collection(pendingActionsCollection).doc(actionId).update({
      'status': PendingActionStatus.rejected.name,
      'reviewedBy': adminUserId,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewNote': reviewNote,
    });
  }

  Future<void> _applySquadUpload({
    required String? teamId,
    required List players,
  }) async {
    if (teamId == null || teamId.isEmpty) return;

    var start = 0;
    while (start < players.length) {
      final end = min(start + 400, players.length);
      final chunk = players.sublist(start, end);
      final batch = _db.batch();
      for (final row in chunk) {
        if (row is! Map) continue;
        final name = (row['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final docRef = _db.collection('players').doc();
        batch.set(docRef, {
          'teamId': teamId,
          'name': name,
          'position': row['position'],
          'preferredFoot': row['preferredFoot'],
          'number': row['number'],
          'birthYear': row['birthYear'],
          'photoUrl': row['photoUrl'],
          'goals': 0,
          'assists': 0,
          'yellowCards': 0,
          'redCards': 0,
          'matchesPlayed': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      start = end;
    }
  }
}
