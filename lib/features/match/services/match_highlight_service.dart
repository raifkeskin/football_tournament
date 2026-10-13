import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// YZ'nin maç videosunda bulduğu an (şimdilik gol). Video kesilmez; YouTube
/// yayınının [startSec]–[endSec] aralığı oynatılır.
class MatchHighlight {
  final String id;
  final String matchId;
  final String kind;
  final String? matchEventId;
  final String? teamId;
  final int? minute;
  final String videoId;
  final int startSec;
  final int endSec;
  final String? description;

  /// high | medium | low
  final String? confidence;

  /// pending | approved | rejected
  final String status;

  const MatchHighlight({
    required this.id,
    required this.matchId,
    required this.kind,
    this.matchEventId,
    this.teamId,
    this.minute,
    required this.videoId,
    required this.startSec,
    required this.endSec,
    this.description,
    this.confidence,
    required this.status,
  });

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';

  factory MatchHighlight.fromMap(Map<String, dynamic> m) {
    int? readInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    String? readStr(dynamic v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    return MatchHighlight(
      id: m['id'].toString(),
      matchId: m['match_id'].toString(),
      kind: readStr(m['kind']) ?? 'goal',
      matchEventId: readStr(m['match_event_id']),
      teamId: readStr(m['team_id']),
      minute: readInt(m['minute']),
      videoId: m['video_id'].toString(),
      startSec: readInt(m['start_sec']) ?? 0,
      endSec: readInt(m['end_sec']) ?? 0,
      description: readStr(m['description']),
      confidence: readStr(m['confidence']),
      status: readStr(m['status']) ?? 'pending',
    );
  }
}

/// Maçın son YZ analiz işi.
class MatchHighlightJob {
  /// running | done | error
  final String status;
  final String? mode;
  final int? found;
  final String? error;
  final DateTime? startedAt;

  const MatchHighlightJob({
    required this.status,
    this.mode,
    this.found,
    this.error,
    this.startedAt,
  });

  bool get isRunning =>
      status == 'running' &&
      startedAt != null &&
      DateTime.now().difference(startedAt!) < const Duration(minutes: 10);
}

/// `match_highlights` okuma/yazma ve `video-highlights` fonksiyonunu
/// tetikleme. Satırlar maç başına bellekte tutulur; değişiklik olunca
/// [changes] artar, açık ekranlar yeniden okur.
class MatchHighlightService {
  MatchHighlightService._();

  static SupabaseClient get _db => Supabase.instance.client;

  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static final Map<String, List<MatchHighlight>> _cache = {};

  /// Bellekteki son liste (ekran ilk açılışta beklemeden çizsin).
  static List<MatchHighlight>? cached(String matchId) => _cache[matchId];

  /// RLS: herkes onaylıları, yetkili (owns_match) bekleyenleri de görür.
  static Future<List<MatchHighlight>> fetch(String matchId) async {
    final rows = await _db
        .from('match_highlights')
        .select()
        .eq('match_id', matchId)
        .neq('status', 'rejected')
        .order('start_sec');
    final list = [
      for (final r in rows)
        MatchHighlight.fromMap(Map<String, dynamic>.from(r)),
    ];
    _cache[matchId] = list;
    return list;
  }

  static Future<MatchHighlightJob?> job(String matchId) async {
    final r = await _db
        .from('match_highlight_jobs')
        .select('status, mode, found, error, started_at')
        .eq('match_id', matchId)
        .maybeSingle();
    if (r == null) return null;
    return MatchHighlightJob(
      status: (r['status'] ?? '').toString(),
      mode: r['mode']?.toString(),
      found: r['found'] is num ? (r['found'] as num).toInt() : null,
      error: r['error']?.toString(),
      startedAt: DateTime.tryParse('${r['started_at'] ?? ''}'),
    );
  }

  /// Analizi başlatır; iş arka planda sürer. Hata metnini döner (yoksa null).
  static Future<String?> analyze(
    String matchId, {
    int? kickoffSec,
    int? secondHalfSec,
  }) async {
    try {
      await _db.functions.invoke(
        'video-highlights',
        body: {
          'match_id': matchId,
          'kickoff_sec': ?kickoffSec,
          'second_half_sec': ?secondHalfSec,
        },
      );
      return null;
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) return d['error'].toString();
      return 'Analiz başlatılamadı (${e.status}).';
    } catch (e) {
      return 'Analiz başlatılamadı: $e';
    }
  }

  static Future<void> update(
    MatchHighlight h, {
    int? startSec,
    int? endSec,
    String? status,
  }) async {
    final patch = <String, dynamic>{
      'start_sec': ?startSec,
      'end_sec': ?endSec,
      if (status != null) ...{
        'status': status,
        'reviewed_by': _db.auth.currentUser?.id,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      },
    };
    if (patch.isEmpty) return;
    await _db.from('match_highlights').update(patch).eq('id', h.id);
    await fetch(h.matchId);
    changes.value++;
  }
}
