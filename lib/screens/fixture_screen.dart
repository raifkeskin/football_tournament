import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/league.dart';
import '../models/match.dart';
import '../services/database_service.dart';
import '../services/app_session.dart';
import '../widgets/web_safe_image.dart';
import 'match_details_screen.dart';

class FixtureScreen extends StatefulWidget {
  const FixtureScreen({super.key});

  @override
  State<FixtureScreen> createState() => _FixtureScreenState();
}

class _FixtureScreenState extends State<FixtureScreen> {
  final _db = DatabaseService();
  String? _leagueId;
  String? _groupId;
  int? _week;

  DateTime? _parseYyyyMmDd(String yyyyMmDd) {
    final s = yyyyMmDd.trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final y = int.tryParse(m.group(1) ?? '');
    final mo = int.tryParse(m.group(2) ?? '');
    final d = int.tryParse(m.group(3) ?? '');
    if (y == null || mo == null || d == null) return null;
    return DateTime(y, mo, d);
  }

  String _dateStripText(String yyyyMmDd) {
    final s = yyyyMmDd.trim();
    final dt = _parseYyyyMmDd(s);
    if (dt == null) return s;
    return DateFormat('dd.MM.yyyy EEEE', 'tr_TR').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = AppSession.of(context).value.isAdmin;

    const headerForest = Color(0xFF064E3B);
    const bgDark = Color(0xFF0F172A);
    const cardBg = Color(0xFF1E293B);
    const outline = Color(0xFF334155);

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.calendar_month_outlined),
            SizedBox(width: 8),
            Text('Fikstür'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('teams').snapshots(),
        builder: (context, teamsSnap) {
          final teamLogoById = <String, String>{};
          if (teamsSnap.hasData) {
            for (final doc in teamsSnap.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              teamLogoById[doc.id] = data['logoUrl']?.toString() ?? '';
            }
          }

          return StreamBuilder<QuerySnapshot>(
            stream: _db.getLeagues(),
            builder: (context, leaguesSnap) {
              if (!leaguesSnap.hasData)
                return const Center(child: CircularProgressIndicator());

              final leagues =
                  leaguesSnap.data!.docs
                      .map(
                        (d) => League.fromMap({
                          ...d.data() as Map<String, dynamic>,
                          'id': d.id,
                        }),
                      )
                      .toList()
                    ..sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    );

              if (leagues.isEmpty)
                return const Center(child: Text('Turnuva bulunamadı.'));

              _leagueId ??= leagues.any((l) => l.isDefault)
                  ? (leagues.where((l) => l.isDefault).first.id)
                  : leagues.first.id;

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('groups')
                    .where('tournamentId', isEqualTo: _leagueId)
                    .snapshots(),
                builder: (context, snapshot) {
                  final groups = snapshot.hasData
                      ? snapshot.data!.docs
                            .map(
                              (doc) =>
                                  (doc.data() as Map<String, dynamic>)['name']
                                      ?.toString() ??
                                  doc.id,
                            )
                            .toList()
                      : <String>[];

                  final selectedGroupId = (groups.contains(_groupId))
                      ? _groupId
                      : null;
                  final groupNameById = {for (final g in groups) g: g};

                  return FutureBuilder<int?>(
                    key: ValueKey('$_leagueId|$selectedGroupId'),
                    future: _db.getFixtureMaxWeek(
                      _leagueId!,
                      groupId: selectedGroupId,
                    ),
                    builder: (context, maxWeekSnap) {
                      final maxWeek = maxWeekSnap.data ?? 30;
                      final weeks = <int>[for (var i = 1; i <= maxWeek; i++) i];

                      if (_week == null && maxWeek > 0) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _week = 1);
                        });
                      }

                      return StreamBuilder<List<MatchModel>>(
                        stream: _week == null
                            ? Stream.empty()
                            : _db.watchFixtureMatches(
                                _leagueId!,
                                _week!,
                                groupId: selectedGroupId,
                              ),
                        builder: (context, matchesSnap) {
                          if (matchesSnap.connectionState ==
                              ConnectionState.waiting)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );

                          final matches = (matchesSnap.data ?? [])
                            ..sort(
                              (a, b) => (a.matchDate ?? '').compareTo(
                                b.matchDate ?? '',
                              ),
                            );

                          return Column(
                            children: [
                              Container(
                                color: headerForest,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  16,
                                  32,
                                ),
                                child: Column(
                                  children: [
                                    _buildDropdown(
                                      'Turnuva Seçin',
                                      _leagueId,
                                      leagues
                                          .map(
                                            (l) => DropdownMenuItem(
                                              value: l.id,
                                              child: Text(l.name),
                                            ),
                                          )
                                          .toList(),
                                      (v) => setState(() {
                                        _leagueId = v;
                                        _groupId = null;
                                        _week = null;
                                      }),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildDropdown(
                                            'Grup Seçin',
                                            selectedGroupId,
                                            [
                                              const DropdownMenuItem(
                                                value: null,
                                                child: Text('Tümü'),
                                              ),
                                              ...groups.map(
                                                (g) => DropdownMenuItem(
                                                  value: g,
                                                  child: Text(
                                                    g.toLowerCase().contains(
                                                          'grup',
                                                        )
                                                        ? g
                                                        : '$g Grubu',
                                                  ),
                                                ),
                                              ),
                                            ],
                                            (v) => setState(() => _groupId = v),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildDropdown(
                                            'Hafta Seçin',
                                            _week,
                                            weeks
                                                .map(
                                                  (w) => DropdownMenuItem(
                                                    value: w,
                                                    child: Text('$w. Hafta'),
                                                  ),
                                                )
                                                .toList(),
                                            (v) => setState(() => _week = v),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Transform.translate(
                                  offset: const Offset(0, -24),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: bgDark,
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(24),
                                      ),
                                    ),
                                    padding: const EdgeInsets.only(top: 18),
                                    child: matches.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'Maç bulunamadı.',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          )
                                        : _FixtureList(
                                            matches: matches,
                                            dateStripText: _dateStripText,
                                            groupNameById: groupNameById,
                                            showGroupInHeader:
                                                selectedGroupId == null,
                                            teamLogoById: teamLogoById,
                                            isAdmin: isAdmin,
                                            onMatchTap: (m) => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    MatchDetailsScreen(
                                                      match: m,
                                                    ),
                                              ),
                                            ),
                                            cardColor: cardBg,
                                            outlineColor: outline,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    dynamic value,
    List<DropdownMenuItem<dynamic>> items,
    Function(dynamic) onChanged,
  ) {
    return DropdownButtonFormField(
      value: value,
      isExpanded: true,
      dropdownColor: const Color(0xFF1E293B),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _FixtureList extends StatelessWidget {
  const _FixtureList({
    required this.matches,
    required this.dateStripText,
    required this.groupNameById,
    required this.showGroupInHeader,
    required this.teamLogoById,
    required this.onMatchTap,
    required this.cardColor,
    required this.outlineColor,
    required this.isAdmin,
  });

  final List<MatchModel> matches;
  final String Function(String yyyyMmDd) dateStripText;
  final Map<String, String> groupNameById;
  final bool showGroupInHeader;
  final Map<String, String> teamLogoById;
  final void Function(MatchModel match) onMatchTap;
  final Color cardColor;
  final Color outlineColor;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    String groupLabel(String groupId) {
      final name = groupNameById[groupId] ?? 'Grup';
      return name.toLowerCase().contains('grup') ? name : '$name Grubu';
    }

    final bySection = <String, List<MatchModel>>{};
    for (final m in matches) {
      final dateKey = (m.matchDate ?? '').trim().isEmpty
          ? '__NO_DATE__'
          : m.matchDate!.trim();
      final sectionKey = showGroupInHeader
          ? '$dateKey|${m.groupId ?? ''}'
          : dateKey;
      (bySection[sectionKey] ??= []).add(m);
    }

    final sectionKeys = bySection.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        for (final k in sectionKeys)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: outlineColor.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  () {
                    final parts = k.split('|');
                    final dateText = parts[0] == '__NO_DATE__'
                        ? 'Tarih Belirlenmedi'
                        : dateStripText(parts[0]);
                    return showGroupInHeader
                        ? '$dateText - ${groupLabel(parts.length > 1 ? parts[1] : '')}'
                        : dateText;
                  }(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                for (final m in bySection[k]!)
                  _MatchCard(
                    match: m,
                    teamLogoById: teamLogoById,
                    isAdmin: isAdmin,
                    onTap: () => onMatchTap(m),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.teamLogoById,
    required this.onTap,
    required this.isAdmin,
  });

  final MatchModel match;
  final Map<String, String> teamLogoById;
  final VoidCallback onTap;
  final bool isAdmin;

  Widget _logo(String url) {
    return SizedBox(
      width: 28,
      height: 28,
      child: WebSafeImage(
        url: url,
        width: 28,
        height: 28,
        isCircle: true,
        fallbackIconSize: 18,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFinished = match.status == MatchStatus.finished;
    final timeText = (match.matchTime ?? '').trim();
    final leftText = isFinished
        ? 'MS'
        : (timeText.isEmpty ? '--:--' : timeText);

    const fg = Color(0xFFF8FAFC);
    const mid = Color(0xFF94A3B8);
    const accent = Color(0xFF10B981);

    final homeLogo = match.homeTeamLogoUrl.trim().isNotEmpty
        ? match.homeTeamLogoUrl
        : (teamLogoById[match.homeTeamId] ?? '');
    final awayLogo = match.awayTeamLogoUrl.trim().isNotEmpty
        ? match.awayTeamLogoUrl
        : (teamLogoById[match.awayTeamId] ?? '');

    final hs = match.homeScore;
    final as = match.awayScore;
    final showScore = isFinished || hs != 0 || as != 0;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              // SAAT VE TAKVİM İKONU ALANI - DİKEY DÜZENLEME YAPILDI
              SizedBox(
                width: 50,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isAdmin)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          Icons.edit_calendar,
                          size: 22,
                          color: Colors.white, // İKON RENGİ BEYAZ YAPILDI
                        ),
                        onPressed: () => _showEditPopup(context),
                      ),
                    const SizedBox(height: 4), // İkon ve saat arasına boşluk
                    Text(
                      leftText,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: isFinished ? accent : mid,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _teamRow(
                      match.homeTeamName,
                      homeLogo,
                      hs,
                      showScore,
                      hs >= as,
                    ),
                    const SizedBox(height: 12),
                    _teamRow(
                      match.awayTeamName,
                      awayLogo,
                      as,
                      showScore,
                      as >= hs,
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

  Widget _teamRow(
    String name,
    String logo,
    int score,
    bool showScore,
    bool highlight,
  ) {
    return Row(
      children: [
        _logo(logo),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: highlight ? Colors.white : Colors.white70,
              fontSize: 13,
            ),
          ),
        ),
        SizedBox(
          width: 25,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              showScore ? '$score' : '-',
              style: TextStyle(
                color: highlight ? Colors.white : Colors.white38,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
void _showEditPopup(BuildContext context) async {
    // 1. TARİHİ DD/MM/YYYY FORMATINA ÇEVİREREK AÇ (DB: 2026-04-18 -> Ekran: 18/04/2026)
    String initialDate = '';
    if (match.matchDate != null && match.matchDate!.contains('-')) {
      final p = match.matchDate!.split('-');
      if (p.length == 3) initialDate = '${p[2]}/${p[1]}/${p[0]}';
    } else {
      initialDate = match.matchDate ?? '';
    }

    final dCtrl = TextEditingController(text: initialDate);
    final tCtrl = TextEditingController(text: match.matchTime ?? '');
    String? selectedPitch = match.pitchName;

    final pitchesSnap = await FirebaseFirestore.instance.collection('pitches').get();
    final pitches = pitchesSnap.docs.map((d) => (d.data() as Map<String, dynamic>)['name'] as String).toList();

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Maçı Düzenle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView( // Klavye açıldığında taşmaması için
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // TARİH INPUT (Maskeleme yapıldı)
                TextField(
                  controller: dCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _DateInputFormatter(), // Özel tarih maskesi
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Tarih (GG/AA/YYYY)',
                    hintText: '18/04/2026',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  ),
                ),
                const SizedBox(height: 20), // Üst üste binmeyi engelleyen boşluk
                // SAAT INPUT (Maskeleme yapıldı)
                TextField(
                  controller: tCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _TimeInputFormatter(), // Özel saat maskesi (Otomatik :)
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Saat (SS:DD)',
                    hintText: '20:00',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  ),
                ),
                const SizedBox(height: 25),
                DropdownButtonFormField<String>(
                  value: pitches.contains(selectedPitch) ? selectedPitch : null,
                  dropdownColor: const Color(0xFF0F172A),
                  decoration: const InputDecoration(
                    labelText: 'Stad Seçin',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  ),
                  items: pitches.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(color: Colors.white)))).toList(),
                  onChanged: (val) => setDialogState(() => selectedPitch = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('İptal', style: TextStyle(color: Colors.white70))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              onPressed: () async {
                final date = dCtrl.text;
                final time = tCtrl.text;

                // 2. DOĞRULAMA (VALIDATION)
                if (date.length != 10) {
                  _showError(context, 'Tarih formatı hatalı! (GG/AA/YYYY)');
                  return;
                }
                if (time.length != 5) {
                  _showError(context, 'Saat formatı hatalı! (SS:DD)');
                  return;
                }

                try {
                  // 3. DB FORMATINA ÇEVİR (18/04/2026 -> 2026-04-18)
                  final parts = date.split('/');
                  final dbDate = '${parts[2]}-${parts[1]}-${parts[0]}';

                  await FirebaseFirestore.instance.collection('matches').doc(match.id).update({
                    'matchDate': dbDate,
                    'matchTime': time,
                    'pitchName': selectedPitch,
                  });
                  Navigator.pop(c);
                  _showSuccess(context, 'Maç güncellendi!');
                } catch (e) {
                  _showError(context, 'Güncelleme başarısız oldu.');
                }
              },
              child: const Text('Güncelle', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // Yardımcı Uyarı Metotları
  void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }
  void _showSuccess(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }
}

// --- OTOMATİK FORMATLAYICILAR (DOSYANIN EN ALTINA EKLEYEBİLİRSİN) ---

class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldV, TextEditingValue newV) {
    var text = newV.text;
    if (newV.selection.baseOffset < oldV.selection.baseOffset) return newV;
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 2 == 0 && nonZeroIndex != text.length && nonZeroIndex < 5) buffer.write('/');
    }
    var string = buffer.toString();
    return newV.copyWith(text: string, selection: TextSelection.collapsed(offset: string.length));
  }
}

class _TimeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldV, TextEditingValue newV) {
    var text = newV.text;
    if (newV.selection.baseOffset < oldV.selection.baseOffset) return newV;
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex == 2 && nonZeroIndex != text.length) buffer.write(':');
    }
    var string = buffer.toString();
    return newV.copyWith(text: string, selection: TextSelection.collapsed(offset: string.length));
  }
}

}
