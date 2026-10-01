import 'package:supabase_flutter/supabase_flutter.dart';

/// Onay taleplerinin durumları (`pending_actions.status`).
enum PendingActionStatus { pending, approved, rejected, cancelled }

/// Talep türleri (`pending_actions.action_type`).
///
/// payload biçimleri:
/// - rosterAdd    : {"player_id": uuid, "jersey_number": int?}
///                  veya yeni oyuncu için {"player": {...}, "jersey_number": int?}
/// - rosterRemove : {"player_id": uuid}
/// - jerseyChange : {"player_id": uuid, "jersey_number": int | null}
enum PendingActionType {
  rosterAdd('roster_add', 'Kadroya ekleme'),
  rosterRemove('roster_remove', 'Kadrodan çıkarma'),
  jerseyChange('jersey_change', 'Forma numarası değişikliği');

  const PendingActionType(this.code, this.label);

  final String code;
  final String label;

  static PendingActionType? fromCode(String code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// Supabase `pending_actions` tablosundaki bir talep.
class PendingAction {
  const PendingAction({
    required this.id,
    required this.actionType,
    required this.status,
    required this.leagueId,
    required this.seasonId,
    required this.teamId,
    required this.submittedBy,
    required this.payload,
    this.reviewNote,
    this.reviewedBy,
    this.reviewedAt,
    this.createdAt,
  });

  final String id;
  final String actionType;
  final PendingActionStatus status;
  final String leagueId;
  final String seasonId;
  final String teamId;
  final String submittedBy;
  final Map<String, dynamic> payload;
  final String? reviewNote;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  PendingActionType? get type => PendingActionType.fromCode(actionType);

  String get typeLabel => type?.label ?? actionType;

  String? get playerId {
    final v = (payload['player_id'] ?? '').toString().trim();
    return v.isEmpty ? null : v;
  }

  /// Yeni oyuncu talebinde girilen ad soyad.
  String? get newPlayerName {
    final p = payload['player'];
    if (p is! Map) return null;
    final full = [
      (p['name'] ?? '').toString().trim(),
      (p['surname'] ?? '').toString().trim(),
    ].where((e) => e.isNotEmpty).join(' ');
    return full.isEmpty ? null : full;
  }

  int? get jerseyNumber {
    final v = payload['jersey_number'];
    if (v is int) return v;
    return int.tryParse((v ?? '').toString());
  }

  factory PendingAction.fromMap(Map<String, dynamic> map) {
    final statusStr = (map['status'] ?? '').toString();
    final payload = map['payload'];
    return PendingAction(
      id: (map['id'] ?? '').toString(),
      actionType: (map['action_type'] ?? '').toString(),
      status: PendingActionStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => PendingActionStatus.pending,
      ),
      leagueId: (map['league_id'] ?? '').toString(),
      seasonId: (map['season_id'] ?? '').toString(),
      teamId: (map['team_id'] ?? '').toString(),
      submittedBy: (map['submitted_by'] ?? '').toString(),
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : const <String, dynamic>{},
      reviewNote: map['review_note']?.toString(),
      reviewedBy: map['reviewed_by']?.toString(),
      reviewedAt: DateTime.tryParse((map['reviewed_at'] ?? '').toString()),
      createdAt: DateTime.tryParse((map['created_at'] ?? '').toString()),
    );
  }
}

/// Takım sorumlusu taleplerini açan ve sonuçlandıran servis.
///
/// Yetki veritabanında: talebi sadece o takımın sorumlusu (veya turnuva
/// sahibi/admin) açabilir; listeler RLS ile süzülür (admin hepsini, turnuva
/// sahibi kendi turnuvalarını, sorumlu kendi taleplerini görür). Onay/red
/// `review_pending_action` fonksiyonuyla sunucuda ve tek adımda yapılır.
class ApprovalService {
  ApprovalService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _table = 'pending_actions';

  /// Yeni talep açar. Gönderen, turnuva ve durum sunucuda belirlenir.
  Future<PendingAction> submit({
    required PendingActionType type,
    required String seasonId,
    required String teamId,
    required Map<String, dynamic> payload,
  }) async {
    final row = await _client
        .from(_table)
        .insert({
          'action_type': type.code,
          'season_id': seasonId,
          'team_id': teamId,
          'payload': payload,
        })
        .select()
        .single();
    return PendingAction.fromMap(row);
  }

  /// Onay bekleyen talepler (en yeni önce).
  Future<List<PendingAction>> fetchPendingActions({String? leagueId}) async {
    var query = _client
        .from(_table)
        .select()
        .eq('status', PendingActionStatus.pending.name);
    if (leagueId != null) query = query.eq('league_id', leagueId);
    final rows = await query.order('created_at', ascending: false);
    return rows.map(PendingAction.fromMap).toList();
  }

  /// Kullanıcının kendi açtığı talepler (en yeni önce).
  Future<List<PendingAction>> fetchMyActions() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from(_table)
        .select()
        .eq('submitted_by', uid)
        .order('created_at', ascending: false);
    return rows.map(PendingAction.fromMap).toList();
  }

  Future<void> approveAction({required String actionId, String? reviewNote}) =>
      _review(actionId, approve: true, note: reviewNote);

  Future<void> rejectAction({required String actionId, String? reviewNote}) =>
      _review(actionId, approve: false, note: reviewNote);

  Future<void> _review(
    String actionId, {
    required bool approve,
    String? note,
  }) async {
    final n = (note ?? '').trim();
    await _client.rpc(
      'review_pending_action',
      params: {
        'p_action_id': actionId,
        'p_approve': approve,
        'p_note': n.isEmpty ? null : n,
      },
    );
  }

  /// Gönderen, sonuçlanmamış talebini geri çeker.
  Future<void> cancelAction(String actionId) async {
    await _client
        .from(_table)
        .update({'status': PendingActionStatus.cancelled.name})
        .eq('id', actionId);
  }
}
