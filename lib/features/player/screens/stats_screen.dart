import 'package:flutter/material.dart';
import 'package:football_tournament/core/widgets/master_class_app_bar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/app_config.dart';
import '../../tournament/models/league.dart';
import '../../tournament/models/season.dart';
import '../../match/models/match.dart';
import '../models/player_stats.dart';
import '../../team/models/team.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../../match/services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/services/global_filter.dart';

// ORTAK BİLEŞEN
import '../../../core/widgets/custom_popup_selector.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final IMatchService _matchService = ServiceLocator.matchService;
  final ITeamService _teamService = ServiceLocator.teamService;
  
  String? _selectedLeagueId;
  String? _selectedSeasonId;

  Stream<List<League>>? _leaguesStream;

  String? _lastLeagueIdForSeason;
  Stream<List<Season>>? _seasonsStream;

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

  Stream<List<Season>> _getSeasonsStream(String leagueId) {
    if (_lastLeagueIdForSeason != leagueId || _seasonsStream == null) {
      _lastLeagueIdForSeason = leagueId;
      _seasonsStream = _watchSeasons(leagueId);
    }
    return _seasonsStream!;
  }

  @override
  void initState() {
    super.initState();
    _leaguesStream = _leagueService.watchLeagues();
    _selectedLeagueId = GlobalFilter.leagueId.value;
    _selectedSeasonId = GlobalFilter.seasonId.value;
    GlobalFilter.leagueId.addListener(_onGlobalFilterChanged);
    GlobalFilter.seasonId.addListener(_onGlobalFilterChanged);
  }

  void _onGlobalFilterChanged() {
    if (!mounted) return;
    setState(() {
      _selectedLeagueId = GlobalFilter.leagueId.value;
      _selectedSeasonId = GlobalFilter.seasonId.value;
    });
  }

  @override
  void dispose() {
    GlobalFilter.leagueId.removeListener(_onGlobalFilterChanged);
    GlobalFilter.seasonId.removeListener(_onGlobalFilterChanged);
    super.dispose();
  }

  // İSTATİSTİK EKRANI İÇİN ORTADAN AÇILAN FİLTRE DİALOGU
  void _showFilterDialog(BuildContext context, List<League> leagues, List<Season> seasons) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E293B), Color(0xFF064E3B)],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 15, offset: Offset(0, 8)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // Kapsülü ortada tutar
                  children: [
                    CustomPopupSelector<String>(
                      label: 'Turnuva',
                      selectedValue: _selectedLeagueId,
                      items: leagues.map((l) => l.id).toList(),
                      labelBuilder: (id) => leagues.firstWhere((l) => l.id == id, orElse: () => leagues.first).name,
                      onChanged: (String? val) {
                        if (val != null) {
                          setState(() {
                            _selectedLeagueId = val;
                            _selectedSeasonId = null;
                          });
                          setDialogState(() {});
                          GlobalFilter.setLeague(val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    
                    CustomPopupSelector<String>(
                      label: 'Sezon',
                      selectedValue: _selectedSeasonId,
                      items: seasons.map((s) => s.id).toList(),
                      labelBuilder: (id) => seasons.firstWhere((s) => s.id == id, orElse: () => seasons.first).name,
                      onChanged: (String? val) {
                        if (val != null) {
                          setState(() => _selectedSeasonId = val);
                          setDialogState(() {});
                          GlobalFilter.setSeason(val);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Filtreleri Uygula', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const bgDark = Color(0xFF0F172A);

    return StreamBuilder<List<League>>(
      stream: _leaguesStream,
      builder: (context, leaguesSnap) {
        if (!leaguesSnap.hasData && leaguesSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: bgDark,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final leagues = leaguesSnap.data ?? const <League>[];
        if (leagues.isEmpty) {
          return const Scaffold(
            backgroundColor: bgDark,
            body: Center(child: Text('Turnuva bulunamadı.', style: TextStyle(color: Colors.white))),
          );
        }

        return Scaffold(
          backgroundColor: bgDark,
          extendBodyBehindAppBar: true, 
          appBar: const MasterClassAppBar(title: 'İstatistik'),
          body: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.15,
                  child: Image.asset(
                    'assets/images/background_ball.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    // KAPSÜL BÖLÜMÜ
                    StreamBuilder<List<Season>>(
                      stream: _selectedLeagueId == null
                          ? Stream.value([])
                          : _getSeasonsStream(_selectedLeagueId!),
                      builder: (context, seasonSnap) {
                        final seasons = seasonSnap.data ?? const <Season>[];
                        
                        if (seasons.isNotEmpty && _selectedSeasonId == null && GlobalFilter.seasonId.value == null) {
                          final defaultSeason = seasons.any((s) => s.isDefault)
                              ? seasons.firstWhere((s) => s.isDefault).id
                              : (seasons.any((s) => s.isActive)
                                  ? seasons.firstWhere((s) => s.isActive).id
                                  : seasons.first.id);
                                  
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            GlobalFilter.setSeason(defaultSeason);
                          });
                        }

                        final currentLeagueName = leagues.firstWhere((l) => l.id == _selectedLeagueId, orElse: () => leagues.first).name;
                        final currentSeasonName = seasons.isEmpty ? '' : seasons.firstWhere((s) => s.id == _selectedSeasonId, orElse: () => seasons.first).name;

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: InkWell(
                            onTap: () => _showFilterDialog(context, leagues, seasons),
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white24),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.tune_rounded, color: Color(0xFF10B981), size: 18),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      "$currentLeagueName • $currentSeasonName",
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 18),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    
                    // LİSTE BÖLÜMÜ
                    Expanded(
                      child: _selectedSeasonId == null
                          ? const Center(
                              child: Text(
                                'Lütfen bir turnuva ve sezon seçin.',
                                style: TextStyle(color: Colors.white),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: StreamBuilder<List<Team>>(
                                stream: _teamService.watchAllTeams(),
                                builder: (context, teamsSnap) {
                                  if (!teamsSnap.hasData && teamsSnap.connectionState == ConnectionState.waiting) {
                                    return const Center(child: CircularProgressIndicator());
                                  }

                                  final teams = (teamsSnap.data ?? const <Team>[])
                                          .where((t) => t.id != 'free_agent_pool')
                                          .toList();
                                  final teamById = {for (final t in teams) t.id: t};

                                  return StreamBuilder<List<PlayerStats>>(
                                    stream: _matchService.watchPlayerStats(tournamentId: _selectedLeagueId ?? ''),
                                    builder: (context, statsSnap) {
                                      if (!statsSnap.hasData && statsSnap.connectionState == ConnectionState.waiting) {
                                        return const Center(child: CircularProgressIndicator());
                                      }
                                      
                                      // Sadece golü veya asisti olan oyuncuları dahil et
                                      final stats = (statsSnap.data ?? const <PlayerStats>[])
                                           .where((s) => (s.goals > 0 || s.assists > 0))
                                           .toList();

                                      if (stats.isEmpty) {
                                        return Center(
                                          child: Text(
                                            'Bu sezon için istatistik bulunmuyor.',
                                            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                                          ),
                                        );
                                      }

                                      List<PlayerStats> topBy(int Function(PlayerStats s) getValue) {
                                        final list = [...stats];
                                        list.sort((a, b) {
                                          final cmp = getValue(b).compareTo(getValue(a));
                                          if (cmp != 0) return cmp;
                                          return a.playerPhone.compareTo(b.playerPhone);
                                        });
                                        return list.where((s) => getValue(s) > 0).take(10).toList();
                                      }

                                      final topGoals = topBy((s) => s.goals);
                                      final topAssists = topBy((s) => s.assists);

                                      Widget table({
                                        required String valueHeader,
                                        required List<PlayerStats> rows,
                                        required int Function(PlayerStats) getValue,
                                      }) {
                                        return ListView(
                                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF064E3B),
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: Row(
                                                children: [
                                                  const SizedBox(width: 28, child: Center(child: Text('#', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)))),
                                                  const Expanded(flex: 6, child: Text('Oyuncu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
                                                  const Expanded(flex: 2, child: Text('Maç', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
                                                  Expanded(flex: 2, child: Text(valueHeader, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            if (rows.isEmpty)
                                              Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                child: Text('Veri yok.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                                              )
                                            else
                                              for (var i = 0; i < rows.length; i++)
                                                Card(
                                                  margin: const EdgeInsets.only(bottom: 10),
                                                  color: const Color(0xFF1E293B).withOpacity(0.9),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                    child: Row(
                                                      children: [
                                                        SizedBox(width: 28, child: Center(child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white70)))),
                                                        Expanded(
                                                          flex: 6,
                                                          child: Builder(
                                                            builder: (context) {
                                                              final s = rows[i];
                                                              final team = teamById[s.teamId];
                                                              final teamName = team?.name ?? '';
                                                              final teamLogo = team?.logoUrl ?? '';
                                                              final fallback = teamName.isNotEmpty ? teamName[0].toUpperCase() : '?';
                                                              return Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  FutureBuilder<PlayerModel?>(
                                                                    future: _teamService.getPlayerByPhoneOnce(s.playerPhone),
                                                                    builder: (context, pSnap) {
                                                                      final name = (pSnap.data?.name ?? '').trim().isNotEmpty
                                                                          ? pSnap.data!.name.trim()
                                                                          : s.playerPhone;
                                                                      return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white));
                                                                    },
                                                                  ),
                                                                  const SizedBox(height: 3),
                                                                  Row(
                                                                    children: [
                                                                      _MiniTeamLogo(logoUrl: teamLogo, fallbackText: fallback),
                                                                      const SizedBox(width: 6),
                                                                      Expanded(child: Text(teamName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w600, fontSize: 11))),
                                                                    ],
                                                                  ),
                                                                ],
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                        Expanded(flex: 2, child: Text('${rows[i].matchesPlayed}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white70))),
                                                        Expanded(flex: 2, child: Text('${getValue(rows[i])}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF10B981)))),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                          ],
                                        );
                                      }

                                      return DefaultTabController(
                                        length: 2,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Positioned(
                                              top: -12,
                                              left: 16,
                                              right: 16,
                                              child: Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF1E293B),
                                                  borderRadius: BorderRadius.circular(14),
                                                ),
                                                child: const TabBar(
                                                  labelColor: Colors.white,
                                                  unselectedLabelColor: Colors.white70,
                                                  indicatorColor: Colors.white,
                                                  indicatorSize: TabBarIndicatorSize.tab,
                                                  labelStyle: TextStyle(fontFamily: 'Batangas', fontWeight: FontWeight.bold, fontSize: 14),
                                                  tabs: [Tab(text: 'Gol Krallığı'), Tab(text: 'Asist Krallığı')],
                                                ),
                                              ),
                                            ),
                                            Positioned.fill(
                                              top: 44,
                                              child: Padding(
                                                padding: const EdgeInsets.only(bottom: 120),
                                                child: TabBarView(
                                                  children: [
                                                    table(valueHeader: 'Gol', rows: topGoals, getValue: (s) => s.goals),
                                                    table(valueHeader: 'Asist', rows: topAssists, getValue: (s) => s.assists),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniTeamLogo extends StatelessWidget {
  const _MiniTeamLogo({required this.logoUrl, required this.fallbackText});
  final String logoUrl;
  final String fallbackText;

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = _normalizeUrl(logoUrl);
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary.withValues(alpha: 0.16)),
      child: WebSafeImage(url: url, width: 16, height: 16, isCircle: true, fallbackIconSize: 12),
    );
  }
}