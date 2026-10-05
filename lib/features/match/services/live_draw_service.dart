import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/fixture_draw.dart';

/// Açıklanmış bir eşleşme ([away] null ise rakip henüz açıklanmadı).
typedef LiveDrawPair = ({int week, String home, String? away});

/// Canlı kuranın sunucudaki anlık hali (get_live_draw).
class LiveDrawState {
  const LiveDrawState({
    required this.id,
    required this.leagueId,
    required this.seasonId,
    required this.title,
    required this.startWeek,
    required this.teamIds,
    required this.total,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.clockOffset,
    required this.revealed,
    required this.current,
    required this.byes,
    required this.nextIn,
  });

  final String id;
  final String leagueId;
  final String seasonId;
  final String title;
  final int startWeek;
  final List<String> teamIds;
  final int total;
  final DateTime startAt;
  final DateTime endAt;

  /// scheduled | done | cancelled
  final String status;

  /// Sunucu saati − cihaz saati: geri sayım herkes için aynı anı gösterir.
  final Duration clockOffset;
  final List<LiveDrawPair> revealed;

  /// Ev sahibi açıklanmış, rakibi beklenen eşleşme.
  final LiveDrawPair? current;

  /// Tamamlanan haftalarda bay geçen takım (hafta indeksi → takım).
  final Map<int, String> byes;

  /// Bir sonraki açıklamaya kalan süre (saniye); yoksa null.
  final double? nextIn;

  DateTime get serverNow => DateTime.now().add(clockOffset);
  bool get cancelled => status == 'cancelled';
  bool get done => status == 'done';
  bool get notStarted => !done && !cancelled && serverNow.isBefore(startAt);
  bool get live => !done && !cancelled && !notStarted;

  static LiveDrawState fromJson(Map<String, dynamic> j) {
    DateTime t(String k) => DateTime.parse(j[k].toString()).toLocal();
    final serverNow = t('server_now');
    LiveDrawPair pair(Map m) => (
      week: (m['w'] as num).toInt(),
      home: m['h'].toString(),
      away: m['a']?.toString(),
    );
    final cur = j['current'];
    return LiveDrawState(
      id: j['id'].toString(),
      leagueId: j['league_id'].toString(),
      seasonId: (j['season_id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      startWeek: (j['start_week'] as num?)?.toInt() ?? 1,
      teamIds: [for (final x in (j['team_ids'] as List? ?? const [])) '$x'],
      total: (j['total'] as num?)?.toInt() ?? 0,
      startAt: t('start_at'),
      endAt: t('end_at'),
      status: (j['status'] ?? 'scheduled').toString(),
      clockOffset: serverNow.difference(DateTime.now()),
      revealed: [
        for (final m in (j['revealed'] as List? ?? const [])) pair(m as Map),
      ],
      current: cur is Map ? pair(cur) : null,
      byes: {
        for (final b in (j['byes'] as List? ?? const []))
          ((b as Map)['w'] as num).toInt(): b['t'].toString(),
      },
      nextIn: (j['next_in'] as num?)?.toDouble(),
    );
  }
}

/// Canlı kura sunucu çağrıları. Tabloya doğrudan erişilmez; sonuç sunucuda
/// kilitlidir ve yalnız açıklanan kısmı döner.
class LiveDrawService {
  LiveDrawService._();
  static final instance = LiveDrawService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// İlk iki hafta takım takım (ev sahibi, 2 sn sonra rakip), sonrası maç
  /// maç açıklanır; haftalar arasında kısa ara.
  static const _teamByTeamWeeks = 2;
  static const _homeToAway = 2.0;
  static const _pairGapSlow = 3.5;
  static const _pairGapFast = 3.0;
  static const _weekGap = 1.5;

  Future<LiveDrawState?> fetch(String id) async {
    final res = await _sb.rpc('get_live_draw', params: {'p_id': id});
    if (res is! Map) return null;
    return LiveDrawState.fromJson(Map<String, dynamic>.from(res));
  }

  /// Gruptaki son (iptal edilmemiş) canlı kura.
  Future<LiveDrawState?> forGroup(String groupId) async {
    final res = await _sb.rpc(
      'live_draw_for_group',
      params: {'p_group_id': groupId},
    );
    if (res is! Map) return null;
    return LiveDrawState.fromJson(Map<String, dynamic>.from(res));
  }

  Future<void> cancel(String id) =>
      _sb.rpc('cancel_live_draw', params: {'p_id': id});

  /// Kurayı açıklama zamanlarıyla kaydeder ve haberini yayınlar.
  Future<String> create({
    required String leagueId,
    required String seasonId,
    required String groupId,
    required String groupName,
    required int startWeek,
    required DateTime startAt,
    required List<String> teamIds,
    required List<DrawWeek> weeks,
  }) async {
    final steps = <Map<String, dynamic>>[];
    final byes = <Map<String, dynamic>>[];
    var t = 1.5;
    for (var w = 0; w < weeks.length; w++) {
      final slow = w < _teamByTeamWeeks;
      for (final p in weeks[w].pairs) {
        steps.add({
          'w': w,
          'h': p.home,
          'a': p.away,
          'ht': t,
          'at': slow ? t + _homeToAway : t,
        });
        t += slow ? _pairGapSlow : _pairGapFast;
      }
      if (weeks[w].bye != null) byes.add({'w': w, 't': weeks[w].bye});
      t += _weekGap;
    }

    final names = await Future.wait([
      _sb.from('leagues').select('name').eq('id', leagueId).maybeSingle(),
      _sb.from('seasons').select('name').eq('id', seasonId).maybeSingle(),
    ]);
    final league = (names[0]?['name'] ?? '').toString().trim();
    final season = (names[1]?['name'] ?? '').toString().trim();
    final title = [
      league,
      season,
      groupName.trim(),
    ].where((e) => e.isNotEmpty).join(' · ');
    final when = _when(startAt);
    final content =
        'Canlı Kura Çekimi\n'
        '$title fikstürü $when canlı çekiliyor. Takımının hangi haftada '
        'kiminle eşleşeceğini ilk sen öğren.';

    final id = await _sb.rpc(
      'create_live_draw',
      params: {
        'p_league_id': leagueId,
        'p_season_id': seasonId,
        'p_group_id': groupId,
        'p_title': title,
        'p_start_week': startWeek,
        'p_start_at': startAt.toUtc().toIso8601String(),
        'p_team_ids': teamIds,
        'p_steps': steps,
        'p_byes': byes,
        'p_news_content': content,
      },
    );
    return id.toString();
  }

  /// Toplam açıklama süresi (önizleme metni için).
  static Duration estimate(List<DrawWeek> weeks) {
    var t = 1.5;
    for (var w = 0; w < weeks.length; w++) {
      final n = weeks[w].pairs.length;
      t += n * (w < _teamByTeamWeeks ? _pairGapSlow : _pairGapFast) + _weekGap;
    }
    return Duration(seconds: t.round());
  }

  static String _when(DateTime at) {
    final now = DateTime.now();
    if (at.difference(now).inMinutes < 2) return 'şimdi';
    final hm =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    if (sameDay) return 'bugün $hm\'de';
    return '${at.day}.${at.month.toString().padLeft(2, '0')} $hm\'de';
  }
}
