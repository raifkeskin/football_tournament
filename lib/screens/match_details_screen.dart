import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../models/league_extras.dart';
import '../models/match.dart';
import '../models/team.dart';
import '../widgets/web_safe_image.dart';
import '../services/app_session.dart';
import '../services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../services/interfaces/i_team_service.dart';
import '../services/service_locator.dart';
import 'admin_match_event_screen.dart';
import 'admin_match_lineup_screen.dart';

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

class _TeamInfo extends StatelessWidget {
  final String name;
  final String logoUrl;

  const _TeamInfo({required this.name, required this.logoUrl});

  String _smartAbbreviate(String val) {
    if (val.length <= 20) return val;
    return val
        .replaceAll(RegExp(r'Masterlar(ı)?', caseSensitive: false), 'M.')
        .replaceAll(RegExp(r'Master', caseSensitive: false), 'M.')
        .replaceAll(RegExp(r'Spor Kulübü', caseSensitive: false), 'SK')
        .replaceAll(RegExp(r'Futbol Kulübü', caseSensitive: false), 'FK')
        .replaceAll(RegExp(r'Gençlik', caseSensitive: false), 'Gnç.')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _smartAbbreviate(name);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        WebSafeImage(
          url: logoUrl,
          width: 54,
          height: 54,
          isCircle: true,
          fallbackIconSize: 26,
        ),
        const SizedBox(height: 12),
        Text(
          displayName,
          textAlign: TextAlign.center,
          softWrap: true,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
            shadows: const [
              Shadow(
                color: Colors.black,
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
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
  const MatchDetailsScreen({
    super.key,
    required this.match,
    this.isAdmin = false,
  });

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen> {
  final ITeamService _teamService = ServiceLocator.teamService;
  final IMatchService _matchService = ServiceLocator.matchService;
  final ILeagueService _leagueService = ServiceLocator.leagueService;

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

  Future<void> _openPitchLocation(BuildContext context, String rawLocation) async {
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
      final ok = await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
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

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final session = AppSession.of(context).value;

    // HATA DÜZELTİLDİ: managedTeamId yerine teamId kullanıldı
    final bool isSuperAdmin = session.isAdmin;
    final bool isTeamManager =
        session.teamId == m.homeTeamId || session.teamId == m.awayTeamId;
    final bool isAdminAccess = isSuperAdmin || isTeamManager;

    return StreamBuilder<List<Team>>(
      stream: _teamService.watchAllTeams(),
      builder: (context, teamsSnap) {
        final Map<String, String> logoMap = {};
        if (teamsSnap.hasData) {
          for (final team in teamsSnap.data!) {
            logoMap[team.id] = team.logoUrl;
          }
        }

        final homeLogo = logoMap[m.homeTeamId] ?? '';
        final awayLogo = logoMap[m.awayTeamId] ?? '';

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              title: const Text(
                'Maç Detayı',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              centerTitle: true,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
            floatingActionButton: !isSuperAdmin
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        heroTag: 'yt',
                        mini: true,
                        onPressed: () => _openYoutubeLinkEditor(m),
                        child: const Icon(Icons.videocam_rounded),
                      ),
                      const SizedBox(width: 10),
                      FloatingActionButton(
                        heroTag: 'pitch',
                        mini: true,
                        onPressed: () => _openPitchEditor(m),
                        child: const Icon(Icons.location_on),
                      ),
                      const SizedBox(width: 10),
                      FloatingActionButton(
                        heroTag: 'event',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminMatchEventScreen(match: m),
                          ),
                        ),
                        child: const Icon(Icons.edit_note_rounded),
                      ),
                    ],
                  ),
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
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + (kToolbarHeight - 16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _TeamInfo(
                                    name: m.homeTeamName,
                                    logoUrl: homeLogo,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        "${m.homeScore} - ${m.awayScore}",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 38,
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
                                    name: m.awayTeamName,
                                    logoUrl: awayLogo,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
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
                                if ((m.pitchName ?? '').isNotEmpty) ...[
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
                                      stream: _leagueService.watchPitches(),
                                      builder: (context, pitchSnap) {
                                        final pitchName = m.pitchName!.trim();
                                        final pitchId = (m.pitchId ?? '').trim();
                                        final pitches = pitchSnap.data ?? const <Pitch>[];
                                        final location = _resolvePitchLocation(
                                          pitches: pitches,
                                          pitchId: pitchId,
                                          pitchName: pitchName,
                                        );

                                        return InkWell(
                                          onTap: location.isEmpty
                                              ? null
                                              : () => _openPitchLocation(context, location),
                                          child: Text(
                                            pitchName,
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
                const TabBar(
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  tabs: [
                    Tab(text: 'Detay'),
                    Tab(text: 'Kadrolar'),
                    Tab(text: 'Önemli Anlar'),
                  ],
                ),
                Expanded(
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: TabBarView(
                      children: [
                        _DetailTab(match: m),
                        _LineupTab(match: m, isAdmin: isAdminAccess),
                        _HighlightsTab(match: m),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openYoutubeLinkEditor(MatchModel m) {
    final ctrl = TextEditingController(text: m.youtubeUrl);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('YouTube URL'),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _matchService.updateMatchYoutubeUrl(
                matchId: m.id,
                youtubeUrl: ctrl.text,
              );
              Navigator.pop(c);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
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
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// --- TAB İÇERİKLERİ ---

class _HighlightsTab extends StatelessWidget {
  final MatchModel match;
  const _HighlightsTab({required this.match});

  @override
  Widget build(BuildContext context) {
    final homePhoto = (match.homeHighlightPhotoUrl ?? '').trim();
    final awayPhoto = (match.awayHighlightPhotoUrl ?? '').trim();
    final hasPhoto = homePhoto.isNotEmpty || awayPhoto.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (match.youtubeUrl != null && match.youtubeUrl!.isNotEmpty)
          _YoutubePlayerSection(url: match.youtubeUrl!),
        if (match.youtubeUrl != null && match.youtubeUrl!.isNotEmpty)
          const SizedBox(height: 16),
        const Text(
          'Maç Fotoğrafları',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 10),
        if (!hasPhoto)
          const Text(
            'Henüz fotoğraf eklenmedi.',
            style: TextStyle(color: Colors.white70),
          ),
        if (homePhoto.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: WebSafeImage(
              url: homePhoto,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              isCircle: false,
              fallbackIconSize: 32,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (awayPhoto.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: WebSafeImage(
              url: awayPhoto,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              isCircle: false,
              fallbackIconSize: 32,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _YoutubePlayerSection extends StatefulWidget {
  final String url;
  const _YoutubePlayerSection({required this.url});
  @override
  State<_YoutubePlayerSection> createState() => _YoutubePlayerSectionState();
}

class _YoutubePlayerSectionState extends State<_YoutubePlayerSection> {
  late YoutubePlayerController _controller;
  @override
  void initState() {
    super.initState();
    final id = YoutubePlayerController.convertUrlToId(widget.url);
    _controller = YoutubePlayerController.fromVideoId(
      videoId: id ?? '',
      params: const YoutubePlayerParams(showFullscreenButton: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: YoutubePlayer(controller: _controller),
    );
  }
}

class _LineupTab extends StatelessWidget {
  final MatchModel match;
  final bool isAdmin;
  const _LineupTab({required this.match, required this.isAdmin});

  void _showLineupChoice(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.home),
              title: Text('${match.homeTeamName} Kadrosu'),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AdminMatchLineupScreen(match: match, isHome: true),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.outbound),
              title: Text('${match.awayTeamName} Kadrosu'),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AdminMatchLineupScreen(match: match, isHome: false),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isAdmin)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ElevatedButton.icon(
              onPressed: () => _showLineupChoice(context),
              icon: const Icon(Icons.people),
              label: const Text('Kadroları Düzenle'),
            ),
          ),
        _TeamLineupSection(
          teamName: match.homeTeamName,
          lineup: match.homeLineup,
        ),
        const Divider(height: 40, color: Colors.white10),
        _TeamLineupSection(
          teamName: match.awayTeamName,
          lineup: match.awayLineup,
        ),
      ],
    );
  }
}

class _TeamLineupSection extends StatelessWidget {
  final String teamName;
  final List<dynamic>? lineup;
  const _TeamLineupSection({required this.teamName, this.lineup});

  @override
  Widget build(BuildContext context) {
    final starting =
        lineup?.where((p) => p['isStarting'] == true).toList() ?? [];
    final subs = lineup?.where((p) => p['isStarting'] == false).toList() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          teamName,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: Colors.amber,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'İLK 11',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.white54,
          ),
        ),
        if (starting.isEmpty)
          const Text(
            'Kadro girilmedi',
            style: TextStyle(color: Colors.white24, fontSize: 13),
          ),
        ...starting.map(
          (p) => ListTile(
            dense: true,
            leading: Text(
              '${p['number'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            title: Text(p['playerName'] ?? ''),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'YEDEKLER',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.white54,
          ),
        ),
        if (subs.isEmpty)
          const Text(
            'Yedek girilmedi',
            style: TextStyle(color: Colors.white24, fontSize: 13),
          ),
        ...subs.map(
          (p) => ListTile(
            dense: true,
            leading: Text(
              '${p['number'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            title: Text(p['playerName'] ?? ''),
          ),
        ),
      ],
    );
  }
}

class _DetailTab extends StatelessWidget {
  final MatchModel match;
  const _DetailTab({required this.match});

  int _readMinute(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    final s = v.toString().replaceAll('\u0000', '').trim();
    return int.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'))?.toInt() ?? 0;
  }

  String _readString(dynamic v) => (v ?? '').toString().trim();

  Map<String, dynamic> _asMap(dynamic v) =>
      (v is Map) ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  List<Map<String, dynamic>> _fallbackSystemStory() {
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
          {'minute': 45, 'type': 'status', 'title': 'İlk Yarı Bitti'},
        ];
      case MatchStatus.finished:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Başladı'},
          {'minute': 45, 'type': 'status', 'title': 'İlk Yarı Bitti'},
          {'minute': 90, 'type': 'status', 'title': 'Maç Bitti'},
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ServiceLocator.matchService.watchInlineMatchEvents(match.id),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final raw = snap.data ?? const <Map<String, dynamic>>[];

        final systemStory = _fallbackSystemStory();
        final List<Map<String, dynamic>> normalized =
            raw.map((e) => _asMap(e)).toList();

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
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            if (i == 0) {
              return const Text(
                'Maç Akışı',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              );
            }
            final e = normalized[i - 1];
            final type = pickType(e);
            final title = pickTitle(e);
            final minute = _readMinute(e['minute']);
            final teamId = pickTeamId(e);
            final system = isSystem(e);

            final subIn =
                _readString(e['subInPlayerName']).isNotEmpty ? _readString(e['subInPlayerName']) : _readString(e['sub_in_player_name']);
            final assist =
                _readString(e['assistPlayerName']).isNotEmpty ? _readString(e['assistPlayerName']) : _readString(e['assist_player_name']);
            final isOwnGoal = (e['isOwnGoal'] as bool?) ?? (e['is_own_goal'] as bool?) ?? false;

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
                final a = assist.isNotEmpty ? ' (Asist: $assist)' : '';
                return '${title.isEmpty ? 'Gol' : title}$suffix$a';
              }
              return title;
            }

            return _DetailEventTile(
              minute: minute,
              type: type,
              title: displayTitle(),
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
  final String teamId;
  final String homeTeamId;
  final bool system;
  const _DetailEventTile({
    required this.minute,
    required this.type,
    required this.title,
    required this.teamId,
    required this.homeTeamId,
    required this.system,
  });

  Widget _systemIcon(String title) {
    final t = title.toLowerCase();
    if (t.contains('başla')) return const Icon(Icons.play_arrow_rounded, size: 18);
    if (t.contains('devre') || t.contains('yarı')) {
      return const Icon(Icons.timelapse_rounded, size: 18);
    }
    if (t.contains('bitti') || t.contains('son')) {
      return const Icon(Icons.flag_rounded, size: 18);
    }
    return const Icon(Icons.info_outline, size: 18);
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
          ? Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      min,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(width: 10),
                    icon,
                    const SizedBox(width: 10),
                    Text(
                      title.isEmpty ? '-' : title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            )
          : Row(
              mainAxisAlignment:
                  isHome ? MainAxisAlignment.start : MainAxisAlignment.end,
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
                      Flexible(
                        child: Text(
                          title.isEmpty ? '-' : title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]
                  : [
                      Flexible(
                        child: Text(
                          title.isEmpty ? '-' : title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
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
