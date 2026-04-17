import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../models/match.dart';
import '../widgets/web_safe_image.dart';
import '../services/database_service.dart';
import '../services/app_session.dart';
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
            fontWeight: FontWeight.w900,
            fontSize: displayName.length > 15 ? 11 : 13,
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
  String _formatDate(String dateStr) {
    if (dateStr.isEmpty || dateStr == '__NO_DATE__')
      return 'Tarih Belirlenmedi';
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

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('teams').snapshots(),
      builder: (context, teamsSnap) {
        final Map<String, String> logoMap = {};
        if (teamsSnap.hasData) {
          for (var doc in teamsSnap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            logoMap[doc.id] = data['logoUrl']?.toString() ?? '';
          }
        }

        final homeLogo = logoMap[m.homeTeamId] ?? '';
        final awayLogo = logoMap[m.awayTeamId] ?? '';

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text(
                'Maç Detayı',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              centerTitle: true,
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
                // ÜST PANEL
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF064E3B), Color(0xFF065F46)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
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
                                  ),
                                ),
                                if (m.status == MatchStatus.live)
                                  const Text(
                                    "CANLI",
                                    style: TextStyle(
                                      color: Colors.amber,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
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
                              ),
                            ),
                            if ((m.pitchName ?? '').isNotEmpty) ...[
                              const SizedBox(width: 12),
                              const Text(
                                "|",
                                style: TextStyle(color: Colors.white24),
                              ),
                              const SizedBox(width: 12),
                              const Icon(
                                Icons.location_on_rounded,
                                size: 14,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  m.pitchName!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
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
                  child: TabBarView(
                    children: [
                      _SummaryTab(match: m),
                      _LineupTab(match: m, isAdmin: isAdminAccess),
                      _LineupEventsTab(match: m, isAdmin: isSuperAdmin),
                    ],
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
              await FirebaseFirestore.instance
                  .collection('matches')
                  .doc(m.id)
                  .update({'youtubeUrl': ctrl.text});
              Navigator.pop(c);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _openPitchEditor(MatchModel m) async {
    final snap = await FirebaseFirestore.instance.collection('pitches').get();
    final list = snap.docs.map((d) => d.data()['name'] as String).toList();
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
                  await FirebaseFirestore.instance
                      .collection('matches')
                      .doc(m.id)
                      .update({'pitchName': sel});
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

class _SummaryTab extends StatelessWidget {
  final MatchModel match;
  const _SummaryTab({required this.match});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (match.youtubeUrl != null && match.youtubeUrl!.isNotEmpty)
          _YoutubePlayerSection(url: match.youtubeUrl!),
        const SizedBox(height: 20),
        const Text(
          'Maç Hakkında',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 10),
        const Text(
          'Bu maçın detaylı özeti ve saha bilgileri burada yer alacaktır.',
          style: TextStyle(color: Colors.white70),
        ),
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

class _LineupEventsTab extends StatelessWidget {
  final MatchModel match;
  final bool isAdmin;
  const _LineupEventsTab({required this.match, required this.isAdmin});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Maç Olayları',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('matches')
              .doc(match.id)
              .collection('events')
              .orderBy('minute', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData)
              return const Center(child: CircularProgressIndicator());
            if (snap.data!.docs.isEmpty)
              return const Center(
                child: Text(
                  'Henüz olay yok.',
                  style: TextStyle(color: Colors.white38),
                ),
              );
            return Column(
              children: snap.data!.docs
                  .map(
                    (d) => _MatchEventTile(
                      data: d.data() as Map<String, dynamic>,
                      homeTeamId: match.homeTeamId,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _MatchEventTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String homeTeamId;
  const _MatchEventTile({required this.data, required this.homeTeamId});

  @override
  Widget build(BuildContext context) {
    final bool isHome = data['teamId'] == homeTeamId;
    final String type = data['type'] ?? '';
    final String player = data['playerName'] ?? '';
    final String min = data['minute']?.toString() ?? '0';

    Widget icon;
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
      default:
        icon = const Icon(Icons.info_outline, size: 18);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: isHome
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: isHome
            ? [
                Text(
                  "$min'",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(width: 8),
                icon,
                const SizedBox(width: 8),
                Text(
                  player,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ]
            : [
                Text(
                  player,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                icon,
                const SizedBox(width: 8),
                Text(
                  "$min'",
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
