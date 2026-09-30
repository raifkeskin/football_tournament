import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../tournament/models/league_extras.dart';
import '../models/match.dart';
import '../models/match_media.dart';
import '../../team/models/team.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/image_upload_service.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import 'admin_match_event_screen.dart';
import '../../tournament/screens/formation_tab.dart';

// --- YARDIMCI WIDGETLAR ---

class _SecondYellowCardIcon extends StatelessWidget {
  const _SecondYellowCardIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 20,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.white24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.yellow, Colors.red],
          stops: [0.45, 0.55],
        ),
      ),
    );
  }
}

/// Maç detayı üst bandı: logo üstte, takım adı altında ortalı (2 satır).
class _TeamInfo extends StatelessWidget {
  final String name;
  final String logoUrl;

  const _TeamInfo({required this.name, required this.logoUrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
          ),
          child: WebSafeImage(
            url: logoUrl,
            width: 42,
            height: 42,
            isCircle: true,
            fallbackIconSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          shortTeamName(name),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            height: 1.15,
            letterSpacing: 0.2,
            shadows: [
              Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
              Shadow(color: Colors.black87, blurRadius: 3),
            ],
          ),
        ),
      ],
    );
  }
}

// --- ANA EKRAN ---

class MatchDetailsScreen extends StatefulWidget {
  final MatchModel match;
  final bool isAdmin;
  final int initialTabIndex;
  const MatchDetailsScreen({
    super.key,
    required this.match,
    this.isAdmin = false,
    this.initialTabIndex = 0,
  });

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen>
    with SingleTickerProviderStateMixin {
  final ITeamService _teamService = ServiceLocator.teamService;
  final IMatchService _matchService = ServiceLocator.matchService;
  final ILeagueService _leagueService = ServiceLocator.leagueService;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _matchStream = _matchService.watchMatch(widget.match.id);
    _teamsStream = _teamService.watchAllTeams();
    _pitchesStream = _leagueService.watchPitches();
    _prefetchLineups(widget.match);
  }

  // Akışlar bir kez kurulur; sekme değişimi gibi yeniden çizimlerde
  // baştan bağlanıp veri beklenmez.
  late final Stream<MatchModel> _matchStream;
  late final Stream<List<Team>> _teamsStream;
  late final Stream<List<Pitch>> _pitchesStream;

  /// Kadrolar sekmesine basılmadan önce oyuncu ve kadro verisini arka planda
  /// çekip servis önbelleğine alır; sekme açıldığında veri hazır olur.
  void _prefetchLineups(MatchModel m) {
    if (m.id.isEmpty || m.seasonId.isEmpty) return;
    for (final teamId in {m.homeTeamId, m.awayTeamId}) {
      if (teamId.isEmpty) continue;
      _teamService
          .watchPlayers(teamId: teamId, tournamentId: m.seasonId)
          .last
          .ignore();
    }
    _matchService.watchMatchRosters(m.id, m.homeTeamId).first.ignore();
  }

  int _refreshKey = 0;

  void _triggerRefresh() {
    if (mounted) {
      setState(() => _refreshKey++);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _friendlyLoadError(Object? error) {
    final s = (error ?? '').toString();
    final lower = s.toLowerCase();
    if (lower.contains('permission-denied')) {
      return 'Yetki hatası. Giriş yapıldı mı ve kullanıcı yetkisi doğru mu kontrol edin.\n\n$s';
    }
    if (lower.contains('requires an index') ||
        lower.contains('failed-precondition')) {
      return 'Sorgu için Firestore index gerekli olabilir.\n\n$s';
    }
    if (lower.contains('unavailable') || lower.contains('network')) {
      return 'Bağlantı hatası. İnternet bağlantısını kontrol edin.\n\n$s';
    }
    return s;
  }

  String _resolvePitchLocation({
    required List<Pitch> pitches,
    required String pitchId,
    required String pitchName,
  }) {
    final id = pitchId.trim();
    final name = pitchName.trim();

    if (id.isNotEmpty) {
      for (final p in pitches) {
        if (p.id.trim() == id) {
          return p.location;
        }
      }
    }

    if (name.isNotEmpty) {
      for (final p in pitches) {
        if (p.name.trim().toLowerCase() == name.toLowerCase()) {
          return p.location;
        }
      }
    }

    return '';
  }

  Future<void> _openPitchLocation(
    BuildContext context,
    String rawLocation,
  ) async {
    if (rawLocation.isEmpty) return;
    final uri = Uri.tryParse(rawLocation);
    if (uri == null || uri.scheme.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Konum linki geçersiz.')));
      return;
    }

    try {
      final can = await canLaunchUrl(uri);
      if (!can) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Link açılamadı.')));
        return;
      }
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (!ok) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Link açılamadı.')));
      }
    }
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty || dateStr == '__NO_DATE__') {
      return 'Tarih Belirlenmedi';
    }
    try {
      final p = dateStr.split('-');
      if (p.length != 3) return dateStr;
      return "${p[2]}/${p[1]}/${p[0]}";
    } catch (e) {
      return dateStr;
    }
  }

  Widget? _buildTabFab({required MatchModel match, required int tabIndex}) {
    if (tabIndex == 1 || tabIndex == 3) return null;

    if (tabIndex == 0) {
      return _SpeedDialFab(
        key: const ValueKey('fab_detail'),
        actions: [
          _SpeedDialAction(
            label: 'Maç Detayı Gir',
            icon: Icons.edit_note_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminMatchEventScreen(match: match),
              ),
            ),
          ),
          _SpeedDialAction(
            label: 'Stad Seç',
            icon: Icons.location_on,
            onTap: () => _openPitchEditor(match),
          ),
        ],
      );
    }

    if (tabIndex == 2) {
      return _SpeedDialFab(
        key: const ValueKey('fab_highlights'),
        actions: [
          _SpeedDialAction(
            label: 'Medya Ekle',
            icon: Icons.perm_media_rounded,
            onTap: () => _openHighlightMediaAdder(match, _triggerRefresh),
          ),
        ],
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;

    return StreamBuilder<MatchModel>(
      stream: _matchStream,
      initialData: widget.match,
      builder: (context, matchSnap) {
        if (matchSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Maç Detayı')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Maç verisi yüklenemedi.\n\n${_friendlyLoadError(matchSnap.error)}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final m = matchSnap.data ?? widget.match;

        final bool isSuperAdmin = session.isAdmin;
        final bool isTeamManager =
            session.teamId == m.homeTeamId || session.teamId == m.awayTeamId;
        final bool isAdminAccess = isSuperAdmin || isTeamManager;

        return StreamBuilder<List<Team>>(
          stream: _teamsStream,
          builder: (context, teamsSnap) {
            if (teamsSnap.hasError) {
              return Scaffold(
                appBar: AppBar(title: const Text('Maç Detayı')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Takım verileri yüklenemedi.\n\n${_friendlyLoadError(teamsSnap.error)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            final Map<String, String> logoMap = {};
            final Map<String, String> nameMap = {};
            if (teamsSnap.hasData) {
              for (final team in teamsSnap.data!) {
                logoMap[team.id] = team.logoUrl;
                nameMap[team.id] = team.name;
              }
            }

            final homeLogo = (logoMap[m.homeTeamId] ?? '').trim();
            final awayLogo = (logoMap[m.awayTeamId] ?? '').trim();
            final homeName = (nameMap[m.homeTeamId] ?? '').trim().isEmpty
                ? 'Ev Sahibi'
                : (nameMap[m.homeTeamId] ?? '').trim();
            final awayName = (nameMap[m.awayTeamId] ?? '').trim().isEmpty
                ? 'Deplasman'
                : (nameMap[m.awayTeamId] ?? '').trim();

            return Scaffold(
              extendBodyBehindAppBar: true,
              backgroundColor: const Color(0xFF0F172A),
              appBar: AppBar(
                toolbarHeight: 44,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
              ),
              floatingActionButton: !isSuperAdmin
                  ? null
                  : _buildTabFab(match: m, tabIndex: _tabController.index),
              body: Column(
                children: [
                  Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/anasayfa.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                      // Okunurluk için koyu gradient: üstte ve altta koyulaşır,
                      // alt kenar sayfa zeminine yumuşakça bağlanır.
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.70),
                                const Color(0xFF0F172A).withValues(alpha: 0.55),
                                const Color(0xFF0F172A).withValues(alpha: 0.95),
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          top: MediaQuery.of(context).padding.top + 44,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                // Üstten hizalı: isimler kaç satır olursa olsun
                                // skor logolarla aynı hizada kalır.
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _TeamInfo(
                                      name: homeName,
                                      logoUrl: homeLogo,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      4,
                                      10,
                                      0,
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          "${m.homeScore} - ${m.awayScore}",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 30,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black,
                                                blurRadius: 10,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (m.status == MatchStatus.live)
                                          const Text(
                                            "CANLI",
                                            style: TextStyle(
                                              color: Colors.amber,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 10,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: _TeamInfo(
                                      name: awayName,
                                      logoUrl: awayLogo,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.access_time_filled_rounded,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "${_formatDate(m.matchDate ?? '')}  |  ${m.matchTime}",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 10,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if ((m.pitchId ?? '').isNotEmpty) ...[
                                    const SizedBox(width: 12),
                                    const Text(
                                      "|",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black,
                                            blurRadius: 10,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(
                                      Icons.location_on_rounded,
                                      size: 14,
                                      color: Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: StreamBuilder<List<Pitch>>(
                                        stream: _pitchesStream,
                                        builder: (context, pitchSnap) {
                                          final pitchId = (m.pitchId ?? '')
                                              .trim();
                                          final pitches =
                                              pitchSnap.data ?? const <Pitch>[];

                                          // pitchId ile eşleşen stadı bul
                                          String displayPitchName =
                                              'Bilinmeyen Saha';
                                          String location = '';

                                          for (final p in pitches) {
                                            if (p.id == pitchId) {
                                              displayPitchName = p.name;
                                              location = p.location;
                                              break;
                                            }
                                          }

                                          return InkWell(
                                            onTap: location.isEmpty
                                                ? null
                                                : () => _openPitchLocation(
                                                    context,
                                                    location,
                                                  ),
                                            child: Text(
                                              displayPitchName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black,
                                                    blurRadius: 10,
                                                    offset: Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        // Üst bandın altı: diğer ekranlardaki soluk saha zemini
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0.15,
                            child: Image.asset(
                              'assets/images/background_ball.jpg',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            _LiveStreamPanel(
                              key: ValueKey('live_${m.id}_$_refreshKey'),
                              matchId: m.id,
                            ),
                            Container(
                              height: 42,
                              margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: TabBar(
                                controller: _tabController,
                                dividerColor: Colors.transparent,
                                indicatorSize: TabBarIndicatorSize.tab,
                                indicator: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.35),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                labelColor: Colors.white,
                                unselectedLabelColor: Colors.white60,
                                overlayColor: WidgetStateProperty.all(
                                  Colors.transparent,
                                ),
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                labelStyle: const TextStyle(
                                  fontFamily: 'Batangas',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                ),
                                unselectedLabelStyle: const TextStyle(
                                  fontFamily: 'Batangas',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                                tabs: const [
                                  Tab(text: 'Detay'),
                                  Tab(text: 'Kadrolar'),
                                  Tab(text: 'Önemli Anlar'),
                                  Tab(text: 'Diziliş'),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Container(
                                color: Colors.transparent,
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    _DetailTab(match: m),

                                    // İŞTE DEĞİŞİKLİK YAPILAN YER: YENİ _LineupTab BAĞLANTISI
                                    _LineupTab(
                                      match: m,
                                      isAdminAccess: isAdminAccess,
                                      homeName: homeName,
                                      awayName: awayName,
                                    ),

                                    _HighlightsTab(
                                      key: ValueKey(_refreshKey),
                                      match: m,
                                      isSuperAdmin: isSuperAdmin,
                                      onDataChanged: _triggerRefresh,
                                    ),
                                    FormationTab.fromMatch(
                                      match: m,
                                      isTeamManager: isAdminAccess,
                                      homeName: homeName,
                                      awayName: awayName,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openPitchEditor(MatchModel m) async {
    final list = await _leagueService.listPitchesOnce();
    String? sel = m.pitchName;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setS) {
          return AlertDialog(
            title: const Text('Saha Seçimi'),
            content: DropdownButton<String>(
              value: list.contains(sel) ? sel : null,
              isExpanded: true,
              items: list
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setS(() => sel = v),
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  await _matchService.updateMatchPitchName(
                    matchId: m.id,
                    pitchName: sel,
                  );
                  Navigator.pop(c);
                },
                child: const Text('KAYDET'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openHighlightMediaAdder(
    MatchModel matchModel,
    VoidCallback onSuccess,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) =>
          _MediaAdderDialog(match: matchModel, onSuccess: onSuccess),
    );
  }
}

class _MediaAdderDialog extends StatefulWidget {
  final MatchModel match;
  final VoidCallback onSuccess;
  const _MediaAdderDialog({required this.match, required this.onSuccess});

  @override
  State<_MediaAdderDialog> createState() => _MediaAdderDialogState();
}

class _MediaAdderDialogState extends State<_MediaAdderDialog> {
  String _selectedType = 'Maç Yayın Linki';
  final _urlCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isHomeTeam = true;
  File? _pickedFile;
  bool _isUploading = false;

  final List<String> _types = [
    'Maç Yayın Linki',
    'Takım Fotosu',
    'Önemli An',
    'Maçın Adamı',
    'Diğer',
  ];

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    return AlertDialog(
      title: const Text('Medya Ekle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedType,
              items: _types
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedType = v;
                    _pickedFile = null;
                  });
                }
              },
              decoration: const InputDecoration(labelText: 'Medya Türü'),
            ),
            const SizedBox(height: 16),
            if (_selectedType == 'Maç Yayın Linki')
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(labelText: 'YouTube URL'),
              )
            else ...[
              if (_pickedFile != null)
                Image.file(_pickedFile!, height: 100, fit: BoxFit.cover),
              ElevatedButton.icon(
                onPressed: () async {
                  final picked = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 85,
                  );
                  if (picked != null) {
                    setState(() => _pickedFile = File(picked.path));
                  }
                },
                icon: const Icon(Icons.image),
                label: const Text('Galeriden Seç'),
              ),
            ],
            const SizedBox(height: 16),
            if (_selectedType == 'Takım Fotosu')
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<bool>(
                      title: const Text(
                        'Ev Sahibi',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: true,
                      groupValue: _isHomeTeam,
                      onChanged: (v) => setState(() => _isHomeTeam = v!),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<bool>(
                      title: const Text(
                        'Deplasman',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: false,
                      groupValue: _isHomeTeam,
                      onChanged: (v) => setState(() => _isHomeTeam = v!),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Açıklama (Opsiyonel)',
              ),
              maxLines: 2,
            ),
            if (_isUploading) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _save,
          child: const Text('KAYDET'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final m = widget.match;
    String finalUrl = '';

    if (_selectedType == 'Maç Yayın Linki') {
      finalUrl = _urlCtrl.text.trim();
      if (finalUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen geçerli bir yayın linki girin.'),
          ),
        );
        return;
      }
    } else {
      if (_pickedFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen bir görsel seçin.')),
        );
        return;
      }
      setState(() => _isUploading = true);
      try {
        final uploadedUrl = await ImgBBUploadService().uploadImage(
          _pickedFile!,
        );
        if (uploadedUrl == null) {
          throw Exception('Görsel yüklenemedi.');
        }
        finalUrl = uploadedUrl;
      } catch (e) {
        setState(() => _isUploading = false);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Yükleme hatası: $e')));
        }
        return;
      }
    }

    final media = MatchMediaModel(
      id: '',
      matchId: m.id,
      mediaType: _selectedType,
      url: finalUrl,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      teamId: _selectedType == 'Takım Fotosu'
          ? (_isHomeTeam ? m.homeTeamId : m.awayTeamId)
          : null,
      createdAt: DateTime.now(),
    );

    try {
      await ServiceLocator.matchService.addMatchMedia(media);

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medya başarıyla eklendi.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kayıt Hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted && _isUploading) {
        setState(() => _isUploading = false);
      }
    }
  }
}

class _SpeedDialAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SpeedDialAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class _SpeedDialFab extends StatefulWidget {
  final List<_SpeedDialAction> actions;

  const _SpeedDialFab({super.key, required this.actions});

  @override
  State<_SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends State<_SpeedDialFab> {
  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final actions = widget.actions;

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        if (_open)
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.shrink(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ...List.generate(actions.length, (i) {
                final a = actions[i];
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: !_open
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surface.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: cs.outlineVariant),
                                ),
                                child: Text(
                                  a.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FloatingActionButton(
                                heroTag: 'speed_${a.label}_$i',
                                mini: true,
                                onPressed: () {
                                  _close();
                                  a.onTap();
                                },
                                child: Icon(a.icon),
                              ),
                            ],
                          ),
                        ),
                );
              }),
              FloatingActionButton(
                heroTag: 'speed_main',
                onPressed: _toggle,
                child: AnimatedRotation(
                  turns: _open ? 0.125 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(Icons.add),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- TAB İÇERİKLERİ ---

class _HighlightsTab extends StatefulWidget {
  final MatchModel match;
  final bool isSuperAdmin;
  final VoidCallback onDataChanged;
  const _HighlightsTab({
    super.key,
    required this.match,
    required this.isSuperAdmin,
    required this.onDataChanged,
  });

  @override
  State<_HighlightsTab> createState() => _HighlightsTabState();
}

class _HighlightsTabState extends State<_HighlightsTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<MatchMediaModel>> _mediaStream = ServiceLocator
      .matchService
      .watchMatchMedia(widget.match.id);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _HighlightsTabView(
      match: widget.match,
      isSuperAdmin: widget.isSuperAdmin,
      onDataChanged: widget.onDataChanged,
      mediaStream: _mediaStream,
    );
  }
}

class _HighlightsTabView extends StatelessWidget {
  final MatchModel match;
  final bool isSuperAdmin;
  final VoidCallback onDataChanged;
  final Stream<List<MatchMediaModel>> mediaStream;
  const _HighlightsTabView({
    required this.match,
    required this.isSuperAdmin,
    required this.onDataChanged,
    required this.mediaStream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchMediaModel>>(
      stream: mediaStream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final mediaList = snap.data ?? [];
        if (mediaList.isEmpty) {
          return const Center(child: Text('Henüz medya eklenmedi.'));
        }

        // Yayın linkleri üstte büyük video kartı, diğer medyalar altta liste.
        final videos = mediaList
            .where((m) => m.mediaType == 'Maç Yayın Linki')
            .toList();
        final others = mediaList
            .where((m) => m.mediaType != 'Maç Yayın Linki')
            .toList();

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final v in videos)
              _YoutubeMediaCard(
                key: ValueKey(v.id),
                media: v,
                onDelete: isSuperAdmin
                    ? () => _confirmDelete(context, v)
                    : null,
              ),
            for (var i = 0; i < others.length; i++) ...[
              if (i > 0)
                const Divider(color: Colors.white10, height: 1, indent: 72),
              _buildCompactMediaItem(context, others[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCompactMediaItem(BuildContext context, MatchMediaModel media) {
    final bool isVideo = media.mediaType == 'Maç Yayın Linki';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isVideo
              ? Colors.red.withValues(alpha: 0.1)
              : Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isVideo ? Icons.play_arrow_rounded : Icons.camera_alt_rounded,
          color: isVideo ? Colors.redAccent : Colors.blueAccent,
        ),
      ),
      title: Text(
        media.mediaType,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        media.description ??
            (isVideo ? 'Maç videosunu izle' : 'Görseli görüntüle'),
        style: const TextStyle(color: Colors.white60, fontSize: 12),
      ),
      trailing: isSuperAdmin
          ? IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
                size: 22,
              ),
              onPressed: () => _confirmDelete(context, media),
            )
          : const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
      onTap: () => _openFullScreenMedia(context, media),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    MatchMediaModel media,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Medyayı Sil'),
        content: const Text('Bu medya kalıcı olarak silinecek. Emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await ServiceLocator.matchService.deleteMatchMedia(media.id);

      if (context.mounted) {
        onDataChanged();
      }
    }
  }
}

Future<void> _openFullScreenMedia(
  BuildContext context,
  MatchMediaModel media,
) async {
  if (media.mediaType == 'Maç Yayın Linki') {
    final uri = Uri.parse(media.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video linki açılamadı.')));
      }
    }
    return;
  }

  if (!context.mounted) return;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () async {
                final uri = Uri.parse(media.url);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            child: WebSafeImage(
              url: media.url,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    ),
  );
}

/// YouTube linkinden video id'si çıkarır (watch, youtu.be, embed, shorts, live).
String? _youtubeVideoId(String url) {
  final u = url.trim();
  if (RegExp(r'^[_\-a-zA-Z0-9]{11}$').hasMatch(u)) return u;
  final uri = Uri.tryParse(u);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  String? id;
  if (host.endsWith('youtu.be')) {
    id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  } else if (host.contains('youtube.com') ||
      host.contains('youtube-nocookie.com')) {
    id = uri.queryParameters['v'];
    final seg = uri.pathSegments;
    if (id == null &&
        seg.length >= 2 &&
        const {'embed', 'shorts', 'live', 'v'}.contains(seg.first)) {
      id = seg[1];
    }
  }
  if (id == null || !RegExp(r'^[_\-a-zA-Z0-9]{11}$').hasMatch(id)) {
    return null;
  }
  return id;
}

Future<void> _openYoutubeExternally(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  final ok =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Video linki açılamadı.')));
  }
}

/// 16:9 YouTube alanı: küçük resim + oynat butonu; dokununca video yerinde
/// oynar. Link YouTube'a ait değilse dışarıda açılır.
class _YoutubeVideoView extends StatefulWidget {
  final String url;
  const _YoutubeVideoView({super.key, required this.url});

  @override
  State<_YoutubeVideoView> createState() => _YoutubeVideoViewState();
}

class _YoutubeVideoViewState extends State<_YoutubeVideoView> {
  YoutubePlayerController? _controller;

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  void _play(String? id) {
    if (id == null) {
      _openYoutubeExternally(context, widget.url);
      return;
    }
    setState(() {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: id,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showFullscreenButton: true,
          strictRelatedVideos: true,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = _youtubeVideoId(widget.url);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: _controller != null
          ? YoutubePlayer(controller: _controller!)
          : GestureDetector(
              onTap: () => _play(id),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (id != null)
                    WebSafeImage(
                      url: 'https://img.youtube.com/vi/$id/hqdefault.jpg',
                      fit: BoxFit.cover,
                      fallbackIconSize: 48,
                    )
                  else
                    Container(color: Colors.black),
                  // Alt tarafı hafif karart
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 68,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0000),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 12),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.smart_display_rounded,
                            color: Color(0xFFFF0000),
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'İzlemek için dokun',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Önemli Anlar sekmesindeki maç yayın linki kartı.
class _YoutubeMediaCard extends StatelessWidget {
  final MatchMediaModel media;
  final VoidCallback? onDelete;

  const _YoutubeMediaCard({super.key, required this.media, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final desc = (media.description ?? '').trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.live_tv_rounded,
                  color: Colors.redAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    desc.isEmpty ? 'Maç Yayını' : desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: "YouTube'da aç",
                  onPressed: () => _openYoutubeExternally(context, media.url),
                  icon: const Icon(
                    Icons.open_in_new_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Sil',
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
          _YoutubeVideoView(url: media.url),
        ],
      ),
    );
  }
}

/// Sekmelerin üstünde, maça yayın linki eklendiyse görünen açılır/kapanır
/// "Maç Yayını" paneli. Kapatılınca oynatıcı kaldırılır (video durur).
class _LiveStreamPanel extends StatefulWidget {
  final String matchId;
  const _LiveStreamPanel({super.key, required this.matchId});

  @override
  State<_LiveStreamPanel> createState() => _LiveStreamPanelState();
}

class _LiveStreamPanelState extends State<_LiveStreamPanel> {
  late final Stream<List<MatchMediaModel>> _mediaStream = ServiceLocator
      .matchService
      .watchMatchMedia(widget.matchId);
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchMediaModel>>(
      stream: _mediaStream,
      builder: (context, snap) {
        final stream = (snap.data ?? const <MatchMediaModel>[])
            .where(
              (m) =>
                  m.mediaType == 'Maç Yayın Linki' && m.url.trim().isNotEmpty,
            )
            .firstOrNull;
        if (stream == null) return const SizedBox.shrink();

        final desc = (stream.description ?? '').trim();
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.live_tv_rounded,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            desc.isEmpty ? 'Maç Yayını' : desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: "YouTube'da aç",
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _openYoutubeExternally(context, stream.url),
                          icon: const Icon(
                            Icons.open_in_new_rounded,
                            color: Colors.white54,
                            size: 20,
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded)
                  _YoutubeVideoView(key: ValueKey(stream.id), url: stream.url),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// YENİ EKLENEN KADROLAR (ESAME) TABI WIDGET'I
// -----------------------------------------------------------------------------

class _LineupTab extends StatefulWidget {
  final MatchModel match;
  final bool isAdminAccess;
  final String homeName;
  final String awayName;

  const _LineupTab({
    required this.match,
    required this.isAdminAccess,
    required this.homeName,
    required this.awayName,
  });

  @override
  State<_LineupTab> createState() => _LineupTabState();
}

int _jerseyValue(String? n) => int.tryParse((n ?? '').trim()) ?? 999;

class _LineupTabState extends State<_LineupTab>
    with AutomaticKeepAliveClientMixin {
  static const _green = Color(0xFF10B981);
  static const _blue = Color(0xFF3B82F6);

  // Sekmeler arası geçişte kadro yeniden yüklenmesin.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = widget.match;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        // Takım başlıkları + VS
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _teamHeader(
                name: widget.homeName,
                color: _green,
                teamId: m.homeTeamId,
                alignEnd: false,
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E293B), Color(0xFF064E3B)],
                ),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text(
                'VS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(
              child: _teamHeader(
                name: widget.awayName,
                color: _blue,
                teamId: m.awayTeamId,
                alignEnd: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // İki kadro yan yana
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _TeamLineupColumn(
                  match: m,
                  teamId: m.homeTeamId,
                  color: _green,
                ),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: Colors.white.withValues(alpha: 0.08),
              ),
              Expanded(
                child: _TeamLineupColumn(
                  match: m,
                  teamId: m.awayTeamId,
                  color: _blue,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _teamHeader({
    required String name,
    required Color color,
    required String teamId,
    required bool alignEnd,
  }) {
    final label = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: 14,
      ),
    );
    final edit = widget.isAdminAccess
        ? InkWell(
            onTap: () => _showRosterEditSheet(context, teamId),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_note_rounded, size: 16, color: color),
                  const SizedBox(width: 3),
                  Text(
                    'Esame',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          )
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [label, ?edit],
      ),
    );
  }

  void _showRosterEditSheet(BuildContext context, String teamId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _RosterEditSheet(
          match: widget.match,
          teamId: teamId,
          teamName: teamId == widget.match.homeTeamId
              ? widget.homeName
              : widget.awayName,
          isHome: teamId == widget.match.homeTeamId,
        );
      },
    );
  }
}

/// Tek takımın esamesi: İlk 11 ve Yedekler, önce mevki sonra forma
/// numarasına göre sıralı; sıkı satırlarla tüm ilk 11 tek ekrana sığar.
class _TeamLineupColumn extends StatefulWidget {
  const _TeamLineupColumn({
    required this.match,
    required this.teamId,
    required this.color,
  });

  final MatchModel match;
  final String teamId;
  final Color color;

  @override
  State<_TeamLineupColumn> createState() => _TeamLineupColumnState();
}

class _TeamLineupColumnState extends State<_TeamLineupColumn> {
  // Akışlar bir kez kurulur; üst widget yeniden çizildiğinde (ör. oyuncular
  // yüklendiğinde) kadro akışı baştan başlamaz.
  late Stream<List<PlayerModel>> _playersStream;
  late Stream<List<MatchRosterModel>> _rostersStream;

  MatchModel get match => widget.match;
  String get teamId => widget.teamId;
  Color get color => widget.color;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _TeamLineupColumn old) {
    super.didUpdateWidget(old);
    if (old.match.id != widget.match.id ||
        old.match.seasonId != widget.match.seasonId ||
        old.teamId != widget.teamId) {
      _subscribe();
    }
  }

  void _subscribe() {
    _playersStream = ServiceLocator.teamService.watchPlayers(
      teamId: widget.teamId,
      tournamentId: widget.match.seasonId,
    );
    _rostersStream = ServiceLocator.matchService.watchMatchRosters(
      widget.match.id,
      widget.teamId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PlayerModel>>(
      stream: _playersStream,
      builder: (context, playerSnap) {
        final byId = {
          for (final p in playerSnap.data ?? const <PlayerModel>[]) p.id: p,
        };
        return StreamBuilder<List<MatchRosterModel>>(
          stream: _rostersStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Kadro yüklenemedi: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              );
            }
            final rosters = snapshot.data ?? const <MatchRosterModel>[];
            if (rosters.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Kadro girilmemiş.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              );
            }

            String jerseyOf(MatchRosterModel r) =>
                (r.jerseyNumber ?? byId[r.playerId]?.number ?? '').trim();
            int lineOf(MatchRosterModel r) {
              final p = byId[r.playerId];
              return positionLineOf(p?.mainPosition, p?.position);
            }

            // Önce mevki (Kaleci → Defans → Orta Saha → Forvet), sonra numara.
            int order(MatchRosterModel a, MatchRosterModel b) {
              final c = lineOf(a).compareTo(lineOf(b));
              if (c != 0) return c;
              return _jerseyValue(
                jerseyOf(a),
              ).compareTo(_jerseyValue(jerseyOf(b)));
            }

            // İlk 11: oyuncunun kayıtlı mevkisi değil, o maçın diziliş
            // sahasındaki sırası (kaleci → defans → orta saha → forvet).
            final starterRosters = rosters.where((r) => r.isStarting).toList();
            final formationIds = starterIdsInFormationOrder(
              starters: starterRosters,
              players: byId,
              formation: teamId == match.homeTeamId
                  ? match.homeFormation
                  : match.awayFormation,
            );
            final starterById = {for (final r in starterRosters) r.playerId: r};
            final starters = [
              for (final id in formationIds)
                if (starterById[id] != null) starterById[id]!,
            ];
            final gkId = formationIds.isEmpty ? null : formationIds.first;
            final subs = rosters.where((r) => !r.isStarting).toList()
              ..sort(order);

            List<Widget> rows(List<MatchRosterModel> list, {bool xi = false}) {
              return [
                for (final r in list)
                  _row(
                    jersey: jerseyOf(r),
                    name: byId[r.playerId]?.name ?? '-',
                    // İlk 11'de kaleci: sahadaki kaleci; yedeklerde mevki.
                    line: xi ? (r.playerId == gkId ? 0 : 1) : lineOf(r),
                    isCaptain: r.isCaptain,
                  ),
              ];
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...rows(starters, xi: true),
                if (subs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _section('Yedekler'),
                  ...rows(subs),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 14,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _row({
    required String jersey,
    required String name,
    required int line,
    bool isCaptain = false,
  }) {
    final isGk = line == 0;
    final badge = isGk ? const Color(0xFFF59E0B) : color;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badge.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              jersey.isEmpty ? '-' : jersey,
              style: TextStyle(
                color: badge,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
          if (isCaptain) ...[
            const SizedBox(width: 5),
            const CaptainBadge(size: 14),
          ],
        ],
      ),
    );
  }
}

class _RosterEditSheet extends StatefulWidget {
  final MatchModel match;
  final String teamId;
  final String teamName;
  final bool isHome;

  const _RosterEditSheet({
    required this.match,
    required this.teamId,
    required this.teamName,
    required this.isHome,
  });

  @override
  State<_RosterEditSheet> createState() => _RosterEditSheetState();
}

class _RosterEditSheetState extends State<_RosterEditSheet> {
  final _teamService = ServiceLocator.teamService;
  final _matchService = ServiceLocator.matchService;

  List<PlayerModel> _teamPlayers = [];
  final Set<String> _starterIds = {};
  final Set<String> _subIds = {};
  String? _captainId;
  final Map<String, TextEditingController> _jerseyControllers = {};
  final _searchController = TextEditingController();
  String _query = '';
  bool _isLoading = true;
  bool _isSaving = false;

  int _startingLimit = 11;
  int _subLimit = 7;

  static const _green = Color(0xFF10B981);
  static const _blue = Color(0xFF3B82F6);
  static const _mid = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final c in _jerseyControllers.values) {
      c.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // Sezon ayarları, oyuncular ve kadro paralel çekilir.
      Future<Map<String, dynamic>?> loadSeasonLimits() async {
        if (widget.match.seasonId.isEmpty) return null;
        try {
          return await Supabase.instance.client
              .from('seasons')
              .select('starting_player_count, sub_player_count')
              .eq('id', widget.match.seasonId)
              .maybeSingle();
        } catch (_) {
          return null;
        }
      }

      final (sRes, players, rosters) = await (
        loadSeasonLimits(),
        _teamService.getEligiblePlayers(widget.teamId, widget.match.seasonId),
        _matchService.watchMatchRosters(widget.match.id, widget.teamId).first,
      ).wait;
      final int sCount = sRes?['starting_player_count'] ?? 11;
      final int subCount = sRes?['sub_player_count'] ?? 7;

      if (!mounted) return;
      setState(() {
        _startingLimit = sCount;
        _subLimit = subCount;
        _teamPlayers = players;
        for (final p in _teamPlayers) {
          final pid = p.id;
          final r = rosters.where((x) => x.playerId == pid).firstOrNull;
          if (r != null) {
            (r.isStarting ? _starterIds : _subIds).add(pid);
            if (r.isCaptain && r.isStarting) _captainId = pid;
          }
          _jerseyControllers[pid] = TextEditingController(
            text: r?.jerseyNumber ?? p.number ?? '',
          );
        }
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _tab = 0; // 0: İlk 11, 1: Yedekler

  String _norm(String s) =>
      s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().trim();

  /// Mevki (Kaleci → Forvet), sonra forma numarası sırası.
  List<PlayerModel> get _ordered {
    final list = [..._teamPlayers];
    list.sort((a, b) {
      final la = positionLineOf(a.mainPosition, a.position);
      final lb = positionLineOf(b.mainPosition, b.position);
      if (la != lb) return la.compareTo(lb);
      final c = _jerseyValue(
        _jerseyControllers[a.id]?.text,
      ).compareTo(_jerseyValue(_jerseyControllers[b.id]?.text));
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return list;
  }

  /// İlk 11 tamamlanınca kalan oyuncuları yedek kontenjanı kadar ekler.
  void _autoFillSubs() {
    if (_starterIds.length < _startingLimit) return;
    for (final p in _ordered) {
      if (_subIds.length >= _subLimit) break;
      if (!_starterIds.contains(p.id)) _subIds.add(p.id);
    }
  }

  void _toggleStarter(String pid) {
    if (_starterIds.contains(pid)) {
      setState(() {
        _starterIds.remove(pid);
        if (_captainId == pid) _captainId = null;
      });
      return;
    }
    if (_starterIds.length >= _startingLimit) {
      _toast('İlk 11 dolu ($_startingLimit). Önce birini çıkarın.');
      return;
    }
    setState(() {
      _starterIds.add(pid);
      _subIds.remove(pid);
      _autoFillSubs();
    });
  }

  void _toggleSub(String pid) {
    if (_subIds.contains(pid)) {
      setState(() => _subIds.remove(pid));
      return;
    }
    if (_subIds.length >= _subLimit) {
      _toast('Yedek kontenjanı dolu ($_subLimit).');
      return;
    }
    setState(() => _subIds.add(pid));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _showError(String msg) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hata'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final selectedIds = {..._starterIds, ..._subIds};
    final numericRegExp = RegExp(r'^\d+$');
    final usedNumbers = <String>{};

    for (final pid in selectedIds) {
      final numberText = _jerseyControllers[pid]?.text.trim() ?? '';
      if (numberText.isEmpty || !numericRegExp.hasMatch(numberText)) {
        await _showError(
          'Lütfen seçilen tüm oyuncuların forma numaralarını kontrol ediniz '
          '(Sadece sayı girilmelidir).',
        );
        return;
      }
      if (!usedNumbers.add(numberText)) {
        await _showError(
          'Aynı takımda birden fazla oyuncu aynı forma numarasını kullanamaz '
          '($numberText).',
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final newRosters = <MatchRosterModel>[];
      for (final p in _teamPlayers) {
        final pid = p.id;
        final isStarter = _starterIds.contains(pid);
        if (!isStarter && !_subIds.contains(pid)) continue;
        newRosters.add(
          MatchRosterModel(
            id: '',
            matchId: widget.match.id,
            leagueId: widget.match.leagueId,
            seasonId: widget.match.seasonId,
            teamId: widget.teamId,
            playerId: pid,
            isHome: widget.isHome,
            isStarting: isStarter,
            jerseyNumber: _jerseyControllers[pid]?.text.trim(),
            isCaptain: isStarter && pid == _captainId,
          ),
        );
      }

      await _matchService.updateMatchRoster(
        matchId: widget.match.id,
        leagueId: widget.match.leagueId,
        seasonId: widget.match.seasonId,
        teamId: widget.teamId,
        isHome: widget.isHome,
        rosters: newRosters,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _toast('Hata: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _tabButton(int index, String label, int value, int limit, Color c) {
    final on = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
          decoration: BoxDecoration(
            color: on ? c.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: on ? c : Colors.white.withValues(alpha: 0.12),
              width: on ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: on ? Colors.white : Colors.white60,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                '$value / $limit',
                style: TextStyle(
                  color: on ? c : Colors.white54,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playerRow(PlayerModel p, {required bool starterTab}) {
    final pid = p.id;
    final selected = starterTab
        ? _starterIds.contains(pid)
        : _subIds.contains(pid);
    final color = starterTab ? _green : _blue;
    final sub = (p.position ?? '').trim();
    final isCaptain = _captainId == pid;

    return GestureDetector(
      onTap: () => starterTab ? _toggleStarter(pid) : _toggleSub(pid),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: TextField(
                controller: _jerseyControllers[pid],
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: '#',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.3),
                  contentPadding: const EdgeInsets.symmetric(vertical: 7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: p.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                  children: [
                    if (sub.isNotEmpty)
                      TextSpan(
                        text: '  $sub',
                        style: const TextStyle(
                          color: _mid,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (starterTab && selected)
              GestureDetector(
                onTap: () =>
                    setState(() => _captainId = isCaptain ? null : pid),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Opacity(
                    opacity: isCaptain ? 1 : 0.3,
                    child: const CaptainBadge(size: 20),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? color : Colors.white30,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final q = _norm(_query);
    final starterTab = _tab == 0;

    // İlk 11 sekmesi: tüm kadro. Yedekler: ilk 11 dışındakiler.
    final visible = _ordered.where((p) {
      if (!starterTab && _starterIds.contains(p.id)) return false;
      return q.isEmpty || _norm(p.name).contains(q);
    }).toList();
    final groups = List.generate(4, (_) => <PlayerModel>[]);
    for (final p in visible) {
      groups[positionLineOf(p.mainPosition, p.position)].add(p);
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Esame Listesi',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                        children: [
                          TextSpan(
                            text: '  ${widget.teamName}',
                            style: const TextStyle(
                              color: _mid,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (!_isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    _tabButton(
                      0,
                      'İlk 11',
                      _starterIds.length,
                      _startingLimit,
                      _green,
                    ),
                    const SizedBox(width: 8),
                    _tabButton(1, 'Yedekler', _subIds.length, _subLimit, _blue),
                  ],
                ),
              ),
            if (!_isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Oyuncu ara',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _teamPlayers.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Bu takımın sezon kadrosunda oyuncu yok.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        for (var i = 0; i < groups.length; i++)
                          if (groups[i].isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
                              child: Text(
                                positionLineLabels[i],
                                style: const TextStyle(
                                  color: _mid,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            ...groups[i].map(
                              (p) => _playerRow(p, starterTab: starterTab),
                            ),
                          ],
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSaving || _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'KAYDET',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DETAY TABI (MAÇ AKIŞI)
// -----------------------------------------------------------------------------

class _DetailTab extends StatefulWidget {
  final MatchModel match;
  const _DetailTab({required this.match});

  @override
  State<_DetailTab> createState() => _DetailTabState();
}

class _DetailTabState extends State<_DetailTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<Map<String, dynamic>>> _eventsStream = ServiceLocator
      .matchService
      .watchInlineMatchEvents(widget.match.id);
  late final Future<int> _periodFuture = _DetailTabView._periodMinutes(
    widget.match.seasonId,
  );

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _DetailTabView(
      match: widget.match,
      eventsStream: _eventsStream,
      periodFuture: _periodFuture,
    );
  }
}

class _DetailTabView extends StatelessWidget {
  final MatchModel match;
  final Stream<List<Map<String, dynamic>>> eventsStream;
  final Future<int> periodFuture;
  const _DetailTabView({
    required this.match,
    required this.eventsStream,
    required this.periodFuture,
  });

  String _friendlyLoadError(Object? error) {
    final s = (error ?? '').toString();
    final lower = s.toLowerCase();
    if (lower.contains('permission-denied')) {
      return 'Yetki hatası. Giriş yapıldı mı ve kullanıcı yetkisi doğru mu kontrol edin.\n\n$s';
    }
    if (lower.contains('requires an index') ||
        lower.contains('failed-precondition')) {
      return 'Sorgu için Firestore index gerekli olabilir.\n\n$s';
    }
    if (lower.contains('unavailable') || lower.contains('network')) {
      return 'Bağlantı hatası. İnternet bağlantısını kontrol edin.\n\n$s';
    }
    return s;
  }

  int _readMinute(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    final s = v.toString().replaceAll('\u0000', '').trim();
    return int.tryParse(s) ??
        double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
        0;
  }

  String _readString(dynamic v) => (v ?? '').toString().trim();

  Map<String, dynamic> _asMap(dynamic v) =>
      (v is Map) ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  /// Sezon başına devre süresi (dk) önbelleği.
  static final Map<String, Future<int>> _periodBySeason = {};

  /// `seasons.match_period_duration` = TEK DEVRE süresi.
  /// Devre arası bu değer, maç sonu bu değerin iki katıdır.
  static Future<int> _periodMinutes(String seasonId) {
    final sid = seasonId.trim();
    if (sid.isEmpty) return Future.value(45);
    return _periodBySeason.putIfAbsent(sid, () async {
      try {
        final res = await Supabase.instance.client
            .from('seasons')
            .select('match_period_duration')
            .eq('id', sid)
            .limit(1);
        if (res.isEmpty) return 45;
        final v = res.first['match_period_duration'];
        final m = v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
        return m > 0 ? m : 45;
      } catch (_) {
        _periodBySeason.remove(sid); // hata kalıcı önbelleğe alınmasın
        return 45;
      }
    });
  }

  List<Map<String, dynamic>> _fallbackSystemStory(int period) {
    switch (match.status) {
      case MatchStatus.notStarted:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Henüz Başlamadı'},
        ];
      case MatchStatus.postponed:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Ertelendi'},
        ];
      case MatchStatus.cancelled:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç İptal Edildi'},
        ];
      case MatchStatus.live:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Başladı'},
        ];
      case MatchStatus.halftime:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Başladı'},
          {'minute': period, 'type': 'status', 'title': 'İlk Yarı Bitti'},
        ];
      case MatchStatus.finished:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Başladı'},
          {'minute': period, 'type': 'status', 'title': 'İlk Yarı Bitti'},
          {'minute': period * 2, 'type': 'status', 'title': 'Maç Bitti'},
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: periodFuture,
      builder: (context, periodSnap) {
        if (!periodSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildFlow(context, periodSnap.data!);
      },
    );
  }

  Widget _buildFlow(BuildContext context, int period) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: eventsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Maç akışı yüklenemedi.\n\n${_friendlyLoadError(snap.error)}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final raw = snap.data ?? const <Map<String, dynamic>>[];

        final systemStory = _fallbackSystemStory(period);
        final List<Map<String, dynamic>> normalized = raw
            .map((e) => _asMap(e))
            .toList();

        String pickType(Map<String, dynamic> e) {
          return _readString(e['type']).isNotEmpty
              ? _readString(e['type'])
              : _readString(e['eventType']).isNotEmpty
              ? _readString(e['eventType'])
              : _readString(e['event_type']);
        }

        String pickTitle(Map<String, dynamic> e) {
          final a = _readString(e['playerName']);
          if (a.isNotEmpty) return a;
          final b = _readString(e['player_name']);
          if (b.isNotEmpty) return b;
          final c = _readString(e['title']);
          if (c.isNotEmpty) return c;
          return _readString(e['eventType']).isNotEmpty
              ? _readString(e['eventType'])
              : _readString(e['event_type']);
        }

        String pickTeamId(Map<String, dynamic> e) {
          final a = _readString(e['teamId']);
          if (a.isNotEmpty) return a;
          return _readString(e['team_id']);
        }

        bool isSystem(Map<String, dynamic> e) {
          final t = pickType(e);
          final et = _readString(e['eventType']).isNotEmpty
              ? _readString(e['eventType'])
              : _readString(e['event_type']);
          if (t == 'status' || t == 'system') return true;
          if (et == 'status' || et == 'system') return true;
          if (pickTeamId(e).isEmpty && pickTitle(e).isNotEmpty) return true;
          return false;
        }

        if (normalized.isEmpty) {
          normalized.addAll(systemStory);
        } else {
          final existingTitleKeys = normalized
              .map((e) => pickTitle(e).toLowerCase())
              .where((s) => s.isNotEmpty)
              .toSet();
          for (final s in systemStory) {
            final key = pickTitle(s).toLowerCase();
            if (key.isNotEmpty && !existingTitleKeys.contains(key)) {
              normalized.add(s);
            }
          }
        }

        normalized.sort((a, b) {
          final am = _readMinute(a['minute']);
          final bm = _readMinute(b['minute']);
          if (am != bm) return am.compareTo(bm);
          final at = pickType(a);
          final bt = pickType(b);
          return at.compareTo(bt);
        });

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: normalized.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            if (i == 0) {
              return const Text(
                'Maç Detayı',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              );
            }
            final e = normalized[i - 1];
            final type = pickType(e);
            final title = pickTitle(e);
            final minute = _readMinute(e['minute']);
            final teamId = pickTeamId(e);
            final system = isSystem(e);

            final subIn = _readString(e['subInPlayerName']).isNotEmpty
                ? _readString(e['subInPlayerName'])
                : _readString(e['sub_in_player_name']);
            final assist = _readString(e['assistPlayerName']).isNotEmpty
                ? _readString(e['assistPlayerName'])
                : _readString(e['assist_player_name']);
            final isOwnGoal =
                (e['isOwnGoal'] as bool?) ??
                (e['is_own_goal'] as bool?) ??
                false;

            String displayTitle() {
              if (type == 'substitution') {
                final outName = title;
                final inName = subIn;
                if (outName.isNotEmpty && inName.isNotEmpty) {
                  return '$outName → $inName';
                }
                return outName.isEmpty ? 'Değişiklik' : outName;
              }
              if (type == 'goal') {
                final suffix = isOwnGoal ? ' (KK)' : '';
                return '${title.isEmpty ? 'Gol' : title}$suffix';
              }
              return title;
            }

            return _DetailEventTile(
              minute: minute,
              type: type,
              title: displayTitle(),
              // Asist, gol atanın altında daha küçük ve soluk gösterilir.
              subtitle: type == 'goal' && assist.isNotEmpty
                  ? 'Asist: $assist'
                  : null,
              teamId: teamId,
              homeTeamId: match.homeTeamId,
              system: system,
            );
          },
        );
      },
    );
  }
}

class _DetailEventTile extends StatelessWidget {
  final int minute;
  final String type;
  final String title;
  final String? subtitle;
  final String teamId;
  final String homeTeamId;
  final bool system;
  const _DetailEventTile({
    required this.minute,
    required this.type,
    required this.title,
    this.subtitle,
    required this.teamId,
    required this.homeTeamId,
    required this.system,
  });

  Widget _systemIcon(String title) {
    final t = title.toLowerCase();
    if (t.contains('başla')) {
      return const Icon(Icons.play_arrow_rounded);
    }
    if (t.contains('devre') || t.contains('yarı')) {
      return const Icon(Icons.timelapse_rounded);
    }
    if (t.contains('bitti') || t.contains('son')) {
      return const Icon(Icons.flag_rounded);
    }
    return const Icon(Icons.info_outline);
  }

  Widget _titleBlock(CrossAxisAlignment align) {
    final sub = (subtitle ?? '').trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        Text(
          title.isEmpty ? '-' : title,
          style: const TextStyle(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        if (sub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              sub,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isHome = teamId == homeTeamId;
    final String min = "$minute'";

    Widget icon;
    if (system) {
      icon = _systemIcon(title);
    } else {
      switch (type) {
        case 'goal':
          icon = const Icon(Icons.sports_soccer, size: 18, color: Colors.white);
          break;
        case 'yellow_card':
          icon = const Icon(Icons.rectangle, color: Colors.yellow, size: 18);
          break;
        case 'red_card':
          icon = const Icon(Icons.rectangle, color: Colors.red, size: 18);
          break;
        case 'second_yellow':
          icon = const _SecondYellowCardIcon();
          break;
        case 'substitution':
          icon = const Icon(Icons.swap_horiz_rounded, size: 18);
          break;
        default:
          icon = const Icon(Icons.info_outline, size: 18);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: system
          ? Row(
              children: [
                Expanded(
                  child: Divider(
                    color: Colors.white.withValues(alpha: 0.12),
                    height: 1,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        min,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconTheme(
                        data: const IconThemeData(
                          size: 13,
                          color: Colors.white60,
                        ),
                        child: icon,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        title.isEmpty ? '-' : title,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: Colors.white.withValues(alpha: 0.12),
                    height: 1,
                  ),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: isHome
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.end,
              children: isHome
                  ? [
                      Text(
                        min,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 8),
                      icon,
                      const SizedBox(width: 8),
                      Flexible(child: _titleBlock(CrossAxisAlignment.start)),
                    ]
                  : [
                      Flexible(child: _titleBlock(CrossAxisAlignment.end)),
                      const SizedBox(width: 8),
                      icon,
                      const SizedBox(width: 8),
                      Text(
                        min,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
            ),
    );
  }
}
