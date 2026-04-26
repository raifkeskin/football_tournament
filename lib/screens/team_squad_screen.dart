import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import '../models/league.dart';
import '../models/match.dart';
import '../services/approval_service.dart';
import '../services/app_session.dart';
import '../services/image_upload_service.dart';
import '../services/interfaces/i_team_service.dart';
import '../services/service_locator.dart';
import '../widgets/web_safe_image.dart';

class TeamSquadScreen extends StatefulWidget {
  final String teamId;
  final String tournamentId;
  final String teamName;
  final String teamLogoUrl;

  const TeamSquadScreen({
    super.key,
    required this.teamId,
    required this.tournamentId,
    required this.teamName,
    required this.teamLogoUrl,
  });

  @override
  State<TeamSquadScreen> createState() => _TeamSquadScreenState();
}

class _TeamSquadScreenState extends State<TeamSquadScreen> {
  final _approvalService = ApprovalService();
  final ITeamService _teamService = ServiceLocator.teamService;

  final _rosterSearchController = TextEditingController();
  String _rosterQuery = '';

  final Map<String, String> _playerPhotoUrlByPhone = {};
  final Set<String> _playerPhotoFetchInFlight = {};

  bool _isTeamManager = false;
  bool _isLoadingTournaments = true;
  List<League> _teamTournaments = [];
  String? _selectedTournamentId;

  Future<void> _deleteRosterPlayer({
    required String tournamentId,
    required String teamId,
    required String playerPhone,
  }) async {
    await _teamService.deleteRosterEntry(
      tournamentId: tournamentId,
      teamId: teamId,
      playerPhone: playerPhone,
    );
  }

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  String _displayPosition(PlayerModel p) {
    final main = (p.mainPosition ?? '').trim();
    final sub = (p.position ?? '').trim();
    if (sub.isNotEmpty) {
      switch (sub) {
        case 'GK':
          return 'Kaleci';
        case 'DEF':
          return 'Defans';
        case 'ORT':
          return 'Orta Saha';
        case 'FOR':
          return 'Forvet';
      }
      return sub;
    }
    if (main.isNotEmpty) return main;
    return '-';
  }

  String _tournamentNameById(String tournamentId) {
    final id = tournamentId.trim();
    if (id.isEmpty) return 'Turnuva';
    for (final t in _teamTournaments) {
      if (t.id == id) return t.name;
    }
    return 'Turnuva';
  }

  int? _ageFromBirthDate(String? birthDate) {
    final s = (birthDate ?? '').trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(s);
    if (m == null) return null;
    final dd = int.tryParse(m.group(1)!) ?? 0;
    final mm = int.tryParse(m.group(2)!) ?? 0;
    final yyyy = int.tryParse(m.group(3)!) ?? 0;
    if (dd < 1 || dd > 31 || mm < 1 || mm > 12 || yyyy < 1900 || yyyy > 2100) {
      return null;
    }
    final now = DateTime.now();
    var age = now.year - yyyy;
    final hadBirthday = (now.month > mm) || (now.month == mm && now.day >= dd);
    if (!hadBirthday) age -= 1;
    return age < 0 ? null : age;
  }

  Future<void> _openPlayerCard(PlayerModel rosterPlayer) async {
    final phone = (rosterPlayer.phone ?? '').trim();
    final cachedPhoto =
        phone.isEmpty ? '' : (_playerPhotoUrlByPhone[phone] ?? '').trim();

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          backgroundColor: Colors.transparent,
          child: FutureBuilder<PlayerModel?>(
            future: phone.isEmpty ? Future.value(null) : _teamService.getPlayerByPhoneOnce(phone),
            builder: (context, snap) {
              final profile = snap.data;
              final photoUrl = ((profile?.photoUrl ?? '').trim().isNotEmpty)
                  ? (profile!.photoUrl ?? '').trim()
                  : cachedPhoto;
              final name = rosterPlayer.name.trim().isNotEmpty
                  ? rosterPlayer.name.trim()
                  : (profile?.name ?? '').trim();
              final birthDate = (profile?.birthDate ?? rosterPlayer.birthDate ?? '').trim();
              final age = _ageFromBirthDate(birthDate);
              final mainPos = (profile?.mainPosition ?? rosterPlayer.mainPosition ?? '').trim();
              final subPos = (profile?.position ?? rosterPlayer.position ?? '').trim();
              final preferredFoot =
                  (profile?.preferredFoot ?? rosterPlayer.preferredFoot ?? '').trim();
              final number = (rosterPlayer.number ?? profile?.number ?? '').toString().trim();

              final cs = Theme.of(context).colorScheme;
              final w = MediaQuery.of(context).size.width;
              final dialogW = min(360.0, w - 36);
              final topH = dialogW * 0.70;

              return ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: dialogW,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.primary.withValues(alpha: 0.95),
                        cs.secondary.withValues(alpha: 0.85),
                        cs.tertiary.withValues(alpha: 0.80),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: topH,
                        width: double.infinity,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.15),
                                child: photoUrl.isNotEmpty
                                    ? WebSafeImage(
                                        url: _normalizeUrl(photoUrl),
                                        width: dialogW,
                                        height: topH,
                                        isCircle: false,
                                        fallbackIconSize: 74,
                                        fit: BoxFit.cover,
                                      )
                                    : Icon(
                                        Icons.person,
                                        size: 96,
                                        color: Colors.white.withValues(alpha: 0.92),
                                      ),
                              ),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.05),
                                        Colors.black.withValues(alpha: 0.55),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 14,
                              right: 14,
                              bottom: 14,
                              child: Text(
                                name.isEmpty ? '-' : name,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        color: Colors.black.withValues(alpha: 0.28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CardRow(
                              label: 'Forma Numarası',
                              value: number.isEmpty ? '-' : number,
                            ),
                            _CardRow(
                              label: 'Doğum Tarihi',
                              value: birthDate.isEmpty
                                  ? '-'
                                  : (age == null ? birthDate : '$birthDate ($age)'),
                            ),
                            _CardRow(
                              label: 'Ana / Alt Mevki',
                              value: [
                                if (mainPos.isNotEmpty) mainPos,
                                if (subPos.isNotEmpty && subPos != mainPos) subPos,
                              ].isEmpty
                                  ? '-'
                                  : [
                                      if (mainPos.isNotEmpty) mainPos,
                                      if (subPos.isNotEmpty && subPos != mainPos) subPos,
                                    ].join(' • '),
                            ),
                            _CardRow(
                              label: 'Kullandığı Ayak',
                              value: preferredFoot.isEmpty ? '-' : preferredFoot,
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text(
                                'Kapat',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _prefetchPlayerPhotos(Iterable<PlayerModel> players) {
    final toFetch = <String>[];
    for (final p in players) {
      final phone = (p.phone ?? '').trim();
      if (phone.isEmpty) continue;
      if (_playerPhotoUrlByPhone.containsKey(phone)) continue;
      if (_playerPhotoFetchInFlight.contains(phone)) continue;
      toFetch.add(phone);
    }
    if (toFetch.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final phone in toFetch) {
        if (!mounted) return;
        if (_playerPhotoUrlByPhone.containsKey(phone)) continue;
        if (!_playerPhotoFetchInFlight.add(phone)) continue;

        _teamService.getPlayerByPhoneOnce(phone).then((player) {
          final url = (player?.photoUrl ?? '').trim();
          if (!mounted) return;
          setState(() {
            _playerPhotoUrlByPhone[phone] = url;
            _playerPhotoFetchInFlight.remove(phone);
          });
        }).catchError((_) {
          if (!mounted) return;
          setState(() {
            _playerPhotoUrlByPhone[phone] = '';
            _playerPhotoFetchInFlight.remove(phone);
          });
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTeamTournaments());
  }

  @override
  void dispose() {
    _rosterSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadTeamTournaments() async {
    if (!mounted) return;

    try {
      final tournaments = await _teamService.getTeamActiveTournaments(
        widget.teamId,
      );

      if (!mounted) return;

      String? selected = _selectedTournamentId;
      final widgetTournamentId = widget.tournamentId.trim();
      final defaultTournaments = tournaments.where((t) => t.isDefault).toList();
      if (defaultTournaments.length > 1) {
        defaultTournaments.sort((a, b) => a.name.compareTo(b.name));
      }
      final defaultTournamentId = defaultTournaments.isNotEmpty
          ? defaultTournaments.first.id
          : null;

      if (selected == null) {
        if (widgetTournamentId.isNotEmpty &&
            tournaments.any((t) => t.id == widgetTournamentId)) {
          selected = widgetTournamentId;
        } else {
          selected = defaultTournamentId;
        }
      }

      if (selected == null && tournaments.length == 1) {
        selected = tournaments.first.id;
      }

      if (selected != null && tournaments.every((t) => t.id != selected)) {
        selected =
            widgetTournamentId.isNotEmpty &&
                tournaments.any((t) => t.id == widgetTournamentId)
            ? widgetTournamentId
            : defaultTournamentId ??
                  (tournaments.isNotEmpty ? tournaments.first.id : null);
      }

      setState(() {
        _teamTournaments = tournaments;
        _selectedTournamentId = selected;
        _isLoadingTournaments = false;
      });

      if (selected != null) {
        await _checkIfTeamManagerForTournament(selected);
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Firestore Sorgu Hatası: ${error.toString()}');
      debugPrint('Hata Kaynağı: $stackTrace');
      if (!mounted) return;
      setState(() {
        _teamTournaments = [];
        _selectedTournamentId = null;
        _isLoadingTournaments = false;
      });
    }
  }

  Future<void> _checkIfTeamManagerForTournament(String tournamentId) async {
    final session = AppSession.of(context).value;
    if (session.isAdmin) {
      if (_isTeamManager) setState(() => _isTeamManager = false);
      return;
    }

    final isManager = await _teamService.isTeamManagerForTournament(
      tournamentId: tournamentId,
      teamId: widget.teamId,
      playerPhone: session.phone,
    );

    if (!mounted) return;
    setState(() => _isTeamManager = isManager);
  }

  Future<String?> _ensureSelectedTournament() async {
    final selected = _selectedTournamentId?.trim();
    if (selected != null && selected.isNotEmpty) {
      return selected;
    }

    final widgetTournamentId = widget.tournamentId.trim();
    if (widgetTournamentId.isNotEmpty) {
      setState(() => _selectedTournamentId = widgetTournamentId);
      await _checkIfTeamManagerForTournament(widgetTournamentId);
      return widgetTournamentId;
    }

    if (_teamTournaments.isEmpty && !_isLoadingTournaments) {
      await _loadTeamTournaments();
    }

    if (_teamTournaments.length == 1) {
      final tournamentId = _teamTournaments.first.id;
      setState(() => _selectedTournamentId = tournamentId);
      await _checkIfTeamManagerForTournament(tournamentId);
      return tournamentId;
    }

    if (_teamTournaments.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu takım için kayıtlı turnuva bulunamadı.'),
          ),
        );
      }
      return null;
    }

    if (!mounted) return null;

    final selectedTournament = await showDialog<String?>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Turnuva seçin'),
          children: _teamTournaments
              .map(
                (league) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, league.id),
                  child: Text(league.name),
                ),
              )
              .toList(),
        );
      },
    );

    if (selectedTournament == null || !mounted) return selectedTournament;

    setState(() => _selectedTournamentId = selectedTournament);
    await _checkIfTeamManagerForTournament(selectedTournament);
    return selectedTournament;
  }

  Future<void> _openPlayerForm({PlayerModel? editing}) async {
    final tournamentId = await _ensureSelectedTournament();
    if (tournamentId == null || !mounted) return;

    final saved = await Navigator.of(context).push<bool?>(
      MaterialPageRoute(
        builder: (_) => PlayerFormScreen(
          teamId: widget.teamId,
          tournamentId: tournamentId,
          normalizeUrl: _normalizeUrl,
          editing: editing,
        ),
      ),
    );

    if (!mounted) return;

    if (saved == true) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editing == null ? 'Futbolcu eklendi.' : 'Futbolcu güncellendi.',
          ),
        ),
      );
    }
  }

  Future<void> _openBulkUpload() async {
    final tournamentId = await _ensureSelectedTournament();
    if (tournamentId == null || !mounted) return;

    final leagueId = tournamentId.trim();
    if (leagueId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turnuva bilgisi bulunamadı.')),
      );
      return;
    }

    bool busy = false;
    String? pickedFileName;
    List<Map<String, dynamic>> parsed = const [];
    int skippedEmpty = 0;
    int skippedShort = 0;
    int skippedNoName = 0;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> downloadTemplate() async {
            setDialogState(() => busy = true);
            try {
              final excel = Excel.createExcel();
              final sheet = excel['Sheet1'];
              sheet.appendRow([
                TextCellValue('Forma No'),
                TextCellValue('Futbolcu Adı'),
                TextCellValue('Mevki'),
                TextCellValue('Doğum Tarihi'),
                TextCellValue('Kullandığı Ayak'),
              ]);
              final bytes = excel.encode();
              if (bytes == null) throw Exception('Şablon üretilemedi.');

              final dir = await getTemporaryDirectory();
              final file = File('${dir.path}/futbolcu_sablonu.xlsx');
              await file.writeAsBytes(bytes, flush: true);
              await Share.shareXFiles([
                XFile(file.path),
              ], text: 'Futbolcu Excel Şablonu');
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Hata: $e')));
            } finally {
              setDialogState(() => busy = false);
            }
          }

          String normalizeHeader(String s) {
            final cleaned = s
                .replaceAll('\u00A0', ' ')
                .replaceAll('\u0000', '')
                .replaceAll('İ', 'i')
                .replaceAll('I', 'ı')
                .trim()
                .toLowerCase();
            return cleaned.replaceAll(RegExp(r'\s+'), ' ');
          }

          int? findIndex(
            Map<String, int> headerToIndex,
            List<String> variants,
          ) {
            for (final v in variants) {
              final i = headerToIndex[normalizeHeader(v)];
              if (i != null) return i;
            }
            return null;
          }

          String? birthDateFrom(dynamic value) {
            if (value == null) return null;
            if (value is DateTime) {
              final dd = value.day.toString().padLeft(2, '0');
              final mm = value.month.toString().padLeft(2, '0');
              final yyyy = value.year.toString().padLeft(4, '0');
              return '$dd/$mm/$yyyy';
            }
            if (value is num) {
              final year = value.toInt();
              if (year >= 1900 && year <= 2100) {
                return '01/01/${year.toString().padLeft(4, '0')}';
              }
            }
            final s = value.toString().replaceAll('\u0000', '').trim();
            if (s.isEmpty) return null;
            final m = RegExp(
              r'^(\\d{1,2})[./-](\\d{1,2})[./-](\\d{4})$',
            ).firstMatch(s);
            if (m != null) {
              final dd = m.group(1)!.padLeft(2, '0');
              final mm = m.group(2)!.padLeft(2, '0');
              final yyyy = m.group(3)!.padLeft(4, '0');
              return '$dd/$mm/$yyyy';
            }
            final year = int.tryParse(s);
            if (year != null && year >= 1900 && year <= 2100) {
              return '01/01/${year.toString().padLeft(4, '0')}';
            }
            final yr = int.tryParse(
              RegExp(r'(19\\d{2}|20\\d{2}|2100)').firstMatch(s)?.group(0) ?? '',
            );
            if (yr != null && yr >= 1900 && yr <= 2100) {
              return '01/01/${yr.toString().padLeft(4, '0')}';
            }
            return null;
          }

          int? yearFromBirthDate(String? birthDate) {
            if (birthDate == null) return null;
            final m = RegExp(r'(\\d{4})$').firstMatch(birthDate);
            final y = m == null ? null : int.tryParse(m.group(1)!);
            if (y == null) return null;
            if (y < 1900 || y > 2100) return null;
            return y;
          }

          String cellStr(Data? cell) {
            final v = cell?.value;
            if (v == null) return '';
            return v.toString().trim();
          }

          String dynStr(dynamic v) =>
              (v ?? '').toString().replaceAll('\u0000', '').trim();

          Future<void> pickAndParse() async {
            setDialogState(() => busy = true);
            try {
              skippedEmpty = 0;
              skippedShort = 0;
              skippedNoName = 0;
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['xlsx', 'xls', 'csv', 'numbers'],
                withData: true,
              );
              if (result == null || result.files.isEmpty) return;
              final file = result.files.first;
              pickedFileName = file.name;

              final path = file.path;
              final ext = (pickedFileName!.split('.').last).toLowerCase();
              final bytes =
                  file.bytes ??
                  (path == null ? null : await File(path).readAsBytes());
              if (bytes == null && ext != 'csv') {
                throw Exception('Dosya okunamadı.');
              }

              List<Map<String, dynamic>> rows;
              if (ext == 'csv') {
                final content = file.bytes != null
                    ? String.fromCharCodes(file.bytes!)
                    : await File(path!).readAsString();
                final lines = content
                    .split(RegExp(r'\r?\n'))
                    .where((l) => l.trim().isNotEmpty)
                    .toList();
                if (lines.isEmpty) throw Exception('CSV boş.');
                final header = lines.first.split(',');
                final headerToIndex = <String, int>{};
                for (var i = 0; i < header.length; i++) {
                  headerToIndex[normalizeHeader(header[i])] = i;
                }
                final idxNo = findIndex(headerToIndex, [
                  'Forma No',
                  'FormaNo',
                  'No',
                  'Forma',
                  '#',
                ]);
                final idxName = findIndex(headerToIndex, [
                  'Futbolcu Adı',
                  'Futbolcu Adi',
                  'Ad Soyad',
                  'Adı Soyadı',
                  'Oyuncu',
                ]);
                final idxPos = findIndex(headerToIndex, [
                  'Mevki',
                  'Pozisyon',
                  'Posizyon',
                ]);
                final idxBirth = findIndex(headerToIndex, [
                  'Doğum Yılı',
                  'Dogum Yili',
                  'Doğum Tarihi',
                  'Dogum Tarihi',
                  'Doğum',
                  'Dogum',
                  'Birth Year',
                  'Year',
                ]);
                final idxFoot = findIndex(headerToIndex, [
                  'Kullandığı Ayak',
                  'Kullandigi Ayak',
                  'Ayak',
                ]);
                if (idxName == null ||
                    idxPos == null ||
                    idxBirth == null ||
                    idxFoot == null) {
                  throw Exception('CSV sütunları şablonla uyuşmuyor.');
                }
                rows = [];
                for (var i = 1; i < lines.length; i++) {
                  final cols = lines[i].split(',');
                  if (cols.isEmpty) {
                    skippedEmpty++;
                    continue;
                  }
                  if (cols.length < 2 || idxName >= cols.length) {
                    skippedShort++;
                    continue;
                  }
                  final name = cols[idxName].trim();
                  if (name.isEmpty) {
                    skippedNoName++;
                    continue;
                  }
                  final number = (idxNo != null && idxNo < cols.length)
                      ? cols[idxNo].trim()
                      : '';
                  final position = idxPos < cols.length
                      ? cols[idxPos].trim()
                      : '';
                  final birthRaw = idxBirth < cols.length
                      ? cols[idxBirth].trim()
                      : '';
                  final foot = idxFoot < cols.length
                      ? cols[idxFoot].trim()
                      : '';
                  final birthDate = birthDateFrom(birthRaw);
                  final birthYear = yearFromBirthDate(birthDate);
                  rows.add({
                    'name': name,
                    'number': number.isEmpty ? null : number,
                    'position': position.isEmpty ? null : position,
                    'birthDate': birthDate,
                    'birthYear': birthYear,
                    'preferredFoot': foot.isEmpty ? null : foot,
                  });
                }
              } else if (ext == 'xlsx') {
                List<Map<String, dynamic>> parseWithExcelPackage() {
                  final excel = Excel.decodeBytes(bytes!);
                  final availableSheets = excel.tables.entries.toList();
                  if (availableSheets.isEmpty) {
                    throw Exception('Excel sayfası bulunamadı.');
                  }
                  Sheet sheetResolved = availableSheets.first.value;
                  for (final e in availableSheets) {
                    if (e.value.rows.isNotEmpty) {
                      sheetResolved = e.value;
                      break;
                    }
                  }
                  if (sheetResolved.rows.isEmpty) throw Exception('Excel boş.');

                  int headerRowIndex = -1;
                  int? idxName;
                  int? idxPos;
                  int? idxBirth;
                  int? idxFoot;
                  int? idxNo;
                  final scanLimit = min(sheetResolved.rows.length, 20);
                  for (var r = 0; r < scanLimit; r++) {
                    final headerRow = sheetResolved.rows[r];
                    final headerToIndex = <String, int>{};
                    for (var i = 0; i < headerRow.length; i++) {
                      final text = cellStr(headerRow[i]);
                      if (text.isEmpty) continue;
                      headerToIndex[normalizeHeader(text)] = i;
                    }
                    final foundName = findIndex(headerToIndex, [
                      'Futbolcu Adı',
                      'Futbolcu Adi',
                      'Ad Soyad',
                      'Adı Soyadı',
                      'Oyuncu',
                    ]);
                    final foundPos = findIndex(headerToIndex, [
                      'Mevki',
                      'Pozisyon',
                      'Posizyon',
                    ]);
                    final foundBirth = findIndex(headerToIndex, [
                      'Doğum Yılı',
                      'Dogum Yili',
                      'Doğum Tarihi',
                      'Dogum Tarihi',
                      'Doğum',
                      'Dogum',
                      'Birth Year',
                      'Year',
                    ]);
                    final foundFoot = findIndex(headerToIndex, [
                      'Kullandığı Ayak',
                      'Kullandigi Ayak',
                      'Ayak',
                    ]);
                    final foundNo = findIndex(headerToIndex, [
                      'Forma No',
                      'FormaNo',
                      'No',
                      'Forma',
                      '#',
                    ]);
                    if (foundName != null &&
                        foundPos != null &&
                        foundBirth != null &&
                        foundFoot != null) {
                      headerRowIndex = r;
                      idxName = foundName;
                      idxPos = foundPos;
                      idxBirth = foundBirth;
                      idxFoot = foundFoot;
                      idxNo = foundNo;
                      break;
                    }
                  }
                  if (headerRowIndex == -1 ||
                      idxName == null ||
                      idxPos == null ||
                      idxBirth == null ||
                      idxFoot == null) {
                    throw Exception(
                      'Sütun başlıkları bulunamadı. Lütfen şablonu kullanın.',
                    );
                  }

                  final parsedRows = <Map<String, dynamic>>[];
                  for (
                    var r = headerRowIndex + 1;
                    r < sheetResolved.rows.length;
                    r++
                  ) {
                    final row = sheetResolved.rows[r];
                    if (row.isEmpty) {
                      skippedEmpty++;
                      continue;
                    }
                    if (row.length < 2) {
                      skippedShort++;
                      continue;
                    }
                    final nameCell = row.length > idxName ? row[idxName] : null;
                    final nameValue = nameCell?.value;
                    if (nameValue == null ||
                        nameValue.toString().trim().isEmpty) {
                      skippedNoName++;
                      continue;
                    }
                    final name = cellStr(nameCell);
                    final number = (idxNo != null && row.length > idxNo)
                        ? cellStr(row[idxNo])
                        : '';
                    final position = row.length > idxPos
                        ? cellStr(row[idxPos])
                        : '';
                    final birthRaw = row.length > idxBirth
                        ? row[idxBirth]?.value
                        : null;
                    final foot = row.length > idxFoot
                        ? cellStr(row[idxFoot])
                        : '';
                    final birthDate = birthDateFrom(birthRaw);
                    final birthYear = yearFromBirthDate(birthDate);
                    parsedRows.add({
                      'name': name,
                      'number': number.isEmpty ? null : number,
                      'position': position.isEmpty ? null : position,
                      'birthDate': birthDate,
                      'birthYear': birthYear,
                      'preferredFoot': foot.isEmpty ? null : foot,
                    });
                  }
                  return parsedRows;
                }

                rows = parseWithExcelPackage();
              } else if (ext == 'xls') {
                final decoder = SpreadsheetDecoder.decodeBytes(bytes!);
                if (decoder.tables.isEmpty) {
                  throw Exception('Excel sayfası bulunamadı.');
                }
                SpreadsheetTable table = decoder.tables.values.first;
                for (final e in decoder.tables.entries) {
                  if (e.value.rows.isNotEmpty) {
                    table = e.value;
                    break;
                  }
                }
                final rowsRaw = table.rows;
                if (rowsRaw.isEmpty) throw Exception('Excel boş.');

                int headerRowIndex = -1;
                int? idxName;
                int? idxPos;
                int? idxBirth;
                int? idxFoot;
                int? idxNo;
                final scanLimit = min(rowsRaw.length, 20);
                for (var r = 0; r < scanLimit; r++) {
                  final headerRow = rowsRaw[r];
                  final headerToIndex = <String, int>{};
                  for (var i = 0; i < headerRow.length; i++) {
                    final text = dynStr(headerRow[i]);
                    if (text.isEmpty) continue;
                    headerToIndex[normalizeHeader(text)] = i;
                  }
                  final foundName = findIndex(headerToIndex, [
                    'Futbolcu Adı',
                    'Futbolcu Adi',
                    'Ad Soyad',
                    'Adı Soyadı',
                    'Oyuncu',
                  ]);
                  final foundPos = findIndex(headerToIndex, [
                    'Mevki',
                    'Pozisyon',
                    'Posizyon',
                  ]);
                  final foundBirth = findIndex(headerToIndex, [
                    'Doğum Yılı',
                    'Dogum Yili',
                    'Doğum Tarihi',
                    'Dogum Tarihi',
                    'Doğum',
                    'Dogum',
                    'Birth Year',
                    'Year',
                  ]);
                  final foundFoot = findIndex(headerToIndex, [
                    'Kullandığı Ayak',
                    'Kullandigi Ayak',
                    'Ayak',
                  ]);
                  final foundNo = findIndex(headerToIndex, [
                    'Forma No',
                    'FormaNo',
                    'No',
                    'Forma',
                    '#',
                  ]);
                  if (foundName != null &&
                      foundPos != null &&
                      foundBirth != null &&
                      foundFoot != null) {
                    headerRowIndex = r;
                    idxName = foundName;
                    idxPos = foundPos;
                    idxBirth = foundBirth;
                    idxFoot = foundFoot;
                    idxNo = foundNo;
                    break;
                  }
                }
                if (headerRowIndex == -1 ||
                    idxName == null ||
                    idxPos == null ||
                    idxBirth == null ||
                    idxFoot == null) {
                  throw Exception(
                    'Sütun başlıkları bulunamadı. Lütfen şablonu kullanın.',
                  );
                }

                rows = [];
                for (var r = headerRowIndex + 1; r < rowsRaw.length; r++) {
                  final row = rowsRaw[r];
                  if (row.isEmpty) {
                    skippedEmpty++;
                    continue;
                  }
                  if (row.length < 2) {
                    skippedShort++;
                    continue;
                  }
                  final rawName = row.length > idxName ? row[idxName] : null;
                  final name = dynStr(rawName);
                  if (rawName == null || name.isEmpty) {
                    skippedNoName++;
                    continue;
                  }
                  final number = (idxNo != null && row.length > idxNo)
                      ? dynStr(row[idxNo])
                      : '';
                  final position = row.length > idxPos
                      ? dynStr(row[idxPos])
                      : '';
                  final birthRaw = row.length > idxBirth ? row[idxBirth] : null;
                  final foot = row.length > idxFoot ? dynStr(row[idxFoot]) : '';
                  final birthDate = birthDateFrom(birthRaw);
                  final birthYear = yearFromBirthDate(birthDate);
                  rows.add({
                    'name': name,
                    'number': number.isEmpty ? null : number,
                    'position': position.isEmpty ? null : position,
                    'birthDate': birthDate,
                    'birthYear': birthYear,
                    'preferredFoot': foot.isEmpty ? null : foot,
                  });
                }
              } else if (ext == 'numbers') {
                if (bytes != null &&
                    bytes.length >= 2 &&
                    bytes[0] == 0x50 &&
                    bytes[1] == 0x4B) {
                  final archive = ZipDecoder().decodeBytes(bytes);
                  ArchiveFile? best;
                  int bestScore = -1;
                  for (final f in archive) {
                    if (!f.isFile) continue;
                    final name = f.name.toLowerCase();
                    if (!name.endsWith('.csv')) continue;
                    var score = 0;
                    if (name.contains('preview')) score += 3;
                    if (name.contains('export')) score += 2;
                    if (name.contains('sheet')) score += 1;
                    if (score > bestScore) {
                      best = f;
                      bestScore = score;
                    }
                  }
                  if (best == null) {
                    throw Exception(
                      'Numbers dosyasında CSV bulunamadı. CSV olarak dışa aktarın.',
                    );
                  }
                  final content = best.content;
                  if (content is! List<int>) throw Exception('CSV okunamadı.');
                  var decoded = utf8.decode(content, allowMalformed: true);
                  if (decoded.isNotEmpty && decoded.codeUnitAt(0) == 0xFEFF) {
                    decoded = decoded.substring(1);
                  }
                  final lines = decoded
                      .split(RegExp(r'\r?\n'))
                      .where((l) => l.trim().isNotEmpty)
                      .toList();
                  if (lines.isEmpty) throw Exception('CSV boş.');
                  final header = lines.first.split(',');
                  final headerToIndex = <String, int>{};
                  for (var i = 0; i < header.length; i++) {
                    headerToIndex[normalizeHeader(header[i])] = i;
                  }
                  final idxNo = findIndex(headerToIndex, [
                    'Forma No',
                    'FormaNo',
                    'No',
                    'Forma',
                    '#',
                  ]);
                  final idxName = findIndex(headerToIndex, [
                    'Futbolcu Adı',
                    'Futbolcu Adi',
                    'Ad Soyad',
                    'Adı Soyadı',
                    'Oyuncu',
                  ]);
                  final idxPos = findIndex(headerToIndex, [
                    'Mevki',
                    'Pozisyon',
                    'Posizyon',
                  ]);
                  final idxBirth = findIndex(headerToIndex, [
                    'Doğum Yılı',
                    'Dogum Yili',
                    'Doğum Tarihi',
                    'Dogum Tarihi',
                    'Doğum',
                    'Dogum',
                    'Birth Year',
                    'Year',
                  ]);
                  final idxFoot = findIndex(headerToIndex, [
                    'Kullandığı Ayak',
                    'Kullandigi Ayak',
                    'Ayak',
                  ]);
                  if (idxName == null ||
                      idxPos == null ||
                      idxBirth == null ||
                      idxFoot == null) {
                    throw Exception('CSV sütunları şablonla uyuşmuyor.');
                  }
                  rows = [];
                  for (var i = 1; i < lines.length; i++) {
                    final cols = lines[i].split(',');
                    if (cols.isEmpty) {
                      skippedEmpty++;
                      continue;
                    }
                    if (cols.length < 2 || idxName >= cols.length) {
                      skippedShort++;
                      continue;
                    }
                    final name = cols[idxName].trim();
                    if (name.isEmpty) {
                      skippedNoName++;
                      continue;
                    }
                    final number = (idxNo != null && idxNo < cols.length)
                        ? cols[idxNo].trim()
                        : '';
                    final position = idxPos < cols.length
                        ? cols[idxPos].trim()
                        : '';
                    final birthRaw = idxBirth < cols.length
                        ? cols[idxBirth].trim()
                        : '';
                    final foot = idxFoot < cols.length
                        ? cols[idxFoot].trim()
                        : '';
                    final birthDate = birthDateFrom(birthRaw);
                    final birthYear = yearFromBirthDate(birthDate);
                    rows.add({
                      'name': name,
                      'number': number.isEmpty ? null : number,
                      'position': position.isEmpty ? null : position,
                      'birthDate': birthDate,
                      'birthYear': birthYear,
                      'preferredFoot': foot.isEmpty ? null : foot,
                    });
                  }
                } else {
                  throw Exception(
                    'Numbers formatı için lütfen dosyayı CSV’ye dışa aktarın.',
                  );
                }
              } else {
                throw Exception('Desteklenmeyen dosya türü.');
              }

              setDialogState(() => parsed = rows);
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Hata: $e')));
            } finally {
              setDialogState(() => busy = false);
            }
          }

          Future<void> submitForApproval() async {
            if (parsed.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Yüklenecek kayıt bulunamadı.')),
              );
              return;
            }
            setDialogState(() => busy = true);
            var shouldClose = false;
            try {
              final actionId =
                  'squad_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
              await _approvalService.submitPendingAction(
                PendingAction(
                  actionId: actionId,
                  actionType: 'squad_upload',
                  leagueId: leagueId,
                  teamId: widget.teamId,
                  submittedBy: 'admin',
                  payload: {
                    'teamName': widget.teamName,
                    'tournamentId': leagueId,
                    'fileName': pickedFileName,
                    'players': parsed,
                  },
                ),
              );
              shouldClose = true;
              if (!context.mounted) return;
              Navigator.pop(context);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final skipped = skippedEmpty + skippedShort + skippedNoName;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Onaya gönderildi: ${parsed.length} oyuncu • Atlanan satır: $skipped',
                    ),
                  ),
                );
              });
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Hata: $e')));
            } finally {
              if (!shouldClose && context.mounted) {
                setDialogState(() => busy = false);
              }
            }
          }

          return AlertDialog(
            title: Text('Toplu Kadro Yükle • ${widget.teamName}'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : downloadTemplate,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Örnek Şablonunu İndir'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : pickAndParse,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Dosya Yükle (.xls/.xlsx/.csv/.numbers)'),
                  ),
                  const SizedBox(height: 12),
                  if (pickedFileName != null)
                    Text(
                      'Dosya: $pickedFileName',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  if (parsed.isNotEmpty)
                    Text(
                      'Okunan kayıt: ${parsed.length}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  if (pickedFileName != null)
                    Text(
                      'Atlanan satır: ${skippedEmpty + skippedShort + skippedNoName}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  if (busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
              FilledButton(
                onPressed: busy ? null : submitForApproval,
                child: const Text('Onaya Gönder'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleTeam = widget.teamName.trim();
    final session = AppSession.of(context).value;
    final isAdmin = session.isAdmin;
    final widgetTournamentId = widget.tournamentId.trim();
    final effectiveTournamentId =
        (_selectedTournamentId != null && _selectedTournamentId!.trim().isNotEmpty)
            ? _selectedTournamentId!.trim()
            : (_teamTournaments.isEmpty && widgetTournamentId.isNotEmpty
                ? widgetTournamentId
                : null);
    final canAdd = effectiveTournamentId != null && (isAdmin || _isTeamManager);
    final headerTournamentName = _tournamentNameById(
      effectiveTournamentId ?? widgetTournamentId,
    );
    final headerTeamName =
        titleTeam.isEmpty ? widget.teamName.trim() : titleTeam;

    return Scaffold(
      appBar: AppBar(
        title: Text(titleTeam.isEmpty ? 'Takım Kadrosu' : '$titleTeam Kadrosu'),
        centerTitle: true,
        actions: [
          if (canAdd)
            IconButton(
              tooltip: 'Futbolcu Ekle',
              onPressed: _openPlayerForm,
              icon: const Icon(Icons.add),
            ),
          if (canAdd)
            IconButton(
              tooltip: 'Excel Yükle',
              onPressed: _openBulkUpload,
              icon: const Icon(Icons.upload_file),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoadingTournaments)
            const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                TextField(
                  controller: _rosterSearchController,
                  onChanged: (v) =>
                      setState(() => _rosterQuery = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Futbolcu Ara',
                    prefixIcon: Icon(Icons.search, color: cs.primary),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: cs.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cs.primary, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: effectiveTournamentId == null
                ? Center(
                    child: Text(
                      'Lütfen turnuva seçin.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : StreamBuilder<List<PlayerModel>>(
                    stream: _teamService.watchPlayers(
                      teamId: widget.teamId,
                      tournamentId: effectiveTournamentId,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Hata: ${snapshot.error}'));
                      }
                      final allPlayers = snapshot.data ?? const <PlayerModel>[];
                      if (allPlayers.isEmpty) {
                        return const Center(
                          child: Text('Henüz kadro girişi yapılmamış.'),
                        );
                      }
                      final q = _rosterQuery;
                      final players = q.isEmpty
                          ? allPlayers
                          : allPlayers
                                .where((p) => p.name.toLowerCase().contains(q))
                                .toList();
                      if (players.isEmpty) {
                        return const Center(
                          child: Text('Aramanıza uygun futbolcu bulunamadı.'),
                        );
                      }

                      _prefetchPlayerPhotos(players);

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                        itemCount: players.length,
                        itemBuilder: (context, index) {
                          final p = players[index];
                          final photo = (p.photoUrl ?? '').trim();
                          final phone = (p.phone ?? '').trim();
                          final cached = phone.isEmpty ? '' : (_playerPhotoUrlByPhone[phone] ?? '');
                          final resolvedPhoto = photo.isNotEmpty ? photo : cached;
                          final num = (p.number ?? '').trim();
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 2,
                              ),
                              onTap: () => _openPlayerCard(p),
                              leading: resolvedPhoto.isNotEmpty
                                  ? WebSafeImage(
                                      url: _normalizeUrl(resolvedPhoto),
                                      width: 36,
                                      height: 36,
                                      isCircle: true,
                                      fallbackIconSize: 18,
                                    )
                                  : CircleAvatar(
                                      radius: 18,
                                      backgroundColor: cs.primary.withValues(alpha: 0.12),
                                      child: Icon(
                                        Icons.person,
                                        size: 18,
                                        color: cs.primary,
                                      ),
                                    ),
                              title: Text(
                                p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    num.isEmpty ? '-' : num,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert),
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Düzenle'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Sil'),
                                      ),
                                    ],
                                    onSelected: (value) async {
                                      switch (value) {
                                        case 'edit':
                                          _openPlayerForm(editing: p);
                                          break;
                                        case 'delete':
                                          final tId = effectiveTournamentId;
                                          final phone = (p.phone ?? '').trim();
                                          if (tId == null || tId.trim().isEmpty || phone.isEmpty) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Silme için eksik bilgi.')),
                                            );
                                            return;
                                          }
                                          final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('Futbolcu Sil'),
                                              content: Text(
                                                '${p.name} oyuncusunu bu takımdan kaldırmak istiyor musunuz?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(context, false),
                                                  child: const Text('İptal'),
                                                ),
                                                FilledButton(
                                                  onPressed: () => Navigator.pop(context, true),
                                                  child: const Text('Sil'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (ok != true) return;
                                          await _deleteRosterPlayer(
                                            tournamentId: tId,
                                            teamId: widget.teamId,
                                            playerPhone: phone,
                                          );
                                          if (mounted) setState(() {});
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Kadrodan kaldırıldı.')),
                                          );
                                          break;
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class PlayerFormScreen extends StatefulWidget {
  const PlayerFormScreen({
    super.key,
    required this.teamId,
    required this.tournamentId,
    this.editing,
    String Function(String raw)? normalizeUrl,
  }) : normalizeUrl = normalizeUrl ?? _defaultNormalizeUrl;

  final String teamId;
  final String tournamentId;
  final PlayerModel? editing;
  final String Function(String raw) normalizeUrl;

  static String _defaultNormalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  @override
  State<PlayerFormScreen> createState() => _PlayerFormScreenState();
}

class _PlayerFormScreenState extends State<PlayerFormScreen> {
  final ITeamService _teamService = ServiceLocator.teamService;
  final _picker = ImagePicker();
  final _imageUploadService = ImgBBUploadService();

  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _identityNoController = TextEditingController();
  final _numberController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _phoneController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();

  static const _mainPositions = <String>[
    'Kaleci',
    'Defans',
    'Orta Saha',
    'Forvet',
  ];
  static const Map<String, List<String>> _subPositionsByMain = {
    'Kaleci': ['Kaleci'],
    'Defans': ['Stoper', 'Bek'],
    'Orta Saha': ['Defansif', 'Merkez', 'Ofansif', 'Kanat'],
    'Forvet': ['Santrfor', 'Kanat Forvet'],
  };
  static const _roles = <String>['Her İkisi', 'Takım Sorumlusu', 'Futbolcu'];
  static const _feet = <String>['Sağ', 'Sol', 'Her İkisi'];

  String _mainPosition = _mainPositions.first;
  String _subPosition = _subPositionsByMain[_mainPositions.first]!.first;
  String _role = 'Futbolcu';
  String _preferredFoot = '';
  String? _activePlayerId;
  String? _existingPhotoUrl;
  String? _implicitPhoneKey;
  XFile? _pickedPhoto;
  bool _removePhoto = false;
  bool _saving = false;
  bool _managerExists = false;

  bool _isManagerRole(String role) =>
      role == 'Takım Sorumlusu' || role == 'Her İkisi';

  String _deriveMainPosition(String? main, String? subOrLegacy) {
    final m = (main ?? '').trim();
    if (_subPositionsByMain.containsKey(m)) return m;
    final s = (subOrLegacy ?? '').trim();
    if (s.isEmpty) return _mainPositions.first;
    switch (s) {
      case 'GK':
        return 'Kaleci';
      case 'DEF':
        return 'Defans';
      case 'ORT':
        return 'Orta Saha';
      case 'FOR':
        return 'Forvet';
    }
    for (final entry in _subPositionsByMain.entries) {
      if (entry.value.contains(s)) return entry.key;
    }
    return _mainPositions.first;
  }

  String _deriveSubPosition(String main, String? subOrLegacy) {
    final options = _subPositionsByMain[main] ?? const <String>[];
    if (options.isEmpty) return '';
    final s = (subOrLegacy ?? '').trim();
    if (options.contains(s)) return s;
    switch (s) {
      case 'GK':
        return 'Kaleci';
      case 'DEF':
        return 'Stoper';
      case 'ORT':
        return 'Merkez';
      case 'FOR':
        return 'Santrfor';
    }
    return options.first;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _activePlayerId = (e.phone ?? e.id).trim().isEmpty
          ? e.id
          : (e.phone ?? e.id);
      _identityNoController.text = (e.nationalId ?? '').toString();
      final full = e.name.trim().replaceAll(RegExp(r'\s+'), ' ');
      final parts = full.isEmpty ? const <String>[] : full.split(' ');
      _nameController.text = parts.isEmpty ? '' : parts.first;
      _surnameController.text = parts.length <= 1 ? '' : parts.sublist(1).join(' ');
      _numberController.text = (e.number ?? '').toString();
      _birthDateController.text = (e.birthDate ?? '').toString();
      _mainPosition = _deriveMainPosition(e.mainPosition, e.position);
      _subPosition = _deriveSubPosition(_mainPosition, e.position);
      final pf = (e.preferredFoot ?? '').trim();
      _preferredFoot = _feet.contains(pf) ? pf : '';
      _heightController.text = (e.height ?? '').toString();
      _weightController.text = (e.weight ?? '').toString();
      final r = e.role.trim();
      _role = r.isEmpty ? 'Futbolcu' : r;
      if (!_roles.contains(_role)) _role = 'Futbolcu';
      final phoneRaw = (e.phone ?? '').toString();
      if (phoneRaw.startsWith('no_phone_')) {
        _implicitPhoneKey = phoneRaw;
        _phoneController.text = '';
      } else {
        _implicitPhoneKey = null;
        _phoneController.text = PhoneMaskFormatter.formatFromRaw(phoneRaw);
      }
      _existingPhotoUrl = (e.photoUrl ?? '').trim().isEmpty ? null : e.photoUrl;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadManagerState());
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateExistingPhotoFromIdentity());
  }

  Future<void> _hydrateExistingPhotoFromIdentity() async {
    if (!mounted) return;
    if (_pickedPhoto != null) return;
    if (_removePhoto) return;
    final phone = _rawPhone();
    final keyPhone = phone.isNotEmpty ? phone : (_implicitPhoneKey ?? '');
    if (keyPhone.trim().isEmpty) return;
    final player = await _teamService.getPlayerByPhoneOnce(keyPhone.trim());
    final url = (player?.photoUrl ?? '').trim();
    if (!mounted) return;
    if (url.isEmpty) return;
    setState(() => _existingPhotoUrl = url);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _identityNoController.dispose();
    _numberController.dispose();
    _birthDateController.dispose();
    _phoneController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _loadManagerState() async {
    final exists = await _teamService.managerExistsForTeamTournament(
      tournamentId: widget.tournamentId,
      teamId: widget.teamId,
      excludePlayerPhone: _activePlayerId,
    );
    if (!mounted) return;
    setState(() => _managerExists = exists);
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final originalFile = File(picked.path);
    final bytes = await originalFile.length();
    if (bytes > 10 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dosya boyutu çok yüksek (Max 10MB). Lütfen daha düşük boyutlu bir görsel seçiniz.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final tmp = await getTemporaryDirectory();

    const maxUploadedBytes = 800 * 1024;
    const targetWidth = 1024;
    const targetHeight = 1024;
    const qualities = [85, 75, 65, 55];

    XFile? best;
    for (final q in qualities) {
      final targetPath =
          '${tmp.path}/player_${DateTime.now().millisecondsSinceEpoch}_q$q.jpg';
      final out = await FlutterImageCompress.compressAndGetFile(
        originalFile.absolute.path,
        targetPath,
        quality: q,
        minWidth: targetWidth,
        minHeight: targetHeight,
      );
      if (out == null) continue;
      best = out;
      final size = await File(out.path).length();
      if (size <= maxUploadedBytes) break;
    }

    if (best == null) {
      setState(() {
        _pickedPhoto = picked;
        _removePhoto = false;
      });
      return;
    }
    setState(() {
      _pickedPhoto = best;
      _removePhoto = false;
    });
  }

  String _rawPhone() {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return digits;
  }

  int? _birthYearFromDate(String? birthDate) {
    if (birthDate == null) return null;
    final m = RegExp(r'(\d{4})$').firstMatch(birthDate.trim());
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  bool _isValidBirthDate(String s) {
    final v = s.trim();
    if (v.isEmpty) return true;
    if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(v)) return false;
    final y = _birthYearFromDate(v);
    if (y == null) return false;
    return y >= 1900 && y <= 2100;
  }

  bool _isValidPhoneRaw(String raw) {
    if (raw.isEmpty) return true;
    if (!RegExp(r'^\d{10}$').hasMatch(raw)) return false;
    return true;
  }

  Future<PlayerModel?> _selectExistingPlayer() async {
    return showModalBottomSheet<PlayerModel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PlayerPickerSheet(
        teamId: widget.teamId,
        tournamentId: widget.tournamentId,
        normalizeUrl: widget.normalizeUrl,
      ),
    );
  }

  void _applySelectedPlayer(PlayerModel p) {
    _activePlayerId = p.id;
    _identityNoController.text = (p.nationalId ?? '').toString();
    final full = p.name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final parts = full.isEmpty ? const <String>[] : full.split(' ');
    _nameController.text = parts.isEmpty ? '' : parts.first;
    _surnameController.text = parts.length <= 1 ? '' : parts.sublist(1).join(' ');
    _numberController.text = (p.number ?? '').toString();
    _birthDateController.text = (p.birthDate ?? '').toString();
    _mainPosition = _deriveMainPosition(p.mainPosition, p.position);
    _subPosition = _deriveSubPosition(_mainPosition, p.position);
    final pf = (p.preferredFoot ?? '').trim();
    _preferredFoot = _feet.contains(pf) ? pf : '';
    _heightController.text = (p.height ?? '').toString();
    _weightController.text = (p.weight ?? '').toString();
    final r = p.role.trim();
    _role = _roles.contains(r) ? r : 'Futbolcu';
    final phoneRaw = (p.phone ?? '').toString();
    if (phoneRaw.startsWith('no_phone_')) {
      _implicitPhoneKey = phoneRaw;
      _phoneController.text = '';
    } else {
      _implicitPhoneKey = null;
      _phoneController.text = PhoneMaskFormatter.formatFromRaw(phoneRaw);
    }
    _existingPhotoUrl = (p.photoUrl ?? '').trim().isEmpty ? null : p.photoUrl;
    _pickedPhoto = null;
    _removePhoto = false;

    if (_managerExists && _isManagerRole(_role)) {
      _role = 'Futbolcu';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bu takımda zaten takım sorumlusu var. Rol "Futbolcu" olarak ayarlandı.',
            ),
          ),
        );
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateExistingPhotoFromIdentity());
  }

  String _generateNoPhoneKey() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random().nextInt(1 << 31);
    return 'no_phone_${ts}_$rnd';
  }

  Future<void> _save() async {
    final nationalId = _identityNoController.text.replaceAll(RegExp(r'\D'), '').trim();
    if (nationalId.isNotEmpty && nationalId.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kimlik no 11 haneli olmalı.')),
      );
      return;
    }

    final firstName = _nameController.text.trim();
    final surname = _surnameController.text.trim();
    if (firstName.isEmpty || surname.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lütfen ad soyad girin.')));
      return;
    }
    final fullName = '$firstName $surname'.trim();

    final number = _numberController.text.trim();
    if (number.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Forma numarası zorunludur.')));
      return;
    }

    final birthDate = _birthDateController.text.trim();
    if (!_isValidBirthDate(birthDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Doğum tarihi DD/MM/YYYY formatında olmalı.'),
        ),
      );
      return;
    }

    final rawPhone = _rawPhone();
    if (!_isValidPhoneRaw(rawPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefon no 10 haneli olmalı.')),
      );
      return;
    }
    final keyPhone = rawPhone.isNotEmpty
        ? rawPhone
        : (_implicitPhoneKey ??= _generateNoPhoneKey());

    if (_managerExists &&
        _isManagerRole(_role) &&
        !(widget.editing != null && _isManagerRole(widget.editing!.role))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu takımda zaten takım sorumlusu var.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      String? uploadedPhotoUrl;
      if (_pickedPhoto != null) {
        uploadedPhotoUrl = await _imageUploadService.uploadImage(
          File(_pickedPhoto!.path),
        );
        if ((uploadedPhotoUrl ?? '').trim().isEmpty) {
          throw Exception('Fotoğraf yüklenemedi, lütfen tekrar deneyin.');
        }
      }

      final resolvedBirthDate = birthDate.isEmpty ? null : birthDate;
      await _teamService.upsertPlayerIdentity(
        phone: keyPhone,
        name: fullName,
        nationalId: nationalId.isEmpty ? null : nationalId,
        birthDate: resolvedBirthDate,
        mainPosition: _mainPosition,
        preferredFoot: _preferredFoot.trim().isEmpty ? null : _preferredFoot.trim(),
        height: int.tryParse(_heightController.text.replaceAll(RegExp(r'\D'), '').trim()),
        weight: int.tryParse(_weightController.text.replaceAll(RegExp(r'\D'), '').trim()),
      );
      await _teamService.updatePlayer(
        playerId: keyPhone,
        data: {
          'name': firstName,
          'surname': surname,
          'birthDate': resolvedBirthDate,
          'nationalId': nationalId.isEmpty ? null : nationalId,
          'mainPosition': _mainPosition,
          'subPosition': _subPosition,
          'preferredFoot': _preferredFoot.trim().isEmpty ? null : _preferredFoot.trim(),
          'height': int.tryParse(_heightController.text.replaceAll(RegExp(r'\D'), '').trim()),
          'weight': int.tryParse(_weightController.text.replaceAll(RegExp(r'\D'), '').trim()),
          'defaultJerseyNumber': int.tryParse(number.replaceAll(RegExp(r'\D'), '').trim()),
          'role': _role,
        },
      );
      await _teamService.upsertRosterEntry(
        tournamentId: widget.tournamentId,
        teamId: widget.teamId,
        playerPhone: keyPhone,
        playerName: fullName,
        jerseyNumber: number,
        role: _role,
      );

      if (uploadedPhotoUrl != null) {
        final url = uploadedPhotoUrl.trim();
        await _teamService.updatePlayer(
          playerId: keyPhone,
          data: {'photoUrl': url},
        );
      } else if (_removePhoto) {
        await _teamService.updatePlayer(
          playerId: keyPhone,
          data: {'photoUrl': null},
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final uniq = 'Bu futbolcu zaten sistemde kayıtlı!';
      final text = msg.contains(uniq) ? uniq : 'Hata: $msg';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), backgroundColor: Colors.red),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final editing = widget.editing != null;
    final allowManagerOptions = !_managerExists || _isManagerRole(_role);

    final hasPicked = _pickedPhoto != null;
    final editingUrl = (_existingPhotoUrl ?? '').trim();
    final hasEditingUrl = editingUrl.isNotEmpty;
    final hasPhoto = hasPicked || hasEditingUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Oyuncu Güncelle' : 'Futbolcu Ekle'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final h = min(MediaQuery.of(context).size.height * 0.38, 340.0);
              return SizedBox(
                height: h,
                width: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.10),
                          border: Border(
                            bottom: BorderSide(
                              color: cs.primary.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                        ),
                        child: hasPicked
                            ? Image.file(
                                File(_pickedPhoto!.path),
                                fit: BoxFit.cover,
                              )
                            : hasEditingUrl
                            ? WebSafeImage(
                                url: widget.normalizeUrl(editingUrl),
                                width: constraints.maxWidth,
                                height: h,
                                isCircle: false,
                                fallbackIconSize: 64,
                                fit: BoxFit.cover,
                              )
                            : Icon(Icons.person, size: 88, color: cs.primary),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.00),
                                Colors.black.withValues(alpha: 0.25),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Material(
                            color: _saving
                                ? cs.primary.withValues(alpha: 0.45)
                                : cs.primary,
                            shape: const CircleBorder(),
                            child: IconButton(
                              onPressed: _saving ? null : _pickPhoto,
                              icon: const Icon(Icons.photo_camera_outlined),
                              color: Colors.white,
                              iconSize: 30,
                              padding: const EdgeInsets.all(14),
                              constraints: const BoxConstraints(
                                minWidth: 56,
                                minHeight: 56,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Material(
                            color: (!_saving && hasPhoto)
                                ? cs.error
                                : cs.error.withValues(alpha: 0.35),
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Fotoğrafı Kaldır',
                              onPressed: (_saving || !hasPhoto)
                                  ? null
                                  : () {
                                      setState(() {
                                        _pickedPhoto = null;
                                        _existingPhotoUrl = null;
                                        _removePhoto = true;
                                      });
                                    },
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.white,
                              iconSize: 28,
                              padding: const EdgeInsets.all(14),
                              constraints: const BoxConstraints(
                                minWidth: 56,
                                minHeight: 56,
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Column(
              children: [
                TextField(
                  controller: _identityNoController,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Kimlik No',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Ad',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _surnameController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Soyad',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
 /*                    const SizedBox(width: 10),
                    SizedBox(
                      height: 52,
                     child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                        ),
                        onPressed: _saving
                            ? null
                            : () async {
                                final selected = await _selectExistingPlayer();
                                if (selected == null) return;
                                setState(() => _applySelectedPlayer(selected));
                                await _loadManagerState();
                              },
                        child: const Text(
                          'SEÇ',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),*/
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _numberController,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Forma No',
                          prefixIcon: Icon(Icons.confirmation_number_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _birthDateController,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [BirthDateInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Doğum Tarihi',
                          prefixIcon: Icon(Icons.cake_outlined),
                          hintText: 'DD/MM/YYYY',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _preferredFoot.trim().isEmpty ? null : _preferredFoot,
                  decoration: const InputDecoration(
                    labelText: 'Kullandığı Ayak',
                    prefixIcon: Icon(Icons.directions_run_outlined),
                  ),
                  items: _feet
                      .map(
                        (f) => DropdownMenuItem<String>(
                          value: f,
                          child: Text(f),
                        ),
                      )
                      .toList(),
                  onChanged: _saving ? null : (v) => setState(() => _preferredFoot = v ?? ''),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _heightController,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Boy (cm)',
                          prefixIcon: Icon(Icons.height_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _weightController,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Kilo (kg)',
                          prefixIcon: Icon(Icons.monitor_weight_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _mainPosition,
                        decoration: const InputDecoration(
                          labelText: 'Ana Mevki',
                          prefixIcon: Icon(Icons.sports_soccer_outlined),
                        ),
                        items: _mainPositions
                            .map(
                              (p) => DropdownMenuItem<String>(
                                value: p,
                                child: Text(p),
                              ),
                            )
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() {
                                  _mainPosition = v;
                                  _subPosition =
                                      (_subPositionsByMain[v] ??
                                              const <String>[])
                                          .first;
                                });
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _subPosition,
                        decoration: const InputDecoration(
                          labelText: 'Alt Mevki',
                          prefixIcon: Icon(Icons.sports_outlined),
                        ),
                        items:
                            (_subPositionsByMain[_mainPosition] ??
                                    const <String>[])
                                .map(
                                  (p) => DropdownMenuItem<String>(
                                    value: p,
                                    child: Text(p),
                                  ),
                                )
                                .toList(),
                        onChanged: _saving
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() => _subPosition = v);
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Rolü',
                    prefixIcon: Icon(Icons.manage_accounts_outlined),
                  ),
                  items: _roles.map((r) {
                    final disabled = _isManagerRole(r) && !allowManagerOptions;
                    return DropdownMenuItem<String>(
                      value: r,
                      enabled: !disabled,
                      child: Text(
                        r,
                        style: disabled
                            ? TextStyle(
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.45,
                                ),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() => _role = v);
                        },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneController,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [PhoneMaskFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Telefon No',
                    prefixIcon: Icon(Icons.phone_outlined),
                    prefixText: '0 ',
                    hintText: '(5XX) XXX XX XX',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: _saving
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: cs.primary),
                    onPressed: _save,
                    child: Text(
                      editing ? 'GÜNCELLE' : 'KAYDET',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PlayerPickerSheet extends StatefulWidget {
  const _PlayerPickerSheet({
    required this.teamId,
    required this.tournamentId,
    required this.normalizeUrl,
  });

  final String teamId;
  final String tournamentId;
  final String Function(String raw) normalizeUrl;

  @override
  State<_PlayerPickerSheet> createState() => _PlayerPickerSheetState();
}

class _PlayerPickerSheetState extends State<_PlayerPickerSheet> {
  final ITeamService _teamService = ServiceLocator.teamService;
  final _searchController = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 10,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  color: cs.primary,
                ),
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) =>
                          setState(() => _q = v.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Oyuncu Ara',
                        prefixIcon: Icon(Icons.search, color: cs.primary),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.filter_list),
                  color: cs.primary,
                ),
              ],
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Flexible(
              child: StreamBuilder<List<PlayerModel>>(
                stream: _teamService.watchPlayers(
                  teamId: widget.teamId,
                  tournamentId: widget.tournamentId,
                ),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snapshot.data ?? const <PlayerModel>[];
                  final filtered = _q.isEmpty
                      ? [...all]
                      : all
                            .where((p) => p.name.toLowerCase().contains(_q))
                            .toList();
                  filtered.sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );
                  if (filtered.isEmpty) {
                    return const Center(child: Text('Oyuncu bulunamadı.'));
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = filtered[i];
                      final birth = (p.birthDate ?? '').trim();
                      final photo = (p.photoUrl ?? '').trim();
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 40,
                              height: 40,
                              color: cs.primary.withValues(alpha: 0.10),
                              child: photo.isEmpty
                                  ? Center(
                                      child: Text(
                                        p.name.trim().isEmpty
                                            ? '?'
                                            : p.name.trim()[0].toUpperCase(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    )
                                  : WebSafeImage(
                                      url: widget.normalizeUrl(photo),
                                      width: 40,
                                      height: 40,
                                      isCircle: false,
                                      fallbackIconSize: 18,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                          title: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          trailing: Text(
                            birth.isEmpty ? '-' : birth,
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(p),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BirthDateInputFormatter extends TextInputFormatter {
  static String _digits(String text) => text.replaceAll(RegExp(r'\D'), '');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldDigits = _digits(oldValue.text);
    final newDigits = _digits(newValue.text);

    final deletingOneChar = oldValue.text.length == newValue.text.length + 1;
    final deletedOnlySlash =
        deletingOneChar &&
        oldValue.text.contains('/') &&
        oldDigits == newDigits &&
        !newValue.text.contains('//');
    if (deletedOnlySlash) {
      final text = newValue.text.length > 10
          ? newValue.text.substring(0, 10)
          : newValue.text;
      final offset = newValue.selection.baseOffset.clamp(0, text.length);
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset),
      );
    }

    var digits = newDigits;
    if (digits.length > 8) digits = digits.substring(0, 8);

    final rawCursor = newValue.selection.baseOffset.clamp(
      0,
      newValue.text.length,
    );
    final digitsBeforeCursor = _digits(
      newValue.text.substring(0, rawCursor),
    ).length;
    final clippedDigitsBeforeCursor = min(digitsBeforeCursor, digits.length);

    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) b.write('/');
      b.write(digits[i]);
    }
    final text = b.toString(); // max 10

    var offset = clippedDigitsBeforeCursor;
    if (offset > 2) offset += 1;
    if (offset > 4) offset += 1;
    offset = offset.clamp(0, text.length);

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class PhoneMaskFormatter extends TextInputFormatter {
  static String formatFromRaw(String raw) {
    String digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.isEmpty) return '';

    final clipped = digits.length > 10 ? digits.substring(0, 10) : digits;
    final a = clipped.isNotEmpty
        ? clipped.substring(0, min(3, clipped.length))
        : '';
    final b = clipped.length > 3
        ? clipped.substring(3, min(6, clipped.length))
        : '';
    final c = clipped.length > 6
        ? clipped.substring(6, min(8, clipped.length))
        : '';
    final e = clipped.length > 8
        ? clipped.substring(8, min(10, clipped.length))
        : '';

    final sb = StringBuffer();
    if (a.isNotEmpty) {
      sb.write('(');
      sb.write(a);
      if (a.length == 3) sb.write(') ');
    }
    if (b.isNotEmpty) {
      sb.write(b);
      if (b.length == 3) sb.write(' ');
    }
    if (c.isNotEmpty) {
      sb.write(c);
      if (c.length == 2) sb.write(' ');
    }
    if (e.isNotEmpty) {
      sb.write(e);
    }
    return sb.toString().trimRight();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatFromRaw(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
