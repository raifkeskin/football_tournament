import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/league.dart';
import '../models/match.dart';
import '../services/database_service.dart';
import '../services/app_session.dart';
import '../widgets/web_safe_image.dart';
import 'groups_screen.dart';
import 'match_details_screen.dart';

/// Ana sayfa — günün maçları, tarih şeridi ve maç kartları.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _yaricap = 2; // 2 gün geri, bugün, 2 gün ileri

  static const List<String> _haftaKisa = [
    'Pzt',
    'Sal',
    'Çar',
    'Per',
    'Cum',
    'Cmt',
    'Paz',
  ];

  final _databaseService = DatabaseService();
  late List<DateTime> _tarihler;
  int _seciliIndeks = 2;
  String? _activeLeagueId;
  bool _didAutoSelectDefaultLeague = false;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    // Bugünün tarihini odak noktası yapalım (Saatleri sıfırla)
    final now = DateTime.now();
    final bugun = DateTime(now.year, now.month, now.day);
    _selectedDate = bugun;
    _rebuildDates(_selectedDate);
  }

  @override
  void dispose() {
    super.dispose();
  }

  bool _bugunMu(DateTime t) {
    final n = DateTime.now();
    return t.year == n.year && t.month == n.month && t.day == n.day;
  }

  void _tarihSec(int index) {
    final picked = _tarihler[index];
    setState(() {
      _selectedDate = picked;
      _rebuildDates(_selectedDate);
    });
  }

  void _rebuildDates(DateTime center) {
    final c = DateTime(center.year, center.month, center.day);
    _tarihler = List.generate(
      _yaricap * 2 + 1,
      (i) => c.add(Duration(days: i - _yaricap)),
      growable: true,
    );
    _seciliIndeks = 2;
  }

  DateTime _gunBasinaIndir(DateTime d) => DateTime(d.year, d.month, d.day);

  void _setSelectedDate(DateTime date) {
    final target = _gunBasinaIndir(date);
    setState(() {
      _selectedDate = target;
      _rebuildDates(_selectedDate);
    });
  }

  Future<void> _openDatePicker() async {
    final cs = Theme.of(context).colorScheme;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final themed = Theme.of(context).copyWith(
          colorScheme: cs,
          dialogTheme: DialogThemeData(backgroundColor: cs.surface),
        );
        return Theme(data: themed, child: child);
      },
    );
    if (picked != null) {
      _setSelectedDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    const headerForest = Color(0xFF064E3B);
    const bgDark = Color(0xFF0F172A);
    const cardBg = Color(0xFF1E293B);
    const accent = Color(0xFF10B981);
    const gold = Color(0xFFFBBF24);
    return Scaffold(
      backgroundColor: bgDark,
      body: StreamBuilder<QuerySnapshot>(
        stream: _databaseService.getLeagues(),
        builder: (context, leagueSnapshot) {
          if (!leagueSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final isAdmin = AppSession.of(context).value.isAdmin;
          final allLeagues = leagueSnapshot.data!.docs
              .map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return League.fromMap({...data, 'id': doc.id});
              })
              .where((l) => isAdmin || l.isActive) // Show all if admin, else only active
              .toList();

          if (allLeagues.isEmpty) {
            return const Center(
              child: Text(
                'Henüz turnuva eklenmemiş.',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          if (!_didAutoSelectDefaultLeague && _activeLeagueId == null) {
            League? def;
            for (final l in allLeagues) {
              if (l.isDefault) {
                def = l;
                break;
              }
            }
            _didAutoSelectDefaultLeague = true;
            if (def != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => _activeLeagueId = def!.id);
              });
            }
          }
          final effectiveLeagueId = _activeLeagueId ??
              (allLeagues.any((l) => l.isDefault)
                  ? allLeagues.firstWhere((l) => l.isDefault).id
                  : allLeagues.first.id);
          if (_activeLeagueId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _activeLeagueId = effectiveLeagueId);
            });
          }

          final leagueName = allLeagues
              .firstWhere(
                (l) => l.id == effectiveLeagueId,
                orElse: () => allLeagues.first,
              )
              .name;

          String turkishKey(String s) {
            return s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: headerForest,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 50),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: effectiveLeagueId,
                              dropdownColor: cardBg,
                              icon:
                                  const Icon(Icons.keyboard_arrow_down_rounded),
                              iconEnabledColor: Colors.white,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                              items: allLeagues
                                  .map(
                                    (l) => DropdownMenuItem<String>(
                                      value: l.id,
                                      child: Text(
                                        l.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _activeLeagueId = val),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _openDatePicker,
                          icon: const Icon(Icons.calendar_month_outlined),
                          color: Colors.white,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => _setSelectedDate(
                            _selectedDate.add(const Duration(days: -1)),
                          ),
                          icon: const Icon(Icons.chevron_left),
                          color: Colors.white,
                        ),
                        Expanded(
                          child: _TarihSeridi(
                            tarihler: _tarihler,
                            seciliIndeks: _seciliIndeks,
                            bugunMu: _bugunMu,
                            onSec: _tarihSec,
                            vurguRenk: accent,
                            haftaKisa: _haftaKisa,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _setSelectedDate(
                            _selectedDate.add(const Duration(days: 1)),
                          ),
                          icon: const Icon(Icons.chevron_right),
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -20),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: bgDark,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.only(top: 18),
                    child: StreamBuilder<List<GroupModel>>(
                      stream: _databaseService.getGroups(effectiveLeagueId),
                      builder: (context, groupSnapshot) {
                        if (!groupSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final groups = groupSnapshot.data ?? [];
                        final groupById = {for (final g in groups) g.id: g};

                        return StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('teams')
                              .snapshots(),
                          builder: (context, teamSnapshot) {
                            final teamLogoById = <String, String>{};
                            if (teamSnapshot.hasData) {
                              for (final doc in teamSnapshot.data!.docs) {
                                final data = doc.data() as Map<String, dynamic>;
                                final raw =
                                    (data['logoUrl'] ?? data['logo'] ?? '')
                                        .toString()
                                        .trim();
                                teamLogoById[doc.id] = raw;
                              }
                            }

                            return StreamBuilder<List<MatchModel>>(
                              stream: _databaseService.getMatchesByDate(
                                leagueId: effectiveLeagueId,
                                date: _tarihler[_seciliIndeks],
                              ),
                              builder: (context, matchSnapshot) {
                                if (matchSnapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                final matches = matchSnapshot.data ?? [];
                                if (matches.isEmpty) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.event_busy_rounded,
                                          size: 64,
                                          color: Colors.grey.shade400,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Bu tarihte maç bulunamadı.',
                                          style: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final sectionMap =
                                    <String?, List<MatchModel>>{};
                                for (final m in matches) {
                                  sectionMap
                                      .putIfAbsent(m.groupId, () => [])
                                      .add(m);
                                }

                                String headerForGroup(String? groupId) {
                                  final groupName = groupId == null
                                      ? 'Grup'
                                      : (groupById[groupId]?.name ?? 'Grup');
                                  final upper = groupName.trim().toUpperCase();
                                  return upper.contains('GRUP')
                                      ? upper
                                      : '$upper GRUBU';
                                }

                                final groupIds = sectionMap.keys.toList()
                                  ..sort(
                                    (a, b) => turkishKey(headerForGroup(a))
                                        .compareTo(turkishKey(headerForGroup(b))),
                                  );
                                final children = <Widget>[];
                                for (final gid in groupIds) {
                                  final h = headerForGroup(gid);
                                  final list = sectionMap[gid]!
                                    ..sort(
                                      (a, b) {
                                        final at = (a.matchTime ?? '').trim();
                                        final bt = (b.matchTime ?? '').trim();
                                        if (at.isEmpty && bt.isEmpty) return 0;
                                        if (at.isEmpty) return 1;
                                        if (bt.isEmpty) return -1;
                                        return at.compareTo(bt);
                                      },
                                    );
                                  children.add(
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => GroupsScreen(
                                                initialLeagueId: effectiveLeagueId,
                                                initialGroupId: gid,
                                              ),
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.shield_outlined,
                                                color: gold,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '$leagueName - $h',
                                                  style: const TextStyle(
                                                    color: gold,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                              const Icon(
                                                Icons.chevron_right_rounded,
                                                color: gold,
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                  for (var i = 0; i < list.length; i++) {
                                    final m = list[i];
                                    final homeLogo =
                                        (m.homeTeamLogoUrl.trim()).isNotEmpty
                                            ? m.homeTeamLogoUrl
                                            : (teamLogoById[m.homeTeamId] ??
                                                '');
                                    final awayLogo =
                                        (m.awayTeamLogoUrl.trim()).isNotEmpty
                                            ? m.awayTeamLogoUrl
                                            : (teamLogoById[m.awayTeamId] ??
                                                '');
                                    children.add(
                                      _MacSatiri(
                                        match: m,
                                        homeLogoUrlOverride: homeLogo,
                                        awayLogoUrlOverride: awayLogo,
                                      ),
                                    );
                                    if (i != list.length - 1) {
                                      children.add(const SizedBox(height: 8));
                                    }
                                  }
                                  children.add(const SizedBox(height: 12));
                                }

                                return ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    120,
                                  ),
                                  children: children,
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KucukLogo extends StatelessWidget {
  const _KucukLogo({required this.logoUrl, this.size = 26});
  final String? logoUrl;
  final double size;

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = _normalizeUrl(logoUrl ?? '');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        shape: BoxShape.circle,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: ClipOval(
        child: WebSafeImage(
          url: url,
          width: size,
          height: size,
          isCircle: true,
          fallbackIconSize: (size * 0.62).clamp(14, 22),
        ),
      ),
    );
  }
}

class _TarihSeridi extends StatelessWidget {
  const _TarihSeridi({
    required this.tarihler,
    required this.seciliIndeks,
    required this.bugunMu,
    required this.onSec,
    required this.vurguRenk,
    required this.haftaKisa,
  });
  final List<DateTime> tarihler;
  final int seciliIndeks;
  final bool Function(DateTime) bugunMu;
  final void Function(int) onSec;
  final Color vurguRenk;
  final List<String> haftaKisa;

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: Row(
        children: List.generate(tarihler.length, (index) {
          final t = tarihler[index];
          final secili = index == seciliIndeks;
          final isToday = bugunMu(t);
          final gun = isToday ? 'Bugün' : haftaKisa[t.weekday - 1];
          final tarih = '${_two(t.day)}/${_two(t.month)}';

          return Expanded(
            child: GestureDetector(
              onTap: () => onSec(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: secili
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: secili
                        ? [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.10),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                secili ? FontWeight.w900 : FontWeight.w800,
                            letterSpacing: 0.2,
                            color: secili
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.70),
                          ),
                          child: Text(gun),
                        ),
                        const SizedBox(height: 4),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                            color: secili
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.85),
                          ),
                          child: Text(tarih),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _MacSatiri extends StatelessWidget {
  const _MacSatiri({
    required this.match,
    required this.homeLogoUrlOverride,
    required this.awayLogoUrlOverride,
  });
  final MatchModel match;
  final String homeLogoUrlOverride;
  final String awayLogoUrlOverride;

  String get _timeText {
    final t = (match.matchTime ?? '').trim();
    if (t.isNotEmpty) return t;
    return '--:--';
  }

  String get _statusText {
    if (match.status == MatchStatus.finished) return 'MS';
    if (match.status == MatchStatus.live) {
      return match.minute == null ? 'CANLI' : "${match.minute}'";
    }
    return 'Oynanmadı';
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    const cardBg = Color(0xFF1E293B);
    const fg = Color(0xFFF8FAFC);
    const mid = Color(0xFF94A3B8);
    const accent = Color(0xFF10B981);

    final showScore = match.status == MatchStatus.finished ||
        match.homeScore != 0 ||
        match.awayScore != 0;
    final hs = match.homeScore;
    final as = match.awayScore;
    final homeWin = showScore && hs > as;
    final awayWin = showScore && as > hs;

    Widget scoreBox({
      required int? score,
      required bool highlight,
    }) {
      return SizedBox(
        width: 25,
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            showScore ? '${score ?? 0}' : '-',
            style: TextStyle(
              color: highlight ? fg : mid,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      color: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MatchDetailsScreen(
              match: match,
              isAdmin: isAdmin,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 58,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _timeText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: mid,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (match.status == MatchStatus.finished)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'MS',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      )
                    else
                      Text(
                        match.status == MatchStatus.live ? _statusText : '-',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: mid,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _KucukLogo(logoUrl: homeLogoUrlOverride, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            match.homeTeamName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            scoreBox(
                              score: hs,
                              highlight: homeWin || !showScore,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _KucukLogo(logoUrl: awayLogoUrlOverride, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            match.awayTeamName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            scoreBox(
                              score: as,
                              highlight: awayWin || !showScore,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
