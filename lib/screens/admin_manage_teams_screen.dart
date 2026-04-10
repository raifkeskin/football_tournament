import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/match.dart'; // PlayerModel burada tanımlı
import '../services/approval_service.dart';
import '../services/app_session.dart';
import '../services/database_service.dart';
import '../services/image_upload_service.dart';
import 'team_squad_screen.dart';

class AdminManageTeamsScreen extends StatefulWidget {
  const AdminManageTeamsScreen({super.key});

  @override
  State<AdminManageTeamsScreen> createState() => _AdminManageTeamsScreenState();
}

class _AdminManageTeamsScreenState extends State<AdminManageTeamsScreen> {
  final dbService = DatabaseService();
  final approvalService = ApprovalService();
  String _searchQuery = '';
  final _teamNameController = TextEditingController();
  final _picker = ImagePicker();
  final _imageUploadService = ImgBBUploadService();
  XFile? _teamLogo;
  String? _selectedLeagueId;
  bool _addingTeam = false;

  /// Türkçe karakter duyarlı küçük harfe çevirme (Arama için)
  String _toTurkishLow(String input) {
    return input.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  }

  Future<void> _openAddTeamSheet() async {
    _teamNameController.clear();
    _teamLogo = null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickLogo() async {
              final picked = await _picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 85,
              );
              if (picked == null) return;
              setSheetState(() => _teamLogo = picked);
            }

            Future<void> save() async {
              final leagueId = _selectedLeagueId;
              final teamName = _teamNameController.text.trim();
              if (leagueId == null || leagueId.isEmpty || teamName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Lütfen turnuva ve takım adını girin.'),
                  ),
                );
                return;
              }
              setSheetState(() => _addingTeam = true);
              try {
                var logoUrl = '';
                if (_teamLogo != null) {
                  final uploaded = await _imageUploadService.uploadImage(
                    File(_teamLogo!.path),
                  );
                  if (uploaded == null) {
                    throw Exception('Logo yüklenemedi.');
                  }
                  logoUrl = uploaded;
                }
                await dbService.addTeam(leagueId, teamName, logoUrl);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  this.context,
                ).showSnackBar(const SnackBar(content: Text('Takım eklendi.')));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Hata: $e')));
              } finally {
                if (context.mounted) setSheetState(() => _addingTeam = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 4,
                bottom: viewInsets.bottom + 16,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    'Takım Ekle',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: dbService.getLeagues(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox(height: 56);
                      final docs = snapshot.data!.docs.toList();
                      docs.sort((a, b) {
                        final aName =
                            ((a.data() as Map<String, dynamic>)['name']
                                        ?.toString() ??
                                    '')
                                .toLowerCase();
                        final bName =
                            ((b.data() as Map<String, dynamic>)['name']
                                        ?.toString() ??
                                    '')
                                .toLowerCase();
                        return aName.compareTo(bName);
                      });
                      if (docs.isNotEmpty &&
                          (_selectedLeagueId == null ||
                              _selectedLeagueId!.isEmpty)) {
                        _selectedLeagueId = docs.first.id;
                      }
                      return DropdownButtonFormField<String>(
                        value: _selectedLeagueId,
                        decoration: const InputDecoration(labelText: 'Turnuva'),
                        items: docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text(
                              data['name']?.toString() ?? 'Turnuva',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: _addingTeam
                            ? null
                            : (val) =>
                                  setSheetState(() => _selectedLeagueId = val),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _teamNameController,
                    decoration: const InputDecoration(labelText: 'Takım Adı'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _addingTeam ? null : pickLogo,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(
                      _teamLogo == null
                          ? 'Logo Seç (Galeri)'
                          : 'Seçildi: ${_teamLogo!.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 48,
                    child: _addingTeam
                        ? const Center(child: CircularProgressIndicator())
                        : FilledButton.icon(
                            onPressed: save,
                            icon: const Icon(Icons.add),
                            label: const Text('Ekle'),
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

  Future<void> _takimSil(String teamId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Takım Sil'),
        content: const Text(
          'Takım ve ilişkili veriler silinecektir. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hayır'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Evet'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await dbService.deleteTeamCascade(teamId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Takım silindi.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  void dispose() {
    _teamNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('Takım Yönetimi')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: _openAddTeamSheet,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Takım Ara',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) =>
                  setState(() => _searchQuery = _toTurkishLow(val)),
            ),
          ),
          Divider(color: Colors.grey.shade300, height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: dbService.getTeams(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());

                final teams = snapshot.data!.docs.where((doc) {
                  final name =
                      (doc.data() as Map<String, dynamic>)['name']
                          ?.toString() ??
                      '';
                  return _toTurkishLow(name).contains(_searchQuery);
                }).toList();

                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Card(
                    child: ListView.separated(
                      itemCount: teams.length,
                      separatorBuilder: (context, index) =>
                          Divider(color: Colors.grey.shade300, height: 1),
                      itemBuilder: (context, index) {
                        final doc = teams[index];
                        final data = doc.data() as Map<String, dynamic>;
                        return ListTile(
                          leading:
                              data['logoUrl'] != null &&
                                  data['logoUrl'].isNotEmpty
                              ? Image.network(
                                  data['logoUrl'],
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                )
                              : const Icon(Icons.groups),
                          title: Text(
                            data['name'] ?? '',
                            maxLines: 3,
                            softWrap: true,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            if (!isAdmin) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TeamSquadScreen(
                                    teamId: doc.id,
                                    teamName: data['name'] ?? '',
                                    teamLogoUrl: data['logoUrl'] ?? '',
                                  ),
                                ),
                              );
                              return;
                            }

                            await showModalBottomSheet<void>(
                              context: context,
                              showDragHandle: true,
                              builder: (context) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.badge_outlined),
                                      title: const Text('Kadro'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => TeamSquadScreen(
                                              teamId: doc.id,
                                              teamName: data['name'] ?? '',
                                              teamLogoUrl: data['logoUrl'] ?? '',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(
                                        Icons.person_add_alt_1_outlined,
                                      ),
                                      title: const Text('Futbolcu Ekle'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        _showAddPlayerDialog(doc.id);
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.upload_file_rounded),
                                      title: const Text('Toplu Kadro Yükle'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        _showBulkUploadDialog(
                                          teamId: doc.id,
                                          leagueId:
                                              (data['leagueId'] as String?) ?? '',
                                          teamName: (data['name'] as String?) ?? '',
                                        );
                                      },
                                    ),
                                    const Divider(height: 1),
                                    ListTile(
                                      leading: const Icon(Icons.edit_outlined),
                                      title: const Text('Düzenle'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => EditTeamScreen(
                                              teamId: doc.id,
                                              data: data,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.delete_outline),
                                      title: const Text('Sil'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        _takimSil(doc.id);
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddPlayerDialog(String teamId) {
    final nameController = TextEditingController();
    final numberController = TextEditingController();
    final yearController = TextEditingController();
    String position = 'Forvet';
    XFile? playerPhoto;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Futbolcu Ekle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final picked = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 85,
                      );
                      if (picked != null)
                        setDialogState(() => playerPhoto = picked);
                    },
                    child: CircleAvatar(
                      radius: 40,
                      backgroundImage: playerPhoto != null
                          ? FileImage(File(playerPhoto!.path))
                          : null,
                      child: playerPhoto == null
                          ? const Icon(Icons.add_a_photo, size: 30)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Ad Soyad',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: numberController,
                          decoration: const InputDecoration(
                            labelText: 'Forma No',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: yearController,
                          decoration: const InputDecoration(
                            labelText: 'Doğum Yılı',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: position,
                    decoration: const InputDecoration(
                      labelText: 'Mevki',
                      border: OutlineInputBorder(),
                    ),
                    items: ['Kaleci', 'Defans', 'Ortasaha', 'Forvet']
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => position = v!),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (nameController.text.isEmpty) return;
                        setDialogState(() => isSaving = true);

                        try {
                          String photoUrl = '';
                          if (playerPhoto != null) {
                            final uploaded = await ImgBBUploadService()
                                .uploadImage(File(playerPhoto!.path));
                            if (uploaded != null) photoUrl = uploaded;
                          }

                          await dbService.addPlayer(
                            PlayerModel(
                              id: '',
                              teamId: teamId,
                              name: nameController.text.trim(),
                              number: numberController.text.trim(),
                              birthYear: int.tryParse(yearController.text),
                              position: position,
                              photoUrl: photoUrl,
                            ),
                          );

                          if (!mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Futbolcu başarıyla eklendi.'),
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                        } finally {
                          setDialogState(() => isSaving = false);
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showBulkUploadDialog({
    required String teamId,
    required String leagueId,
    required String teamName,
  }) async {
    bool busy = false;
    String? pickedFileName;
    List<Map<String, dynamic>> parsed = const [];

    await showDialog(
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
            final m = RegExp(r'(19\d{2}|20\d{2}|2100)').firstMatch(s);
            if (m != null) {
              final y = int.tryParse(m.group(0)!);
              if (y != null && y >= 1900 && y <= 2100) return y;
            }
            return null;
          }

          String cellStr(Data? cell) {
            final v = cell?.value;
            if (v == null) return '';
            final s = v.toString();
            return s.trim();
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
                  file.bytes ??
                  (path == null ? null : await File(path).readAsBytes());
              if (bytes == null && ext != 'csv')
                throw Exception('Dosya okunamadı.');

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
                  if (idxName >= cols.length) continue;
                  final name = cols[idxName].trim();
                  if (name.isEmpty) continue;
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
                  if (availableSheets.isEmpty)
                    throw Exception('Excel sayfası bulunamadı.');

                  Sheet? pickedSheet;
                  String? pickedSheetName;
                  for (final e in availableSheets) {
                    if (e.value.rows.isNotEmpty) {
                      pickedSheet = e.value;
                      pickedSheetName = e.key;
                      break;
                    }
                  }
                  final sheetResolved =
                      pickedSheet ?? availableSheets.first.value;
                  final sheetNameResolved =
                      pickedSheetName ?? availableSheets.first.key;

                  if (sheetResolved.rows.isEmpty) throw Exception('Excel boş.');

                  int headerRowIndex = -1;
                  int? idxName;
                  int? idxPos;
                  int? idxBirth;
                  int? idxFoot;
                  int? idxNo;
                  Map<String, int> lastHeaderToIndex = const {};

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
                      lastHeaderToIndex = headerToIndex;
                      break;
                    }
                    lastHeaderToIndex = headerToIndex;
                  }

                  assert(() {
                    debugPrint(
                      '[bulk-upload] reader=excel file=$pickedFileName ext=$ext sheet=$sheetNameResolved rows=${sheetResolved.rows.length}',
                    );
                    debugPrint(
                      '[bulk-upload] headerScanLast=$lastHeaderToIndex',
                    );
                    debugPrint(
                      '[bulk-upload] headerRowIndex=$headerRowIndex idxName=$idxName idxPos=$idxPos idxBirth=$idxBirth idxFoot=$idxFoot',
                    );
                    return true;
                  }());

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
                    final name = row.length > idxName
                        ? cellStr(row[idxName])
                        : '';
                    if (name.isEmpty) continue;
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
                    final birthYear = birthYearFrom(birthRaw);
                    parsedRows.add({
                      'name': name,
                      'number': number.isEmpty ? null : number,
                      'position': position.isEmpty ? null : position,
                      'birthYear': birthYear,
                      'preferredFoot': foot.isEmpty ? null : foot,
                    });
                  }

                  assert(() {
                    debugPrint(
                      '[bulk-upload] reader=excel parsed=${parsedRows.length}',
                    );
                    if (parsedRows.isNotEmpty)
                      debugPrint(
                        '[bulk-upload] reader=excel first=${parsedRows.first}',
                      );
                    return true;
                  }());

                  return parsedRows;
                }

                List<Map<String, dynamic>> parseWithSpreadsheetDecoder() {
                  final decoder = SpreadsheetDecoder.decodeBytes(bytes!);
                  if (decoder.tables.isEmpty)
                    throw Exception('Excel sayfası bulunamadı.');

                  SpreadsheetTable? table;
                  String? tableName;
                  for (final e in decoder.tables.entries) {
                    if (e.value.rows.isNotEmpty) {
                      table = e.value;
                      tableName = e.key;
                      break;
                    }
                  }
                  table ??= decoder.tables.values.first;
                  tableName ??= decoder.tables.keys.first;

                  final rowsRaw = table!.rows;
                  if (rowsRaw.isEmpty) throw Exception('Excel boş.');

                  int headerRowIndex = -1;
                  int? idxName;
                  int? idxPos;
                  int? idxBirth;
                  int? idxFoot;
                  int? idxNo;
                  Map<String, int> lastHeaderToIndex = const {};

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
                      lastHeaderToIndex = headerToIndex;
                      break;
                    }
                    lastHeaderToIndex = headerToIndex;
                  }

                  assert(() {
                    debugPrint(
                      '[bulk-upload] reader=spreadsheet_decoder file=$pickedFileName ext=$ext sheet=$tableName rows=${rowsRaw.length}',
                    );
                    debugPrint(
                      '[bulk-upload] headerScanLast=$lastHeaderToIndex',
                    );
                    debugPrint(
                      '[bulk-upload] headerRowIndex=$headerRowIndex idxName=$idxName idxPos=$idxPos idxBirth=$idxBirth idxFoot=$idxFoot',
                    );
                    return true;
                  }());

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
                  for (var r = headerRowIndex + 1; r < rowsRaw.length; r++) {
                    final row = rowsRaw[r];
                    final name = row.length > idxName
                        ? dynStr(row[idxName])
                        : '';
                    if (name.isEmpty) continue;
                    final number = (idxNo != null && row.length > idxNo)
                        ? dynStr(row[idxNo])
                        : '';
                    final position = row.length > idxPos
                        ? dynStr(row[idxPos])
                        : '';
                    final birthRaw = row.length > idxBirth
                        ? row[idxBirth]
                        : null;
                    final foot = row.length > idxFoot
                        ? dynStr(row[idxFoot])
                        : '';
                    final birthYear = birthYearFrom(birthRaw);
                    parsedRows.add({
                      'name': name,
                      'number': number.isEmpty ? null : number,
                      'position': position.isEmpty ? null : position,
                      'birthYear': birthYear,
                      'preferredFoot': foot.isEmpty ? null : foot,
                    });
                  }

                  assert(() {
                    debugPrint(
                      '[bulk-upload] reader=spreadsheet_decoder parsed=${parsedRows.length}',
                    );
                    if (parsedRows.isNotEmpty)
                      debugPrint(
                        '[bulk-upload] reader=spreadsheet_decoder first=${parsedRows.first}',
                      );
                    return true;
                  }());

                  return parsedRows;
                }

                try {
                  rows = parseWithExcelPackage();
                } catch (e) {
                  final msg = e.toString();
                  assert(() {
                    debugPrint('[bulk-upload] reader=excel failed: $msg');
                    return true;
                  }());
                  if (msg.contains('custom numFmtId') ||
                      msg.contains('numFmtId')) {
                    rows = parseWithSpreadsheetDecoder();
                  } else {
                    rethrow;
                  }
                }
              } else if (ext == 'xls') {
                final decoder = SpreadsheetDecoder.decodeBytes(bytes!);
                if (decoder.tables.isEmpty)
                  throw Exception('Excel sayfası bulunamadı.');

                SpreadsheetTable? table;
                for (final e in decoder.tables.entries) {
                  if (e.value.rows.isNotEmpty) {
                    table = e.value;
                    break;
                  }
                }
                table ??= decoder.tables.values.first;

                final rowsRaw = table!.rows;
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
                  final name = row.length > idxName ? dynStr(row[idxName]) : '';
                  if (name.isEmpty) continue;
                  final number = (idxNo != null && row.length > idxNo)
                      ? dynStr(row[idxNo])
                      : '';
                  final position = row.length > idxPos
                      ? dynStr(row[idxPos])
                      : '';
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
                if (bytes != null &&
                    bytes.length >= 2 &&
                    bytes[0] == 0x50 &&
                    bytes[1] == 0x4B) {
                  // Zip arşivinde CSV ara
                  final archiveFile = ArchiveDecoder(bytes);
                  final csv = await archiveFile.findFirstCsv();
                  if (csv == null) {
                    throw Exception(
                      'Numbers dosyasında CSV bulunamadı. Lütfen Numbers’tan CSV olarak dışa aktarın.',
                    );
                  }
                  final content = csv;
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
                    if (idxName >= cols.length) continue;
                    final name = cols[idxName].trim();
                    if (name.isEmpty) continue;
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
                  throw Exception(
                    'Numbers formatı için lütfen dosyayı CSV’ye dışa aktarın.',
                  );
                }
              } else {
                throw Exception('Desteklenmeyen dosya türü.');
              }

              setDialogState(() {
                parsed = rows;
              });
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
            if (leagueId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Takımın leagueId alanı bulunamadı.'),
                ),
              );
              return;
            }
            if (parsed.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Yüklenecek kayıt bulunamadı.')),
              );
              return;
            }
            setDialogState(() => busy = true);
            try {
              final actionId =
                  'squad_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
              await approvalService.submitPendingAction(
                PendingAction(
                  actionId: actionId,
                  actionType: 'squad_upload',
                  leagueId: leagueId,
                  teamId: teamId,
                  submittedBy: 'admin',
                  payload: {
                    'teamName': teamName,
                    'fileName': pickedFileName,
                    'players': parsed,
                  },
                ),
              );

              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Onaya gönderildi.'),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Hata: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            } finally {
              setDialogState(() => busy = false);
            }
          }

          return AlertDialog(
            title: Text('Excel ile Toplu Yükleme • $teamName'),
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
}

class ArchiveDecoder {
  ArchiveDecoder(this.bytes);
  final List<int> bytes;

  Future<String?> findFirstCsv() async {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) return null;
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
      } else if (score == bestScore && best != null) {
        if (f.size > 0 && f.size < best!.size) best = f;
      }
    }
    if (best == null) return null;
    final content = best!.content;
    if (content is! List<int>) return null;
    var decoded = utf8.decode(content, allowMalformed: true);
    if (decoded.isNotEmpty && decoded.codeUnitAt(0) == 0xFEFF) {
      decoded = decoded.substring(1);
    }
    return decoded;
  }
}

class EditTeamScreen extends StatefulWidget {
  final String teamId;
  final Map<String, dynamic> data;
  const EditTeamScreen({super.key, required this.teamId, required this.data});

  @override
  State<EditTeamScreen> createState() => _EditTeamScreenState();
}

class _EditTeamScreenState extends State<EditTeamScreen> {
  late TextEditingController _nameController;
  late TextEditingController _foundedController;
  late TextEditingController _managerController;
  XFile? _newLogo;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.data['name']);
    _foundedController = TextEditingController(
      text: (widget.data['foundedYear'] ?? widget.data['founded'] ?? '')
          .toString()
          .trim(),
    );
    _managerController = TextEditingController(
      text: (widget.data['managerName'] ?? widget.data['manager'] ?? '')
          .toString()
          .trim(),
    );
  }

  Future<void> _update() async {
    setState(() => _isLoading = true);
    try {
      String logoUrl = widget.data['logoUrl'] ?? '';
      if (_newLogo != null) {
        final uploaded = await ImgBBUploadService().uploadImage(
          File(_newLogo!.path),
        );
        if (uploaded != null) {
          logoUrl = uploaded;
        } else {
          throw Exception('Logo yüklenemedi.');
        }
      }

      await DatabaseService().updateTeam(widget.teamId, {
        'name': _nameController.text.trim(),
        'logoUrl': logoUrl,
        'foundedYear': _foundedController.text.trim(),
        'managerName': _managerController.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) setState(() => _newLogo = picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentLogoUrl = widget.data['logoUrl'] ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Takımı Düzenle')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      children: [
                        Center(
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 64,
                                backgroundColor:
                                    cs.primary.withValues(alpha: 0.10),
                                backgroundImage: _newLogo != null
                                    ? FileImage(File(_newLogo!.path))
                                          as ImageProvider
                                    : (currentLogoUrl.isNotEmpty
                                          ? NetworkImage(currentLogoUrl)
                                          : null),
                                child:
                                    (_newLogo == null && currentLogoUrl.isEmpty)
                                        ? Icon(
                                            Icons.groups,
                                            size: 46,
                                            color: cs.primary,
                                          )
                                        : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: CircleAvatar(
                                  backgroundColor: cs.primary,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                    ),
                                    onPressed: _pickLogo,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: 'Takım Adı'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _foundedController,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Kuruluş Tarihi'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _managerController,
                          decoration:
                              const InputDecoration(labelText: 'Takım Sorumlusu'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _update,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Bilgileri Güncelle'),
                ),
              ],
            ),
    );
  }
}
