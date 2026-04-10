import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/match.dart';
import '../services/database_service.dart';
import 'admin_match_event_screen.dart';
import 'admin_match_lineup_screen.dart';

class _SecondYellowCardIcon extends StatelessWidget {
  const _SecondYellowCardIcon();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 14,
      height: 20,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.amber, Colors.red],
          stops: [0.5, 0.5],
        ),
      ),
    );
  }
}

String _shortenName(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return cleaned;
  final parts = cleaned.split(' ');
  if (parts.length <= 2) return cleaned;
  final first = parts[0];
  final second = parts[1];
  final last = parts.last;
  final initial = last.isEmpty ? '' : '${last[0].toUpperCase()}.';
  return '$first $second $initial';
}

Widget _eventIcon(
  String type, {
  required bool isSecondYellow,
  required bool isOwnGoal,
}) {
  switch (type) {
    case 'goal':
      return Icon(
        Icons.sports_soccer,
        color: isOwnGoal ? Colors.red : Colors.green,
      );
    case 'substitution':
      return const Icon(Icons.swap_horiz_rounded, color: Colors.blueGrey);
    case 'assist':
      return const Icon(Icons.handshake_rounded, color: Colors.blue);
    case 'yellow_card':
      return isSecondYellow
          ? const _SecondYellowCardIcon()
          : const Icon(Icons.rectangle, color: Colors.amber, size: 20);
    case 'red_card':
      return const Icon(Icons.rectangle, color: Colors.red, size: 20);
    default:
      return const Icon(Icons.info_outline);
  }
}

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

class _MatchDetailsScreenState extends State<MatchDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _tabIndex = 0;

  Future<void> _openYoutubeLinkEditor(MatchModel match) async {
    final controller = TextEditingController(text: match.youtubeUrl ?? '');
    final db = DatabaseService();
    final cs = Theme.of(context).colorScheme;

    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    'YouTube Maç Linki',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: cs.surfaceContainerLow,
                    elevation: 0.5,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          hintText: 'https://youtube.com/…',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            controller.clear();
                            Navigator.pop(context, true);
                          },
                          child: const Text('Kaldır'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Kaydet'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (saved != true) return;
      await db.updateMatchYoutubeUrl(
        matchId: match.id,
        youtubeUrl: controller.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('YouTube linki güncellendi.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() => _tabIndex = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dbService = DatabaseService();
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<MatchEvent>>(
      stream: dbService.getMatchEvents(widget.match.id),
      builder: (context, eventSnapshot) {
        if (eventSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Maç Detayı')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (eventSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Maç Detayı')),
            body: Center(child: Text('Hata: ${eventSnapshot.error}')),
          );
        }
        final events = eventSnapshot.data ?? const <MatchEvent>[];

        int htHomeFromEvents(String teamId) => events
            .where((e) => e.type == 'goal' && e.minute <= 45 && e.teamId == teamId)
            .length;

        return StreamBuilder<MatchModel>(
          stream: dbService.watchMatch(widget.match.id),
          builder: (context, matchSnapshot) {
            if (!matchSnapshot.hasData) {
              return Scaffold(
                appBar: AppBar(title: const Text('Maç Detayı')),
                body: const Center(child: CircularProgressIndicator()),
              );
            }
            final m = matchSnapshot.data!;

            final showScores = m.status != MatchStatus.notStarted;
            final htHome = m.halfTimeHomeScore ??
                (showScores ? htHomeFromEvents(m.homeTeamId) : null);
            final htAway = m.halfTimeAwayScore ??
                (showScores ? htHomeFromEvents(m.awayTeamId) : null);

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('teams')
                  .where(
                    FieldPath.documentId,
                    whereIn: [m.homeTeamId, m.awayTeamId],
                  )
                  .snapshots(),
              builder: (context, teamSnapshot) {
                final teamLogoById = <String, String>{};
                if (teamSnapshot.hasData) {
                  for (final doc in teamSnapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final raw =
                        (data['logoUrl'] ?? data['logo'] ?? '').toString().trim();
                    teamLogoById[doc.id] = raw;
                  }
                }

                final homeLogo = (m.homeTeamLogoUrl.trim()).isNotEmpty
                    ? m.homeTeamLogoUrl
                    : (teamLogoById[m.homeTeamId] ?? '');
                final awayLogo = (m.awayTeamLogoUrl.trim()).isNotEmpty
                    ? m.awayTeamLogoUrl
                    : (teamLogoById[m.awayTeamId] ?? '');

                final isAdmin = widget.isAdmin;
                return Scaffold(
                  appBar: AppBar(title: const Text('Maç Detayı')),
                  floatingActionButton: isAdmin && _tabIndex == 0
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FloatingActionButton(
                              heroTag: 'yt_${m.id}',
                              mini: true,
                              onPressed: () => _openYoutubeLinkEditor(m),
                              child: const Icon(Icons.videocam_rounded),
                            ),
                            const SizedBox(width: 12),
                            FloatingActionButton(
                              heroTag: 'event_${m.id}',
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AdminMatchEventScreen(match: m),
                                  ),
                                );
                              },
                              child: const Icon(Icons.add),
                            ),
                          ],
                        )
                      : null,
                  body: Column(
                    children: [
                      Card(
                        margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 14,
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _TeamInfo(
                                      name: m.homeTeamName,
                                      logoUrl: homeLogo,
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${m.homeScore} - ${m.awayScore}',
                                        style: const TextStyle(
                                          fontSize: 44,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      if (showScores)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (htHome != null && htAway != null)
                                              _ScorePill(
                                                label: 'İY',
                                                value: '$htHome-$htAway',
                                              ),
                                            if (htHome != null && htAway != null)
                                              const SizedBox(width: 8),
                                            _ScorePill(
                                              label: 'MS',
                                              value:
                                                  '${m.homeScore}-${m.awayScore}',
                                            ),
                                          ],
                                        ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${m.matchDate.day.toString().padLeft(2, '0')}.${m.matchDate.month.toString().padLeft(2, '0')}.${m.matchDate.year}  ${m.matchDate.hour.toString().padLeft(2, '0')}:${m.matchDate.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (m.status == MatchStatus.live &&
                                          m.minute != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          "CANLI • ${m.minute}'",
                                          style: TextStyle(
                                            color: cs.primary,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _TeamInfo(
                                      name: m.awayTeamName,
                                      logoUrl: awayLogo,
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: TabBar(
                            controller: _tabController,
                            labelColor: cs.primary,
                            unselectedLabelColor: cs.onSurfaceVariant,
                            indicatorColor: cs.primary,
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                            tabs: const [
                              Tab(text: 'Olaylar'),
                              Tab(text: 'Kadrolar'),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _EventsTab(
                              match: m,
                              events: events,
                              isAdmin: isAdmin,
                            ),
                            _LineupsTab(
                              match: m,
                              isAdmin: isAdmin,
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
      },
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}

class _LineupsTab extends StatelessWidget {
  const _LineupsTab({required this.match, required this.isAdmin});

  final MatchModel match;
  final bool isAdmin;

  Future<void> _openLineupSheet(
    BuildContext context, {
    required bool isStarting,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: Text('Ev Sahibi • ${match.homeTeamName}'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminMatchLineupScreen(
                        match: match,
                        isHome: true,
                        initialTabIndex: isStarting ? 0 : 1,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.flight_takeoff_outlined),
                title: Text('Deplasman • ${match.awayTeamName}'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminMatchLineupScreen(
                        match: match,
                        isHome: false,
                        initialTabIndex: isStarting ? 0 : 1,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _playerRow(LineupPlayer p, ColorScheme cs) {
    final n = (p.number ?? '').trim();
    final number = n.isEmpty ? '-' : n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                number,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              p.name,
              textAlign: TextAlign.left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(BuildContext context, List<LineupPlayer> players) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: players.isEmpty
          ? Text('-', style: TextStyle(color: cs.onSurfaceVariant))
          : Column(children: [for (final p in players) _playerRow(p, cs)]),
    );
  }

  Widget _sectionTitle(
    BuildContext context,
    String text, {
    required bool isStarting,
    required bool hasAnyData,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
      child: SizedBox(
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              text,
              style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900),
            ),
            if (isAdmin && hasAnyData)
              Positioned(
                right: 0,
                child: IconButton(
                  tooltip: 'Düzenle',
                  onPressed: () => _openLineupSheet(
                    context,
                    isStarting: isStarting,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = match.homeLineup;
    final away = match.awayLineup;
    final homeStarting = home?.starting ?? const <LineupPlayer>[];
    final awayStarting = away?.starting ?? const <LineupPlayer>[];
    final homeSubs = home?.subs ?? const <LineupPlayer>[];
    final awaySubs = away?.subs ?? const <LineupPlayer>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (home == null && away == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Kadro henüz girilmedi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle(
                  context,
                  'İlk 11',
                  isStarting: true,
                  hasAnyData: homeStarting.isNotEmpty || awayStarting.isNotEmpty,
                ),
                if (isAdmin && homeStarting.isEmpty && awayStarting.isEmpty)
                  Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: IconButton(
                        tooltip: 'İlk 11 ekle',
                        onPressed: () => _openLineupSheet(
                          context,
                          isStarting: true,
                        ),
                        icon: Icon(
                          Icons.add,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  ),
                if (isAdmin && homeStarting.isEmpty && awayStarting.isEmpty)
                  const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _box(context, homeStarting)),
                    const SizedBox(width: 12),
                    Expanded(child: _box(context, awayStarting)),
                  ],
                ),
                const SizedBox(height: 6),
                _sectionTitle(
                  context,
                  'Yedekler',
                  isStarting: false,
                  hasAnyData: homeSubs.isNotEmpty || awaySubs.isNotEmpty,
                ),
                if (isAdmin && homeSubs.isEmpty && awaySubs.isEmpty)
                  Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: IconButton(
                        tooltip: 'Yedek ekle',
                        onPressed: () => _openLineupSheet(
                          context,
                          isStarting: false,
                        ),
                        icon: Icon(
                          Icons.add,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  ),
                if (isAdmin && homeSubs.isEmpty && awaySubs.isEmpty)
                  const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _box(context, homeSubs)),
                    const SizedBox(width: 12),
                    Expanded(child: _box(context, awaySubs)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EventsTab extends StatelessWidget {
  const _EventsTab({
    required this.match,
    required this.events,
    required this.isAdmin,
  });

  final MatchModel match;
  final List<MatchEvent> events;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(
        child: Text('Henüz kaydedilmiş bir olay (gol/kart) yok.'),
      );
    }

    final runningScores = <String?>[];
    var home = 0;
    var away = 0;
    for (final e in events) {
      if (e.type == 'goal') {
        final scoringTeamId = e.isOwnGoal
            ? (e.teamId == match.homeTeamId ? match.awayTeamId : match.homeTeamId)
            : e.teamId;
        if (scoringTeamId == match.homeTeamId) home += 1;
        if (scoringTeamId == match.awayTeamId) away += 1;
        runningScores.add('$home-$away');
      } else {
        runningScores.add(null);
      }
    }

    final dbService = DatabaseService();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: events.length,
      separatorBuilder: (context, index) =>
          Divider(color: Colors.grey.shade300, height: 1),
      itemBuilder: (context, index) {
        final event = events[index];
        final isHome = event.teamId == match.homeTeamId;
        final isSecondYellow = event.type == 'yellow_card'
            ? events
                    .take(index)
                    .where(
                      (e) =>
                          e.type == 'yellow_card' &&
                          e.teamId == event.teamId &&
                          e.playerName == event.playerName,
                    )
                    .length >=
                1
            : false;
        final row = _TimelineRow(
          isHome: isHome,
          minute: event.minute,
          type: event.type,
          playerName: event.playerName,
          assistPlayerName: event.assistPlayerName,
          subInPlayerName: event.subInPlayerName,
          isSecondYellow: isSecondYellow,
          runningScore: runningScores[index],
          isOwnGoal: event.isOwnGoal,
        );

        if (!isAdmin) return row;

        return InkWell(
          onLongPress: () async {
            final confirmed = await showModalBottomSheet<bool>(
              context: context,
              showDragHandle: true,
              builder: (context) {
                return SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: const Text('Olayı Sil'),
                        onTap: () => Navigator.pop(context, true),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                );
              },
            );
            if (confirmed != true) return;
            try {
              await dbService.deleteMatchEvent(event);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Olay silindi.'),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Silme hatası: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: row,
        );
      },
    );
  }
}

class _TeamInfo extends StatelessWidget {
  final String name;
  final String logoUrl;
  final TextAlign textAlign;
  const _TeamInfo({
    required this.name,
    required this.logoUrl,
    required this.textAlign,
  });

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
    return Column(
      crossAxisAlignment: textAlign == TextAlign.right
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primary.withValues(alpha: 0.10),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: ClipOval(
            child: url.isNotEmpty
                ? Image.network(
                    url,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(Icons.sports_soccer, size: 26, color: cs.primary),
                  )
                : Icon(Icons.sports_soccer, size: 26, color: cs.primary),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          textAlign: textAlign,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.isHome,
    required this.minute,
    required this.type,
    required this.playerName,
    required this.assistPlayerName,
    required this.isSecondYellow,
    this.runningScore,
    required this.isOwnGoal,
    required this.subInPlayerName,
  });
  final bool isHome;
  final int minute;
  final String type;
  final String playerName;
  final String? assistPlayerName;
  final bool isSecondYellow;
  final String? runningScore;
  final bool isOwnGoal;
  final String? subInPlayerName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = _eventIcon(
      type,
      isSecondYellow: isSecondYellow,
      isOwnGoal: isOwnGoal,
    );

    final assist = (assistPlayerName ?? '').trim();
    final isGoal = type == 'goal';
    final isSub = type == 'substitution';
    final titleText = _shortenName(playerName);
    final assistText = _shortenName(assist);
    final inName = _shortenName((subInPlayerName ?? '').trim());

    Widget content;
    if (isSub) {
      content = Column(
        crossAxisAlignment:
            isHome ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: isHome
                ? [
                    Flexible(
                      child: Text(
                        inName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: Color(0xFF2E7D32),
                    ),
                  ]
                : [
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: Color(0xFF2E7D32),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        inName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: isHome
                ? [
                    Flexible(
                      child: Text(
                        titleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.arrow_back_rounded,
                      size: 18,
                      color: Colors.red,
                    ),
                  ]
                : [
                    const Icon(
                      Icons.arrow_back_rounded,
                      size: 18,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        titleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
          ),
        ],
      );
    } else {
      final playerLine = Text(
        isGoal && isOwnGoal ? '$titleText (KK)' : titleText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isGoal ? FontWeight.w900 : FontWeight.w800,
          fontSize: isGoal ? 14 : 13,
        ),
      );
      final assistLine = (isGoal && assistText.isNotEmpty)
          ? Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                assistText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null;

      content = Column(
        crossAxisAlignment:
            isHome ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          playerLine,
          if (assistLine != null) assistLine,
        ],
      );
    }

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isHome ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (runningScore != null)
            SizedBox(
              width: 76,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    runningScore!,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          if (runningScore != null) const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: isHome
                ? [
                    Flexible(child: content),
                    const SizedBox(width: 8),
                    icon,
                  ]
                : [
                    icon,
                    const SizedBox(width: 8),
                    Flexible(child: content),
                  ],
          ),
        ],
      ),
    );

    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: isHome ? bubble : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 54,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: Text(
            "$minute'",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: isHome ? const SizedBox.shrink() : bubble,
          ),
        ),
      ],
    );
  }
}
