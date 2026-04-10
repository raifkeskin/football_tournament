import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import '../models/league.dart';
import '../models/match.dart';
import '../services/database_service.dart';
import '../services/app_session.dart';
import '../services/in_app_browser.dart';
import 'match_details_screen.dart';
import 'groups_screen.dart';

/// Ana sayfa — günün maçları, tarih şeridi ve maç kartları.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _yaricap = 2; // 2 gün geri, bugün, 2 gün ileri
  static const double _itemWidth = 56.0; // Daha kompakt tarih butonu
  static const double _itemMarginH = 4.0;
  static const double _itemExtent = _itemWidth + (_itemMarginH * 2);

  static const List<String> _haftaKisa = [
    'PZT',
    'SAL',
    'ÇAR',
    'PER',
    'CUM',
    'CMT',
    'PAZ',
  ];

  static const Color _softGreen = Color(0xFF2E7D32);

  final _databaseService = DatabaseService();
  late List<DateTime> _tarihler;
  late final ScrollController _tarihScrollController;
  int _seciliIndeks = _yaricap;
  String? _activeLeagueId;
  bool _didAutoSelectDefaultLeague = false;

  @override
  void initState() {
    super.initState();
    // Bugünün tarihini odak noktası yapalım (Saatleri sıfırla)
    final now = DateTime.now();
    final bugun = DateTime(now.year, now.month, now.day);

    _tarihler = List.generate(
      _yaricap * 2 + 1,
      (i) => bugun.add(Duration(days: i - _yaricap)),
      growable: true,
    );

    _tarihScrollController = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected(isJump: true);
    });
  }

  @override
  void dispose() {
    _tarihScrollController.dispose();
    super.dispose();
  }

  bool _bugunMu(DateTime t) {
    final n = DateTime.now();
    return t.year == n.year && t.month == n.month && t.day == n.day;
  }

  void _tarihSec(int index) {
    setState(() {
      _seciliIndeks = index;
    });
    _scrollToSelected();
  }

  void _scrollToSelected({bool isJump = false}) {
    if (_tarihScrollController.hasClients) {
      final screenWidth = MediaQuery.of(context).size.width;
      final availableWidth = screenWidth - (48 * 3);
      final offset =
          (_seciliIndeks * _itemExtent) -
          (availableWidth / 2) +
          (_itemExtent / 2);
      final maxOffset = _tarihScrollController.position.maxScrollExtent;
      final clamped = offset.clamp(0.0, maxOffset);

      if (isJump) {
        _tarihScrollController.jumpTo(clamped);
      } else {
        _tarihScrollController.animateTo(
          clamped,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _oncekiGun() {
    if (_seciliIndeks > 0) {
      _tarihSec(_seciliIndeks - 1);
    }
  }

  void _sonrakiGun() {
    if (_seciliIndeks < _tarihler.length - 1) {
      _tarihSec(_seciliIndeks + 1);
    }
  }

  DateTime _gunBasinaIndir(DateTime d) => DateTime(d.year, d.month, d.day);

  void _setSelectedDate(DateTime date) {
    final target = _gunBasinaIndir(date);
    final index = _tarihler.indexWhere(
      (t) =>
          t.year == target.year &&
          t.month == target.month &&
          t.day == target.day,
    );
    if (index != -1) {
      _tarihSec(index);
      return;
    }

    setState(() {
      _tarihler.clear();
      _tarihler.addAll(
        List.generate(
          _yaricap * 2 + 1,
          (i) => target.add(Duration(days: i - _yaricap)),
        ),
      );
      _seciliIndeks = _yaricap;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected(isJump: true);
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
          dialogBackgroundColor: cs.surface,
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Günün Maçları',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: _openDatePicker,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _databaseService.getLeagues(),
        builder: (context, leagueSnapshot) {
          if (!leagueSnapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final allLeagues = leagueSnapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return League.fromMap({...data, 'id': doc.id});
          }).toList();

          if (allLeagues.isEmpty)
            return const Center(child: Text('Henüz turnuva eklenmemiş.'));

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
          final selectedLeague = _activeLeagueId == null
              ? null
              : allLeagues.where((l) => l.id == _activeLeagueId).isNotEmpty
              ? allLeagues.firstWhere((l) => l.id == _activeLeagueId)
              : null;

          String turkishKey(String s) {
            return s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 32),
                      onPressed: _oncekiGun,
                      color: _softGreen,
                    ),
                    Expanded(
                      child: _TarihSeridi(
                        tarihler: _tarihler,
                        seciliIndeks: _seciliIndeks,
                        scrollController: _tarihScrollController,
                        bugunMu: _bugunMu,
                        onSec: _tarihSec,
                        vurguRenk: _softGreen,
                        haftaKisa: _haftaKisa,
                        itemWidth: _itemWidth,
                        itemMarginH: _itemMarginH,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 32),
                      onPressed: _sonrakiGun,
                      color: _softGreen,
                    ),
                  ],
                ),
              ),
              _SonDakikaBandi(
                databaseService: _databaseService,
                koyuYesil: _softGreen,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _activeLeagueId,
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(20),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  'Tüm Turnuvalar',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              ...allLeagues.map(
                                (l) => DropdownMenuItem<String?>(
                                  value: l.id,
                                  child: Text(
                                    l.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (val) =>
                                setState(() => _activeLeagueId = val),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if ((selectedLeague?.youtubeUrl ?? '').trim().isNotEmpty)
                        _SocialIcon(
                          icon: Icons.play_circle_filled_rounded,
                          url: selectedLeague?.youtubeUrl,
                          color: Colors.red,
                        ),
                      if ((selectedLeague?.twitterUrl ?? '').trim().isNotEmpty)
                        _SocialIcon(
                          icon: Icons.alternate_email_rounded,
                          url: selectedLeague?.twitterUrl,
                          color: Colors.black,
                        ),
                      if ((selectedLeague?.instagramUrl ?? '').trim().isNotEmpty)
                        _SocialIcon(
                          icon: Icons.camera_alt_rounded,
                          url: selectedLeague?.instagramUrl,
                          color: Colors.purple,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<List<GroupModel>>(
                  stream: _databaseService.getAllGroups(),
                  builder: (context, groupSnapshot) {
                    if (!groupSnapshot.hasData)
                      return const Center(child: CircularProgressIndicator());

                    final groups = groupSnapshot.data ?? [];
                    final leagueById = {for (final l in allLeagues) l.id: l};
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
                            final raw = (data['logoUrl'] ?? data['logo'] ?? '')
                                .toString()
                                .trim();
                            teamLogoById[doc.id] = raw;
                          }
                        }

                        return StreamBuilder<List<MatchModel>>(
                          stream: _databaseService.getMatchesByDate(
                            leagueId: _activeLeagueId,
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
                                  mainAxisAlignment: MainAxisAlignment.center,
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
                                        color: Colors.grey.shade600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final sectionMap = <String, List<MatchModel>>{};
                            final headerLeagueId = <String, String>{};
                            final headerGroupId = <String, String?>{};
                            for (final m in matches) {
                              final leagueName =
                                  leagueById[m.leagueId]?.name ?? 'Turnuva';
                              final groupName = m.groupId == null
                                  ? 'Grup'
                                  : (groupById[m.groupId!]?.name ?? 'Grup');
                              final header = '$leagueName - $groupName';
                              sectionMap.putIfAbsent(header, () => []).add(m);
                              headerLeagueId.putIfAbsent(
                                header,
                                () => m.leagueId,
                              );
                              headerGroupId.putIfAbsent(
                                header,
                                () => m.groupId,
                              );
                            }

                            final headers = sectionMap.keys.toList()
                              ..sort(
                                (a, b) =>
                                    turkishKey(a).compareTo(turkishKey(b)),
                              );
                            final children = <Widget>[];
                            for (final h in headers) {
                              final list = sectionMap[h]!
                                ..sort(
                                  (a, b) => a.matchDate.compareTo(b.matchDate),
                                );
                              children.add(
                                _MacBolumBasligi(
                                  text: h,
                                  onTap: () {
                                    final leagueId = headerLeagueId[h];
                                    if (leagueId == null || leagueId.isEmpty) {
                                      return;
                                    }
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => GroupsScreen(
                                          initialLeagueId: leagueId,
                                          initialGroupId: headerGroupId[h],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                              for (var i = 0; i < list.length; i++) {
                                final m = list[i];
                                final homeLogo =
                                    (m.homeTeamLogoUrl.trim()).isNotEmpty
                                    ? m.homeTeamLogoUrl
                                    : (teamLogoById[m.homeTeamId] ?? '');
                                final awayLogo =
                                    (m.awayTeamLogoUrl.trim()).isNotEmpty
                                    ? m.awayTeamLogoUrl
                                    : (teamLogoById[m.awayTeamId] ?? '');
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
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              children: children,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SocialIcon extends StatelessWidget {
  final IconData icon;
  final String? url;
  final Color color;
  const _SocialIcon({required this.icon, this.url, required this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        icon,
        color: url != null && url!.isNotEmpty ? color : Colors.grey.shade400,
      ),
      onPressed: url != null && url!.isNotEmpty
          ? () async {
              await openInAppBrowser(context, url!);
            }
          : null,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(8),
    );
  }
}

class _SonDakikaBandi extends StatelessWidget {
  const _SonDakikaBandi({
    required this.databaseService,
    required this.koyuYesil,
  });
  final DatabaseService databaseService;
  final Color koyuYesil;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return StreamBuilder<QuerySnapshot>(
      stream: databaseService.getNews(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return const SizedBox.shrink();
        final publishedDocs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final isPublished = data['isPublished'];
          if (isPublished == null) return true;
          if (isPublished is bool) return isPublished;
          return true;
        }).toList();
        if (publishedDocs.isEmpty) return const SizedBox.shrink();

        final newsList = publishedDocs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['content'] as String? ?? '';
        }).toList();
        final marqueeText = newsList.join('  •  ');
        return Container(
          height: 40,
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: koyuYesil,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(9),
                    bottomLeft: Radius.circular(9),
                  ),
                ),
                child: const Center(
                  child: Text(
                    'SON DAKİKA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Marquee(
                  text: marqueeText,
                  style: const TextStyle(fontSize: 13),
                  scrollAxis: Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  blankSpace: 50.0,
                  velocity: 30.0,
                  pauseAfterRound: const Duration(seconds: 1),
                ),
              ),
            ],
          ),
        );
      },
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
        child: url.isNotEmpty
            ? Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.sports_soccer,
                  size: (size * 0.62).clamp(14, 22),
                  color: cs.primary,
                ),
              )
            : Icon(
                Icons.shield_outlined,
                size: (size * 0.62).clamp(14, 22),
                color: cs.primary,
              ),
      ),
    );
  }
}

class _TarihSeridi extends StatelessWidget {
  const _TarihSeridi({
    required this.tarihler,
    required this.seciliIndeks,
    required this.scrollController,
    required this.bugunMu,
    required this.onSec,
    required this.vurguRenk,
    required this.haftaKisa,
    required this.itemWidth,
    required this.itemMarginH,
  });
  final List<DateTime> tarihler;
  final int seciliIndeks;
  final ScrollController scrollController;
  final bool Function(DateTime) bugunMu;
  final void Function(int) onSec;
  final Color vurguRenk;
  final List<String> haftaKisa;
  final double itemWidth;
  final double itemMarginH;

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: ListView.builder(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: tarihler.length,
        itemBuilder: (context, index) {
          final t = tarihler[index];
          final secili = index == seciliIndeks;
          final isToday = bugunMu(t);
          final gun = haftaKisa[t.weekday - 1];
          final tarih = '${_two(t.day)}/${_two(t.month)}';
          return GestureDetector(
            onTap: () => onSec(index),
            child: Container(
              width: itemWidth,
              margin: EdgeInsets.symmetric(
                horizontal: itemMarginH,
                vertical: 8,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: secili ? vurguRenk : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: secili
                        ? vurguRenk
                        : isToday
                        ? vurguRenk.withOpacity(0.55)
                        : Colors.grey.shade300,
                    width: secili ? 1.6 : 1,
                  ),
                  boxShadow: secili
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.10),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        style: TextStyle(
                          fontSize: secili ? 13 : 11,
                          fontWeight: secili
                              ? FontWeight.w900
                              : FontWeight.w800,
                          letterSpacing: 0.4,
                          color: secili ? Colors.white : Colors.black87,
                        ),
                        child: Text(gun),
                      ),
                      const SizedBox(height: 2),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        style: TextStyle(
                          fontSize: secili ? 12 : 10,
                          fontWeight: secili
                              ? FontWeight.w800
                              : FontWeight.w700,
                          letterSpacing: 0.2,
                          color: secili
                              ? Colors.white.withOpacity(0.95)
                              : Colors.black54,
                        ),
                        child: Text(tarih),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MacBolumBasligi extends StatelessWidget {
  const _MacBolumBasligi({required this.text, this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1B5E20),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _TakimAdiYazi extends StatelessWidget {
  const _TakimAdiYazi({required this.text, required this.textAlign});
  final String text;
  final TextAlign textAlign;

  String _clean(String s) {
    final cleaned = s
        .replaceAll(RegExp(r'[\u00AD\u200B\u2060]'), '')
        .replaceAll('\u00A0', ' ')
        .trim();
    return cleaned.replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = const TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 12,
      height: 1.08,
    );
    final textDirection = Directionality.of(context);
    final cleaned = _clean(text);
    final pretty = _prettyBreak(cleaned);

    return LayoutBuilder(
      builder: (context, constraints) {
        double fontSize = 12;
        const minFontSize = 9.0;
        const step = 0.5;

        bool fits(double fs) {
          final painter = TextPainter(
            text: TextSpan(
              text: pretty,
              style: baseStyle.copyWith(fontSize: fs),
            ),
            textAlign: textAlign,
            textDirection: textDirection,
            maxLines: 2,
            ellipsis: '…',
          )..layout(maxWidth: constraints.maxWidth);
          return !painter.didExceedMaxLines;
        }

        while (fontSize > minFontSize && !fits(fontSize)) {
          fontSize -= step;
        }

        return Text(
          pretty,
          textAlign: textAlign,
          maxLines: 2,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: baseStyle.copyWith(fontSize: fontSize),
        );
      },
    );
  }

  String _prettyBreak(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.length <= 1) return s.trim();
    return '${parts.first}\n${parts.sublist(1).join(' ')}';
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

  String _two(int n) => n.toString().padLeft(2, '0');

  String get _timeText =>
      '${_two(match.matchDate.hour)}:${_two(match.matchDate.minute)}';

  String get _statusText {
    if (match.status == MatchStatus.finished) return 'MS';
    if (match.status == MatchStatus.live)
      return match.minute == null ? 'CANLI' : "${match.minute}'";
    return 'Oynanmadı';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAdmin = AppSession.of(context).value.isAdmin;
    final showScore =
        match.status != MatchStatus.notStarted || match.homeScore != 0 || match.awayScore != 0;
    final homeScoreText = showScore ? '${match.homeScore}' : '-';
    final awayScoreText = showScore ? '${match.awayScore}' : '-';
    final youtubeUrl = (match.youtubeUrl ?? '').trim();
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _timeText,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusText,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _KucukLogo(logoUrl: homeLogoUrlOverride, size: 24),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TakimAdiYazi(
                            text: match.homeTeamName,
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _KucukLogo(logoUrl: awayLogoUrlOverride, size: 24),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TakimAdiYazi(
                            text: match.awayTeamName,
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 40,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      homeScoreText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      awayScoreText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              if (youtubeUrl.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => openInAppBrowser(context, youtubeUrl),
                  icon: const Icon(
                    Icons.play_circle_filled_rounded,
                    color: Colors.red,
                  ),
                  tooltip: 'YouTube',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
