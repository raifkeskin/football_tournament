import 'package:flutter/material.dart';
import '../models/league.dart';
import '../models/match.dart';
import '../services/app_session.dart';
import '../models/team.dart';
import '../services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../services/interfaces/i_team_service.dart';
import '../services/service_locator.dart';
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
  static const int _yaricap = 2;

  static const List<String> _haftaKisa = [
    'Pzt',
    'Sal',
    'Çar',
    'Per',
    'Cum',
    'Cmt',
    'Paz',
  ];

  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final IMatchService _matchService = ServiceLocator.matchService;
  final ITeamService _teamService = ServiceLocator.teamService;
  late List<DateTime> _tarihler;
  int _seciliIndeks = 2;
  String? _activeLeagueId;
  bool _didAutoSelectDefaultLeague = false;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final bugun = DateTime(now.year, now.month, now.day);
    _selectedDate = bugun;
    _rebuildDates(bugun);
  }

  bool _bugunMu(DateTime t) {
    final n = DateTime.now();
    return t.year == n.year && t.month == n.month && t.day == n.day;
  }

  void _tarihSec(int index) {
    setState(() {
      _selectedDate = _tarihler[index];
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

  void _setSelectedDate(DateTime date) {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _rebuildDates(_selectedDate);
    });
  }

  Future<void> _openDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _setSelectedDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/anasayfa.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0F172A).withOpacity(0.6),
                    const Color(0xFF0F172A).withOpacity(0.95),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: StreamBuilder<List<League>>(
              stream: _leagueService.watchLeagues(),
              builder: (context, leagueSnapshot) {
                if (!leagueSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final isAdmin = AppSession.of(context).value.isAdmin;
                final allLeagues = (leagueSnapshot.data ?? const <League>[])
                    .where((l) => isAdmin || l.isActive)
                    .toList();

                if (allLeagues.isEmpty) {
                  return const Center(child: Text('Henüz aktif turnuva yok.'));
                }

                if (!_didAutoSelectDefaultLeague ||
                    !allLeagues.any((l) => l.id == _activeLeagueId)) {
                  final def = allLeagues.any((l) => l.isDefault)
                      ? allLeagues.firstWhere((l) => l.isDefault).id
                      : allLeagues.first.id;
                  _activeLeagueId = def;
                  _didAutoSelectDefaultLeague = true;
                }

                final currentLeague = allLeagues.firstWhere(
                  (l) => l.id == _activeLeagueId,
                  orElse: () => allLeagues.first,
                );

                return Stack(
                  children: [
                    // 1. KATMAN: YEŞİL ARKA PLAN (OVAL GEÇİŞİN ARKASI)
                    Container(
                      height: 250,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        image: const DecorationImage(
                          image: AssetImage('assets/cim.jpg'),
                          fit: BoxFit.cover,
                        ),
                      ),
                      foregroundDecoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            const Color(0xFF064E3B).withOpacity(0.95),
                            const Color(0xFF064E3B).withOpacity(0.6),
                          ],
                        ),
                      ),
                    ),

                    // 2. KATMAN: ANA LİSTE (OVAL HATLARI OLAN KISIM)
                    Column(
                      children: [
                        const SizedBox(
                          height: 185,
                        ), // Başlıkların ezilmemesi için ayarlandı
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withOpacity(0.30),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            child: _buildMatchList(context, currentLeague),
                          ),
                        ),
                      ],
                    ),

                    // 3. KATMAN: ETKİLEŞİMLİ PANEL (HEADER BUTONLARI)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 44, 16, 20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _activeLeagueId,
                                      dropdownColor: cs.surfaceContainerHighest,
                                      icon: Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: cs.onPrimaryContainer,
                                      ),
                                      style: TextStyle(
                                        color: cs.onPrimaryContainer,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black87,
                                            blurRadius: 4,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      items: allLeagues
                                          .map(
                                            (l) => DropdownMenuItem(
                                              value: l.id,
                                              child: Text(l.name),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (val) =>
                                          setState(() => _activeLeagueId = val),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _openDatePicker,
                                  icon: Icon(
                                    Icons.calendar_month_outlined,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () => _setSelectedDate(
                                    _selectedDate.subtract(
                                      const Duration(days: 1),
                                    ),
                                  ),
                                  icon: Icon(
                                    Icons.chevron_left_rounded,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                                Expanded(
                                  child: _TarihSeridi(
                                    tarihler: _tarihler,
                                    seciliIndeks: _seciliIndeks,
                                    bugunMu: _bugunMu,
                                    onSec: _tarihSec,
                                    vurguRenk: cs.primary,
                                    haftaKisa: _haftaKisa,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _setSelectedDate(
                                    _selectedDate.add(const Duration(days: 1)),
                                  ),
                                  icon: Icon(
                                    Icons.chevron_right_rounded,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchList(BuildContext context, League currentLeague) {
    return StreamBuilder<List<Team>>(
      stream: _teamService.watchAllTeams(),
      builder: (context, teamSnapshot) {
        final Map<String, String> logoMap = {};
        if (teamSnapshot.hasData) {
          for (final t in teamSnapshot.data!) {
            logoMap[t.id] = t.logoUrl;
          }
        }

        return StreamBuilder<List<GroupModel>>(
          stream: _activeLeagueId == null
              ? const Stream<List<GroupModel>>.empty()
              : _leagueService.watchGroups(_activeLeagueId!),
          builder: (context, groupsSnap) {
            final groups = groupsSnap.data ?? const <GroupModel>[];
            final groupNameById = <String, String>{
              for (final g in groups) g.id: g.name.trim(),
            };

            int effectiveGroupCount() {
              if (groups.isNotEmpty) return groups.length;
              final n1 = currentLeague.numberOfGroups;
              if (n1 > 0) return n1;
              final n2 = currentLeague.groupCount;
              if (n2 > 0) return n2;
              final n3 = currentLeague.groups.length;
              if (n3 > 0) return n3;
              return 1;
            }

            final groupCount = effectiveGroupCount();

            String bannerTitleForGroupId(String groupId) {
              final leagueName = currentLeague.name.trim();
              if (groupCount <= 1) return leagueName;
              final groupName = (groupNameById[groupId] ?? '').trim();
              if (groupName.isEmpty) return leagueName;
              return '$leagueName - $groupName';
            }

            return StreamBuilder<List<MatchModel>>(
              stream: _activeLeagueId == null
                  ? const Stream<List<MatchModel>>.empty()
                  : _matchService.watchMatchesByDate(
                      leagueId: _activeLeagueId!,
                      date: _selectedDate,
                    ),
              builder: (context, matchSnapshot) {
                if (matchSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final matches = matchSnapshot.data ?? [];
                if (matches.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_busy_rounded,
                          size: 64,
                          color: Colors.white24,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Bu tarihte maç bulunamadı.',
                          style: TextStyle(color: Colors.white24, fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }

                final Map<String, List<MatchModel>> sectionMap = {};
                for (var m in matches) {
                  final gId = m.groupId ?? 'default';
                  (sectionMap[gId] ??= []).add(m);
                }

                final sortedGroupIds = sectionMap.keys.toList()
                  ..sort((a, b) {
                    if (a == 'default') return 1;
                    if (b == 'default') return -1;
                    return a.toUpperCase().compareTo(b.toUpperCase());
                  });

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: sortedGroupIds.map((groupId) {
                    final titleText = bannerTitleForGroupId(groupId);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupsScreen(
                                initialLeagueId: _activeLeagueId!,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.shield_outlined,
                                  color: Color(0xFFFBBF24),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    titleText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFFBBF24),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Color(0xFFFBBF24),
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                        ...sectionMap[groupId]!.map(
                          (m) => _MatchCard(
                            match: m,
                            homeLogo: logoMap[m.homeTeamId] ?? '',
                            awayLogo: logoMap[m.awayTeamId] ?? '',
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MatchCard extends StatelessWidget {
  final MatchModel match;
  final String homeLogo;
  final String awayLogo;
  const _MatchCard({
    required this.match,
    required this.homeLogo,
    required this.awayLogo,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAdmin = AppSession.of(context).value.isAdmin;
    final hs = match.homeScore;
    final as = match.awayScore;
    final timeText = (match.matchTime ?? '').trim();

    // Skorun gösterilip gösterilmeyeceği kontrolü
    final showScore =
        match.status == MatchStatus.finished ||
        match.status == MatchStatus.live ||
        hs != 0 ||
        as != 0;

    // PANEL YEŞİLİ SKOR KUTUCUĞU
    Widget scoreBox(int score) {
      return Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primaryContainer, // Paneldeki Forest Green tonu
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          showScore ? '$score' : '-',
          style: TextStyle(
            color: cs.onPrimaryContainer, // Yeşil üzerindeki okunaklı renk
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      );
    }

    Widget? statusUnderTime() {
      switch (match.status) {
        case MatchStatus.notStarted:
          return null;
        case MatchStatus.finished:
          return const Text(
            'MS',
            style: TextStyle(
              color: Color(0xFF10B981),
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          );
        case MatchStatus.halftime:
          return const Text(
            'İY',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          );
        case MatchStatus.live:
          final m = match.minute;
          return Text(
            m == null ? "CANLI" : "$m'",
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          );
        case MatchStatus.cancelled:
          return const Text(
            'IPT',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          );
        case MatchStatus.postponed:
          return const Text(
            'ERT',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          );
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E293B).withOpacity(0.78),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MatchDetailsScreen(match: match, isAdmin: isAdmin),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // SAAT VE CANLI DURUMU
              SizedBox(
                width: 50,
                child: Column(
                  children: [
                    Text(
                      match.status == MatchStatus.notStarted && timeText.isEmpty
                          ? ''
                          : (timeText.isEmpty ? '--:--' : timeText),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                    if (statusUnderTime() != null) statusUnderTime()!,
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 40,
                color: cs.outlineVariant.withOpacity(0.35),
              ),
              const SizedBox(width: 12),

              // TAKIMLAR VE SKOR KUTUCUKLARI
              Expanded(
                child: Column(
                  children: [
                    _row(match.homeTeamName, homeLogo, scoreBox(hs)),
                    const SizedBox(height: 12),
                    _row(match.awayTeamName, awayLogo, scoreBox(as)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Satır yapısını skorWidget'ını kabul edecek şekilde güncelledik
  Widget _row(String name, String logo, Widget scoreWidget) {
    return Row(
      children: [
        _KucukLogo(logoUrl: logo, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
        ),
        scoreWidget, // Artık burada yeşil kutucuk görünecek
      ],
    );
  }
}

class _KucukLogo extends StatelessWidget {
  final String logoUrl;
  final double size;
  const _KucukLogo({required this.logoUrl, required this.size});
  @override
  Widget build(BuildContext context) {
    return WebSafeImage(
      url: logoUrl,
      width: size,
      height: size,
      isCircle: true,
      fallbackIconSize: size * 0.7,
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
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        children: List.generate(tarihler.length, (index) {
          final t = tarihler[index];
          final secili = index == seciliIndeks;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSec(index),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: secili
                      ? Colors.white.withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      bugunMu(t) ? 'Bugün' : haftaKisa[t.weekday - 1],
                      style: TextStyle(
                        fontSize: 10,
                        color: secili ? Colors.white : Colors.white60,
                        fontWeight: FontWeight.bold,
                        shadows: const [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${t.day}/${t.month}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
