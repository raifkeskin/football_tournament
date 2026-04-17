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

  final _databaseService = DatabaseService();
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
      body: StreamBuilder<QuerySnapshot>(
        stream: _databaseService.getLeagues(),
        builder: (context, leagueSnapshot) {
          if (!leagueSnapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final isAdmin = AppSession.of(context).value.isAdmin;
          final allLeagues = leagueSnapshot.data!.docs
              .map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return League.fromMap({...data, 'id': doc.id});
              })
              .where((l) => isAdmin || l.isActive)
              .toList();

          if (allLeagues.isEmpty)
            return const Center(child: Text('Henüz aktif turnuva yok.'));

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
              Container(color: cs.primaryContainer, height: 250),

              // 2. KATMAN: ANA LİSTE (OVAL HATLARI OLAN KISIM)
              Column(
                children: [
                  const SizedBox(
                    height: 185,
                  ), // Başlıkların ezilmemesi için ayarlandı
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
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
    );
  }

  Widget _buildMatchList(BuildContext context, League currentLeague) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('teams').snapshots(),
      builder: (context, teamSnapshot) {
        final Map<String, String> logoMap = {};
        if (teamSnapshot.hasData) {
          for (var doc in teamSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            logoMap[doc.id] = data['logoUrl']?.toString() ?? '';
          }
        }

        return StreamBuilder<List<MatchModel>>(
          stream: _databaseService.getMatchesByDate(
            leagueId: _activeLeagueId!,
            date: _selectedDate,
          ),
          builder: (context, matchSnapshot) {
            if (matchSnapshot.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator());

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

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: sectionMap.keys.map((groupId) {
                final String groupLabel = groupId == 'default'
                    ? 'GENEL'
                    : (groupId.toUpperCase().contains('GRUP')
                          ? groupId.toUpperCase()
                          : '$groupId GRUBU');

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              GroupsScreen(initialLeagueId: _activeLeagueId!),
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
                            Text(
                              '${currentLeague.name} - $groupLabel',
                              style: const TextStyle(
                                color: Color(0xFFFBBF24),
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      match.matchTime ?? '--:--',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                    if (match.status == MatchStatus.live)
                      Text(
                        'CANLI',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 40, color: cs.outlineVariant),
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
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${t.day}/${t.month}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
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
