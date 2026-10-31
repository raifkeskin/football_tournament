import 'package:supabase_flutter/supabase_flutter.dart';

import '../tournament/models/league_extras.dart';

/// Haber yorumu (`news_comments`).
class NewsComment {
  const NewsComment({
    required this.id,
    required this.newsId,
    required this.userId,
    required this.authorName,
    this.authorTeam,
    required this.body,
    required this.status,
    this.flagReason,
    this.createdAt,
    this.newsTitle = '',
  });

  final String id;
  final String newsId;
  final String userId;
  final String authorName;
  final String? authorTeam;
  final String body;

  /// 'published' | 'pending' | 'rejected'
  final String status;

  /// Onaya düşme sebebi ("salak", Bağlantı, Şikâyet (3 kişi)…).
  final String? flagReason;
  final DateTime? createdAt;

  /// Onay ekranında hangi habere yazıldığı.
  final String newsTitle;

  bool get isPending => status == 'pending';

  factory NewsComment.fromRow(Map<String, dynamic> r) {
    final news = r['news'];
    var title = '';
    if (news is Map) {
      final h = (news['headline'] ?? '').toString().trim();
      title = h.isNotEmpty
          ? h
          : (news['content'] ?? '').toString().split('\n').first.trim();
    }
    final team = (r['author_team'] ?? '').toString().trim();
    final reason = (r['flag_reason'] ?? '').toString().trim();
    return NewsComment(
      id: r['id'].toString(),
      newsId: (r['news_id'] ?? '').toString(),
      userId: (r['user_id'] ?? '').toString(),
      authorName: (r['author_name'] ?? '').toString(),
      authorTeam: team.isEmpty ? null : team,
      body: (r['body'] ?? '').toString(),
      status: (r['status'] ?? '').toString(),
      flagReason: reason.isEmpty ? null : reason,
      createdAt: DateTime.tryParse((r['created_at'] ?? '').toString()),
      newsTitle: title,
    );
  }
}

/// Tribün tepkisinin etiketi: yuva (1-3) haber türüne göre.
typedef NewsReaction = ({int slot, String emoji, String label});

List<NewsReaction> newsReactionsFor(NewsItem n) {
  List<NewsReaction> of(List<(String, String)> x) => [
    for (var i = 0; i < x.length; i++)
      (slot: i + 1, emoji: x[i].$1, label: x[i].$2),
  ];
  if (n.isMatchResult) {
    return of([
      ('👏', 'Hak etti'),
      ('🔥', 'Maç gibi maç'),
      ('🏆', 'Zirve kokusu'),
    ]);
  }
  if (n.isWeekResults) {
    return of([
      ('🍿', 'Nefes kesti'),
      ('📈', 'Yarış kızıştı'),
      ('👏', 'Güzel hafta'),
    ]);
  }
  if (n.isWeeklyPick) {
    return of([('👑', 'Hak etti'), ('🔥', 'Efsane'), ('🐐', 'GOAT')]);
  }
  if (n.isDayPreview) {
    return of([('🔥', 'Heyecanlı'), ('⚽', 'Gol olur'), ('👏', 'Bol şans')]);
  }
  return of([('👍', 'Beğendim'), ('❤️', 'Süper'), ('💯', 'Harika')]);
}

/// Maç önü haberinde tepkiler yerine "Kim kazanır?" anketi.
bool newsHasPoll(NewsItem n) => n.isMatchPreview && n.matchId != null;

/// Anketin oy toplamı.
int newsPollTotal(Map<String, int> poll) =>
    (poll['home'] ?? 0) + (poll['draw'] ?? 0) + (poll['away'] ?? 0);

/// Haberdeki tarih/saate göre maç başlamadı mı (oylama açık mı). Kesin
/// denetim veritabanında; bu yalnız görünüm için.
bool newsPollOpen(NewsItem n) {
  final d = n.autoData;
  final date = DateTime.tryParse((d?['date'] ?? '').toString());
  if (date == null) return false;
  final m = RegExp(
    r'^(\d{1,2}):(\d{2})$',
  ).firstMatch((d?['time'] ?? '').toString().trim());
  final kickoff = m == null
      ? DateTime(date.year, date.month, date.day + 1)
      : DateTime(
          date.year,
          date.month,
          date.day,
          int.parse(m.group(1)!),
          int.parse(m.group(2)!),
        );
  return DateTime.now().isBefore(kickoff);
}

/// Tepki ve yorum işlemleri (yazma yalnız veritabanı fonksiyonlarıyla).
class NewsTalkService {
  NewsTalkService._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Hata mesajı: veritabanının Türkçe açıklaması.
  static String message(Object e) =>
      e is PostgrestException ? e.message : e.toString();

  static Future<int?> myReaction(String newsId) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _sb
        .from('news_reactions')
        .select('slot')
        .eq('news_id', newsId)
        .eq('user_id', uid)
        .maybeSingle();
    return (row?['slot'] as num?)?.toInt();
  }

  /// Tepki verir / değiştirir; aynı tepki ya da null: geri alır.
  static Future<int?> react(String newsId, int? slot) async {
    final r = await _sb.rpc(
      'news_react',
      params: {'p_news_id': newsId, 'p_slot': slot},
    );
    return (r as num?)?.toInt();
  }

  static Future<String?> myPick(String matchId) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _sb
        .from('match_predictions')
        .select('pick')
        .eq('match_id', matchId)
        .eq('user_id', uid)
        .maybeSingle();
    return row?['pick']?.toString();
  }

  /// Ankete oy verir ya da oyu değiştirir ('home' | 'draw' | 'away').
  static Future<void> predict(String matchId, String pick) =>
      _sb.rpc('match_predict', params: {'p_match_id': matchId, 'p_pick': pick});

  /// Haberin güncel anket sayıları.
  static Future<Map<String, int>> poll(String newsId) async {
    final row = await _sb
        .from('news')
        .select('poll')
        .eq('id', newsId)
        .maybeSingle();
    final p = row?['poll'];
    return {
      if (p is Map)
        for (final e in p.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toInt(),
    };
  }

  static Future<List<NewsComment>> comments(String newsId) async {
    final rows = await _sb
        .from('news_comments')
        .select(
          'id, news_id, user_id, author_name, author_team, body, status, '
          'flag_reason, created_at',
        )
        .eq('news_id', newsId)
        .neq('status', 'rejected')
        .order('created_at', ascending: false)
        .limit(200);
    return rows.map(NewsComment.fromRow).toList();
  }

  /// 'published' ya da 'pending' döner; küfürde hata.
  static Future<String> add(String newsId, String body) async {
    final r = await _sb.rpc(
      'news_comment_add',
      params: {'p_news_id': newsId, 'p_body': body},
    );
    return r.toString();
  }

  static Future<void> delete(String id) =>
      _sb.rpc('news_comment_delete', params: {'p_id': id});

  static Future<void> report(String id) =>
      _sb.rpc('news_comment_report', params: {'p_id': id});

  /// 'publish' | 'reject' | 'ban'
  static Future<void> review(String id, String action) async {
    await _sb.rpc(
      'news_comment_review',
      params: {'p_id': id, 'p_action': action},
    );
    _pending.clear();
  }

  /// Turnuvada onay bekleyen yorumlar (sorumlu görür; RLS süzer).
  static Future<List<NewsComment>> pending(String leagueId) async {
    final rows = await _sb
        .from('news_comments')
        .select(
          'id, news_id, user_id, author_name, author_team, body, status, '
          'flag_reason, created_at, '
          'news!inner(headline, content, seasons!inner(league_id))',
        )
        .eq('status', 'pending')
        .eq('news.seasons.league_id', leagueId)
        .order('created_at')
        .limit(100);
    return rows.map(NewsComment.fromRow).toList();
  }

  static final _pending = <String, (DateTime, Future<int>)>{};

  /// Ana sayfa uyarısı için sayı; bir dakika önbellekte.
  static Future<int> pendingCount(String leagueId) {
    final hit = _pending[leagueId];
    if (hit != null &&
        DateTime.now().difference(hit.$1) < const Duration(minutes: 1)) {
      return hit.$2;
    }
    final f = pending(leagueId).then((l) => l.length, onError: (_) => 0);
    _pending[leagueId] = (DateTime.now(), f);
    return f;
  }
}
