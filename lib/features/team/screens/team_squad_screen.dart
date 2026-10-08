import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../auth/widgets/phone_input.dart';
import '../../player/consent/consent_service.dart';
import '../../player/consent/consent_widgets.dart';
import 'package:flutter/services.dart';
import 'package:football_tournament/core/widgets/custom_bottom_sheet_dropdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../tournament/models/league.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../../match/models/match.dart';
import '../../player/widgets/player_card.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/panel_scope.dart';
import '../../../core/services/image_upload_service.dart';
import '../models/team.dart';
import '../services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../services/supabase/supabase_team_service.dart';
import '../../../core/utils/resilient_stream.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../../core/widgets/master_class_app_bar.dart';
import '../../../core/widgets/web_safe_image.dart';
import 'package:football_tournament/core/widgets/picked_image.dart';
import 'package:football_tournament/core/widgets/admin_form.dart';
import '../../../core/utils/string_utils.dart';
import '../../share/poster_share.dart';
import '../../share/squad_poster.dart';
import '../../../core/utils/team_colors.dart';
import '../widgets/team_page_tabs.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

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

Future<void> showSquadBulkUploadDialog({
  required BuildContext context,
  required String leagueId,
  required String teamId,
  required String teamName,
}) async {
  final lid = leagueId.trim();
  final tid = teamId.trim();
  if (lid.isEmpty || tid.isEmpty) return;

  bool busy = false;
  String? pickedFileName;
  List<Map<String, dynamic>> parsed = const [];
  int skippedEmpty = 0;
  int skippedShort = 0;
  int skippedNoName = 0;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
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
            if (!dialogContext.mounted) return;
            ScaffoldMessenger.of(
              dialogContext,
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

        int? findIndex(Map<String, int> headerToIndex, List<String> variants) {
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
            r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$',
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
          return null;
        }

        int? yearFromBirthDate(String? birthDate) {
          final s = (birthDate ?? '').trim();
          if (s.isEmpty) return null;
          final m = RegExp(r'^\d{2}/\d{2}/(\d{4})$').firstMatch(s);
          if (m == null) return null;
          return int.tryParse(m.group(1)!);
        }

        Future<void> pickAndParse() async {
          setDialogState(() => busy = true);
          skippedEmpty = 0;
          skippedShort = 0;
          skippedNoName = 0;
          try {
            final picked = await FilePicker.pickFiles(
              type: FileType.custom,
              allowedExtensions: const ['xlsx', 'xls', 'csv', 'numbers'],
            );
            if (picked.isEmpty) return;
            final f = picked.first;
            pickedFileName = f.name;

            final bytes = await f.readAsBytes();
            if (bytes.isEmpty) {
              throw Exception('Dosya okunamadı.');
            }

            List<Map<String, dynamic>> rows;
            final lower = f.name.toLowerCase();
            if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
              final excel = Excel.decodeBytes(bytes);
              final sheetName = excel.tables.keys.isEmpty
                  ? null
                  : excel.tables.keys.first;
              if (sheetName == null) {
                throw Exception('Excel sayfası bulunamadı.');
              }
              final table = excel.tables[sheetName];
              if (table == null) throw Exception('Excel sayfası okunamadı.');

              final data = table.rows;
              if (data.isEmpty) throw Exception('Dosyada satır yok.');
              final header = data.first;
              final headerToIndex = <String, int>{};
              for (var i = 0; i < header.length; i++) {
                final v = header[i]?.value?.toString() ?? '';
                final k = normalizeHeader(v);
                if (k.isNotEmpty) headerToIndex[k] = i;
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
                throw Exception('Excel sütunları şablonla uyuşmuyor.');
              }

              rows = [];
              for (var i = 1; i < data.length; i++) {
                final cols = data[i];
                if (cols.isEmpty) {
                  skippedEmpty++;
                  continue;
                }
                if (cols.length < 2 || idxName >= cols.length) {
                  skippedShort++;
                  continue;
                }
                final name = (cols[idxName]?.value?.toString() ?? '').trim();
                if (name.isEmpty) {
                  skippedNoName++;
                  continue;
                }
                final number = (idxNo != null && idxNo < cols.length)
                    ? (cols[idxNo]?.value?.toString() ?? '').trim()
                    : '';
                final position = idxPos < cols.length
                    ? (cols[idxPos]?.value?.toString() ?? '').trim()
                    : '';
                final birthRaw = idxBirth < cols.length
                    ? cols[idxBirth]?.value
                    : null;
                final foot = idxFoot < cols.length
                    ? (cols[idxFoot]?.value?.toString() ?? '').trim()
                    : '';
                final birthDate = birthDateFrom(birthRaw);
                final birthYear = yearFromBirthDate(birthDate);
                rows.add({
                  'number': number,
                  'name': name,
                  'position': position,
                  'birthDate': birthDate,
                  'birthYear': birthYear,
                  'preferredFoot': foot.isEmpty ? null : foot,
                });
              }
            } else if (lower.endsWith('.csv') || lower.endsWith('.numbers')) {
              final content = utf8.decode(bytes, allowMalformed: true);
              final lines = const LineSplitter().convert(content);
              if (lines.isEmpty) throw Exception('Dosyada satır yok.');
              final headers = lines.first.split(',');
              final headerToIndex = <String, int>{};
              for (var i = 0; i < headers.length; i++) {
                final k = normalizeHeader(headers[i]);
                if (k.isNotEmpty) headerToIndex[k] = i;
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
                final foot = idxFoot < cols.length ? cols[idxFoot].trim() : '';
                final birthDate = birthDateFrom(birthRaw);
                final birthYear = yearFromBirthDate(birthDate);
                rows.add({
                  'number': number,
                  'name': name,
                  'position': position,
                  'birthDate': birthDate,
                  'birthYear': birthYear,
                  'preferredFoot': foot.isEmpty ? null : foot,
                });
              }
            } else {
              throw Exception('Desteklenmeyen dosya türü.');
            }

            setDialogState(() => parsed = rows);
          } catch (e) {
            if (!dialogContext.mounted) return;
            ScaffoldMessenger.of(
              dialogContext,
            ).showSnackBar(SnackBar(content: Text('Hata: $e')));
          } finally {
            setDialogState(() => busy = false);
          }
        }

        // Toplu yükleme sezon ve telefon bilgisiyle yeniden kurgulanacak;
        // o zamana kadar kayıtlar gönderilmez (eski akış Firestore'a
        // yazıyordu ve onaylanan oyuncular uygulamada görünmüyordu).
        Future<void> submitForApproval() async {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            const SnackBar(
              content: Text(
                'Toplu kadro yükleme yeniden düzenleniyor. '
                'Şimdilik oyuncuları tek tek ekleyin.',
              ),
            ),
          );
        }

        Widget action({
          required IconData icon,
          required String label,
          required String value,
          required VoidCallback? onTap,
        }) => AdminFieldRow(
          icon: icon,
          label: label,
          enabled: onTap != null,
          onTap: onTap,
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white54,
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: AdminDialogCloseOverlay(
              onClose: busy ? null : () => Navigator.pop(dialogContext),
              child: Container(
                decoration: adminDialogDecoration(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AdminDialogHeader(
                        icon: Icons.upload_file_rounded,
                        title: 'Toplu Kadro Yükle',
                        subtitle: teamName,
                      ),
                      const SizedBox(height: 18),
                      AdminFieldGroup(
                        children: [
                          action(
                            icon: Icons.download_rounded,
                            label: 'Örnek Şablon',
                            value: 'Şablonu indir',
                            onTap: busy ? null : downloadTemplate,
                          ),
                          action(
                            icon: Icons.upload_file_rounded,
                            label: 'Dosya (.xls / .xlsx / .csv / .numbers)',
                            value: pickedFileName ?? 'Dosya seçin',
                            onTap: busy ? null : pickAndParse,
                          ),
                        ],
                      ),
                      if (pickedFileName != null) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final (label, color) in [
                              ('Okunan: ${parsed.length}', kAdminAccent),
                              (
                                'Atlanan: '
                                    '${skippedEmpty + skippedShort + skippedNoName}',
                                kAdminAmber,
                              ),
                            ])
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: color.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (busy) ...[
                        const SizedBox(height: 14),
                        const LinearProgressIndicator(color: kAdminAccent),
                      ],
                      const SizedBox(height: 22),
                      AdminPrimaryButton(
                        label: 'ONAYA GÖNDER',
                        onPressed: busy ? null : submitForApproval,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _TeamSquadScreenState extends State<TeamSquadScreen> {
  final _consentCache = ConsentStatusCache();
  final ITeamService _teamService = ServiceLocator.teamService;

  SupabaseTeamService? get _sbTeamService =>
      _teamService is SupabaseTeamService ? _teamService : null;

  final _rosterSearchController = TextEditingController();
  String _rosterQuery = '';

  final Map<String, String> _playerPhotoUrlByPhone = {};
  final Set<String> _playerPhotoFetchInFlight = {};

  bool _isTeamManager = false;
  bool _isLoadingTournaments = true;

  /// Üst bant altındaki sekme: 0 Kadro, 1 Fikstür, 2 İstatistik.
  int _tab = 0;

  /// Takım renkleri (üst bandın zemini); bir kez okunur.
  late final Future<(String?, String?)> _teamColors = () async {
    try {
      final r = await Supabase.instance.client
          .from('teams')
          .select('first_color, second_color')
          .eq('id', widget.teamId)
          .maybeSingle();
      return (r?['first_color'] as String?, r?['second_color'] as String?);
    } catch (_) {
      return (null, null);
    }
  }();
  List<League> _teamTournaments = [];
  String? _selectedTournamentId;
  Stream<List<PlayerModel>>? _playersStream;
  String? _playersStreamTournamentId;

  void _setPlayersStreamForTournament(String tournamentId) {
    final tid = tournamentId.trim();
    if (tid.isEmpty) {
      _playersStreamTournamentId = null;
      _playersStream = null;
      return;
    }
    _playersStreamTournamentId = tid;
    _playersStream = _teamService.watchPlayers(
      teamId: widget.teamId,
      tournamentId: tid,
      caller: 'TeamSquadScreen',
    );
  }

  void _refreshPlayersStreamForTournament(String tournamentId) {
    if (!mounted) return;
    setState(() => _setPlayersStreamForTournament(tournamentId));
  }

  Future<void> _confirmAndRemovePlayer(
    PlayerModel p,
    String tournamentId,
  ) async {
    final tId = tournamentId.trim();
    // Telefonu olmayan oyuncular id ile bulunur.
    final key = (p.phone ?? '').trim().isNotEmpty ? p.phone!.trim() : p.id;
    if (tId.isEmpty || key.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Silme için eksik bilgi.')));
      return;
    }
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Futbolcu Sil',
      message: '${p.name} oyuncusunu bu takımdan kaldırmak istiyor musunuz?',
      icon: Icons.person_remove_outlined,
    );
    if (ok != true || !mounted) return;
    try {
      await _deleteRosterPlayer(
        tournamentId: tId,
        teamId: widget.teamId,
        playerPhone: key,
      );
      if (!mounted) return;
      _refreshPlayersStreamForTournament(tId);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kadrodan kaldırıldı.')));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Silinemedi: $msg')));
    }
  }

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

  Future<void> _openExistingPlayerPicker({
    required String leagueId,
    required String teamId,
  }) async {
    final svc = _sbTeamService;
    if (svc == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu özellik Supabase modunda kullanılabilir.'),
        ),
      );
      return;
    }

    final lid = leagueId.trim();
    final tid = teamId.trim();
    if (lid.isEmpty || tid.isEmpty) return;

    final added = await showAdminPopup<bool>(
      context: context,
      builder: (_) => _SeasonPlayerPicker(
        service: svc,
        seasonId: lid,
        teamId: tid,
        displayPosition: _displayPosition,
        normalizeUrl: _normalizeUrl,
      ),
    );
    if (added != true || !mounted) return;
    _refreshPlayersStreamForTournament(lid);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Seçilen futbolcular kadroya eklendi.')),
    );
  }

  Future<void> _promptJerseyNumberEdit({
    required PlayerModel player,
    required String leagueId,
    required String teamId,
  }) async {
    final svc = _sbTeamService;
    if (svc == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu özellik Supabase modunda kullanılabilir.'),
        ),
      );
      return;
    }

    final lid = leagueId.trim();
    final tid = teamId.trim();
    if (lid.isEmpty || tid.isEmpty) return;

    final input = await showAdminTextInputDialog(
      context: context,
      title: 'Forma No',
      icon: Icons.checkroom_rounded,
      subtitle: player.name.trim(),
      label: 'Forma Numarası',
      fieldIcon: Icons.numbers_rounded,
      initialValue: (player.number ?? '').trim(),
      hint: 'Örn. 10',
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
    );
    if (input == null) return;

    final raw = input.replaceAll(RegExp(r'\D'), '').trim();
    final n = int.tryParse(raw);
    if (n == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Forma numarası geçersiz.')));
      return;
    }

    try {
      await svc.updateJerseyNumber(player.id, tid, lid, n);
      if (!mounted) return;
      _refreshPlayersStreamForTournament(lid);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Forma numarası güncellendi.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Güncellenemedi: $msg')));
    }
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

  /// Takım renkleriyle kadro afişi hazırlar.
  Future<void> _shareSquadPoster({
    required String teamName,
    required String tournamentId,
    required List<PlayerModel> players,
  }) async {
    String? first, second;
    try {
      final row = await Supabase.instance.client
          .from('teams')
          .select('first_color, second_color')
          .eq('id', widget.teamId)
          .maybeSingle();
      first = row?['first_color']?.toString();
      second = row?['second_color']?.toString();
    } catch (_) {
      // Renk okunamazsa varsayılan palet kullanılır.
    }
    if (!mounted) return;

    League? league;
    for (final t in _teamTournaments) {
      if (t.id == tournamentId.trim()) league = t;
    }
    final groups = <String, List<PosterPlayer>>{
      for (final sec in _positionSections(players))
        sec.key: [
          for (final p in sec.value)
            () {
              final parts = p.name.trim().split(RegExp(r'\s+'));
              return PosterPlayer(
                firstName: parts.length > 1
                    ? parts.sublist(0, parts.length - 1).join(' ')
                    : parts.first,
                lastName: parts.length > 1 ? parts.last : '',
                number: (p.number ?? '').trim(),
              );
            }(),
        ],
    };
    final teamLogo = widget.teamLogoUrl.trim();
    final leagueLogo = (league?.logoUrl ?? '').trim();

    await showPosterPreview(
      context: context,
      fileName: 'kadro_${teamName.replaceAll(RegExp(r'\s+'), '_')}',
      imageUrls: [teamLogo, leagueLogo],
      poster: SquadPoster(
        teamName: teamName,
        teamLogo: teamLogo,
        leagueName: league?.name ?? _tournamentNameById(tournamentId),
        leagueLogo: leagueLogo,
        seasonName: '',
        palette: TeamPalette.of(first, second),
        groups: groups,
      ),
    );
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
    // GG/AA/YYYY, GG-AA-YYYY, GG.AA.YYYY veya veritabanındaki YYYY-AA-GG.
    int dd, mm, yyyy;
    final dmy = RegExp(r'^(\d{2})[./-](\d{2})[./-](\d{4})$').firstMatch(s);
    final ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (dmy != null) {
      dd = int.parse(dmy.group(1)!);
      mm = int.parse(dmy.group(2)!);
      yyyy = int.parse(dmy.group(3)!);
    } else if (ymd != null) {
      yyyy = int.parse(ymd.group(1)!);
      mm = int.parse(ymd.group(2)!);
      dd = int.parse(ymd.group(3)!);
    } else {
      return null;
    }
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
    final cachedPhoto = phone.isEmpty
        ? ''
        : (_playerPhotoUrlByPhone[phone] ?? '').trim();

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          backgroundColor: Colors.transparent,
          child: FutureBuilder<PlayerModel?>(
            future: phone.isEmpty
                ? Future.value(null)
                : _teamService.getPlayerByPhoneOnce(phone),
            builder: (context, snap) {
              final profile = snap.data;
              final resolvedPhotoUrl =
                  ((profile?.photoUrl ?? '').trim().isNotEmpty)
                  ? (profile!.photoUrl ?? '').trim()
                  : cachedPhoto;
              final resolvedName = rosterPlayer.name.trim().isNotEmpty
                  ? rosterPlayer.name.trim()
                  : (profile?.name ?? '').trim();
              final resolvedBirthDate =
                  (profile?.birthDate ?? rosterPlayer.birthDate ?? '').trim();
              final mainPos =
                  (profile?.mainPosition ?? rosterPlayer.mainPosition ?? '')
                      .trim();
              final subPos = (profile?.position ?? rosterPlayer.position ?? '')
                  .trim();

              String displayPos() {
                final sub = subPos;
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
                if (mainPos.isNotEmpty) return mainPos;
                return '-';
              }

              final number = (rosterPlayer.number ?? profile?.number ?? '')
                  .toString()
                  .trim();
              final initialSeasonId =
                  (_selectedTournamentId ?? widget.tournamentId)
                      .toString()
                      .trim();

              return PlayerCard(
                playerPhone: phone.isEmpty ? rosterPlayer.id : phone,
                name: resolvedName,
                number: number,
                photoUrl: resolvedPhotoUrl,
                position: displayPos(),
                birthDate: resolvedBirthDate,
                height: profile?.height ?? rosterPlayer.height,
                weight: profile?.weight ?? rosterPlayer.weight,
                seasons: _teamTournaments,
                initialSeasonId: initialSeasonId,
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

        _teamService
            .getPlayerByPhoneOnce(phone)
            .then((player) {
              final url = (player?.photoUrl ?? '').trim();
              if (!mounted) return;
              setState(() {
                _playerPhotoUrlByPhone[phone] = url;
                _playerPhotoFetchInFlight.remove(phone);
              });
            })
            .catchError((_) {
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
    final widgetTournamentId = widget.tournamentId.trim();
    if (widgetTournamentId.isNotEmpty) {
      _setPlayersStreamForTournament(widgetTournamentId);
    }
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
        if (selected != null) {
          _setPlayersStreamForTournament(selected);
        } else {
          _playersStreamTournamentId = null;
          _playersStream = null;
        }
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
        _playersStreamTournamentId = null;
        _playersStream = null;
      });
    }
  }

  /// Kadroyu düzenleyebilir mi: bu takımın sorumlusu (team_managers), ya da
  /// sezonun kurucu başkanı / takımın bölgesinin sorumlusu (veritabanındaki
  /// kadro yazma kuralıyla aynı: owns_season_team). Başka takımın sorumlusu
  /// ya da oyuncusu düzenleyemez. Admin ayrıca [build]'de.
  Future<void> _checkIfTeamManagerForTournament(String tournamentId) async {
    final session = AppSession.of(context).value;
    final seasonId = tournamentId.trim();
    if (session.isAdmin || seasonId.isEmpty) {
      if (_isTeamManager) setState(() => _isTeamManager = false);
      return;
    }
    var allowed = session.managesTeam(seasonId, widget.teamId);
    if (!allowed && session.hasManagementPanel) {
      try {
        allowed =
            await Supabase.instance.client.rpc(
              'owns_season_team',
              params: {'p_season_id': seasonId, 'p_team_id': widget.teamId},
            ) ==
            true;
      } catch (_) {
        allowed = false;
      }
    }
    if (!mounted) return;
    setState(() => _isTeamManager = allowed);
  }

  Future<String?> _ensureSelectedTournament() async {
    final selected = _selectedTournamentId?.trim();
    if (selected != null && selected.isNotEmpty) {
      return selected;
    }

    final widgetTournamentId = widget.tournamentId.trim();
    if (widgetTournamentId.isNotEmpty) {
      setState(() {
        _selectedTournamentId = widgetTournamentId;
        _setPlayersStreamForTournament(widgetTournamentId);
      });
      await _checkIfTeamManagerForTournament(widgetTournamentId);
      return widgetTournamentId;
    }

    if (_teamTournaments.isEmpty && !_isLoadingTournaments) {
      await _loadTeamTournaments();
    }

    if (_teamTournaments.length == 1) {
      final tournamentId = _teamTournaments.first.id;
      setState(() {
        _selectedTournamentId = tournamentId;
        _setPlayersStreamForTournament(tournamentId);
      });
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

    setState(() {
      _selectedTournamentId = selectedTournament;
      _setPlayersStreamForTournament(selectedTournament);
    });
    await _checkIfTeamManagerForTournament(selectedTournament);
    return selectedTournament;
  }

  Future<void> _openPlayerForm({PlayerModel? editing}) async {
    final tournamentId = await _ensureSelectedTournament();
    if (tournamentId == null || !mounted) return;

    final saved = await showPlayerFormPopup(
      context,
      PlayerFormScreen(
        teamId: widget.teamId,
        tournamentId: tournamentId,
        normalizeUrl: _normalizeUrl,
        editing: editing,
      ),
    );

    if (!mounted) return;

    if (saved == true) {
      _refreshPlayersStreamForTournament(tournamentId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editing == null ? 'Futbolcu eklendi.' : 'Futbolcu güncellendi.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleTeam = widget.teamName.trim();
    final session = AppSession.of(context).value;
    final isAdmin = session.isAdmin;
    final widgetTournamentId = widget.tournamentId.trim();
    final effectiveTournamentId =
        (_selectedTournamentId != null &&
            _selectedTournamentId!.trim().isNotEmpty)
        ? _selectedTournamentId!.trim()
        : (_teamTournaments.isEmpty && widgetTournamentId.isNotEmpty
              ? widgetTournamentId
              : null);
    final Stream<List<PlayerModel>>? playersStream =
        effectiveTournamentId == null
        ? null
        : (_playersStreamTournamentId == effectiveTournamentId &&
              _playersStream != null)
        ? _playersStream
        : () {
            final tid = effectiveTournamentId;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (tid.trim().isEmpty) return;
              if (_playersStreamTournamentId == tid && _playersStream != null) {
                return;
              }
              setState(() => _setPlayersStreamForTournament(tid));
            });
            return _teamService.watchPlayers(
              teamId: widget.teamId,
              tournamentId: effectiveTournamentId,
              caller: 'TeamSquadScreen',
            );
          }();
    final canAdd = effectiveTournamentId != null && (isAdmin || _isTeamManager);
    _tournamentNameById(effectiveTournamentId ?? widgetTournamentId);

    // Bir üst menüyle (sezon/grup/takım listeleri) aynı tema: koyu zemin,
    // soluk saha görseli ve şeffaf başlık.
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Turnuva seçilmeden bant çizilmez; geri düğmesi yine görünsün.
          if (effectiveTournamentId == null)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  tooltip: 'Geri',
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                if (_isLoadingTournaments)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: effectiveTournamentId == null
                      ? Center(
                          child: Text(
                            'Lütfen turnuva seçin.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      : StreamBuilder<List<PlayerModel>>(
                          stream: playersStream,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Hata: ${snapshot.error}'),
                              );
                            }
                            final allPlayers =
                                snapshot.data ?? const <PlayerModel>[];
                            _prefetchPlayerPhotos(allPlayers);
                            final q = _rosterQuery;
                            final players = q.isEmpty
                                ? allPlayers
                                : allPlayers
                                      .where(
                                        (p) => p.name.toLowerCase().contains(q),
                                      )
                                      .toList();

                            return ListView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                24,
                              ),
                              children: [
                                FutureBuilder<(String?, String?)>(
                                  future: _teamColors,
                                  builder: (context, colorSnap) =>
                                      _SquadSummaryCard(
                                        firstColor: colorSnap.data?.$1,
                                        secondColor: colorSnap.data?.$2,
                                        teamName: titleTeam,
                                        logoUrl: widget.teamLogoUrl,
                                        // Üst satır yerine bandın köşelerinde.
                                        onBack: () =>
                                            Navigator.of(context).maybePop(),
                                        onAdd: !canAdd
                                            ? null
                                            : () => _openExistingPlayerPicker(
                                                leagueId: effectiveTournamentId,
                                                teamId: widget.teamId,
                                              ),
                                        subtitle: _tournamentNameById(
                                          effectiveTournamentId,
                                        ),
                                        players: allPlayers,
                                        ageOf: (p) =>
                                            _ageFromBirthDate(p.birthDate),
                                        // Paylaş şimdilik yalnızca admin ve
                                        // turnuva sahibine açık.
                                        onShare:
                                            allPlayers.isEmpty ||
                                                !AppSession.of(
                                                  context,
                                                ).value.canManageLeague(
                                                  effectiveTournamentId,
                                                )
                                            ? null
                                            : () => _shareSquadPoster(
                                                teamName: titleTeam,
                                                tournamentId:
                                                    effectiveTournamentId,
                                                players: allPlayers,
                                              ),
                                      ),
                                ),
                                const SizedBox(height: 8),
                                TeamPageTabBar(
                                  index: _tab,
                                  onChanged: (i) => setState(() => _tab = i),
                                ),
                                if (_tab == 1)
                                  TeamFixtureTab(
                                    seasonId: effectiveTournamentId,
                                    teamId: widget.teamId,
                                    teamName: titleTeam,
                                  ),
                                if (_tab == 2)
                                  TeamStatsTab(
                                    seasonId: effectiveTournamentId,
                                    teamId: widget.teamId,
                                    players: allPlayers,
                                  ),
                                if (_tab == 0) ...[
                                  FutureBuilder(
                                    future: _consentCache.of(
                                      allPlayers.map((p) => p.id),
                                    ),
                                    builder: (context, snap) {
                                      final st = snap.data ?? const {};
                                      if (st.values.every((s) => s.complete)) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: ConsentSummaryBanner(
                                          statuses: st,
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _rosterSearchController,
                                    style: const TextStyle(color: Colors.white),
                                    onChanged: (v) => setState(
                                      () =>
                                          _rosterQuery = v.trim().toLowerCase(),
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Futbolcu ara',
                                      prefixIcon: const Icon(
                                        Icons.search,
                                        color: _squadMuted,
                                      ),
                                      filled: true,
                                      fillColor: const Color(
                                        0xFF1E293B,
                                      ).withValues(alpha: 0.9),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                          color: _squadAccent,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (players.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 32),
                                      child: Text(
                                        allPlayers.isEmpty
                                            ? 'Henüz kadro girişi yapılmamış.'
                                            : 'Aramanıza uygun futbolcu bulunamadı.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: _squadMuted),
                                      ),
                                    )
                                  else
                                    for (final section in _positionSections(
                                      players,
                                    ))
                                      _SquadSection(
                                        title: section.key,
                                        count: section.value.length,
                                        children: [
                                          for (
                                            var i = 0;
                                            i < section.value.length;
                                            i++
                                          )
                                            _squadRow(
                                              section.value[i],
                                              first: i == 0,
                                              canAdd: canAdd,
                                              tournamentId:
                                                  effectiveTournamentId,
                                            ),
                                        ],
                                      ),
                                ],
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _squadRow(
    PlayerModel p, {
    required bool first,
    required bool canAdd,
    required String tournamentId,
  }) {
    final number = (p.number ?? '').trim();
    final age = _ageFromBirthDate(p.birthDate);
    final position = (p.mainPosition ?? p.position ?? '').trim();
    final sub = [
      if (position.isNotEmpty) position,
      if (age != null) '$age yaş',
      if (number.isEmpty) 'forma no yok',
    ].join(' · ');
    void editJersey() => _promptJerseyNumberEdit(
      player: p,
      leagueId: tournamentId,
      teamId: widget.teamId,
    );

    return InkWell(
      onTap: () => _openPlayerCard(p),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          border: first
              ? null
              : Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
        ),
        child: Row(
          children: [
            _JerseyBadge(number: number, onTap: canAdd ? editJersey : null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(color: _squadMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            // Düzenleme menüsü yalnız admin ve kadroyu yönetebilenlere
            // (takım sorumlusu, kurucu başkan, bölge sorumlusu).
            if (canAdd)
              PopupMenuButton<String>(
                tooltip: 'Diğer işlemler',
                icon: const Icon(Icons.menu_rounded, color: _squadMuted),
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      _openPlayerForm(editing: p);
                    case 'jersey':
                      editJersey();
                    case 'remove':
                      _confirmAndRemovePlayer(p, tournamentId);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: _MenuRow(icon: Icons.edit_outlined, text: 'Düzenle'),
                  ),
                  const PopupMenuItem(
                    value: 'jersey',
                    child: _MenuRow(
                      icon: Icons.tag_rounded,
                      text: 'Forma no değiştir',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: _MenuRow(
                      icon: Icons.person_remove_outlined,
                      text: 'Kadrodan çıkar',
                      color: Color(0xFFF87171),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
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
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Futbolcu ekle / güncelle formunu ortada açılan temalı popup olarak açar.
/// Dışarı dokunmak kaydetmeden kapatır. Kaydedilirse true döner.
Future<bool?> showPlayerFormPopup(BuildContext context, PlayerFormScreen form) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: AdminDialogCloseOverlay(
        onClose: () => Navigator.pop(ctx),
        child: Container(
          height: MediaQuery.of(ctx).size.height * 0.9,
          clipBehavior: Clip.antiAlias,
          decoration: adminDialogDecoration(),
          child: form,
        ),
      ),
    ),
  );
}

class PlayerFormScreen extends StatefulWidget {
  const PlayerFormScreen({
    super.key,
    this.teamId,
    this.tournamentId,
    this.editing,
    this.standalone = false,
    String Function(String raw)? normalizeUrl,
  }) : normalizeUrl = normalizeUrl ?? _defaultNormalizeUrl;

  final String? teamId;
  final String? tournamentId;
  final PlayerModel? editing;
  final bool standalone;
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
  final _imageUploadService = SupabaseImageUploadService();

  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _identityNoController = TextEditingController();
  final _numberController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _phoneController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();

  static const String _unsetOption = 'Seçilmedi';

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
  static const _feet = <String>['Sağ', 'Sol', 'Her İkisi'];

  String _mainPosition = _unsetOption;
  String _subPosition = _unsetOption;
  String _preferredFoot = '';
  String? _activePlayerId;
  String? _existingPhotoUrl;
  String? _implicitPhoneKey;
  XFile? _pickedPhoto;
  bool _removePhoto = false;
  bool _saving = false;

  bool get _isMainPositionSelected =>
      _mainPosition.trim().isNotEmpty && _mainPosition != _unsetOption;

  String _birthDateToDisplay(String? raw) => birthDateDbToUi(raw);

  Future<void> _pickBirthDate() async {
    final current = DateTime.tryParse(
      _birthDateToDb(_birthDateController.text) ?? '',
    );
    final now = DateTime.now();
    final picked = await showAppDatePicker(
      context: context,
      initialDate: current ?? DateTime(1990, 1, 1),
      firstYear: 1940,
      lastYear: now.year,
      title: 'Doğum Tarihi',
    );
    if (picked == null || !mounted) return;
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    setState(() => _birthDateController.text = birthDateDbToUi(iso));
  }

  String? _birthDateToDb(String raw) => birthDateUiToDb(raw);

  String _deriveMainPosition(String? main, String? subOrLegacy) {
    final m = (main ?? '').trim();
    if (_subPositionsByMain.containsKey(m)) return m;
    final s = (subOrLegacy ?? '').trim();
    if (s.isEmpty) return _unsetOption;
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
    return _unsetOption;
  }

  String _deriveSubPosition(String main, String? subOrLegacy) {
    if (main.trim().isEmpty || main == _unsetOption) return _unsetOption;
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
      _surnameController.text = parts.length <= 1
          ? ''
          : parts.sublist(1).join(' ');
      _numberController.text = (e.number ?? '').toString();
      _birthDateController.text = _birthDateToDisplay(e.birthDate);
      _mainPosition = _deriveMainPosition(e.mainPosition, e.position);
      _subPosition = _deriveSubPosition(_mainPosition, e.position);
      final pf = (e.preferredFoot ?? '').trim();
      _preferredFoot = _feet.contains(pf) ? pf : '';
      _heightController.text = (e.height ?? '').toString();
      _weightController.text = (e.weight ?? '').toString();
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _hydrateExistingPhotoFromIdentity(),
    );
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

  // Sıkıştırma yükleme servisinde yapılır; burada yalnızca seçilir. Dosya
  // sistemi kullanılmaz (web'de çalışmıyordu).
  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    if (await picked.length() > 10 * 1024 * 1024) {
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
    if (!mounted) return;
    setState(() {
      _pickedPhoto = picked;
      _removePhoto = false;
    });
  }

  String _rawPhone() {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return digits;
  }

  bool _isValidBirthDate(String s) {
    final v = s.trim();
    if (v.isEmpty) return true;
    return _birthDateToDb(v) != null;
  }

  bool _isValidPhoneRaw(String raw) {
    if (raw.isEmpty) return true;
    if (!RegExp(r'^\d{10}$').hasMatch(raw)) return false;
    return true;
  }

  String _generateNoPhoneKey() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random().nextInt(1 << 31);
    return 'no_phone_${ts}_$rnd';
  }

  Future<void> _save() async {
    final nationalId = _identityNoController.text
        .replaceAll(RegExp(r'\D'), '')
        .trim();
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
    final jerseyInt = number.isEmpty ? null : int.tryParse(number);
    if (number.isNotEmpty && jerseyInt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Forma no sadece sayı olmalı.')),
      );
      return;
    }

    final birthDate = _birthDateController.text.trim();
    if (!_isValidBirthDate(birthDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Doğum tarihi DD-MM-YYYY formatında olmalı.'),
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
    final isEditing = widget.editing != null;
    // Telefonu olmayan mevcut oyuncu düzenlenirken sahte "no_phone_" anahtarı
    // üretilip telefon alanına yazılmaz; oyuncu id'si ile işlem yapılır.
    final editingWithoutPhone =
        isEditing && rawPhone.isEmpty && _implicitPhoneKey == null;
    final keyPhone = rawPhone.isNotEmpty
        ? rawPhone
        : editingWithoutPhone
        ? widget.editing!.id
        : (_implicitPhoneKey ??= _generateNoPhoneKey());
    final phoneToStore = editingWithoutPhone ? null : keyPhone;

    setState(() => _saving = true);
    try {
      final sbTeamService = _teamService is SupabaseTeamService
          ? _teamService
          : null;

      String? uploadedPhotoUrl;
      if (_pickedPhoto != null) {
        uploadedPhotoUrl = await _imageUploadService.uploadImage(
          _pickedPhoto!,
          folder: MediaFolder.players,
        );
        if ((uploadedPhotoUrl ?? '').trim().isEmpty) {
          throw Exception('Fotoğraf yüklenemedi, lütfen tekrar deneyin.');
        }
      }

      final resolvedBirthDate = birthDate.isEmpty
          ? null
          : _birthDateToDb(birthDate);
      final resolvedMainPosition = _isMainPositionSelected
          ? _mainPosition
          : null;
      final resolvedSubPosition = _isMainPositionSelected
          ? (_subPosition == _unsetOption ? null : _subPosition)
          : null;
      final updateKey = (widget.editing?.id ?? '').toString().trim().isNotEmpty
          ? widget.editing!.id
          : keyPhone;
      final finalPhotoUrl = uploadedPhotoUrl != null
          ? uploadedPhotoUrl.trim()
          : _removePhoto
          ? null
          : (_existingPhotoUrl ?? '').trim().isEmpty
          ? null
          : (_existingPhotoUrl ?? '').trim();
      if (!isEditing) {
        await _teamService.upsertPlayerIdentity(
          phone: keyPhone,
          name: fullName,
          nationalId: nationalId.isEmpty ? null : nationalId,
          birthDate: resolvedBirthDate,
          mainPosition: resolvedMainPosition,
          preferredFoot: _preferredFoot.trim().isEmpty
              ? null
              : _preferredFoot.trim(),
          height: int.tryParse(
            _heightController.text.replaceAll(RegExp(r'\D'), '').trim(),
          ),
          weight: int.tryParse(
            _weightController.text.replaceAll(RegExp(r'\D'), '').trim(),
          ),
        );
      }
      await _teamService.updatePlayer(
        playerId: updateKey,
        data: {
          'name': firstName,
          'surname': surname,
          'birth_date': resolvedBirthDate,
          'preferred_foot': _preferredFoot.trim().isEmpty
              ? null
              : _preferredFoot.trim(),
          'main_position': resolvedMainPosition,
          'sub_position': resolvedSubPosition,
          'photo_url': finalPhotoUrl,
          'phone': phoneToStore,
          'height': int.tryParse(
            _heightController.text.replaceAll(RegExp(r'\D'), '').trim(),
          ),
          'weight': int.tryParse(
            _weightController.text.replaceAll(RegExp(r'\D'), '').trim(),
          ),
          'national_id': nationalId.isEmpty ? null : nationalId,
        },
      );
      if (!widget.standalone) {
        final teamId = (widget.teamId ?? '').trim();
        final tournamentId = (widget.tournamentId ?? '').trim();
        if (teamId.isNotEmpty && tournamentId.isNotEmpty) {
          await _teamService.upsertRosterEntry(
            tournamentId: tournamentId,
            teamId: teamId,
            playerPhone: keyPhone,
            playerName: fullName,
            jerseyNumber: sbTeamService == null ? number : null,
          );

          if (sbTeamService != null) {
            final currentText = (widget.editing?.number ?? '')
                .toString()
                .trim();
            final currentInt = currentText.isEmpty
                ? null
                : int.tryParse(currentText);
            final jerseyChanged = currentInt != jerseyInt;
            if (jerseyChanged) {
              var pid = (widget.editing?.id ?? '').toString().trim();
              if (pid.isEmpty) {
                final resolved = await _teamService.getPlayerByPhoneOnce(
                  keyPhone,
                );
                pid = (resolved?.id ?? '').toString().trim();
              }
              if (pid.isNotEmpty) {
                await sbTeamService.setJerseyNumber(
                  pid,
                  teamId,
                  tournamentId,
                  jerseyInt,
                );
              }
            }
          }
        }
      }

      // Fotoğraf değiştiyse ya da kaldırıldıysa eski dosyayı sil.
      final oldPhoto = (_existingPhotoUrl ?? '').trim();
      if (isEditing && oldPhoto.isNotEmpty && oldPhoto != finalPhotoUrl) {
        await _imageUploadService.deleteImageByUrl(oldPhoto);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      // Düzenlemede ad/soyad/doğum tarihi başka bir kayıtla çakışırsa da.
      final text =
          msg.contains(kPlayerAlreadyRegistered) ||
              msg.contains('players_identity_uq')
          ? kPlayerAlreadyRegistered
          : msg.contains('players_phone_uq')
          ? 'Bu telefon numarası başka bir futbolcuya kayıtlı.'
          : 'Hata: $msg';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), backgroundColor: Colors.red),
      );
      setState(() => _saving = false);
    }
  }

  Future<void> _pickOption({
    required String title,
    required List<String> items,
    required String? selected,
    required ValueChanged<String> onPicked,
  }) async {
    if (_saving) return;
    final v = await showAdminOptionPicker<String>(
      context: context,
      title: title,
      items: items,
      labelBuilder: (s) => s,
      selected: selected,
    );
    if (v != null && mounted) setState(() => onPicked(v));
  }

  Widget _textRow({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? hint,
    String? prefixText,
    Widget? trailing,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return AdminFieldRow(
      icon: icon,
      label: label,
      trailing: trailing,
      child: TextField(
        controller: controller,
        enabled: !_saving,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textCapitalization: capitalization,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        decoration: adminInlineInputDecoration(
          hint: hint,
          prefixText: prefixText,
        ),
      ),
    );
  }

  /// Dikdörtgen (3:4) fotoğraf önizlemesi; köşedeki düğme fotoğraf seçer.
  Widget _photoCard() {
    final editingUrl = (_existingPhotoUrl ?? '').trim();
    final hasPicked = _pickedPhoto != null;
    final hasPhoto = hasPicked || editingUrl.isNotEmpty;
    const w = 132.0, h = 176.0;

    final Widget image = hasPicked
        ? Image(image: pickedImageProvider(_pickedPhoto!), fit: BoxFit.cover)
        : editingUrl.isNotEmpty
        ? WebSafeImage(
            url: widget.normalizeUrl(editingUrl),
            width: w,
            height: h,
            fit: BoxFit.cover,
            fallbackIconSize: 40,
          )
        : Icon(
            Icons.person_rounded,
            size: 64,
            color: kAdminAccent.withValues(alpha: 0.6),
          );

    return Column(
      children: [
        GestureDetector(
          onTap: _saving ? null : _pickPhoto,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: w,
                height: h,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0F172A), Color(0xFF064E3B)],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: SizedBox.expand(child: Center(child: image)),
              ),
              Positioned(
                right: -8,
                bottom: -8,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: kAdminAccent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF1E293B),
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.photo_camera_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (hasPhoto)
          TextButton.icon(
            onPressed: _saving
                ? null
                : () => setState(() {
                    _pickedPhoto = null;
                    _existingPhotoUrl = null;
                    _removePhoto = true;
                  }),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Fotoğrafı Kaldır'),
            style: TextButton.styleFrom(foregroundColor: kAdminDanger),
          )
        else
          const Text(
            'Fotoğraf eklemek için dokunun',
            style: TextStyle(color: kAdminMuted, fontSize: 12),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
    String? valueOrNull(String v) =>
        v.trim().isEmpty || v == _unsetOption ? null : v;

    // Popup içinde kendi ScaffoldMessenger'ı: uyarılar popup'ın içinde görünür.
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          children: [
            AdminDialogHeader(
              icon: editing
                  ? Icons.manage_accounts_rounded
                  : Icons.person_add_alt_1_rounded,
              title: editing ? 'Futbolcu Güncelle' : 'Futbolcu Ekle',
            ),
            const SizedBox(height: 22),
            Center(child: _photoCard()),
            const SizedBox(height: 16),
            AdminFormSection(
              title: 'Kimlik',
              child: AdminFieldGroup(
                children: [
                  _textRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Ad',
                    controller: _nameController,
                    hint: 'Ad',
                    capitalization: TextCapitalization.words,
                  ),
                  _textRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Soyad',
                    controller: _surnameController,
                    hint: 'Soyad',
                    capitalization: TextCapitalization.words,
                  ),
                  _textRow(
                    icon: Icons.badge_outlined,
                    label: 'Kimlik No',
                    controller: _identityNoController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    hint: '11 haneli',
                  ),
                  _textRow(
                    icon: Icons.cake_outlined,
                    label: 'Doğum Tarihi',
                    controller: _birthDateController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [BirthDateInputFormatter()],
                    hint: 'GG-AA-YYYY',
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.calendar_month_outlined,
                        color: Colors.white54,
                      ),
                      tooltip: 'Takvimden seç',
                      onPressed: _saving ? null : _pickBirthDate,
                    ),
                  ),
                  _textRow(
                    icon: Icons.phone_outlined,
                    label: 'Telefon',
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneMaskFormatter()],
                    prefixText: '0 ',
                    hint: '(5XX) XXX XX XX',
                  ),
                ],
              ),
            ),
            // Takım bilgisi yalnızca kadrodan açılınca (lisansta takım yok).
            // Takım sorumlusu Takım Yönetimi'nden seçilir.
            if (!widget.standalone)
              AdminFormSection(
                title: 'Takım',
                child: AdminFieldGroup(
                  children: [
                    _textRow(
                      icon: Icons.numbers_rounded,
                      label: 'Forma No',
                      controller: _numberController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      hint: 'Örn. 10',
                    ),
                  ],
                ),
              ),
            AdminFormSection(
              title: 'Oyun',
              child: AdminFieldGroup(
                children: [
                  AdminSelectRow(
                    icon: Icons.sports_soccer_outlined,
                    label: 'Ana Mevki',
                    value: valueOrNull(_mainPosition),
                    placeholder: 'Seçilmedi',
                    onClear: () => setState(() {
                      _mainPosition = _unsetOption;
                      _subPosition = _unsetOption;
                    }),
                    onTap: _saving
                        ? null
                        : () => _pickOption(
                            title: 'Ana Mevki',
                            items: _mainPositions,
                            selected: valueOrNull(_mainPosition),
                            onPicked: (v) {
                              _mainPosition = v;
                              // Yeni mevkinin ilk alt mevkisi otomatik seçilir.
                              _subPosition =
                                  (_subPositionsByMain[v] ?? const <String>[])
                                      .first;
                            },
                          ),
                  ),
                  if (_isMainPositionSelected)
                    AdminSelectRow(
                      icon: Icons.sports_outlined,
                      label: 'Alt Mevki',
                      value: valueOrNull(_subPosition),
                      placeholder: 'Seçin',
                      onTap: _saving
                          ? null
                          : () => _pickOption(
                              title: 'Alt Mevki',
                              items:
                                  _subPositionsByMain[_mainPosition] ??
                                  const <String>[],
                              selected: valueOrNull(_subPosition),
                              onPicked: (v) => _subPosition = v,
                            ),
                    ),
                  AdminSelectRow(
                    icon: Icons.directions_run_outlined,
                    label: 'Kullandığı Ayak',
                    value: valueOrNull(_preferredFoot),
                    placeholder: 'Seçilmedi',
                    onClear: () => setState(() => _preferredFoot = ''),
                    onTap: _saving
                        ? null
                        : () => _pickOption(
                            title: 'Kullandığı Ayak',
                            items: _feet,
                            selected: valueOrNull(_preferredFoot),
                            onPicked: (v) => _preferredFoot = v,
                          ),
                  ),
                  _textRow(
                    icon: Icons.height_rounded,
                    label: 'Boy (cm)',
                    controller: _heightController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    hint: 'Örn. 178',
                  ),
                  _textRow(
                    icon: Icons.monitor_weight_outlined,
                    label: 'Kilo (kg)',
                    controller: _weightController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    hint: 'Örn. 80',
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminPrimaryButton(
                label: editing ? 'GÜNCELLE' : 'KAYDET',
                busy: _saving,
                onPressed: _save,
              ),
            ],
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
                                            : p.name.trim()[0].trUpper,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
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
                            style: const TextStyle(fontWeight: FontWeight.w800),
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

String birthDateDbToUi(String? raw) {
  final s = (raw ?? '').toString().replaceAll('\u0000', '').trim();
  if (s.isEmpty) return '';

  final ui = RegExp(r'^(\d{2})[./-](\d{2})[./-](\d{4})$').firstMatch(s);
  if (ui != null) {
    final dd = ui.group(1)!.padLeft(2, '0');
    final mm = ui.group(2)!.padLeft(2, '0');
    final yyyy = ui.group(3)!.padLeft(4, '0');
    return '$dd-$mm-$yyyy';
  }

  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (iso != null) {
    final yyyy = iso.group(1)!;
    final mm = iso.group(2)!;
    final dd = iso.group(3)!;
    return '$dd-$mm-$yyyy';
  }

  final dt = DateTime.tryParse(s);
  if (dt != null) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yyyy = dt.year.toString().padLeft(4, '0');
    return '$dd-$mm-$yyyy';
  }

  return s;
}

String? birthDateUiToDb(String raw) {
  final s = raw.toString().replaceAll('\u0000', '').trim();
  if (s.isEmpty) return null;

  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (iso != null) {
    final yyyy = int.tryParse(iso.group(1)!);
    final mm = int.tryParse(iso.group(2)!);
    final dd = int.tryParse(iso.group(3)!);
    if (yyyy == null || mm == null || dd == null) return null;
    if (yyyy < 1900 || yyyy > 2100) return null;
    if (mm < 1 || mm > 12) return null;
    if (dd < 1 || dd > 31) return null;
    final mmStr = mm.toString().padLeft(2, '0');
    final ddStr = dd.toString().padLeft(2, '0');
    return '${yyyy.toString().padLeft(4, '0')}-$mmStr-$ddStr';
  }

  final ui = RegExp(r'^(\d{2})[./-](\d{2})[./-](\d{4})$').firstMatch(s);
  if (ui == null) return null;
  final dd = int.tryParse(ui.group(1)!);
  final mm = int.tryParse(ui.group(2)!);
  final yyyy = int.tryParse(ui.group(3)!);
  if (dd == null || mm == null || yyyy == null) return null;
  if (yyyy < 1900 || yyyy > 2100) return null;
  if (mm < 1 || mm > 12) return null;
  if (dd < 1 || dd > 31) return null;
  final mmStr = mm.toString().padLeft(2, '0');
  final ddStr = dd.toString().padLeft(2, '0');
  return '${yyyy.toString().padLeft(4, '0')}-$mmStr-$ddStr';
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
        oldValue.text.contains('-') &&
        oldDigits == newDigits &&
        !newValue.text.contains('--');
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
      if (i == 2 || i == 4) b.write('-');
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

class FootballerLicenseScreen extends StatefulWidget {
  const FootballerLicenseScreen({super.key});

  @override
  State<FootballerLicenseScreen> createState() =>
      _FootballerLicenseScreenState();
}

class _FootballerLicenseScreenState extends State<FootballerLicenseScreen> {
  final _consentCache = ConsentStatusCache();
  final ITeamService _teamService = ServiceLocator.teamService;
  final ILeagueService _leagueService = ServiceLocator.leagueService;

  final _searchController = TextEditingController();
  String _q = '';

  String _norm(String input) {
    return input.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().trim();
  }

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  String _positionsBirthLine(PlayerModel p) {
    final main = (p.mainPosition ?? '').trim();
    final sub = (p.position ?? '').trim();
    final pos = main.isEmpty
        ? (sub.isEmpty ? '-' : sub)
        : (sub.isEmpty ? main : '$main($sub)');
    final birth = birthDateDbToUi(p.birthDate).trim();
    return '$pos - ${birth.isEmpty ? '/' : birth}';
  }

  Future<void> _openPlayerForm({PlayerModel? editing}) async {
    await showPlayerFormPopup(
      context,
      PlayerFormScreen(standalone: true, editing: editing),
    );
  }

  Future<void> _openPlayerCard(PlayerModel p) async {
    final phoneOrId = ((p.phone ?? '').trim().isNotEmpty ? p.phone! : p.id)
        .trim();
    final h = MediaQuery.of(context).size.height * 0.95;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: h),
      showDragHandle: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SizedBox(
          height: h,
          child: PlayerCard(
            playerPhone: phoneOrId,
            name: p.name,
            number: (p.number ?? '').trim(),
            photoUrl: (p.photoUrl ?? '').trim(),
            position: (p.position ?? p.mainPosition ?? '').trim(),
            birthDate: birthDateDbToUi(p.birthDate),
            height: p.height,
            weight: p.weight,
            seasons: const <League>[],
            initialSeasonId: '',
          ),
        );
      },
    );
  }

  Future<Map<String, String>?> _pickLeagueTeamForBulkUpload() async {
    String selectedLeagueId = '';
    String selectedTeamId = '';
    String selectedTeamName = '';

    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      showDragHandle: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            Future<List<Team>> loadTeams() async {
              final id = selectedLeagueId.trim();
              if (id.isEmpty) return const <Team>[];
              try {
                return await _teamService.getTeamsCached(
                  id,
                  caller: 'FootballerLicenseScreen',
                );
              } catch (_) {
                return const <Team>[];
              }
            }

            return StreamBuilder<List<League>>(
              stream: _leagueService.watchLeagues(),
              builder: (context, leaguesSnap) {
                final leagues = leaguesSnap.data ?? const <League>[];
                leagues.sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );
                if (selectedLeagueId.isEmpty && leagues.isNotEmpty) {
                  selectedLeagueId = leagues.first.id;
                }

                return FutureBuilder<List<Team>>(
                  future: loadTeams(),
                  builder: (context, teamsSnap) {
                    final teams = teamsSnap.data ?? const <Team>[];
                    final list = teams.toList()
                      ..sort(
                        (a, b) => a.name.toLowerCase().compareTo(
                          b.name.toLowerCase(),
                        ),
                      );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CustomBottomSheetDropdown<League>(
                            labelText: 'Turnuva',
                            prefixIcon: Icons
                                .emoji_events_outlined, // İkonu doğrudan parametre olarak geçiyoruz
                            // 1. Liste olarak elindeki leagues objelerini ver
                            items: leagues,

                            // 2. Seçili objeyi ID'sinden bulup value'ya atıyoruz
                            value: selectedLeagueId.isEmpty
                                ? null
                                : leagues
                                      .where((l) => l.id == selectedLeagueId)
                                      .firstOrNull,
                            // Not: Eğer Flutter/Dart sürümün firstOrNull desteklemiyorsa şunu kullanabilirsin:
                            // : leagues.firstWhere((l) => l.id == selectedLeagueId, orElse: () => leagues.first),

                            // 3. Objenin ekranda ve listede nasıl görüneceğini belirliyoruz
                            itemLabelBuilder: (l) =>
                                l.name.trim().isEmpty ? l.id : l.name,

                            // 4. Seçim yapıldığında state'i güncelliyoruz
                            onChanged: (League? selectedLeague) {
                              setSheetState(() {
                                selectedLeagueId = selectedLeague?.id ?? '';
                                selectedTeamId = '';
                                selectedTeamName = '';
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          if (selectedLeagueId.trim().isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Önce turnuva seçin.'),
                            )
                          else if (teamsSnap.connectionState ==
                              ConnectionState.waiting)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (list.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Bu turnuvada takım bulunamadı.'),
                            )
                          else
                            Flexible(
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: list.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final t = list[i];
                                  final selected = t.id == selectedTeamId;
                                  return ListTile(
                                    title: Text(
                                      t.name.trim().isEmpty ? t.id : t.name,
                                    ),
                                    trailing: selected
                                        ? const Icon(Icons.check_rounded)
                                        : null,
                                    onTap: () {
                                      setSheetState(() {
                                        selectedTeamId = t.id;
                                        selectedTeamName = t.name.trim();
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: FilledButton(
                              onPressed:
                                  selectedLeagueId.trim().isEmpty ||
                                      selectedTeamId.trim().isEmpty
                                  ? null
                                  : () => Navigator.pop(context, {
                                      'leagueId': selectedLeagueId,
                                      'teamId': selectedTeamId,
                                      'teamName': selectedTeamName,
                                    }),
                              child: const Text(
                                'Devam Et',
                                style: TextStyle(fontWeight: FontWeight.w800),
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
          },
        ),
      ),
    );
  }

  Future<void> _openBulkUploadFlow() async {
    final picked = await _pickLeagueTeamForBulkUpload();
    if (!mounted || picked == null) return;

    final leagueId = (picked['leagueId'] ?? '').trim();
    final teamId = (picked['teamId'] ?? '').trim();
    final teamName = (picked['teamName'] ?? '').trim();
    if (leagueId.isEmpty || teamId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Takım/turnuva bilgisi bulunamadı.')),
      );
      return;
    }

    await showSquadBulkUploadDialog(
      context: context,
      leagueId: leagueId,
      teamId: teamId,
      teamName: teamName.isEmpty ? teamId : teamName,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Arama her harfte yeniden abone olmasın; arka plandan dönünce yenilensin.
  late final Stream<List<PlayerModel>> _playersStream = resilientStream(
    () => _teamService.watchAllPlayers(caller: 'FootballerLicenseScreen'),
  );

  /// Kurucu / bölge sorumlusu yalnızca kendi takımlarının oyuncularını görür
  /// (admin için null: hepsi).
  Future<Set<String>?>? _allowedPlayers;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _allowedPlayers ??= PanelScope.playerIds(AppSession.of(context).value);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    final isAdmin = session.isAdmin;
    const accent = Color(0xFF10B981);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      extendBodyBehindAppBar: true,
      appBar: MasterClassAppBar(
        title: 'Futbolcu Lisans Yönetimi',
        actions: [
          if (session.hasManagementPanel)
            PopupMenuButton<String>(
              tooltip: 'Futbolcu ekle',
              icon: const Icon(
                Icons.person_add_alt_1_rounded,
                color: Colors.white,
                size: 26,
              ),
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: (v) {
                if (v == 'create') _openPlayerForm();
                if (v == 'bulk') _openBulkUploadFlow();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'create',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.person_add_alt_1_rounded,
                      color: accent,
                    ),
                    title: Text(
                      'Futbolcu Ekle',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                // Toplu yükleme yalnızca admin.
                if (isAdmin)
                  const PopupMenuItem(
                    value: 'bulk',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.upload_file_rounded, color: accent),
                      title: Text(
                        'Toplu Yükle (Excel)',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Oyuncu ara',
                      prefixIcon: const Icon(Icons.search, color: accent),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.3),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: accent),
                      ),
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<Set<String>?>(
                      future: _allowedPlayers,
                      builder: (context, allowedSnap) =>
                          StreamBuilder<List<PlayerModel>>(
                            stream: _playersStream,
                            builder: (context, snap) {
                              if (!snap.hasData ||
                                  allowedSnap.connectionState !=
                                      ConnectionState.done) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: accent,
                                  ),
                                );
                              }
                              final allowed = allowedSnap.data;
                              final q = _norm(_q);
                              final list =
                                  snap.data!
                                      .where(
                                        (p) =>
                                            allowed == null ||
                                            allowed.contains(p.id),
                                      )
                                      .where(
                                        (p) =>
                                            q.isEmpty ||
                                            _norm(p.name).contains(q),
                                      )
                                      .toList()
                                    ..sort(
                                      (a, b) => a.name.toLowerCase().compareTo(
                                        b.name.toLowerCase(),
                                      ),
                                    );

                              if (list.isEmpty) {
                                return const Center(
                                  child: Text(
                                    'Futbolcu bulunamadı.',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                );
                              }
                              // Durum tüm futbolcular için bir kez yüklenir (aramada
                              // yeniden sorgu atılmaz).
                              final all = snap.data!
                                  .where(
                                    (p) =>
                                        allowed == null ||
                                        allowed.contains(p.id),
                                  )
                                  .map((p) => p.id);
                              return FutureBuilder(
                                future: _consentCache.of(all),
                                builder: (context, cs) {
                                  final st = cs.data ?? const {};
                                  final showBanner = st.values.any(
                                    (s) => !s.complete,
                                  );
                                  return ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 24),
                                    itemCount:
                                        list.length + (showBanner ? 1 : 0),
                                    itemBuilder: (context, i) {
                                      if (showBanner && i == 0) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          child: ConsentSummaryBanner(
                                            statuses: st,
                                          ),
                                        );
                                      }
                                      final p = list[i - (showBanner ? 1 : 0)];
                                      return _licenseCard(p, consent: st[p.id]);
                                    },
                                  );
                                },
                              );
                            },
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _licenseCard(PlayerModel p, {ConsentStatus? consent}) {
    const accent = Color(0xFF10B981);
    final photo = _normalizeUrl((p.photoUrl ?? '').trim());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openPlayerCard(p),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: photo.isNotEmpty
                    ? WebSafeImage(
                        url: photo,
                        width: 42,
                        height: 42,
                        isCircle: true,
                        fit: BoxFit.cover,
                        fallbackIconSize: 18,
                      )
                    : CircleAvatar(
                        backgroundColor: accent.withValues(alpha: 0.12),
                        child: const Icon(
                          Icons.person,
                          size: 20,
                          color: accent,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.name.trim().isEmpty ? p.id : p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (consent != null && !consent.complete) ...[
                          const SizedBox(width: 6),
                          ConsentChip(status: consent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _positionsBirthLine(p),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SmallActionButton(
                icon: Icons.edit_outlined,
                tooltip: 'Düzenle',
                color: Colors.white70,
                onTap: () => _openPlayerForm(editing: p),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kadro listesi: özet kartı, mevki bölümleri, forma no rozeti
// ---------------------------------------------------------------------------

const _squadAccent = Color(0xFF10B981);
const _squadMuted = Color(0xFF94A3B8);
const _squadAmber = Color(0xFFFBBF24);
const _squadCard = Color(0xFF1E293B);

const _positionOrder = [
  'Kaleci',
  'Defans',
  'Orta Saha',
  'Forvet',
  'Mevkisi belirtilmemiş',
];

String _positionGroup(PlayerModel p) {
  final s = (p.mainPosition ?? p.position ?? '').toLowerCase();
  if (s.contains('kaleci')) return 'Kaleci';
  if (s.contains('defans') || s.contains('stoper') || s.contains('bek')) {
    return 'Defans';
  }
  if (s.contains('forvet') ||
      s.contains('santrafor') ||
      s.contains('santrfor')) {
    return 'Forvet';
  }
  if (s.contains('orta') || s.contains('kanat') || s.contains('numara')) {
    return 'Orta Saha';
  }
  return 'Mevkisi belirtilmemiş';
}

/// Mevkiye göre bölümler; bölüm içinde forma numarası olanlar önce.
List<MapEntry<String, List<PlayerModel>>> _positionSections(
  List<PlayerModel> players,
) {
  final byGroup = <String, List<PlayerModel>>{};
  for (final p in players) {
    byGroup.putIfAbsent(_positionGroup(p), () => []).add(p);
  }
  int numberOf(PlayerModel p) => int.tryParse((p.number ?? '').trim()) ?? 1000;
  return [
    for (final g in _positionOrder)
      if (byGroup[g] != null)
        MapEntry(
          g,
          byGroup[g]!..sort((a, b) {
            final c = numberOf(a).compareTo(numberOf(b));
            return c != 0
                ? c
                : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }),
        ),
  ];
}

class _SquadSection extends StatelessWidget {
  const _SquadSection({
    required this.title,
    required this.count,
    required this.children,
  });

  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title
                        .replaceAll('i', 'İ')
                        .replaceAll('ı', 'I')
                        .toUpperCase(),
                    style: const TextStyle(
                      color: _squadAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Text(
                  '$count oyuncu',
                  style: const TextStyle(color: _squadMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _squadCard.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _SquadSummaryCard extends StatelessWidget {
  const _SquadSummaryCard({
    required this.teamName,
    required this.logoUrl,
    required this.subtitle,
    required this.players,
    required this.ageOf,
    this.firstColor,
    this.secondColor,
    this.onShare,
    this.onBack,
    this.onAdd,
  });

  /// Bandın sol üstündeki geri düğmesi.
  final VoidCallback? onBack;

  /// Sağ üstte "Futbolcu ekle" (yalnız yetkililere).
  final VoidCallback? onAdd;

  /// Bandın köşesindeki yarı saydam yuvarlak düğme.
  Widget _cornerButton(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.28),
        minimumSize: const Size(38, 38),
        fixedSize: const Size(38, 38),
        padding: EdgeInsets.zero,
      ),
      icon: Icon(icon, size: 20, color: Colors.white),
    );
  }

  final String teamName;
  final String logoUrl;
  final String subtitle;
  final List<PlayerModel> players;
  final int? Function(PlayerModel) ageOf;

  /// Takım renkleri (teams.first_color / second_color); yoksa yeşil tema.
  final String? firstColor;
  final String? secondColor;

  /// Kadro afişini paylaşır (sağ üstteki düğme).
  final VoidCallback? onShare;

  Widget _stat(String value, String label) {
    return Container(
      constraints: const BoxConstraints(minWidth: 84),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ages = players.map(ageOf).whereType<int>().toList();
    final avgAge = ages.isEmpty
        ? '–'
        : (ages.reduce((a, b) => a + b) / ages.length).round().toString();
    final counts = <String, int>{};
    for (final p in players) {
      final g = _positionGroup(p);
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final words = teamName.trim().split(RegExp(r'\s+'));
    final initials = words
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first)
        .join()
        .trUpper;
    final palette = TeamPalette.of(firstColor, secondColor);
    final primary = palette.primary;
    final secondary = palette.secondary;

    // Takım renkli üst bant: soldan takımın ana rengi koyu zemine geçer
    // (maç detayı başlığıyla aynı dil); altta iki renkli ince şerit.
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(primary, const Color(0xFF0F172A), 0.35)!,
              palette.background,
              const Color(0xFF0F172A),
            ],
            stops: const [0, 0.5, 1],
          ),
        ),
        child: Column(
          children: [
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 92,
                        height: 92,
                        child: logoUrl.trim().isNotEmpty
                            ? WebSafeImage(
                                url: logoUrl,
                                width: 92,
                                height: 92,
                                fit: BoxFit.contain,
                              )
                            : Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        teamName.trUpper,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle.isEmpty ? 'KADRO' : 'KADRO · $subtitle',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _stat('${players.length}', 'Oyuncu'),
                          _stat(avgAge, 'Ort. yaş'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final g in _positionOrder)
                            if ((counts[g] ?? 0) > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${counts[g]} $g',
                                  style: const TextStyle(
                                    color: Color(0xFFE2E8F0),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onBack != null)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _cornerButton(
                      Icons.arrow_back_rounded,
                      'Geri',
                      onBack!,
                    ),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Row(
                    children: [
                      if (onShare != null)
                        _cornerButton(
                          Icons.ios_share_rounded,
                          'Kadro afişini paylaş',
                          onShare!,
                        ),
                      if (onShare != null && onAdd != null)
                        const SizedBox(width: 8),
                      if (onAdd != null)
                        _cornerButton(
                          Icons.person_add_alt_1_rounded,
                          'Futbolcu ekle',
                          onAdd!,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 4,
              child: Row(
                children: [
                  Expanded(child: ColoredBox(color: primary)),
                  Expanded(child: ColoredBox(color: secondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Forma numarası rozeti; numara yoksa kesik çizgili boş rozet.
class _JerseyBadge extends StatelessWidget {
  const _JerseyBadge({required this.number, this.onTap});

  final String number;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final has = number.isNotEmpty;
    final badge = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: has ? _squadAccent.withValues(alpha: 0.16) : null,
          borderRadius: BorderRadius.circular(12),
          border: has
              ? null
              : Border.all(color: _squadMuted.withValues(alpha: 0.45)),
        ),
        child: Text(
          has ? number : '—',
          style: TextStyle(
            color: has ? _squadAccent : _squadMuted,
            fontSize: 16,
            fontWeight: has ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ),
    );
    return onTap == null
        ? badge
        : Tooltip(message: 'Forma no değiştir', child: badge);
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.text,
    this.color = Colors.white,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(text, style: TextStyle(color: color)),
      ],
    );
  }
}

/// Kadroya mevcut futbolcu ekleme popup'ı. En az 3 harf yazılınca arar;
/// sezonda başka bir takıma kayıtlı futbolcular kilitli gösterilir.
class _SeasonPlayerPicker extends StatefulWidget {
  const _SeasonPlayerPicker({
    required this.service,
    required this.seasonId,
    required this.teamId,
    required this.displayPosition,
    required this.normalizeUrl,
  });

  final SupabaseTeamService service;
  final String seasonId;
  final String teamId;
  final String Function(PlayerModel) displayPosition;
  final String Function(String) normalizeUrl;

  @override
  State<_SeasonPlayerPicker> createState() => _SeasonPlayerPickerState();
}

class _SeasonPlayerPickerState extends State<_SeasonPlayerPicker> {
  static const _minChars = 3;

  final _searchController = TextEditingController();
  final _selected = <String, PlayerModel>{};
  Timer? _debounce;
  int _requestSeq = 0;
  bool _loading = false;
  bool _busy = false;
  String? _error;
  List<({PlayerModel player, String? teamId, String? teamName})> _results =
      const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < _minChars) {
      _requestSeq++;
      setState(() {
        _loading = false;
        _error = null;
        _results = const [];
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final seq = ++_requestSeq;
    try {
      final res = await widget.service.searchPlayersForSeason(
        widget.seasonId,
        q,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _results = res;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
        _loading = false;
      });
    }
  }

  void _toggle(PlayerModel p) {
    setState(() {
      if (_selected.remove(p.id) == null) _selected[p.id] = p;
    });
  }

  Future<void> _addSelected() async {
    if (_busy || _selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.service.addMultiplePlayersToTeam(
        _selected.keys.toList(),
        widget.teamId,
        widget.seasonId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Eklenemedi: $msg')));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.8;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: kAdminAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person_search_rounded,
                    color: kAdminAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Futbolcu Seç',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Başka takımdaki futbolcular seçilemez',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              enabled: !_busy,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onChanged: _onQueryChanged,
              style: const TextStyle(color: Colors.white),
              cursorColor: kAdminAccent,
              decoration: InputDecoration(
                hintText: 'Futbolcu adı (en az 3 harf)',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: kAdminAccent,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(
                          Icons.clear_rounded,
                          color: Colors.white54,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _onQueryChanged('');
                        },
                      ),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.3),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kAdminAccent),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
            ),
            if (_selected.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selected.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final p = _selected.values.elementAt(i);
                    return InputChip(
                      label: Text(p.name),
                      labelStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      backgroundColor: kAdminAccent.withValues(alpha: 0.2),
                      side: BorderSide(
                        color: kAdminAccent.withValues(alpha: 0.5),
                      ),
                      shape: const StadiumBorder(),
                      visualDensity: VisualDensity.compact,
                      deleteIconColor: Colors.white70,
                      onDeleted: _busy ? null : () => _toggle(p),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(child: _buildResults()),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAdminAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _busy || _selected.isEmpty ? null : _addSelected,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _selected.isEmpty
                            ? 'KADROYA EKLE'
                            : 'KADROYA EKLE (${_selected.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final q = _searchController.text.trim();
    if (q.length < _minChars) {
      final left = _minChars - q.length;
      return _PickerHint(
        icon: Icons.manage_search_rounded,
        text: q.isEmpty
            ? 'Aramak için futbolcu adını yazın'
            : '$left harf daha yazın',
      );
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: kAdminAccent),
      );
    }
    if (_error != null) {
      return _PickerHint(
        icon: Icons.error_outline_rounded,
        text: 'Arama yapılamadı: $_error',
      );
    }
    if (_results.isEmpty) {
      return const _PickerHint(
        icon: Icons.person_off_outlined,
        text: 'Eşleşen futbolcu bulunamadı',
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _buildRow(_results[i]),
    );
  }

  Widget _buildRow(({PlayerModel player, String? teamId, String? teamName}) r) {
    final p = r.player;
    final inThisTeam = r.teamId == widget.teamId;
    final locked = r.teamId != null;
    final checked = _selected.containsKey(p.id);
    final pos = widget.displayPosition(p).trim();
    final birth = (p.birthDate ?? '').trim();
    final subtitle = [
      if (pos.isNotEmpty && pos != '-') pos,
      if (birth.isNotEmpty) birth,
    ].join(' · ');
    final photo = (p.photoUrl ?? '').trim();

    final Widget trailing;
    if (locked) {
      trailing = Container(
        constraints: const BoxConstraints(maxWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              inThisTeam ? Icons.check_rounded : Icons.lock_outline_rounded,
              size: 13,
              color: Colors.white60,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                inThisTeam
                    ? 'Kadroda'
                    : ((r.teamName ?? '').isEmpty
                          ? 'Başka takım'
                          : r.teamName!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      trailing = AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? kAdminAccent : Colors.transparent,
          border: Border.all(
            color: checked ? kAdminAccent : Colors.white38,
            width: 2,
          ),
        ),
        child: checked
            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
            : null,
      );
    }

    return Opacity(
      opacity: locked ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: locked || _busy ? null : () => _toggle(p),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: checked
                  ? kAdminAccent.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: checked
                    ? kAdminAccent.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                ClipOval(
                  child: Container(
                    width: 42,
                    height: 42,
                    color: Colors.white.withValues(alpha: 0.08),
                    child: photo.isEmpty
                        ? const Icon(
                            Icons.person_rounded,
                            color: Colors.white54,
                            size: 24,
                          )
                        : WebSafeImage(
                            url: widget.normalizeUrl(photo),
                            width: 42,
                            height: 42,
                            fit: BoxFit.cover,
                            isCircle: true,
                            fallbackIconSize: 22,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerHint extends StatelessWidget {
  const _PickerHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
