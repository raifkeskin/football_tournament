import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import '../models/match.dart';
import '../services/approval_service.dart';
import '../services/database_service.dart';
import '../services/image_upload_service.dart';

class TeamSquadScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  final String teamLogoUrl;

  const TeamSquadScreen({
    super.key,
    required this.teamId,
    required this.teamName,
    required this.teamLogoUrl,
  });

  @override
  State<TeamSquadScreen> createState() => _TeamSquadScreenState();
}

class _TeamSquadScreenState extends State<TeamSquadScreen> {
  final _dbService = DatabaseService();
  final _approvalService = ApprovalService();
  final _imageUploadService = ImgBBUploadService();
  final _picker = ImagePicker();
  bool _fabOpen = false;

  static const _positions = <String>['GK', 'DEF', 'ORT', 'FOR'];

  @override
  void dispose() {
    super.dispose();
  }

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  Future<void> _openPlayerForm({PlayerModel? editing}) async {
    final nameController = TextEditingController(text: editing?.name ?? '');
    final numberController = TextEditingController(
      text: (editing?.number ?? '').toString(),
    );
    final birthController = TextEditingController(
      text: editing?.birthYear?.toString() ?? '',
    );
    String position = (editing?.position ?? '').trim();
    if (!_positions.contains(position)) position = _positions.first;
    XFile? pickedPhoto;
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final insets = MediaQuery.of(context).viewInsets;
        final cs = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickPhoto() async {
              final picked = await _picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 85,
              );
              if (picked == null) return;
              setSheetState(() => pickedPhoto = picked);
            }

            Future<void> save() async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lütfen ad soyad girin.')),
                );
                return;
              }

              final nRaw = numberController.text.trim();
              final number = nRaw.isEmpty ? null : nRaw;
              final bRaw = birthController.text.trim();
              final birthYear = bRaw.isEmpty ? null : int.tryParse(bRaw);
              if (bRaw.isNotEmpty && birthYear == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Doğum yılı geçerli olmalı.')),
                );
                return;
              }

              setSheetState(() => saving = true);
              var shouldClose = false;
              try {
                String? photoUrl = editing?.photoUrl;
                if (pickedPhoto != null) {
                  final uploaded = await _imageUploadService.uploadImage(
                    File(pickedPhoto!.path),
                  );
                  if (uploaded == null) {
                    throw Exception('Fotoğraf yüklenemedi.');
                  }
                  photoUrl = uploaded;
                }

                if (editing == null) {
                  await _dbService.addPlayer(
                    PlayerModel(
                      id: '',
                      teamId: widget.teamId,
                      name: name,
                      number: number,
                      birthYear: birthYear,
                      position: position,
                      photoUrl: photoUrl,
                    ),
                  );
                } else {
                  await _dbService.updatePlayer(
                    playerId: editing.id,
                    data: {
                      'name': name,
                      'number': number,
                      'birthYear': birthYear,
                      'position': position,
                      'photoUrl': photoUrl ?? '',
                    },
                  );
                }

                shouldClose = true;
                if (!context.mounted) return;
                Navigator.pop(context);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        editing == null
                            ? 'Futbolcu eklendi.'
                            : 'Futbolcu güncellendi.',
                      ),
                    ),
                  );
                });
              } catch (e) {
                if (!context.mounted) return;
                final msg = e.toString();
                final uniq = 'Bu futbolcu zaten sistemde kayıtlı!';
                final text = msg.contains(uniq) ? uniq : 'Hata: $msg';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(text), backgroundColor: Colors.red),
                );
              } finally {
                if (!shouldClose && context.mounted) {
                  setSheetState(() => saving = false);
                }
              }
            }

            final photoPreview = pickedPhoto != null
                ? FileImage(File(pickedPhoto!.path)) as ImageProvider
                : (editing?.photoUrl != null && editing!.photoUrl!.trim().isNotEmpty
                    ? NetworkImage(_normalizeUrl(editing.photoUrl!.trim()))
                    : null);

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 6,
                bottom: insets.bottom + 16,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    editing == null ? 'Futbolcu Ekle' : 'Oyuncu Güncelle',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundColor: cs.primary.withValues(alpha: 0.10),
                          backgroundImage: photoPreview,
                          child: photoPreview == null
                              ? Icon(Icons.person, size: 36, color: cs.primary)
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: cs.primary,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: saving ? null : pickPhoto,
                              icon: const Icon(
                                Icons.photo_camera_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    enabled: !saving,
                    decoration: const InputDecoration(
                      labelText: 'Ad Soyad',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: numberController,
                          enabled: !saving,
                          decoration: const InputDecoration(
                            labelText: 'Forma No',
                            prefixIcon: Icon(Icons.confirmation_number_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: birthController,
                          enabled: !saving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Doğum Yılı',
                            prefixIcon: Icon(Icons.cake_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: position,
                    decoration: const InputDecoration(
                      labelText: 'Mevki',
                      prefixIcon: Icon(Icons.sports_soccer_outlined),
                    ),
                    items: _positions
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p,
                            child: Text(p),
                          ),
                        )
                        .toList(),
                    onChanged: saving ? null : (v) => setSheetState(() => position = v!),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 50,
                    child: saving
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(
                              editing == null ? 'Ekle' : 'Güncelle',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    numberController.dispose();
    birthController.dispose();
  }

  Future<void> _openBulkUpload() async {
    final teamSnap = await FirebaseFirestore.instance
        .collection('teams')
        .doc(widget.teamId)
        .get();
    final teamData = teamSnap.data() ?? <String, dynamic>{};
    final leagueId = (teamData['leagueId'] as String?)?.trim() ?? '';
    if (leagueId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Takımın leagueId alanı bulunamadı.')),
      );
      return;
    }

    bool busy = false;
    String? pickedFileName;
    List<Map<String, dynamic>> parsed = const [];

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
                TextCellValue('Doğum Yılı'),
                TextCellValue('Kullandığı Ayak'),
              ]);
              final bytes = excel.encode();
              if (bytes == null) throw Exception('Şablon üretilemedi.');

              final dir = await getTemporaryDirectory();
              final file = File('${dir.path}/futbolcu_sablonu.xlsx');
              await file.writeAsBytes(bytes, flush: true);
              await Share.shareXFiles([XFile(file.path)], text: 'Futbolcu Excel Şablonu');
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
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

          int? findIndex(Map<String, int> headerToIndex, List<String> variants) {
            for (final v in variants) {
              final i = headerToIndex[normalizeHeader(v)];
              if (i != null) return i;
            }
            return null;
          }

          int? birthYearFrom(dynamic value) {
            if (value == null) return null;
            if (value is DateTime) {
              final y = value.year;
              return (y >= 1900 && y <= 2100) ? y : null;
            }
            if (value is num) {
              final y = value.toInt();
              if (y >= 1900 && y <= 2100) return y;
            }
            final s = value.toString().replaceAll('\u0000', '').trim();
            final direct = int.tryParse(s);
            if (direct != null) {
              if (direct >= 1900 && direct <= 2100) return direct;
            }
            final d = double.tryParse(s.replaceAll(',', '.'));
            if (d != null) {
              final y = d.toInt();
              if (y >= 1900 && y <= 2100) return y;
            }
            final m = RegExp(r'(19\\d{2}|20\\d{2}|2100)').firstMatch(s);
            if (m != null) {
              final y = int.tryParse(m.group(0)!);
              if (y != null && y >= 1900 && y <= 2100) return y;
            }
            return null;
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
                  file.bytes ?? (path == null ? null : await File(path).readAsBytes());
              if (bytes == null && ext != 'csv') throw Exception('Dosya okunamadı.');

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
                final idxPos = findIndex(headerToIndex, ['Mevki', 'Pozisyon', 'Posizyon']);
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
                if (idxName == null || idxPos == null || idxBirth == null || idxFoot == null) {
                  throw Exception('CSV sütunları şablonla uyuşmuyor.');
                }
                rows = [];
                for (var i = 1; i < lines.length; i++) {
                  final cols = lines[i].split(',');
                  if (idxName >= cols.length) continue;
                  final name = cols[idxName].trim();
                  if (name.isEmpty) continue;
                  final number = (idxNo != null && idxNo < cols.length) ? cols[idxNo].trim() : '';
                  final position = idxPos < cols.length ? cols[idxPos].trim() : '';
                  final birthRaw = idxBirth < cols.length ? cols[idxBirth].trim() : '';
                  final foot = idxFoot < cols.length ? cols[idxFoot].trim() : '';
                  final birthYear = birthYearFrom(birthRaw);
                  rows.add({
                    'name': name,
                    'number': number.isEmpty ? null : number,
                    'position': position.isEmpty ? null : position,
                    'birthYear': birthYear,
                    'preferredFoot': foot.isEmpty ? null : foot,
                  });
                }
              } else if (ext == 'xlsx') {
                List<Map<String, dynamic>> parseWithExcelPackage() {
                  final excel = Excel.decodeBytes(bytes!);
                  final availableSheets = excel.tables.entries.toList();
                  if (availableSheets.isEmpty) throw Exception('Excel sayfası bulunamadı.');
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
                    final foundPos = findIndex(headerToIndex, ['Mevki', 'Pozisyon', 'Posizyon']);
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
                    if (foundName != null && foundPos != null && foundBirth != null && foundFoot != null) {
                      headerRowIndex = r;
                      idxName = foundName;
                      idxPos = foundPos;
                      idxBirth = foundBirth;
                      idxFoot = foundFoot;
                      idxNo = foundNo;
                      break;
                    }
                  }
                  if (headerRowIndex == -1 || idxName == null || idxPos == null || idxBirth == null || idxFoot == null) {
                    throw Exception('Sütun başlıkları bulunamadı. Lütfen şablonu kullanın.');
                  }

                  final parsedRows = <Map<String, dynamic>>[];
                  for (var r = headerRowIndex + 1; r < sheetResolved.rows.length; r++) {
                    final row = sheetResolved.rows[r];
                    final name = row.length > idxName ? cellStr(row[idxName]) : '';
                    if (name.isEmpty) continue;
                    final number = (idxNo != null && row.length > idxNo) ? cellStr(row[idxNo]) : '';
                    final position = row.length > idxPos ? cellStr(row[idxPos]) : '';
                    final birthRaw = row.length > idxBirth ? row[idxBirth]?.value : null;
                    final foot = row.length > idxFoot ? cellStr(row[idxFoot]) : '';
                    final birthYear = birthYearFrom(birthRaw);
                    parsedRows.add({
                      'name': name,
                      'number': number.isEmpty ? null : number,
                      'position': position.isEmpty ? null : position,
                      'birthYear': birthYear,
                      'preferredFoot': foot.isEmpty ? null : foot,
                    });
                  }
                  return parsedRows;
                }

                rows = parseWithExcelPackage();
              } else if (ext == 'xls') {
                final decoder = SpreadsheetDecoder.decodeBytes(bytes!);
                if (decoder.tables.isEmpty) throw Exception('Excel sayfası bulunamadı.');
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
                  final foundPos = findIndex(headerToIndex, ['Mevki', 'Pozisyon', 'Posizyon']);
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
                  if (foundName != null && foundPos != null && foundBirth != null && foundFoot != null) {
                    headerRowIndex = r;
                    idxName = foundName;
                    idxPos = foundPos;
                    idxBirth = foundBirth;
                    idxFoot = foundFoot;
                    idxNo = foundNo;
                    break;
                  }
                }
                if (headerRowIndex == -1 || idxName == null || idxPos == null || idxBirth == null || idxFoot == null) {
                  throw Exception('Sütun başlıkları bulunamadı. Lütfen şablonu kullanın.');
                }

                rows = [];
                for (var r = headerRowIndex + 1; r < rowsRaw.length; r++) {
                  final row = rowsRaw[r];
                  final name = row.length > idxName ? dynStr(row[idxName]) : '';
                  if (name.isEmpty) continue;
                  final number = (idxNo != null && row.length > idxNo) ? dynStr(row[idxNo]) : '';
                  final position = row.length > idxPos ? dynStr(row[idxPos]) : '';
                  final birthRaw = row.length > idxBirth ? row[idxBirth] : null;
                  final foot = row.length > idxFoot ? dynStr(row[idxFoot]) : '';
                  final birthYear = birthYearFrom(birthRaw);
                  rows.add({
                    'name': name,
                    'number': number.isEmpty ? null : number,
                    'position': position.isEmpty ? null : position,
                    'birthYear': birthYear,
                    'preferredFoot': foot.isEmpty ? null : foot,
                  });
                }
              } else if (ext == 'numbers') {
                if (bytes != null && bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
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
                    throw Exception('Numbers dosyasında CSV bulunamadı. CSV olarak dışa aktarın.');
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
                  final idxNo = findIndex(headerToIndex, ['Forma No', 'FormaNo', 'No', 'Forma', '#']);
                  final idxName = findIndex(headerToIndex, [
                    'Futbolcu Adı',
                    'Futbolcu Adi',
                    'Ad Soyad',
                    'Adı Soyadı',
                    'Oyuncu',
                  ]);
                  final idxPos = findIndex(headerToIndex, ['Mevki', 'Pozisyon', 'Posizyon']);
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
                  final idxFoot = findIndex(headerToIndex, ['Kullandığı Ayak', 'Kullandigi Ayak', 'Ayak']);
                  if (idxName == null || idxPos == null || idxBirth == null || idxFoot == null) {
                    throw Exception('CSV sütunları şablonla uyuşmuyor.');
                  }
                  rows = [];
                  for (var i = 1; i < lines.length; i++) {
                    final cols = lines[i].split(',');
                    if (idxName >= cols.length) continue;
                    final name = cols[idxName].trim();
                    if (name.isEmpty) continue;
                    final number = (idxNo != null && idxNo < cols.length) ? cols[idxNo].trim() : '';
                    final position = idxPos < cols.length ? cols[idxPos].trim() : '';
                    final birthRaw = idxBirth < cols.length ? cols[idxBirth].trim() : '';
                    final foot = idxFoot < cols.length ? cols[idxFoot].trim() : '';
                    final birthYear = birthYearFrom(birthRaw);
                    rows.add({
                      'name': name,
                      'number': number.isEmpty ? null : number,
                      'position': position.isEmpty ? null : position,
                      'birthYear': birthYear,
                      'preferredFoot': foot.isEmpty ? null : foot,
                    });
                  }
                } else {
                  throw Exception('Numbers formatı için lütfen dosyayı CSV’ye dışa aktarın.');
                }
              } else {
                throw Exception('Desteklenmeyen dosya türü.');
              }

              setDialogState(() => parsed = rows);
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
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
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Onaya gönderildi.')),
                );
              });
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Hata: $e')));
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
    final dbService = _dbService;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Takım Kadrosu')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_fabOpen) ...[
            FloatingActionButton.small(
              heroTag: 'bulk_${widget.teamId}',
              onPressed: () async {
                setState(() => _fabOpen = false);
                await _openBulkUpload();
              },
              child: const Icon(Icons.upload_file_rounded),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.small(
              heroTag: 'add_${widget.teamId}',
              onPressed: () async {
                setState(() => _fabOpen = false);
                await _openPlayerForm();
              },
              child: const Icon(Icons.person_add_alt_1_outlined),
            ),
            const SizedBox(height: 10),
          ],
          FloatingActionButton(
            heroTag: 'main_${widget.teamId}',
            onPressed: () => setState(() => _fabOpen = !_fabOpen),
            child: Icon(_fabOpen ? Icons.close : Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: cs.surfaceContainerLow,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: widget.teamLogoUrl.isNotEmpty
                      ? NetworkImage(_normalizeUrl(widget.teamLogoUrl))
                      : null,
                  child: widget.teamLogoUrl.isEmpty
                      ? const Icon(Icons.groups, size: 30)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.teamName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<PlayerModel>>(
              stream: dbService.getPlayers(widget.teamId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Hata: ${snapshot.error}'));
                }
                final players = snapshot.data ?? const <PlayerModel>[];
                if (players.isEmpty) {
                  return const Center(child: Text('Henüz kadro girişi yapılmamış.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: players.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final p = players[index];
                    final photo = (p.photoUrl ?? '').trim();
                    final photoProvider = photo.isEmpty ? null : NetworkImage(_normalizeUrl(photo));
                    final num = (p.number ?? '').trim();
                    final pos = (p.position ?? '').trim();
                    final birth = p.birthYear;
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        onTap: () => _openPlayerForm(editing: p),
                        leading: CircleAvatar(
                          backgroundImage: photoProvider,
                          child: photoProvider == null
                              ? Text(
                                  p.name.trim().isEmpty
                                      ? '?'
                                      : p.name.trim()[0].toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                )
                              : null,
                        ),
                        title: Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          '${pos.isEmpty ? '-' : pos} | Doğum: ${birth ?? '-'}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (p.suspendedMatches > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.red.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Text(
                                  '${p.suspendedMatches}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            if (p.suspendedMatches > 0 && num.isNotEmpty)
                              const SizedBox(width: 10),
                            if (num.isNotEmpty)
                              Text(
                                num,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
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
