import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/app_navigator.dart';

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

  /// Bu analizin Gemini maliyeti (USD, token sayısından).
  final double? costUsd;

  /// Videoda maçın / 2. yarının başladığı an (girilen ya da YZ'nin bulduğu).
  final int? kickoffSec;
  final int? secondHalfSec;

  const MatchHighlightJob({
    required this.status,
    this.mode,
    this.found,
    this.error,
    this.startedAt,
    this.costUsd,
    this.kickoffSec,
    this.secondHalfSec,
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

  static int _byMinute(MatchHighlight a, MatchHighlight b) {
    final am = a.minute, bm = b.minute;
    if (am != null && bm != null && am != bm) return am.compareTo(bm);
    if (am == null && bm != null) return 1;
    if (am != null && bm == null) return -1;
    return a.startSec.compareTo(b.startSec);
  }

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
    // Gol dakikasına göre; dakikası olmayan sona, kendi arasında videodaki
    // sırasıyla.
    final list = [
      for (final r in rows)
        MatchHighlight.fromMap(Map<String, dynamic>.from(r)),
    ]..sort(_byMinute);
    _cache[matchId] = list;
    return list;
  }

  static Future<MatchHighlightJob?> job(String matchId) async {
    final r = await _db
        .from('match_highlight_jobs')
        .select(
          'status, mode, found, error, started_at, cost_usd, kickoff_sec, '
          'second_half_sec',
        )
        .eq('match_id', matchId)
        .maybeSingle();
    if (r == null) return null;
    return MatchHighlightJob(
      status: (r['status'] ?? '').toString(),
      mode: r['mode']?.toString(),
      found: r['found'] is num ? (r['found'] as num).toInt() : null,
      error: r['error']?.toString(),
      startedAt: DateTime.tryParse('${r['started_at'] ?? ''}'),
      costUsd: r['cost_usd'] is num
          ? (r['cost_usd'] as num).toDouble()
          : double.tryParse('${r['cost_usd'] ?? ''}'),
      kickoffSec: r['kickoff_sec'] is num
          ? (r['kickoff_sec'] as num).toInt()
          : null,
      secondHalfSec: r['second_half_sec'] is num
          ? (r['second_half_sec'] as num).toInt()
          : null,
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

  // ---- Arka plan takibi ---------------------------------------------------
  // Analiz sunucuda sürer; takip ekrana değil buraya bağlıdır. Ekran kapansa
  // da iş bitince uygulamanın neresindeysen bildirim çıkar. Bağlantı koparsa
  // takip bırakılmaz, artan aralıklarla yeniden denenir.

  static final Map<String, Timer> _watchers = {};

  /// Bağlantı kopukken true (ekran "yeniden deneniyor" gösterir).
  static final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  /// Takip edilen maç mı (ekran kendi dönen göstergesini buna göre tutar).
  static bool isWatching(String matchId) => _watchers.containsKey(matchId);

  /// İş bitene kadar takip eder; [label] bildirimde maçın adı.
  static void watch(String matchId, {String? label}) {
    if (_watchers.containsKey(matchId)) return;
    _schedule(matchId, label, 0);
  }

  static void _schedule(String matchId, String? label, int failures) {
    // 6 sn; hata sürdükçe 12, 24, 48, en çok 60 sn. ~30 dk sonra bırakılır.
    if (failures > 30) {
      _watchers.remove(matchId);
      return;
    }
    final wait = math.min(6 << math.min(failures, 4), 60);
    _watchers[matchId] = Timer(Duration(seconds: wait), () async {
      try {
        final j = await job(matchId);
        offline.value = false;
        if (j != null && j.isRunning) {
          _schedule(matchId, label, 0);
          return;
        }
        _watchers.remove(matchId);
        try {
          await fetch(matchId);
        } catch (_) {}
        changes.value++;
        _notifyDone(j, label);
      } catch (_) {
        offline.value = true;
        _schedule(matchId, label, failures + 1);
      }
    });
  }

  static void _notifyDone(MatchHighlightJob? j, String? label) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null || j == null) return;
    final who = (label ?? '').trim().isEmpty ? '' : ' ($label)';
    final String msg;
    if (j.status == 'done') {
      final n = j.found ?? 0;
      msg = n > 0
          ? 'YZ analizi bitti$who: $n gol kesiti bulundu, onay bekliyor.'
          : 'YZ analizi bitti$who: gol kesiti bulunamadı.';
    } else if (j.status == 'error') {
      msg = 'YZ analizi tamamlanamadı$who: ${j.error ?? 'bilinmeyen hata'}';
    } else {
      return;
    }
    ScaffoldMessenger.maybeOf(ctx)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
      );
  }
}
