import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/resilient_stream.dart';
import '../../tournament/models/league.dart';
import '../models/match.dart';
import '../widgets/match_schedule_dialog.dart';
import '../widgets/penalty_badge.dart';
import '../../team/models/team.dart';
import '../../../core/services/app_session.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import 'match_details_screen.dart';
import '../utils/match_clock.dart';
import '../widgets/quick_score_dialog.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/widgets/admin_form.dart';
import '../../share/poster_background.dart';
import '../../share/fixture_poster.dart';
import '../../share/poster_share.dart';
import '../../../core/utils/team_name.dart';

import '../../../core/widgets/app_date_picker.dart';
import '../../../core/utils/string_utils.dart';

/// Bir turnuva + sezon + grubun haftalık fikstürü (üstte hafta şeridi).
/// Başlık çubuğu yok; Turnuva Sayfası'nın Fikstür sekmesinde gösterilir.
/// Hızlı skor, erteleme ve tarih düzenleme akışları maç kartlarında.
class FixtureView extends StatefulWidget {
  const FixtureView({
    super.key,
    required this.leagueId,
    required this.seasonId,
    required this.groupId,
    this.shareAction,
    this.accent = const Color(0xFF10B981),
  });

  final String leagueId;
  final String seasonId;
  final String groupId;

  /// Seçili haftanın afişini paylaşma işlevi (yetki ve maç varsa dolu);
  /// paylaş düğmesi sayfanın kendisinde.
  final ValueNotifier<VoidCallback?>? shareAction;

  /// Turnuvanın rengi (sekmelerle aynı); hafta ve gün seçimi bu renkte.
  final Color accent;

  @override
  State<FixtureView> createState() => _FixtureViewState();
}

class _FixtureViewState extends State<FixtureView> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final IMatchService _matchService = ServiceLocator.matchService;
  final ITeamService _teamService = ServiceLocator.teamService;
  String get _leagueId => widget.leagueId;
  String get _seasonId => widget.seasonId;
  int? _week;

  /// Gün şeridinde seçili gün (maç tarihi 'yyyy-MM-dd' ya da tarihsiz);
  /// hafta değişince sıfırlanır.
  String? _day;

  /// Gün başlıklarına kaydırmak için anahtarlar (tarih → başlık).
  final Map<String, GlobalKey> _dayKeys = {};

  void _selectWeek(int w) => setState(() {
    _week = w;
    _day = null;
  });

  void _selectDay(String key) {
    setState(() => _day = key);
    final ctx = _dayKeys[key]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// [_week] hangi turnuva|sezon|grup için seçildi; grup (bölge) değişince
  /// o grubun güncel haftası açılır.
  String? _weekKey;

  /// Filtre (turnuva|sezon|grup) başına hafta bilgisi önbelleği.
  final Map<String, Future<({int? maxWeek, int? nextWeek})>> _weekInfo = {};

  /// En büyük hafta ve varsayılan (güncel) hafta: en son oynanan haftadan
  /// itibaren oynanmamış maçı olan ilk hafta (o haftanın kalan maçları
  /// sürüyorsa aynı hafta); hepsi oynandıysa son oynanan hafta. Ertelenmiş
  /// eski maçlar (ör. 5. hafta oynanırken bekleyen 3. hafta maçı) seçimi
  /// geriye çekmez.
  Future<({int? maxWeek, int? nextWeek})> _loadWeekInfo(
    String leagueId,
    String? seasonId,
    String? groupId,
  ) async {
    // Son hafta seçili sezon/grubun (bölgenin) kendi maçlarından: bölgelerin
    // hafta sayısı farklı olabilir; olmayan hafta listede görünmez.
    int? maxWeek;
    int? nextWeek;
    try {
      var q = Supabase.instance.client
          .from('matches')
          .select('week, status')
          .eq('league_id', leagueId);
      if (seasonId != null) q = q.eq('season_id', seasonId);
      if (groupId != null) q = q.eq('group_id', groupId);
      final rows = await q;

      int? lastPlayed;
      int? firstAny;
      final unplayed = <int>[];
      for (final r in rows) {
        final w = r['week'];
        final week = w is num ? w.toInt() : int.tryParse('${w ?? ''}');
        if (week == null) continue;
        if (firstAny == null || week < firstAny) firstAny = week;
        if (maxWeek == null || week > maxWeek) maxWeek = week;
        final status = (r['status'] ?? '').toString().trim();
        if (status == MatchStatus.finished.name) {
          if (lastPlayed == null || week > lastPlayed) lastPlayed = week;
        } else if (status != MatchStatus.cancelled.name) {
          unplayed.add(week);
        }
      }
      final pending = unplayed
          .where((w) => lastPlayed == null || w >= lastPlayed)
          .toList();
      nextWeek = pending.isNotEmpty
          ? pending.reduce((a, b) => a < b ? a : b)
          : (lastPlayed ?? firstAny);
    } catch (_) {}
    return (maxWeek: maxWeek, nextWeek: nextWeek);
  }

  Stream<List<Team>>? _teamsStream;
  Stream<League?>? _leagueStream;
  Stream<List<GroupModel>>? _groupsStream;

  @override
  void initState() {
    super.initState();
    _teamsStream = _teamService.watchAllTeams();
    _leagueStream = _leagueService.watchLeagueById(_leagueId);
    _groupsStream = _leagueService.watchGroups(_seasonId);
  }

  @override
  void didUpdateWidget(covariant FixtureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leagueId != widget.leagueId) {
      _leagueStream = _leagueService.watchLeagueById(_leagueId);
    }
    if (oldWidget.seasonId != widget.seasonId) {
      _groupsStream = _leagueService.watchGroups(_seasonId);
    }
  }

  @override
  void dispose() {
    widget.shareAction?.value = null;
    super.dispose();
  }

  // Fikstür maç akışı: yalnızca turnuva/sezon/grup/hafta değişince yeniden
  // kurulur (önceden her yeniden çizimde tekrar sorgulanıyordu).
  Stream<List<MatchModel>>? _fixtureMatchesStream;
  String? _fixtureMatchesKey;

  Stream<List<MatchModel>> _fixtureStream(
    String leagueId,
    String seasonId,
    String? groupId,
    int week,
  ) {
    final key = '$leagueId|$seasonId|${groupId ?? ''}|$week';
    if (_fixtureMatchesStream == null || _fixtureMatchesKey != key) {
      _fixtureMatchesKey = key;
      _fixtureMatchesStream = resilientStream(
        () => _matchService.watchFixtureMatches(
          leagueId,
          week,
          groupId: groupId,
          seasonId: seasonId,
        ),
      );
    }
    return _fixtureMatchesStream!;
  }

  DateTime? _parseYyyyMmDd(String yyyyMmDd) {
    final s = yyyyMmDd.trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final y = int.tryParse(m.group(1) ?? '');
    final mo = int.tryParse(m.group(2) ?? '');
    final d = int.tryParse(m.group(3) ?? '');
    if (y == null || mo == null || d == null) return null;
    return DateTime(y, mo, d);
  }

  String _dateStripText(String yyyyMmDd) {
    final s = yyyyMmDd.trim();
    final dt = _parseYyyyMmDd(s);
    if (dt == null) return s;
    return DateFormat('dd.MM.yyyy EEEE', 'tr_TR').format(dt);
  }

  /// Seçili turnuva / grup / haftanın maçlarıyla fikstür afişi hazırlar.
  Future<void> _shareFixturePoster({
    required League league,
    required String groupName,
    required int week,
    required List<MatchModel> matches,
    required Map<String, String> teamNameById,
    required Map<String, String> teamLogoById,
  }) async {
    final pitchNameById = <String, String>{};
    try {
      for (final p in await _leagueService.watchPitches().first) {
        pitchNameById[p.id] = p.name.trim();
      }
    } catch (_) {
      // Saha adları gelmezse afiş sahasız hazırlanır.
    }
    // Bay geçen takım(lar): grubun takımlarından bu hafta maçı olmayanlar.
    final byes = <PosterTeam>[];
    try {
      final groupIds = {
        for (final m in matches)
          if ((m.groupId ?? '').isNotEmpty) m.groupId!,
      };
      final playing = {
        for (final m in matches) ...[m.homeTeamId, m.awayTeamId],
      };
      if (groupIds.isNotEmpty) {
        final rows = await Supabase.instance.client
            .from('season_teams')
            .select('team_id, teams(name, logo_url)')
            .inFilter('group_id', groupIds.toList());
        for (final r in rows) {
          final id = (r['team_id'] ?? '').toString();
          if (id.isEmpty || playing.contains(id)) continue;
          final t = r['teams'] is Map ? r['teams'] as Map : const {};
          byes.add(
            PosterTeam(
              name: (t['name'] ?? teamNameById[id] ?? '').toString().trim(),
              logo: (t['logo_url'] ?? teamLogoById[id] ?? '').toString().trim(),
            ),
          );
        }
      }
    } catch (_) {
      // Bay bilgisi gelmezse afiş baysız hazırlanır.
    }
    if (!mounted) return;

    String dateText(String? ymd) {
      final d = DateTime.tryParse((ymd ?? '').trim());
      return d == null
          ? 'Tarih belirsiz'
          : DateFormat('dd.MM.yyyy EEEE', 'tr_TR').format(d);
    }

    // Gün + saha bazında gruplanır (sıralı maç listesi korunur).
    final days = <String, List<MatchModel>>{};
    for (final m in matches) {
      (days['${m.matchDate ?? ''}|${m.pitchId ?? ''}'] ??= []).add(m);
    }
    PosterMatch toPoster(MatchModel m) {
      final t = (m.matchTime ?? '').trim();
      final played = m.status == MatchStatus.finished;
      return PosterMatch(
        homeName: teamNameById[m.homeTeamId] ?? 'Ev Sahibi',
        awayName: teamNameById[m.awayTeamId] ?? 'Deplasman',
        homeLogo: (teamLogoById[m.homeTeamId] ?? '').trim(),
        awayLogo: (teamLogoById[m.awayTeamId] ?? '').trim(),
        time: t.isEmpty
            ? '--.--'
            : (t.length >= 5 ? t.substring(0, 5) : t).replaceAll(':', '.'),
        score: played ? '${m.homeScore} - ${m.awayScore}' : null,
      );
    }

    final posterDays = [
      for (final e in days.entries)
        PosterDay(
          dateText: dateText(e.value.first.matchDate),
          pitchText: pitchNameById[e.value.first.pitchId ?? ''] ?? '',
          matches: [for (final m in e.value) toPoster(m)],
        ),
    ];
    final logos = <String>{
      league.logoUrl,
      for (final d in posterDays)
        for (final m in d.matches) ...[m.homeLogo, m.awayLogo],
      for (final b in byes) b.logo,
    }.where((u) => u.isNotEmpty).toList();

    // Haftanın bütün maçları bittiyse afiş "Maç Sonuçları" olarak çıkar.
    final results =
        matches.isNotEmpty &&
        matches.every((m) => m.status == MatchStatus.finished);
    await showPosterPreview(
      context: context,
      fileName: results
          ? 'mac_sonuclari_${week}_hafta'
          : 'fikstur_${week}_hafta',
      imageUrls: logos,
      leagueId: league.id,
      kind: results ? PosterKind.results : PosterKind.fixture,
      formats: const [PosterFormat.post, PosterFormat.story],
      poster: FixturePoster(
        leagueName: league.name,
        leagueLogo: league.logoUrl,
        subtitle: results
            ? (groupName.isEmpty ? 'Maç Sonuçları' : '$groupName Maç Sonuçları')
            : (groupName.isEmpty ? 'Fikstür' : '$groupName Fikstür'),
        weekText: results ? '$week. Hafta Maç Sonuçları' : '$week. Hafta',
        days: posterDays,
        byes: byes,
      ),
    );
  }

  /// Fikstür üst kısmı: hafta şeridi. Paylaş işlevi sayfaya bildirilir.
  Widget _buildFixtureHeader({
    required BuildContext context,
    required League? league,
    required List<int> weeks,
    required int week,
    required String groupName,
    required List<MatchModel> matches,
    required Map<String, String> teamNameById,
    required Map<String, String> teamLogoById,
  }) {
    final canShare =
        league != null &&
        matches.isNotEmpty &&
        AppSession.of(context).value.canManageLeague(_leagueId);
    final VoidCallback? share = !canShare
        ? null
        : () => _shareFixturePoster(
            league: league,
            groupName: groupName,
            week: week,
            matches: matches,
            teamNameById: teamNameById,
            teamLogoById: teamLogoById,
          );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.shareAction?.value = share;
    });

    // Haftanın maç günleri (ertelenip başka güne alınan maç kendi gününde
    // görünür). Nokta: hepsi bitti yeşil, canlı kırmızı, oynanmadı gri.
    final dayStatus = <String, Color>{};
    for (final m in matches) {
      final k = _dayKeyOf(m);
      final live =
          m.status == MatchStatus.live || m.status == MatchStatus.halftime;
      final done =
          m.status == MatchStatus.finished || m.status == MatchStatus.cancelled;
      final prev = dayStatus[k];
      dayStatus[k] = live || prev == _FixtureDayStrip.live
          ? _FixtureDayStrip.live
          : (done && (prev == null || prev == _FixtureDayStrip.done))
          ? _FixtureDayStrip.done
          : _FixtureDayStrip.upcoming;
    }
    // Tarihi belirlenmemiş maçlar şeritte gösterilmez (listede kendi
    // başlıklarıyla durur); hiç tarihli maç yoksa şerit çıkmaz.
    final days =
        dayStatus.keys.where((k) => k != _FixtureDayStrip.noDate).toList()
          ..sort();
    final selectedDay = days.contains(_day)
        ? _day
        : (days.isEmpty ? null : days.first);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WeekHeader(
            weeks: weeks,
            week: week,
            accent: widget.accent,
            onSelect: _selectWeek,
          ),
          if (days.isNotEmpty) ...[
            const SizedBox(height: 10),
            _FixtureDayStrip(
              days: days,
              status: dayStatus,
              selected: selectedDay,
              accent: widget.accent,
              onSelect: _selectDay,
            ),
          ],
        ],
      ),
    );
  }

  static String _dayKeyOf(MatchModel m) {
    final d = (m.matchDate ?? '').trim();
    return d.isEmpty ? _FixtureDayStrip.noDate : d;
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    final bool isAdmin = session.isAdmin;
    // Tarih / saat / saha düzenleme ve maç menüsü: admin, kurucu başkan ve
    // bölge sorumlusu görür (veritabanı kuralı owns_league / owns_group).
    final ownsLeague = session.canManageLeague(_leagueId);
    final myRegions = session.regionsInSeason(_seasonId);
    final canEditSchedule = ownsLeague || myRegions.isNotEmpty;
    final cardBg = Colors.black.withValues(alpha: 0.3);
    final outline = Colors.white.withValues(alpha: 0.08);

    return StreamBuilder<List<Team>>(
      stream: _teamsStream,
      builder: (context, teamsSnap) {
        final teamLogoById = <String, String>{};
        final teamNameById = <String, String>{};
        for (final t in teamsSnap.data ?? const <Team>[]) {
          teamLogoById[t.id] = t.logoUrl;
          teamNameById[t.id] = t.name;
        }
        return StreamBuilder<League?>(
          stream: _leagueStream,
          builder: (context, leagueSnap) {
            final league = leagueSnap.data;
            return StreamBuilder<List<GroupModel>>(
              stream: _groupsStream,
              builder: (context, groupsSnap) {
                final groups = groupsSnap.data ?? const <GroupModel>[];
                final groupName = groups.length > 1
                    ? (groups
                              .where((g) => g.id == widget.groupId)
                              .firstOrNull
                              ?.name ??
                          '')
                    : '';
                final weekKey = '$_leagueId|$_seasonId|${widget.groupId}';
                return FutureBuilder<({int? maxWeek, int? nextWeek})>(
                  key: ValueKey(weekKey),
                  future: _weekInfo.putIfAbsent(
                    weekKey,
                    () => _loadWeekInfo(_leagueId, _seasonId, widget.groupId),
                  ),
                  builder: (context, weekSnap) {
                    // Bilgi gelmeden hafta seçilmez; aksi halde geçici olarak
                    // 1. hafta seçilip kalıcı oluyordu.
                    if (!weekSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final info = weekSnap.data!;
                    final maxWeek = info.maxWeek ?? 1;
                    final safeMaxWeek = maxWeek > 0 ? maxWeek : 1;
                    final weeks = <int>[
                      for (var i = 1; i <= safeMaxWeek; i++) i,
                    ];

                    // Kullanıcı hafta seçmediyse: oynanmamış ilk maçın haftası.
                    final defaultWeek = weeks.contains(info.nextWeek)
                        ? info.nextWeek
                        : weeks.first;
                    final userWeek = _weekKey == weekKey ? _week : null;
                    final displayWeek = weeks.contains(userWeek)
                        ? userWeek
                        : defaultWeek;

                    if (_week != displayWeek || _weekKey != weekKey) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _week = displayWeek;
                            _weekKey = weekKey;
                          });
                        }
                      });
                    }

                    return StreamBuilder<List<MatchModel>>(
                      stream: displayWeek == null
                          ? const Stream.empty()
                          : _fixtureStream(
                              _leagueId,
                              _seasonId,
                              widget.groupId,
                              displayWeek,
                            ),
                      builder: (context, matchesSnap) {
                        if (matchesSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final matches = (matchesSnap.data ?? [])
                          ..sort((a, b) {
                            final dateComp = (a.matchDate ?? '').compareTo(
                              b.matchDate ?? '',
                            );
                            if (dateComp != 0) return dateComp;
                            return (a.matchTime ?? '').compareTo(
                              b.matchTime ?? '',
                            );
                          });

                        final header = _buildFixtureHeader(
                          context: context,
                          league: league,
                          weeks: weeks,
                          week: displayWeek ?? 1,
                          groupName: groupName,
                          matches: matches,
                          teamNameById: teamNameById,
                          teamLogoById: teamLogoById,
                        );
                        // Başlık listeyle birlikte kayar; aşağı kaydırınca
                        // ekranın tamamı maçlara kalır.
                        return _FixtureList(
                          header: header,
                          dayKeys: _dayKeys,
                          matches: matches,
                          dateStripText: _dateStripText,
                          groupNameById: {for (final g in groups) g.id: g.name},
                          showGroupInHeader: false,
                          teamLogoById: teamLogoById,
                          teamNameById: teamNameById,
                          isAdmin: isAdmin,
                          canEditSchedule: canEditSchedule,
                          // Bölge sorumlusu yalnız kendi bölgesinin grubunda
                          // işlem yapar; başka grupta uyarı görür.
                          canActOnGroup:
                              ownsLeague ||
                              myRegions.any(
                                (r) =>
                                    r.id ==
                                    groups
                                        .where((g) => g.id == widget.groupId)
                                        .firstOrNull
                                        ?.regionId,
                              ),
                          onMatchTap: (m) => Navigator.push(
                            context,
                            MaterialPageRoute(
                              settings: const RouteSettings(
                                name: 'MatchDetailsScreen',
                              ),
                              builder: (_) => MatchDetailsScreen(match: m),
                            ),
                          ),
                          cardColor: cardBg,
                          outlineColor: outline,
                          // Akış önbellekli; kayıttan sonra hafta listesi
                          // yeniden okunsun.
                          onDataChanged: () => setState(() {
                            _fixtureMatchesStream = null;
                            _weekInfo.remove(weekKey);
                          }),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FixtureList extends StatelessWidget {
  const _FixtureList({
    required this.header,
    required this.dayKeys,
    required this.matches,
    required this.dateStripText,
    required this.groupNameById,
    required this.showGroupInHeader,
    required this.teamLogoById,
    required this.teamNameById,
    required this.onMatchTap,
    required this.cardColor,
    required this.outlineColor,
    required this.isAdmin,
    required this.canEditSchedule,
    required this.canActOnGroup,
    required this.onDataChanged,
  });

  final bool canEditSchedule;
  final bool canActOnGroup;
  final Widget header;
  final Map<String, GlobalKey> dayKeys;
  final List<MatchModel> matches;
  final String Function(String yyyyMmDd) dateStripText;
  final Map<String, String> groupNameById;
  final bool showGroupInHeader;
  final Map<String, String> teamLogoById;
  final Map<String, String> teamNameById;
  final void Function(MatchModel match) onMatchTap;
  final Color cardColor;
  final Color outlineColor;
  final bool isAdmin;
  final VoidCallback onDataChanged;

  @override
  Widget build(BuildContext context) {
    String groupLabel(String groupId) {
      final name = groupNameById[groupId] ?? 'Grup';
      return name.toLowerCase().contains('grup') ? name : '$name Grubu';
    }

    final byDate = <String, List<MatchModel>>{};
    for (final m in matches) {
      final dateKey = (m.matchDate ?? '').trim().isEmpty
          ? _FixtureDayStrip.noDate
          : m.matchDate!.trim();
      (byDate[dateKey] ??= []).add(m);
    }

    final sortedDates = byDate.keys.toList()..sort();

    String dayLabel(String key) {
      if (key == _FixtureDayStrip.noDate) return 'Tarih Belirlenmedi';
      final dt = DateTime.tryParse(key);
      if (dt == null) return key;
      // Ör. "04 Ekim Pazar"
      return DateFormat('dd MMMM EEEE', 'tr_TR').format(dt);
    }

    // Liste kısa (bir hafta); tüm gün başlıkları kurulsun ki gün şeridi
    // uzaktaki güne de kaydırabilsin.
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (matches.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(
                child: Text(
                  'Maç bulunamadı.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          for (final dKey in sortedDates) ...[
            Padding(
              key: dayKeys.putIfAbsent(dKey, GlobalKey.new),
              padding: const EdgeInsets.fromLTRB(70, 12, 16, 6),
              child: Text(
                dayLabel(dKey),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            ..._buildGroupedSection(byDate[dKey]!, groupLabel),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildGroupedSection(
    List<MatchModel> matchesInDate,
    String Function(String) groupLabel,
  ) {
    final groupedByGroup = <String, List<MatchModel>>{};
    for (var m in matchesInDate) {
      final gId = m.groupId ?? '';
      (groupedByGroup[gId] ??= []).add(m);
    }

    final sortedGroupIds = groupedByGroup.keys.toList()..sort();
    final List<Widget> items = [];

    for (var gId in sortedGroupIds) {
      if (showGroupInHeader && gId.isNotEmpty) {
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(70, 2, 16, 6),
            child: Text(
              groupLabel(gId).trUpper,
              style: TextStyle(
                color: Colors.amberAccent.withValues(alpha: 0.8),
                fontWeight: FontWeight.w800,
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ),
        );
      }

      final groupMatches = groupedByGroup[gId]!;
      for (int i = 0; i < groupMatches.length; i++) {
        final m = groupMatches[i];
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
            child: _MatchCard(
              match: m,
              teamLogoById: teamLogoById,
              teamNameById: teamNameById,
              isAdmin: isAdmin,
              canEditSchedule: canEditSchedule,
              canActOnGroup: canActOnGroup,
              onTap: () => onMatchTap(m),
              onDataChanged: onDataChanged,
            ),
          ),
        );
      }
    }
    return items;
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.teamLogoById,
    required this.teamNameById,
    required this.onTap,
    required this.isAdmin,
    required this.canEditSchedule,
    required this.canActOnGroup,
    required this.onDataChanged,
  });

  /// Tarih / saat düzenleme düğmesi ve maç menüsü (admin, kurucu, bölge
  /// sorumlusu).
  final bool canEditSchedule;

  /// Bu grupta işlem yetkisi (bölge sorumlusu yalnız kendi bölgesinde).
  final bool canActOnGroup;

  bool _guard(BuildContext context) {
    if (canActOnGroup) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bu işlem için yetkiniz bulunmamaktadır.'),
        duration: Duration(seconds: 2),
      ),
    );
    return false;
  }


  final MatchModel match;
  final Map<String, String> teamLogoById;
  final Map<String, String> teamNameById;
  final VoidCallback onTap;
  final bool isAdmin;
  final VoidCallback onDataChanged;

  @override
  Widget build(BuildContext context) {
    final homeName = (teamNameById[match.homeTeamId] ?? '').trim();
    final awayName = (teamNameById[match.awayTeamId] ?? '').trim();

    return MatchClockBuilder(
      match: match,
      builder: (context, liveMinute) => _timelineItem(
        context,
        homeName.isEmpty ? 'Ev Sahibi' : homeName,
        awayName.isEmpty ? 'Deplasman' : awayName,
        liveMinute,
      ),
    );
  }

  void _onLongPress(BuildContext context) {
    if (!canEditSchedule || !_guard(context)) return;
    _showMatchActions(context);
  }

  /// Yönetici menüsü: hızlı skor, ertele, iptal et, yeniden oynanacak yap.
  Future<void> _showMatchActions(BuildContext context) async {
    final unplayed =
        match.status == MatchStatus.postponed ||
        match.status == MatchStatus.cancelled;
    final actions = <(String, String)>[
      ('score', 'Hızlı Skor Girişi'),
      ('postpone', 'Ertelendi (ERT)'),
      if (match.status != MatchStatus.cancelled)
        ('cancel', 'İptal Edildi (İPT)'),
      if (unplayed) ('restore', 'Oynanacak (Erteleme/İptali Kaldır)'),
    ];
    final picked = await showAdminOptionPicker<(String, String)>(
      context: context,
      title: 'Maç İşlemleri',
      items: actions,
      labelBuilder: (a) => a.$2,
      emptyText: 'İşlem yok.',
    );
    if (picked == null || !context.mounted) return;
    switch (picked.$1) {
      case 'score':
        _showQuickScoreDialog(context);
      case 'postpone':
        await _postpone(context);
      case 'cancel':
        await _setStatus(
          context,
          MatchStatus.cancelled,
          confirm:
              'Maç iptal edilsin mi? Oynanmamış sayılır; puan durumuna ve '
              'istatistiğe yansımaz.',
        );
      case 'restore':
        await _setStatus(context, MatchStatus.notStarted);
    }
  }

  /// Erteleme: yeni tarih (isteğe bağlı saat) sorulur; tarih seçilmezse
  /// maç tarihsiz ertelenmiş kalır.
  Future<void> _postpone(BuildContext context) async {
    final current = DateTime.tryParse((match.matchDate ?? '').trim());
    final date = await showAppDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      title: 'Ertelenen Tarih',
    );
    if (!context.mounted) return;
    TimeOfDay? time;
    if (date != null) {
      final raw = (match.matchTime ?? '').trim();
      final parts = raw.split(':');
      time = await showTimePicker(
        context: context,
        helpText: 'Maç Saati',
        initialTime: parts.length >= 2
            ? TimeOfDay(
                hour: int.tryParse(parts[0]) ?? 20,
                minute: int.tryParse(parts[1]) ?? 0,
              )
            : const TimeOfDay(hour: 20, minute: 0),
      );
      if (!context.mounted) return;
    }
    String two(int v) => v.toString().padLeft(2, '0');
    await _setStatus(
      context,
      MatchStatus.postponed,
      matchDate: date == null
          ? null
          : '${date.year}-${two(date.month)}-${two(date.day)}',
      matchTime: time == null ? null : '${two(time.hour)}:${two(time.minute)}',
    );
  }

  Future<void> _setStatus(
    BuildContext context,
    MatchStatus status, {
    String? confirm,
    String? matchDate,
    String? matchTime,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (confirm != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(confirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Evet'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ServiceLocator.matchService.setMatchSchedulingStatus(
        matchId: match.id,
        status: status,
        matchDate: matchDate,
        matchTime: matchTime,
      );
      onDataChanged();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // Zaman çizelgesi satırı: solda saat/durum, ortada çizgi ve nokta, sağda
  // iki takımlı kart. Kazanan beyaz ve kalın, kaybeden soluk.
  /// Planlanan saatten 2 saat geçti mi (saat yoksa hayır).
  static bool _isOverdue(MatchModel m) {
    final d = DateTime.tryParse((m.matchDate ?? '').trim());
    final t = RegExp(
      r'^(\d{1,2}):(\d{2})',
    ).firstMatch((m.matchTime ?? '').trim());
    if (d == null || t == null) return false;
    final start = DateTime(
      d.year,
      d.month,
      d.day,
      int.parse(t.group(1)!),
      int.parse(t.group(2)!),
    );
    return DateTime.now().isAfter(start.add(const Duration(hours: 2)));
  }

  Widget _timelineItem(
    BuildContext context,
    String homeName,
    String awayName,
    String? liveMinute,
  ) {
    const mid = Color(0xFF94A3B8);
    const accent = Color(0xFF10B981);
    const live = Color(0xFFF87171);

    final rawTime = (match.matchTime ?? '').trim();
    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
    final isLive =
        match.status == MatchStatus.live ||
        match.status == MatchStatus.halftime;
    // Sorumluya: maç saatinden 2 saat geçmiş, sonucu girilmemiş maç.
    final overdue =
        match.status != MatchStatus.finished &&
        match.displayStatus != MatchStatus.postponed &&
        match.status != MatchStatus.cancelled &&
        _isOverdue(match) &&
        AppSession.of(context).value.canManageLeague(match.leagueId);
    final ({String text, Color color})? status = overdue
        ? (text: 'SKOR?', color: const Color(0xFFF59E0B))
        : switch (match.displayStatus) {
            MatchStatus.notStarted => null,
            MatchStatus.finished => (text: 'MS', color: accent),
            MatchStatus.halftime => (text: 'İY', color: live),
            MatchStatus.live => (text: liveMinute ?? 'CANLI', color: live),
            MatchStatus.cancelled => (text: 'İPT', color: Colors.white54),
            MatchStatus.postponed => (text: 'ERT', color: Colors.white54),
          };
    final dotColor = isLive
        ? live
        : (match.status == MatchStatus.finished ? accent : Colors.white38);

    final hs = match.homeScore;
    final as = match.awayScore;
    // Ertelenen / iptal maçta skor yerine ERT / İPT yazar (yeni güne
    // alınmış ertelenen maç oynanacak maç gibi görünür).
    final unplayed =
        match.displayStatus == MatchStatus.postponed ||
        match.displayStatus == MatchStatus.cancelled;
    final cancelled = match.displayStatus == MatchStatus.cancelled;
    // Kazanan (eleme maçında penaltılarla); berabere ise null.
    final winner = match.homeWins;
    final showScore =
        !unplayed &&
        (match.status == MatchStatus.finished || isLive || hs != 0 || as != 0);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    time.isEmpty ? '--:--' : time,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        status.text,
                        style: TextStyle(
                          color: status.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  if (canEditSchedule)
                    IconButton(
                      padding: const EdgeInsets.only(top: 6),
                      constraints: const BoxConstraints(),
                      tooltip: 'Tarih / saat düzenle',
                      icon: const Icon(
                        Icons.edit_calendar,
                        size: 18,
                        color: mid,
                      ),
                      onPressed: () {
                        if (_guard(context)) _showEditPopup(context);
                      },
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 22,
            child: Stack(
              children: [
                Positioned(
                  left: 10,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 12,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0F172A),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: const Color(0xFF152036).withValues(alpha: 0.9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isLive
                        ? live.withValues(alpha: 0.45)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTap,
                  onLongPress: () => _onLongPress(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (match.cupLabel != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    match.cupLabel!.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF60A5FA),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                              _teamLine(
                                homeName,
                                (teamLogoById[match.homeTeamId] ?? '').trim(),
                                showScore ? '$hs' : '-',
                                !showScore || (winner ?? true),
                                isLive,
                                scoreBox: !cancelled,
                                pens: showScore ? match.homePens : null,
                              ),
                              const SizedBox(height: 4),
                              _teamLine(
                                awayName,
                                (teamLogoById[match.awayTeamId] ?? '').trim(),
                                showScore ? '$as' : '-',
                                !showScore || !(winner ?? false),
                                isLive,
                                scoreBox: !cancelled,
                                pens: showScore ? match.awayPens : null,
                              ),
                            ],
                          ),
                        ),
                        // İptal maçta "-" kutuları yerine tek "İPTAL" etiketi.
                        if (cancelled)
                          Container(
                            margin: const EdgeInsets.only(left: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFEF4444,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(
                                  0xFFEF4444,
                                ).withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Text(
                              'İPTAL',
                              style: TextStyle(
                                color: Color(0xFFFCA5A5),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamLine(
    String name,
    String logo,
    String score,
    bool strong,
    bool isLive, {
    bool scoreBox = true,
    int? pens,
  }) {
    return Row(
      children: [
        WebSafeImage(
          url: logo,
          width: 22,
          height: 22,
          fit: BoxFit.contain,
          fallbackIconSize: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            compactTeamName(name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: strong ? Colors.white : const Color(0xFF94A3B8),
              fontSize: 13,
            ),
          ),
        ),
        // Uzun ad kesilse bile "…" skora yapışmasın.
        if (scoreBox) const SizedBox(width: 12),
        // Penaltı skoru: skor kutusunun solunda sarı "4 P".
        if (scoreBox && pens != null) ...[
          PenaltyBadge(pens, size: 11),
          const SizedBox(width: 6),
        ],
        // Skor kutusu: yeşil kare; canlı maçta kırmızı.
        if (scoreBox)
          Container(
            width: 30,
            height: 25,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isLive
                  ? const Color(0xFFF87171).withValues(alpha: 0.22)
                  : const Color(0xFF064E3B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    (isLive ? const Color(0xFFF87171) : const Color(0xFF10B981))
                        .withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              score,
              style: TextStyle(
                color: isLive
                    ? const Color(0xFFF87171)
                    : (strong ? Colors.white : Colors.white60),
                fontWeight: FontWeight.w800,
                fontSize: 14,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }

  void _showQuickScoreDialog(BuildContext context) => showQuickScoreDialog(
    context,
    match: match,
    homeName: (teamNameById[match.homeTeamId] ?? '').trim(),
    awayName: (teamNameById[match.awayTeamId] ?? '').trim(),
    onSaved: onDataChanged,
  );

  void _showEditPopup(BuildContext context) => showMatchScheduleDialog(
    context,
    match: match,
    onDataChanged: onDataChanged,
  );
}

/// Hafta başlığı: "3. HAFTA" ve önceki / sonraki hafta okları. Başlığa
/// dokununca bütün haftalar listelenir.
class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.weeks,
    required this.week,
    required this.accent,
    required this.onSelect,
  });

  final List<int> weeks;
  final int week;
  final Color accent;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final sorted = [...weeks]..sort();
    final i = sorted.indexOf(week);
    final prev = i > 0 ? sorted[i - 1] : null;
    final next = i >= 0 && i < sorted.length - 1 ? sorted[i + 1] : null;

    Widget arrow(IconData icon, int? target, String tip) => Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: target == null ? null : () => onSelect(target),
        child: SizedBox(
          width: 40,
          height: 38,
          child: Icon(
            icon,
            semanticLabel: tip,
            color: target == null ? Colors.white24 : Colors.white,
          ),
        ),
      ),
    );

    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: sorted.length < 2
                  ? null
                  : () async {
                      final w = await showAdminOptionPicker<int>(
                        context: context,
                        title: 'Hafta Seç',
                        items: sorted,
                        selected: week,
                        labelBuilder: (w) => '$w. Hafta',
                      );
                      if (w != null) onSelect(w);
                    },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$week. HAFTA',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (sorted.length > 1)
                      Icon(Icons.expand_more_rounded, color: accent, size: 22),
                  ],
                ),
              ),
            ),
          ),
        ),
        arrow(Icons.chevron_left_rounded, prev, 'Önceki hafta'),
        const SizedBox(width: 6),
        arrow(Icons.chevron_right_rounded, next, 'Sonraki hafta'),
      ],
    );
  }
}

/// Haftanın maç günleri (gün adı, gün, ay). Güne dokununca liste o güne
/// kayar. Altındaki nokta günün durumunu gösterir.
class _FixtureDayStrip extends StatelessWidget {
  const _FixtureDayStrip({
    required this.days,
    required this.status,
    required this.selected,
    required this.accent,
    required this.onSelect,
  });

  static const noDate = '__NO_DATE__';
  static const done = Color(0xFF10B981);
  static const live = Color(0xFFF87171);
  static const upcoming = Colors.white38;

  final List<String> days;
  final Map<String, Color> status;
  final String? selected;
  final Color accent;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    // Açık turnuva renginde (ör. beyaz) seçili kutunun yazısı koyu.
    final light = accent.computeLuminance() > 0.6;
    final onFg = light ? const Color(0xFF0F172A) : Colors.white;
    final onMuted = light ? const Color(0xB30F172A) : Colors.white70;
    Widget chip(String key) {
      final on = key == selected;
      final dt = DateTime.tryParse(key);
      final dot = status[key] ?? upcoming;
      final top = dt == null ? 'Tarih' : DateFormat('EEE', 'tr_TR').format(dt);
      final mid = dt == null ? '?' : '${dt.day}';
      final bottom = dt == null ? 'yok' : DateFormat('MMM', 'tr_TR').format(dt);
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: on ? accent : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelect(key),
            child: SizedBox(
              width: 54,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      top,
                      style: TextStyle(
                        color: on ? onMuted : Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      mid,
                      style: TextStyle(
                        color: on ? onFg : Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      bottom,
                      style: TextStyle(
                        color: on ? onMuted : Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        border: on ? Border.all(color: onFg, width: 1) : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [for (final d in days) chip(d)]),
    );
  }
}
