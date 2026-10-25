import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/app_navigator.dart';
import '../../../core/widgets/youtube_player_page.dart';

/// YZ'nin maç videosunda bulduğu an (şimdilik gol). Video kesilmez; YouTube
/// yayınının [startSec]–[endSec] aralığı oynatılır.
class MatchHighlight {
  final String id;
  final String matchId;
  final String kind;
  final String? matchEventId;
  final String? teamId;

  /// Golü atan (YZ eşleştirdi ya da yetkili seçti). Boşsa bağlı golün
  /// oyuncusu kullanılır.
  final String? playerId;
  final int? minute;

  /// Uzatma dakikası (30+2'); yoksa null.
  final int? addedMinute;
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
    this.playerId,
    this.minute,
    this.addedMinute,
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
      playerId: readStr(m['player_id']),
      minute: readInt(m['minute']),
      addedMinute: readInt(m['added_minute']),
      videoId: m['video_id'].toString(),
      startSec: readInt(m['start_sec']) ?? 0,
      endSec: readInt(m['end_sec']) ?? 0,
      description: readStr(m['description']),
      confidence: readStr(m['confidence']),
      status: readStr(m['status']) ?? 'pending',
    );
  }
}

/// Kesitte gösterilen golü atan: forma no + ad.
typedef HighlightScorer = ({String playerId, String name, int? jersey});

/// Golü atan seçimi için esame (yoksa kadro) satırı.
typedef HighlightRosterPlayer = ({
  String playerId,
  String teamId,
  String name,
  int? jersey,
});

/// Maçın son YZ analiz işi.
class MatchHighlightJob {
  /// running | done | error
  final String status;
  final String? mode;
  final int? found;

  /// Maç raporunda olup yayında görüntüsü bulunamayan gol sayısı.
  final int? missing;

  /// Sistem emin olamadı (başlangıç tutmadı / gollerin azı bulundu).
  final bool needsReview;
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
    this.missing,
    this.needsReview = false,
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
          'status, mode, found, missing, needs_review, error, started_at, '
          'cost_usd, kickoff_sec, '
          'second_half_sec',
        )
        .eq('match_id', matchId)
        .maybeSingle();
    if (r == null) return null;
    return MatchHighlightJob(
      status: (r['status'] ?? '').toString(),
      mode: r['mode']?.toString(),
      found: r['found'] is num ? (r['found'] as num).toInt() : null,
      missing: r['missing'] is num ? (r['missing'] as num).toInt() : null,
      needsReview: r['needs_review'] == true,
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

  /// Maç detayındaki gol kaydı sayısı (kendi kalesine dahil). Analiz, gol
  /// kayıtları skorla eşitse başlatılır (yoksa boşa tarama yapılmaz).
  static Future<int> goalCount(String matchId) async {
    final rows = await _db
        .from('match_events')
        .select('id')
        .eq('match_id', matchId)
        .eq('event_type', 'goal');
    return (rows as List).length;
  }

  /// Maçın YouTube yayın linkinin video kimliği (yoksa null).
  static Future<String?> streamVideoId(String matchId) async {
    try {
      final rows = await _db
          .from('match_media')
          .select('url')
          .eq('match_id', matchId)
          .eq('media_type', 'Maç Yayın Linki');
      for (final r in rows as List) {
        final id = youtubeVideoId((r['url'] ?? '').toString());
        if (id != null) return id;
      }
    } catch (_) {}
    return null;
  }

  /// Otomatik tarama durumu: 'running' sürüyor, 'pending' yayın bitince /
  /// yeniden denenecek; null yok.
  static Future<String?> autoStatus(String matchId) async {
    try {
      final v = await _db.rpc(
        'highlights_auto_status',
        params: {'p_match_id': matchId},
      );
      return v?.toString();
    } catch (_) {
      return null;
    }
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
    String? description,
    String? playerId,
  }) async {
    final patch = <String, dynamic>{
      'start_sec': ?startSec,
      'end_sec': ?endSec,
      if (description != null)
        'description': description.trim().isEmpty ? null : description.trim(),
      'player_id': ?playerId,
      'status': ?status,
      // Sorumlunun dokunduğu kesit (onay, düzeltme, kaldırma) YZ yeniden
      // çalışınca silinmez.
      if (status != null || startSec != null || endSec != null) ...{
        'reviewed_by': _db.auth.currentUser?.id,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      },
    };
    if (patch.isEmpty) return;
    await _db.from('match_highlights').update(patch).eq('id', h.id);
    await fetch(h.matchId);
    changes.value++;
  }

  /// Videodaki maç / 2. yarı başlangıcı düzeltilince o devrenin bütün
  /// kesitleri aradaki fark kadar kayar (uzunluk korunur).
  static Future<void> shiftStarts(
    String matchId, {
    int? kickoffSec,
    int? secondHalfSec,
  }) async {
    await _db.rpc(
      'shift_match_highlights',
      params: {
        'p_match_id': matchId,
        'p_kickoff_sec': kickoffSec,
        'p_second_half_sec': secondHalfSec,
      },
    );
    await fetch(matchId);
    changes.value++;
  }

  /// Esame (yoksa sezon kadrosu) oyuncuları; golü atan seçimi ve gösterim
  /// için. Forma numarası esameden, yoksa kadrodan.
  static Future<List<HighlightRosterPlayer>> roster({
    required String matchId,
    required String seasonId,
    required List<String> teamIds,
  }) async {
    List<HighlightRosterPlayer> read(List rows) => [
      for (final r in rows)
        if (r['player_id'] != null)
          (
            playerId: r['player_id'].toString(),
            teamId: (r['team_id'] ?? '').toString(),
            name: [
              (r['players']?['name'] ?? '').toString().trim(),
              (r['players']?['surname'] ?? '').toString().trim(),
            ].where((x) => x.isNotEmpty).join(' '),
            jersey: r['jersey_number'] is num
                ? (r['jersey_number'] as num).toInt()
                : null,
          ),
    ];
    const cols = 'player_id, team_id, jersey_number, players(name, surname)';
    final esame = read(
      await _db
          .from('match_rosters')
          .select(cols)
          .eq('match_id', matchId)
          .inFilter('team_id', teamIds),
    );
    final list = esame.isNotEmpty
        ? esame
        : read(
            await _db
                .from('season_team_players')
                .select(cols)
                .eq('season_id', seasonId)
                .inFilter('team_id', teamIds),
          );
    list.sort((a, b) => (a.jersey ?? 999).compareTo(b.jersey ?? 999));
    return list;
  }

  static final Map<String, Map<String, HighlightScorer>> _scorers = {};

  /// Bellekteki golü atanlar (kesit id → oyuncu).
  static Map<String, HighlightScorer>? cachedScorers(String matchId) =>
      _scorers[matchId];

  /// Kesitlerin golü atanları: kesitteki oyuncu, yoksa bağlı golün oyuncusu.
  static Future<Map<String, HighlightScorer>> scorers({
    required String matchId,
    required String seasonId,
    required String homeTeamId,
    required String awayTeamId,
    required List<MatchHighlight> items,
  }) async {
    final byHighlight = <String, String>{
      for (final h in items)
        if (h.playerId != null) h.id: h.playerId!,
    };
    final eventIds = [
      for (final h in items)
        if (h.playerId == null && h.matchEventId != null) h.matchEventId!,
    ];
    if (eventIds.isNotEmpty) {
      final rows = await _db
          .from('match_events')
          .select('id, player_id')
          .inFilter('id', eventIds);
      final byEvent = {
        for (final r in rows)
          if (r['player_id'] != null)
            r['id'].toString(): r['player_id'].toString(),
      };
      for (final h in items) {
        final p = h.playerId == null ? byEvent[h.matchEventId] : null;
        if (p != null) byHighlight[h.id] = p;
      }
    }
    final result = <String, HighlightScorer>{};
    if (byHighlight.isNotEmpty) {
      final players = {
        for (final p in await roster(
          matchId: matchId,
          seasonId: seasonId,
          teamIds: [homeTeamId, awayTeamId],
        ))
          p.playerId: p,
      };
      // Esamede olmayan oyuncu (ör. sonradan eklenen) adıyla okunur.
      final missing = byHighlight.values
          .where((id) => !players.containsKey(id))
          .toSet()
          .toList();
      final extra = <String, String>{};
      if (missing.isNotEmpty) {
        final rows = await _db
            .from('players')
            .select('id, name, surname')
            .inFilter('id', missing);
        for (final r in rows) {
          extra[r['id'].toString()] = [
            (r['name'] ?? '').toString().trim(),
            (r['surname'] ?? '').toString().trim(),
          ].where((x) => x.isNotEmpty).join(' ');
        }
      }
      byHighlight.forEach((hid, pid) {
        final p = players[pid];
        final name = p?.name ?? extra[pid] ?? '';
        if (name.isEmpty) return;
        result[hid] = (playerId: pid, name: name, jersey: p?.jersey);
      });
    }
    _scorers[matchId] = result;
    return result;
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
          ? 'Gol analizi bitti$who: $n gol kesiti bulundu, onay bekliyor.'
          : 'Gol analizi bitti$who: gol kesiti bulunamadı.';
    } else if (j.status == 'error') {
      msg = 'Gol analizi tamamlanamadı$who: ${j.error ?? 'bilinmeyen hata'}';
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
