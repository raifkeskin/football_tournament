import 'package:supabase_flutter/supabase_flutter.dart';

/// Turnuva kanalında bulunan YouTube yayını.
class FoundBroadcast {
  const FoundBroadcast({required this.videoId, required this.title, this.at});

  final String videoId;
  final String title;
  final DateTime? at;

  String get thumbnail => 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';

  factory FoundBroadcast.fromMap(Map<String, dynamic> m) => FoundBroadcast(
    videoId: (m['video_id'] ?? '').toString(),
    title: (m['title'] ?? '').toString(),
    at: DateTime.tryParse((m['at'] ?? '').toString())?.toLocal(),
  );
}

/// Elle girilen yayın linki ile kanalda bulunan yayının uyuşmazlığı
/// (Bekleyen Onaylar › Yayın).
class YoutubeLinkConflict {
  const YoutubeLinkConflict({
    required this.id,
    required this.matchId,
    required this.leagueId,
    required this.manualUrl,
    required this.manual,
    required this.auto,
    required this.createdAt,
  });

  final String id;
  final String matchId;
  final String leagueId;
  final String manualUrl;

  /// Elle girilen video (YouTube'dan başlık alınamadıysa başlık boş).
  final FoundBroadcast? manual;
  final FoundBroadcast auto;
  final DateTime? createdAt;

  factory YoutubeLinkConflict.fromMap(Map<String, dynamic> m) {
    final manualId = (m['manual_video_id'] ?? '').toString();
    return YoutubeLinkConflict(
      id: m['id'].toString(),
      matchId: m['match_id'].toString(),
      leagueId: m['league_id'].toString(),
      manualUrl: (m['manual_url'] ?? '').toString(),
      manual: manualId.isEmpty
          ? null
          : FoundBroadcast(
              videoId: manualId,
              title: (m['manual_title'] ?? '').toString(),
              at: DateTime.tryParse(
                (m['manual_at'] ?? '').toString(),
              )?.toLocal(),
            ),
      auto: FoundBroadcast(
        videoId: (m['auto_video_id'] ?? '').toString(),
        title: (m['auto_title'] ?? '').toString(),
        at: DateTime.tryParse((m['auto_at'] ?? '').toString())?.toLocal(),
      ),
      createdAt: DateTime.tryParse(
        (m['created_at'] ?? '').toString(),
      )?.toLocal(),
    );
  }
}

/// YouTube yayınını maça bağlama (edge function youtube-autolink) ve
/// uyuşmazlık onayları.
class YoutubeAutolinkService {
  YoutubeAutolinkService([SupabaseClient? client])
    : _sb = client ?? Supabase.instance.client;

  final SupabaseClient _sb;

  /// Turnuvada "YouTube canlı yayın" açık mı?
  Future<bool> isEnabled(String leagueId) async {
    final row = await _sb
        .from('leagues')
        .select('youtube_live')
        .eq('id', leagueId)
        .maybeSingle();
    return row?['youtube_live'] == true;
  }

  /// Kanaldaki uygun yayınlar (en uygunu başta).
  Future<List<FoundBroadcast>> search(String matchId) async {
    final res = await _invoke({'action': 'search', 'match_id': matchId});
    return [
      for (final m in (res['items'] as List? ?? const []))
        FoundBroadcast.fromMap(Map<String, dynamic>.from(m as Map)),
    ];
  }

  /// Yayını maçın canlı yayın linki yapar.
  Future<void> attach(String matchId, String videoId) =>
      _invoke({'action': 'attach', 'match_id': matchId, 'video_id': videoId});

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _sb.functions.invoke('youtube-autolink', body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final d = e.details;
      throw d is Map && d['error'] != null
          ? d['error'].toString()
          : 'İşlem yapılamadı (${e.status}).';
    }
  }

  /// Bekleyen uyuşmazlıklar (RLS: admin, kurucu başkan, bölge sorumlusu).
  Future<List<YoutubeLinkConflict>> pendingConflicts() async {
    final rows = await _sb
        .from('youtube_link_conflicts')
        .select()
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return [for (final r in rows) YoutubeLinkConflict.fromMap(r)];
  }

  /// Karar: true → kanaldakini kullan, false → elle gireni koru.
  Future<void> resolve(String id, {required bool useAuto}) => _sb.rpc(
    'resolve_youtube_conflict',
    params: {'p_id': id, 'p_use_auto': useAuto},
  );
}
