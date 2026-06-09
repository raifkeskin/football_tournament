import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../tournament/models/league.dart';
import '../../tournament/models/season.dart';
import '../../match/models/match.dart';
import '../../../core/services/app_session.dart';
import '../../team/models/team.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../../match/services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/services/global_filter.dart';
import '../../team/screens/groups_screen.dart';
import '../../match/screens/match_details_screen.dart';

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
    _activeLeagueId = GlobalFilter.leagueId.value;
    
    GlobalFilter.leagueId.addListener(_onGlobalFilterChanged);
  }

  void _onGlobalFilterChanged() {
    if (!mounted) return;
    setState(() {
      _activeLeagueId = GlobalFilter.leagueId.value ?? _activeLeagueId;
    });
  }

  @override
  void dispose() {
    GlobalFilter.leagueId.removeListener(_onGlobalFilterChanged);
    super.dispose();
  }

  Stream<List<Season>> _watchSeasons(String leagueId) {
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      return Stream.value([]);
    }
    return Supabase.instance.client
        .from('seasons')
        .stream(primaryKey: ['id'])
        .eq('league_id', leagueId)
        .order('start_date', ascending: false)
        .map((rows) => rows.map((r) => Season.fromMap(r)).toList());
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

  // YENİ EKLENEN: Erişim Kodu Soran Dialog
  void _showAccessCodeDialog(BuildContext parentContext, League league) {
    final TextEditingController codeCtrl = TextEditingController();
    String? errorMsg;

    showDialog(
      context: parentContext,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.lock, color: Colors.white, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    league.name,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Bu turnuva gizlidir. Görüntüleyebilmek için lütfen erişim kodunu girin.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeCtrl,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'Erişim Kodu',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white10,
                    errorText: errorMsg,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF10B981)),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.redAccent),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('İptal', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final enteredCode = codeCtrl.text.trim().toLowerCase();
                  // League modelindeki accessCode değişkeninin adından emin olunuz (accessCode veya access_code olabilir)
                  final actualCode = (league.accessCode ?? '').trim().toLowerCase(); 
                  
                  if (enteredCode.isNotEmpty && enteredCode == actualCode) {
                    setState(() => _activeLeagueId = league.id);
                    GlobalFilter.setLeague(league.id);
                    Navigator.pop(c); // Dialogu kapat
                    Navigator.pop(parentContext); // Alttaki menüyü kapat
                  } else {
                    setDialogState(() => errorMsg = 'Hatalı kod girdiniz.');
                  }
                },
                child: const Text('Onayla', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          );
        }
      )
    );
  }

  // YENİ EKLENEN: Özel Turnuva Seçici (Bottom Sheet)
  void _showLeagueSelectorBottomSheet(BuildContext context, List<League> leagues, bool isAdmin) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))
      ),
      builder: (c) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2)
                    ),
                  ),
                ),
                const Text(
                  'Turnuva Seçin',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: leagues.map((l) {
                      // Gizli ve admin değilse kilitli kabul et
                      final isLocked = l.isPrivate && !isAdmin;
                      final isSelected = l.id == _activeLeagueId;

                      return ListTile(
                        leading: isLocked 
                          ? const Icon(Icons.lock_rounded, color: Colors.white54, size: 22) 
                          : Icon(Icons.emoji_events_rounded, color: isSelected ? const Color(0xFF10B981) : Colors.white70, size: 22),
                        title: Text(
                          l.name,
                          style: TextStyle(
                            color: isLocked ? Colors.white54 : (isSelected ? const Color(0xFF10B981) : Colors.white),
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                          ),
                        ),
                        trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20) : null,
                        onTap: () {
                          if (isLocked) {
                            _showAccessCodeDialog(context, l);
                          } else {
                            setState(() => _activeLeagueId = l.id);
                            GlobalFilter.setLeague(l.id);
                            Navigator.pop(c);
                          }
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/anasayfa.jpg', fit: BoxFit.cover),
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

                // GÜNCELLENDİ: isPrivate olanları listede TUTUYORUZ (Kilitli göstermek için)
                final allLeagues = (leagueSnapshot.data ?? const <League>[]).where((l) {
                  if (isAdmin) return true; // Admin her şeyi görür
                  if (!l.isActive) return false; // Pasif turnuvalar görünmez
                  return true; // isPrivate olanlar da gelsin, UI'da kilitleyeceğiz
                }).toList();

                if (allLeagues.isEmpty) {
                  return const Center(
                    child: Text('Görüntülenebilir turnuva yok.', style: TextStyle(color: Colors.white)),
                  );
                }

                if (!_didAutoSelectDefaultLeague ||
                    !allLeagues.any((l) => l.id == _activeLeagueId)) {
                  // İlk girişte gizli turnuvanın default gelmesini önlemek için küçük kontrol
                  final def = allLeagues.any((l) => l.isDefault && (!l.isPrivate || isAdmin))
                      ? allLeagues.firstWhere((l) => l.isDefault && (!l.isPrivate || isAdmin)).id
                      : allLeagues.firstWhere((l) => !l.isPrivate || isAdmin, orElse: () => allLeagues.first).id;
                  _activeLeagueId = def;
                  GlobalFilter.setLeague(def);
                  _didAutoSelectDefaultLeague = true;
                }

                final currentLeague = allLeagues.firstWhere(
                  (l) => l.id == _activeLeagueId,
                  orElse: () => allLeagues.first,
                );

                return Stack(
                  children: [
                    // 1. KATMAN: YEŞİL ARKA PLAN
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

                    // 2. KATMAN: ANA LİSTE
                    Column(
                      children: [
                        const SizedBox(height: 185), 
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
                                  // YENİ EKLENEN: Standart Dropdown Yerine Kendi Tasarımımız
                                  child: InkWell(
                                    onTap: () => _showLeagueSelectorBottomSheet(context, allLeagues, isAdmin),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              currentLeague.name,
                                              style: TextStyle(
                                                color: cs.onPrimaryContainer,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 20,
                                                shadows: const [
                                                  Shadow(
                                                    color: Colors.black87,
                                                    blurRadius: 4,
                                                    offset: Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            color: cs.onPrimaryContainer,
                                            shadows: const [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2))],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _openDatePicker,
                                  icon: Icon(
                                    Icons.calendar_month_outlined,
                                    color: cs.onPrimaryContainer,
                                    shadows: const [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2))],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () => _setSelectedDate(
                                    _selectedDate.subtract(const Duration(days: 1)),
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
        final Map<String, String> nameMap = {};
        if (teamSnapshot.hasData) {
          for (final t in teamSnapshot.data!) {
            logoMap[t.id] = t.logoUrl;
            nameMap[t.id] = t.name;
          }
        }

        return StreamBuilder<List<Season>>(
          stream: _activeLeagueId == null
              ? const Stream<List<Season>>.empty()
              : _watchSeasons(_activeLeagueId!),
          builder: (context, seasonsSnap) {
            final seasons = seasonsSnap.data ?? const <Season>[];
            
            if (seasons.isNotEmpty && GlobalFilter.seasonId.value == null) {
              final defaultSeason = seasons.any((s) => s.isDefault)
                  ? seasons.firstWhere((s) => s.isDefault).id
                  : (seasons.any((s) => s.isActive)
                      ? seasons.firstWhere((s) => s.isActive).id
                      : seasons.first.id);
                      
              WidgetsBinding.instance.addPostFrameCallback((_) {
                GlobalFilter.setSeason(defaultSeason);
              });
            }

            final seasonNameById = <String, String>{
              for (final s in seasons) s.id: s.name.trim(),
            };

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
                matches.sort((a, b) {
                  final timeA = (a.matchTime ?? '').trim();
                  final timeB = (b.matchTime ?? '').trim();

                  if (timeA.isEmpty && timeB.isEmpty) return 0;
                  if (timeA.isEmpty) return 1;
                  if (timeB.isEmpty) return -1;

                  return timeA.compareTo(timeB);
                });
                
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
                  final sId = m.seasonId ?? 'default';
                  (sectionMap[sId] ??= []).add(m);
                }

                final sortedSeasonIds = sectionMap.keys.toList()
                  ..sort((a, b) {
                    if (a == 'default') return 1;
                    if (b == 'default') return -1;
                    final nameA = seasonNameById[a] ?? a;
                    final nameB = seasonNameById[b] ?? b;
                    return nameA.toUpperCase().compareTo(nameB.toUpperCase());
                  });

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: sortedSeasonIds.map((sId) {
                    final seasonName = seasonNameById[sId] ?? '';
                    final titleText = seasonName.isEmpty
                        ? currentLeague.name
                        : '${currentLeague.name} - $seasonName';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () {
                            GlobalFilter.setLeague(_activeLeagueId);
                            GlobalFilter.setSeason(sId);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GroupsScreen(
                                  initialLeagueId: _activeLeagueId!,
                                  initialSeasonId: sId,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.emoji_events_outlined,
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
                        ...sectionMap[sId]!.map(
                          (m) => _MatchCard(
                            match: m,
                            homeLogo: logoMap[m.homeTeamId] ?? '',
                            awayLogo: logoMap[m.awayTeamId] ?? '',
                            homeName:
                                (nameMap[m.homeTeamId] ?? '').trim().isEmpty
                                ? 'Ev Sahibi'
                                : (nameMap[m.homeTeamId] ?? '').trim(),
                            awayName:
                                (nameMap[m.awayTeamId] ?? '').trim().isEmpty
                                ? 'Deplasman'
                                : (nameMap[m.awayTeamId] ?? '').trim(),
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

class _MatchCard extends StatefulWidget {
  final MatchModel match;
  final String homeLogo;
  final String awayLogo;
  final String homeName;
  final String awayName;
  const _MatchCard({
    required this.match,
    required this.homeLogo,
    required this.awayLogo,
    required this.homeName,
    required this.awayName,
  });

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  String? _broadcastUrl;

  @override
  void initState() {
    super.initState();
    _checkBroadcast();
  }

  Future<void> _checkBroadcast() async {
    final url = await ServiceLocator.matchService.getBroadcastUrl(widget.match.id);
    if (mounted && url != _broadcastUrl) {
      setState(() => _broadcastUrl = url);
    }
  }

  @override
  void didUpdateWidget(covariant _MatchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.match.id != widget.match.id) {
      _broadcastUrl = null;
      _checkBroadcast();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAdmin = AppSession.of(context).value.isAdmin;
    final hs = widget.match.homeScore;
    final as = widget.match.awayScore;
    final timeText = (widget.match.matchTime ?? '').trim();

    final showScore =
        widget.match.status == MatchStatus.finished ||
        widget.match.status == MatchStatus.live ||
        hs != 0 ||
        as != 0;

    Widget scoreBox(int score) {
      return Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          showScore ? '$score' : '-',
          style: TextStyle(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      );
    }

    Widget? statusUnderTime() {
      switch (widget.match.status) {
        case MatchStatus.notStarted:
          return null;
        case MatchStatus.finished:
          return const Text(
            'MS',
            style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w900, fontSize: 10),
          );
        case MatchStatus.halftime:
          return const Text(
            'İY',
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 10),
          );
        case MatchStatus.live:
          final m = widget.match.minute;
          return Text(
            m == null ? "CANLI" : "$m'",
            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 10),
          );
        case MatchStatus.cancelled:
          return const Text(
            'IPT',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 10),
          );
        case MatchStatus.postponed:
          return const Text(
            'ERT',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 10),
          );
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E293B).withOpacity(0.78),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MatchDetailsScreen(match: widget.match, isAdmin: isAdmin),
            ),
          );
          _checkBroadcast(); // Geri dönüldüğünde ikonu güncelle
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 50,
                child: Column(
                  children: [
                    if (_broadcastUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: InkWell(
                          onTap: () async {
                            final uri = Uri.tryParse(_broadcastUrl!);
                            if (uri != null && await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          child: const Icon(
                            Icons.play_circle_fill,
                            color: Colors.redAccent,
                            size: 22,
                          ),
                        ),
                      ),
                    Text(
                      widget.match.status == MatchStatus.notStarted && timeText.isEmpty
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

              Expanded(
                child: Column(
                  children: [
                    _row(widget.homeName, widget.homeLogo, scoreBox(hs)),
                    const SizedBox(height: 12),
                    _row(widget.awayName, widget.awayLogo, scoreBox(as)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
        scoreWidget,
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