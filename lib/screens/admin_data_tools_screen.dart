import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/fixture_import.dart';
import '../models/league.dart';
import '../services/app_session.dart';
import '../services/database_service.dart';
import '../services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../services/service_locator.dart';
import '../utils/string_utils.dart';

class AdminDataToolsScreen extends StatefulWidget {
  const AdminDataToolsScreen({super.key});

  @override
  State<AdminDataToolsScreen> createState() => _AdminDataToolsScreenState();
}

class _AdminDataToolsScreenState extends State<AdminDataToolsScreen> {
  final _db = DatabaseService();
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  bool _busy = false;
  String? _lastResult;

  Future<void> _exportFirestoreBackup() async {
    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      final collections = <String>[
        'admins',
        'users',
        'players',
        'teams',
        'leagues',
        'groups',
        'matches',
        'news',
        'penalties',
        'pending_actions',
        'pitches',
        'otp_requests',
      ];

      final backup = await _leagueService.buildFirestoreBackup(
        collections: collections,
      );

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/firestore_backup_$ts.json');
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(backup), flush: true);
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Firestore JSON Yedeği');

      if (!mounted) return;
      setState(() {
        _lastResult = 'Yedek oluşturuldu: ${file.path}';
      });
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(e);
      setState(() {
        _lastResult = 'Yedekleme hatası: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDelete(String category) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dikkat'),
        content: Text(
          'Tüm $category verilerini silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Evet'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _showSuccessSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Veriler başarıyla temizlendi')),
    );
  }

  void _showErrorSnackBar(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Hata: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _runDelete({
    required String category,
    required Future<int> Function() action,
  }) async {
    final ok = await _confirmDelete(category);
    if (!ok) return;

    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      final deleted = await action();
      if (!mounted) return;
      _showSuccessSnackBar();
      setState(() {
        _lastResult = 'Silinen toplam kayıt: $deleted';
      });
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(e);
      setState(() {
        _lastResult = 'Hata: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearTeams() async {
    await _runDelete(category: 'Takım', action: _db.deleteAllTeams);
  }

  Future<void> _clearFixtures() async {
    await _runDelete(
      category: 'Fikstür',
      action: _db.deleteAllMatchesAndEvents,
    );
  }

  Future<void> _clearPlayers() async {
    await _runDelete(category: 'Futbolcu', action: _db.deleteAllPlayers);
  }

  Future<void> _migrateMatchTimesFromTimestamp() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dikkat'),
        content: const Text(
          "matches koleksiyonundaki 'time' alanı Timestamp olan kayıtlar, matchDate/matchTime alanlarına dönüştürülecek. time/dateString alanları silinecek.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Başlat'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      final result = await _db.migrateMatchesTimeTimestampToMatchFields();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Migrasyon tamamlandı')));
      setState(() {
        _lastResult =
            "Taranan kayıt: ${result['scanned']} • Güncellenen kayıt: ${result['updated']}";
      });
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(e);
      setState(() {
        _lastResult = 'Hata: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _normalizeMatchesDocIds() async {
    bool confirmed = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Dikkat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Emin misiniz? Veri yapısı league_week_homeTeam formatına güncellenecektir.',
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: (v) => setDialogState(() => confirmed = v == true),
                title: const Text('Onaylıyorum'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: confirmed ? () => Navigator.pop(context, true) : null,
              child: const Text('Başlat'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _lastResult = null;
    });

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Normalize ediliyor...')),
          ],
        ),
      ),
    );

    try {
      final result = await _db.normalizeMatchesDocIdsByLeagueWeekHomeTeam();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Normalize işlemi tamamlandı')));
      setState(() {
        _lastResult =
            'Taranan: ${result['scanned']} • Atlanan: ${result['skipped']} • Yazılan: ${result['rewritten']} • Silinen: ${result['deleted']} • Birleşen: ${result['merged']} • events taşınan: ${result['eventsMoved']} • match_events güncellenen: ${result['matchEventsUpdated']}';
      });
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showErrorSnackBar(e);
      setState(() {
        _lastResult = 'Hata: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    final dangerColor = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text('Veri Araçları')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: !isAdmin
          ? const Center(child: Text('Bu sayfa sadece adminler içindir.'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const AdminTeamFixtureBuildScreen(),
                              ),
                            );
                          },
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Takım ve Fikstür Oluşturma'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _exportFirestoreBackup,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Firestore JSON Yedek Al'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _clearTeams,
                    icon: Icon(
                      Icons.delete_forever_rounded,
                      color: dangerColor,
                    ),
                    label: const Text('Takım Verilerini Temizle'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _clearFixtures,
                    icon: Icon(
                      Icons.delete_forever_rounded,
                      color: dangerColor,
                    ),
                    label: const Text('Fikstür Verilerini Temizle'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _clearPlayers,
                    icon: Icon(
                      Icons.delete_forever_rounded,
                      color: dangerColor,
                    ),
                    label: const Text('Futbolcu Verilerini Temizle'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _migrateMatchTimesFromTimestamp,
                    icon: const Icon(Icons.sync_alt_rounded),
                    label: const Text('Maç Zaman Migrasyonu'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _normalizeMatchesDocIds,
                    icon: const Icon(Icons.rule_folder_outlined),
                    label: const Text('Lig Bazlı Maç Verilerini Normalize Et'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_busy) const LinearProgressIndicator(),
                  if (_lastResult != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _lastResult!,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _TeamInfo {
  const _TeamInfo({
    required this.id,
    required this.name,
    required this.groupId,
    required this.groupName,
  });

  final String id;
  final String name;
  final String groupId;
  final String groupName;
}

class AdminTeamFixtureBuildScreen extends StatefulWidget {
  const AdminTeamFixtureBuildScreen({super.key});

  @override
  State<AdminTeamFixtureBuildScreen> createState() =>
      _AdminTeamFixtureBuildScreenState();
}

class _AdminTeamFixtureBuildScreenState
    extends State<AdminTeamFixtureBuildScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final IMatchService _matchService = ServiceLocator.matchService;
  bool _busy = false;
  String? _selectedLeagueId;
  PlatformFile? _pickedFile;

  String _norm(String input) {
    return StringUtils.normalizeTrKey(input).replaceAll(' ', '');
  }

  String _cellString(Data? cell) {
    final raw = cell?.value;
    if (raw == null) return '';
    final s = raw.toString().replaceAll('\u0000', '').trim();
    return s;
  }

  String? _findSheetName(Excel excel, List<String> candidates) {
    final wanted = candidates.map(_norm).toSet();
    for (final name in excel.tables.keys) {
      if (wanted.contains(_norm(name))) return name;
    }
    return null;
  }

  int _findColumnIndex(List<String> headers, List<String> candidates) {
    final headerNorm = headers.map(_norm).toList();
    final wanted = candidates.map(_norm).toList();
    for (var i = 0; i < headerNorm.length; i++) {
      final h = headerNorm[i];
      for (final w in wanted) {
        if (h == w || h.contains(w)) return i;
      }
    }
    return -1;
  }

  DateTime? _parseExcelDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is num) {
      final base = DateTime(1899, 12, 30);
      return base.add(Duration(days: value.round()));
    }
    final s = value?.toString().replaceAll('\u0000', '').trim() ?? '';
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    final m = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(s);
    if (m != null) {
      final d = int.tryParse(m.group(1) ?? '');
      final mo = int.tryParse(m.group(2) ?? '');
      final y = int.tryParse(m.group(3) ?? '');
      if (d != null && mo != null && y != null) return DateTime(y, mo, d);
    }
    return null;
  }

  ({int hour, int minute}) _parseTime(dynamic value) {
    if (value is DateTime) return (hour: value.hour, minute: value.minute);
    if (value is num) {
      final totalSeconds = (value * 24 * 60 * 60).round();
      final hour = (totalSeconds ~/ 3600) % 24;
      final minute = (totalSeconds % 3600) ~/ 60;
      return (hour: hour, minute: minute);
    }
    final s = value?.toString().replaceAll('\u0000', '').trim() ?? '';
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
    if (m != null) {
      final h = int.tryParse(m.group(1) ?? '') ?? 0;
      final mi = int.tryParse(m.group(2) ?? '') ?? 0;
      return (hour: h.clamp(0, 23), minute: mi.clamp(0, 59));
    }
    return (hour: 0, minute: 0);
  }

  String _yyyyMmDd(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: false,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    setState(() => _pickedFile = result.files.first);
  }

  void _showSnack(String message, {Color? background}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: background),
    );
  }

  Future<void> _downloadTemplate() async {
    setState(() => _busy = true);
    try {
      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'Takimlar');
      final takimlar = excel['Takimlar'];
      takimlar.appendRow([
        TextCellValue('Takım Adı'),
        TextCellValue('Grup Adı'),
        TextCellValue('Sorumlu Telefon (Opsiyonel)'),
      ]);

      final fikstur = excel['Fikstur'];
      fikstur.appendRow([
        TextCellValue('Hafta'),
        TextCellValue('Ev Sahibi'),
        TextCellValue('Deplasman'),
        TextCellValue('Tarih (GG.AA.YYYY)'),
        TextCellValue('Saat (SS:DD)'),
        TextCellValue('Saha'),
      ]);

      // Excel data validation is limited in the `excel` package currently.
      // We will provide the structure as requested.

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Excel oluşturulamadı.');

      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/Fikstur_Sablonu.xlsx';
        final file = File(path);
        await file.writeAsBytes(bytes);

        if (!mounted) return;
        await Share.shareXFiles([XFile(path)], text: 'Fikstür Şablonu');
      } else {
        final blob = html.Blob([
          bytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute("download", "Fikstur_Sablonu.xlsx")
          ..click();
        html.Url.revokeObjectUrl(url);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Şablon oluşturulurken hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final leagueId = _selectedLeagueId?.trim() ?? '';
    final path = _pickedFile?.path?.trim() ?? '';
    if (leagueId.isEmpty) {
      _showSnack('Lütfen turnuva seçin.');
      return;
    }
    if (path.isEmpty) {
      _showSnack('Lütfen bir Excel (.xlsx) dosyası seçin.');
      return;
    }

    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final book = Excel.decodeBytes(bytes);

      final teamsSheetName = _findSheetName(book, const [
        'Takımlar',
        'Takimlar',
        'Teams',
      ]);
      if (teamsSheetName == null) {
        throw Exception("Excel içinde 'Takımlar' sayfası bulunamadı.");
      }

      final fixtureSheetName = _findSheetName(book, const [
        'Fikstur',
        'Fikstür',
        'Fixtures',
        'Matches',
      ]);
      if (fixtureSheetName == null) {
        throw Exception("Excel içinde 'Fikstur' sayfası bulunamadı.");
      }

      final teamsSheet = book.tables[teamsSheetName]!;
      final fixtureSheet = book.tables[fixtureSheetName]!;

      final teamByNameKey = <String, _TeamInfo>{};

      for (var r = 1; r < teamsSheet.rows.length; r++) {
        final row = teamsSheet.rows[r];
        final name = _cellString(row.isNotEmpty ? row[0] : null);
        final groupName = _cellString(row.length > 1 ? row[1] : null);
        final trimmedName = name.trim();
        if (trimmedName.isEmpty) continue;
        final teamKey = _norm(trimmedName);
        if (teamByNameKey.containsKey(teamKey)) continue;

        final gName = groupName.trim().isEmpty ? 'A' : groupName.trim();
        final groupKey = _norm(gName);

        teamByNameKey[teamKey] = _TeamInfo(
          id: '', // Will populate later
          name: trimmedName,
          groupId:
              groupKey, // Using group name key here temporarily to hold the string, we actually just need the raw string
          groupName: gName,
        );
      }

      if (teamByNameKey.isEmpty) {
        throw Exception('Takımlar sayfasında kayıt bulunamadı.');
      }

      final headerRow = fixtureSheet.rows.isNotEmpty
          ? fixtureSheet.rows.first
          : const <Data?>[];
      final headers = headerRow.map(_cellString).toList();

      var weekIdx = _findColumnIndex(headers, const ['Hafta', 'Week']);
      var homeIdx = _findColumnIndex(headers, const ['Ev Sahibi', 'Home']);
      var awayIdx = _findColumnIndex(headers, const ['Deplasman', 'Away']);
      var dateIdx = _findColumnIndex(headers, const ['Tarih', 'Date']);
      var timeIdx = _findColumnIndex(headers, const ['Saat', 'Time']);
      var pitchIdx = _findColumnIndex(headers, const ['Saha', 'Pitch']);

      if (weekIdx == -1) weekIdx = 0;
      if (homeIdx == -1) homeIdx = 1;
      if (awayIdx == -1) awayIdx = 2;
      if (dateIdx == -1) dateIdx = 3;
      if (timeIdx == -1) timeIdx = 4;
      if (pitchIdx == -1) pitchIdx = 5;

      final matchRows = <FixtureImportMatch>[];
      final unknownTeams = <String>{};

      for (var r = 1; r < fixtureSheet.rows.length; r++) {
        final row = fixtureSheet.rows[r];
        Data? cellAt(int idx) => idx >= 0 && idx < row.length ? row[idx] : null;
        String readAt(int idx) => _cellString(cellAt(idx));

        final weekRaw = readAt(weekIdx);
        final homeName = readAt(homeIdx);
        final awayName = readAt(awayIdx);
        final dateCell = cellAt(dateIdx);
        final timeCell = cellAt(timeIdx);
        final pitchCell = cellAt(pitchIdx);

        if (homeName.trim().isEmpty && awayName.trim().isEmpty) continue;

        final homeKey = _norm(homeName);
        final awayKey = _norm(awayName);
        final homeInfo = teamByNameKey[homeKey];
        final awayInfo = teamByNameKey[awayKey];
        if (homeInfo == null) unknownTeams.add(homeName.trim());
        if (awayInfo == null) unknownTeams.add(awayName.trim());
        if (homeInfo == null || awayInfo == null) continue;

        int week = 0;
        final weekNum = int.tryParse(weekRaw.trim());
        if (weekNum != null) week = weekNum;

        final dateText = _cellString(dateCell);
        final timeText = _cellString(timeCell);
        final pitchText = _cellString(pitchCell);

        final datePart = dateText.isEmpty
            ? null
            : _parseExcelDate(dateCell?.value ?? dateText);
        final hasTime = timeText.isNotEmpty;
        final t = hasTime ? _parseTime(timeCell?.value ?? timeText) : null;

        final dt = datePart == null
            ? null
            : DateTime(
                datePart.year,
                datePart.month,
                datePart.day,
                t?.hour ?? 0,
                t?.minute ?? 0,
              );
        final timeFormatted = hasTime && t != null
            ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
            : null;

        matchRows.add(
          FixtureImportMatch(
            week: week,
            groupId: homeInfo.groupName,
            homeTeamName: homeInfo.name,
            awayTeamName: awayInfo.name,
            matchDateYyyyMmDd: dt == null ? null : _yyyyMmDd(dt),
            matchTime: timeFormatted,
            pitchName: pitchText.isEmpty ? null : pitchText,
          ),
        );
      }

      if (unknownTeams.isNotEmpty) {
        throw Exception(
          'Fikstür sayfasında bulunamayan takım(lar): ${unknownTeams.take(5).join(', ')}',
        );
      }

      final teams =
          teamByNameKey.values
              .map((t) => FixtureImportTeam(name: t.name, groupName: t.groupName))
              .toList();
      await _matchService.importTeamsAndFixture(
        tournamentId: leagueId,
        teams: teams,
        matches: matchRows,
      );

      if (!mounted) return;
      _showSnack(
        'Takımlar ve Fikstür başarıyla oluşturuldu',
        background: Theme.of(context).colorScheme.primary,
      );
      setState(() {
        _pickedFile = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Takım ve Fikstür Oluşturma')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StreamBuilder<List<League>>(
                stream: _leagueService.watchLeagues(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final leagues = snapshot.data ?? const <League>[];

                  if (leagues.isEmpty) {
                    return const Text('Turnuva bulunamadı.');
                  }
                  _selectedLeagueId ??= leagues.first.id;
                  return DropdownButtonFormField<String>(
                    key: ValueKey(_selectedLeagueId),
                    initialValue: _selectedLeagueId,
                    decoration: const InputDecoration(
                      labelText: 'Turnuva Seçimi',
                    ),
                    items: [
                      for (final l in leagues)
                        DropdownMenuItem(value: l.id, child: Text(l.name)),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _selectedLeagueId = v),
                  );
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _downloadTemplate,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Şablon İndir'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _pickFile,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Şablon Yükle (.xlsx)'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
              if (_pickedFile != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Seçilen dosya: ${_pickedFile!.name}',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _create,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
                child: const Text('OLUŞTUR'),
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: cs.surface.withValues(alpha: 0.55),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
