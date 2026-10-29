import '../../identity/verified_badge.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../tournament/models/age_rules.dart';
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
import '../../../core/widgets/list_filter.dart';
import '../../../core/services/image_upload_service.dart';
import '../models/team.dart';
import '../services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../services/supabase/supabase_team_service.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../../core/widgets/app_name_band.dart';
import '../../../core/widgets/web_safe_image.dart';

import 'package:football_tournament/core/widgets/photo_crop_screen.dart';
import 'package:football_tournament/core/widgets/picked_image.dart';
import 'package:football_tournament/core/widgets/admin_form.dart';

import '../../../core/utils/string_utils.dart';
import '../../share/poster_share.dart';
import '../../share/squad_poster.dart';
import '../../../core/utils/team_colors.dart';
import '../widgets/team_page_tabs.dart';
import '../widgets/squad_popups.dart';
import '../../admin/services/approval_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/utils/reveal_search.dart';

class TeamSquadScreen extends StatefulWidget {
  final String teamId;
  final String tournamentId;
  final String teamName;
  final String teamLogoUrl;
  final String? initialFirstColor;
  final String? initialSecondColor;

  const TeamSquadScreen({
    super.key,
    required this.teamId,
    required this.tournamentId,
    required this.teamName,
    required this.teamLogoUrl,
    this.initialFirstColor,
    this.initialSecondColor,
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
            await SharePlus.instance.share(
              ShareParams(
                files: [XFile(file.path)],
                text: 'Futbolcu Excel Şablonu',
              ),
            );
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

  /// Arama alanı yalnız sağ alttaki büyüteçle açılır.
  bool _rosterSearchOpen = false;
  final _rosterSearchFocus = FocusNode();

  final Map<String, String> _playerPhotoUrlByPhone = {};
  final Set<String> _playerPhotoFetchInFlight = {};

  bool _isTeamManager = false;

  /// Sezonun yaş ve kontenjan kuralları (kadroda etiket ve özet için).
  AgeRules _ageRules = const AgeRules();
  String? _ageRulesSeason;

  /// Sezonun maç kuralları (Uyarılar sekmesindeki "Turnuva Kuralları").
  Map<String, dynamic> _seasonRules = const {};

  void _ensureAgeRules(String seasonId) {
    if (_ageRulesSeason == seasonId) return;
    _ageRulesSeason = seasonId;
    Supabase.instance.client
        .from('seasons')
        .select(
          'age_rules, starting_player_count, sub_player_count, '
          'match_period_duration, number_of_player_changes, '
          'transfer_start_date, transfer_end_date, goalkeeper_add_anytime, '
          'require_verified_id',
        )
        .eq('id', seasonId)
        .maybeSingle()
        .then((row) {
          if (!mounted || _ageRulesSeason != seasonId) return;
          setState(() {
            _ageRules = AgeRules.fromJson(row?['age_rules']);
            _seasonRules = row ?? const {};
          });
        })
        .catchError((_) {});
  }

  AgeCheck _ageCheck(PlayerModel p) => _ageRules.check(
    birthYear: int.tryParse(
      RegExp(r'(\d{4})').firstMatch(p.birthDate ?? '')?.group(1) ?? '',
    ),
    isGk: (p.mainPosition ?? '').trim() == 'Kaleci',
  );

  /// Kontenjan kullanımı: her kontenjandaki oyuncular ve kural dışılar.
  ({List<List<PlayerModel>> quota, List<PlayerModel> violations}) _ageUsage(
    List<PlayerModel> players,
  ) {
    final quota = [for (final _ in _ageRules.quotas) <PlayerModel>[]];
    final violations = <PlayerModel>[];
    for (final p in players) {
      final c = _ageCheck(p);
      if (c.status == AgeStatus.quota) quota[c.quotaIndex!].add(p);
      if (c.status == AgeStatus.violation) violations.add(p);
    }
    return (quota: quota, violations: violations);
  }

  /// Uyarılar sekmesinin simgesi: izni eksik oyuncu, aşılan kontenjan ya
  /// da kural dışı oyuncu varsa ünlem yanıp söner; yoksa tik.
  bool _hasWarnings(
    List<PlayerModel> players,
    Map<String, ConsentStatus> consent,
  ) {
    if (consent.values.any((s) => !s.complete)) return true;
    if (_ageRules.isEmpty) return false;
    final u = _ageUsage(players);
    if (u.violations.isNotEmpty) return true;
    for (var i = 0; i < _ageRules.quotas.length; i++) {
      if (u.quota[i].length > _ageRules.quotas[i].max) return true;
    }
    return false;
  }

  Widget _tabBar(List<PlayerModel> players) {
    return FutureBuilder<Map<String, ConsentStatus>>(
      future: _consentCache.of(players.map((p) => p.id)),
      builder: (context, snap) {
        final warn = _hasWarnings(players, snap.data ?? const {});
        return TeamPageTabBar(
          index: _tab,
          filled: true,
          onChanged: (i) => setState(() => _tab = i),
          labels: const ['Kadro', 'Fikstür', 'İstatistik', ''],
          icons: [
            null,
            null,
            null,
            warn
                ? const _BlinkingIcon(
                    icon: Icons.error_rounded,
                    color: Color(0xFFFBBF24),
                  )
                : const Icon(
                    Icons.check_circle_rounded,
                    size: 21,
                    color: Color(0xFF6EE7B7),
                  ),
          ],
        );
      },
    );
  }

  Widget _warnHeader(String title, {required bool ok}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_rounded,
            size: 16,
            color: ok ? _squadAccent : const Color(0xFFFBBF24),
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              color: _squadAccent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox(
    String text, {
    Color color = _squadAccent,
    List<String> bold = const [],
  }) {
    // [bold] içindeki ifadeler kalın yazılır.
    final spans = <TextSpan>[];
    var rest = text;
    while (rest.isNotEmpty) {
      var at = -1;
      var hit = '';
      for (final b in bold) {
        final i = rest.indexOf(b);
        if (i >= 0 && (at < 0 || i < at)) {
          at = i;
          hit = b;
        }
      }
      if (at < 0) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (at > 0) spans.add(TextSpan(text: rest.substring(0, at)));
      spans.add(
        TextSpan(
          text: hit,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      );
      rest = rest.substring(at + hit.length);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text.rich(
        TextSpan(children: spans),
        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
      ),
    );
  }

  Widget _playerLine(PlayerModel p, Widget trailing, {String? sub}) {
    return InkWell(
      onTap: () => _openPlayerCard(p),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
        child: Row(
          children: [
            SquadPlayerAvatar(
              name: p.name,
              photoUrl: (_playerPhotoUrlByPhone[p.id] ?? p.photoUrl ?? ''),
              size: 34,
            ),
            const SizedBox(width: 10),
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
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (sub != null)
                    Text(
                      sub,
                      style: const TextStyle(color: _squadMuted, fontSize: 11),
                    ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  List<String> _ruleLines() {
    final r = _seasonRules;
    int? n(String k) => (r[k] as num?)?.toInt();
    String? d(String k) {
      final t = DateTime.tryParse((r[k] ?? '').toString());
      if (t == null) return null;
      final l = t.toLocal();
      return '${l.day.toString().padLeft(2, '0')}.'
          '${l.month.toString().padLeft(2, '0')}.${l.year}';
    }

    final a = _ageRules;
    final start = d('transfer_start_date');
    final end = d('transfer_end_date');
    return [
      if (n('starting_player_count') != null)
        'Sahada ${n('starting_player_count')} oyuncu'
            '${n('sub_player_count') != null ? ', esamede en fazla ${n('sub_player_count')} yedek' : ''}.',
      if (n('match_period_duration') != null)
        'Maç 2 devre, devre süresi ${n('match_period_duration')} dakika.',
      if (n('number_of_player_changes') != null)
        'Maçta en fazla ${n('number_of_player_changes')} oyuncu değişikliği.',
      if (start != null || end != null)
        'Kadro ekleme dönemi: ${start ?? '…'} – ${end ?? '…'}'
            '${r['goalkeeper_add_anytime'] == true ? ' (kaleci her zaman eklenebilir)' : ''}.',
      if (r['require_verified_id'] == true)
        'Esameye yalnız kimliği doğrulanmış (mavi tikli) oyuncular yazılır.',
      if (a.playerMaxYear != null)
        'Oyuncular ${a.playerMaxYear} ve öncesi doğumlu olmalı.',
      if (a.gkMaxYear != null)
        'Kaleciler ${a.gkMaxYear} ve öncesi doğumlu olabilir.',
      for (final q in a.quotas)
        '${q.gk ? 'Kaleci kontenjanı' : 'Kontenjan'} ${q.yearsLabel} doğumlu: '
            'kadroda en fazla ${q.max}'
            '${q.matchMax != null ? ', esamede en fazla ${q.matchMax}' : ''}.',
      if (a.matchMax != null)
        'Maç günü esamede toplam en fazla ${a.matchMax} kontenjan oyuncusu '
            '(kaleci hariç).',
      if (a.matchFieldMax != null)
        'Sahada aynı anda en fazla ${a.matchFieldMax} kontenjan oyuncusu.',
    ];
  }

  /// İzinler, kontenjan ve turnuva kuralları.
  Widget _warningsTab(List<PlayerModel> players) {
    return FutureBuilder<Map<String, ConsentStatus>>(
      future: _consentCache.of(players.map((p) => p.id)),
      builder: (context, snap) {
        final st = snap.data ?? const <String, ConsentStatus>{};
        final missing = [
          for (final p in players)
            if (st[p.id] != null && !st[p.id]!.complete) p,
        ];
        final usage = _ageRules.isEmpty ? null : _ageUsage(players);
        final rules = _ruleLines();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // İzin durumu yalnız yetkiliye döner (takım sorumlusu ve üstü).
            if (st.isNotEmpty) ...[
              _warnHeader('İZİNLER (KVKK / SAĞLIK)', ok: missing.isEmpty),
              if (missing.isEmpty)
                _infoBox('Tüm oyuncuların KVKK ve sağlık izinleri tamam.')
              else ...[
                ConsentSummaryBanner(statuses: st),
                const SizedBox(height: 8),
                _infoBox(
                  'Hesap yok: oyuncu uygulamaya kayıt olmamış; kayıt olup '
                  'izinleri vermeli.\nOnay yok: hesabı var ama Profil › '
                  'İzinlerim ekranından onay vermemiş.\nİzni olmayan '
                  'oyuncular esameye yazılamayacak.',
                  color: const Color(0xFF60A5FA),
                  bold: const ['Hesap yok', 'Onay yok'],
                ),
                _SquadSection(
                  title: 'İzni eksik',
                  count: missing.length,
                  children: [
                    for (final p in missing)
                      _playerLine(p, ConsentChip(status: st[p.id])),
                  ],
                ),
              ],
            ],
            if (usage != null) ...[
              for (var i = 0; i < _ageRules.quotas.length; i++)
                if (usage.quota[i].isNotEmpty)
                  _SquadSection(
                    title: 'Kontenjan ${_ageRules.quotas[i].label}',
                    count: usage.quota[i].length,
                    // Kullanım "2 / 4": sınır aşılırsa kırmızı.
                    trailing: Text(
                      '${usage.quota[i].length} / ${_ageRules.quotas[i].max}',
                      style: TextStyle(
                        color: usage.quota[i].length > _ageRules.quotas[i].max
                            ? const Color(0xFFF87171)
                            : const Color(0xFFFBBF24),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    children: [
                      for (final p in usage.quota[i])
                        _playerLine(
                          p,
                          _ageTag(p) ?? const SizedBox.shrink(),
                          sub: (p.mainPosition ?? '').trim(),
                        ),
                    ],
                  ),
              if (usage.violations.isNotEmpty)
                _SquadSection(
                  title: 'Kural dışı',
                  count: usage.violations.length,
                  trailing: Text(
                    '${usage.violations.length}',
                    style: const TextStyle(
                      color: Color(0xFFF87171),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  children: [
                    for (final p in usage.violations)
                      _playerLine(
                        p,
                        _ageTag(p) ?? const SizedBox.shrink(),
                        sub:
                            '${AgeRules.birthYearOf(p.birthDate) ?? '?'} doğumlu'
                            ' · kurala uymuyor',
                      ),
                  ],
                ),
            ],
            _warnHeader('TURNUVA KURALLARI', ok: true),
            if (rules.isEmpty)
              _infoBox('Bu turnuva için kural girilmemiş.')
            else
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: _squadCard.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in rules)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 6, right: 8),
                              child: Icon(
                                Icons.circle,
                                size: 6,
                                color: _squadAccent,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                line,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// Satırdaki etiket: kontenjan oyuncusu "K", kurala uymayan "KURAL DIŞI".
  Widget? _ageTag(PlayerModel p) {
    final c = _ageCheck(p);
    if (c.status == AgeStatus.ok) return null;
    final quota = c.status == AgeStatus.quota;
    final color = quota ? const Color(0xFFFBBF24) : const Color(0xFFF87171);
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        quota ? 'K' : 'KURAL DIŞI',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  /// Kadroya doğrudan yazabilir mi (admin, kurucu başkan, takımın bölge
  /// sorumlusu). Yalnızca takım sorumlusu olan kişinin ekleme/çıkarması
  /// talep olarak onaya gider; forma numarasını doğrudan değiştirebilir.
  bool _directRoster = false;
  bool get _needsApproval => _isTeamManager && !_directRoster;

  final _approval = ApprovalService();

  /// Bu takım için kişinin onay bekleyen talepleri (yalnız takım sorumlusu).
  Future<List<PendingAction>>? _myPending;
  String? _myPendingSeasonId;

  Future<List<PendingAction>> _pendingFor(String seasonId) {
    if (_myPending == null || _myPendingSeasonId != seasonId) {
      _myPendingSeasonId = seasonId;
      _myPending = _approval.fetchMyActions().then(
        (all) => [
          for (final a in all)
            if (a.status == PendingActionStatus.pending &&
                a.seasonId == seasonId &&
                a.teamId == widget.teamId)
              a,
        ],
      );
    }
    return _myPending!;
  }

  void _reloadPending() {
    if (!mounted) return;
    setState(() => _myPending = null);
  }

  /// Talep gönderildi bilgisi (popup'ın üstünde, okunabilir).
  Future<void> _showRequestSent(String what) => showAdminInfoDialog(
    context: context,
    title: 'Onaya gönderildi',
    message:
        '$what talebiniz bölge sorumlusunun onayına gönderildi. '
        'Onaylanınca kadroya işlenecek.',
    icon: Icons.hourglass_top_rounded,
    iconColor: const Color(0xFFF59E0B),
  );

  /// Talep hatası: aynı oyuncu için bekleyen talep varsa anlaşılır mesaj.
  String _requestError(Object e) {
    final msg = e.toString();
    if (msg.contains('pending_actions_one_open_per_player') ||
        msg.contains('23505')) {
      return 'Bu futbolcu için zaten onay bekleyen bir talebiniz var.';
    }
    return msg.replaceFirst('Exception: ', '').trim();
  }

  bool _isLoadingTournaments = true;

  /// Üst bant altındaki sekme: 0 Kadro, 1 Fikstür, 2 İstatistik.
  int _tab = 0;
  String? _selectedPosition;

  /// Takım renkleri (üst bandın zemini) ve takım sorumlusunun adı; bir kez
  /// okunur.
  /// Kadro satırlarındaki forma yuvarlakları için takım renkleri.
  TeamPalette get _palette => TeamPalette.of(
    widget.initialFirstColor ?? _colorsResolved?.$1,
    widget.initialSecondColor ?? _colorsResolved?.$2,
  );
  (String?, String?, String?)? _colorsResolved;

  late final Future<(String?, String?, String?)> _teamColors = () async {
    try {
      final r = await Supabase.instance.client
          .from('teams')
          .select('first_color, second_color, manager_name')
          .eq('id', widget.teamId)
          .maybeSingle();
      return (
        r?['first_color'] as String?,
        r?['second_color'] as String?,
        r?['manager_name'] as String?,
      );
    } catch (_) {
      return (null, null, null);
    }
  }();
  List<League> _teamTournaments = [];
  String? _selectedTournamentId;

  /// Takımın oynadığı sezonlar (bantta önce sezon yılı, sonra o yılın
  /// turnuvası seçilir).
  List<TeamSeasonOption> _seasonOptions = const [];
  int? _selectedYear;

  Future<List<TeamSeasonOption>> _fetchSeasonOptions() async {
    try {
      final rows = await Supabase.instance.client
          .from('season_teams')
          .select(
            'seasons!inner(id, season_year, start_date, is_default, '
            'deleted_at, leagues!inner(name, is_active))',
          )
          .eq('team_id', widget.teamId);
      final out = <String, TeamSeasonOption>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final s = r['seasons'];
        if (s is! Map || s['deleted_at'] != null) continue;
        final l = s['leagues'];
        if (l is! Map || l['is_active'] == false) continue;
        final id = (s['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final year =
            (s['season_year'] as num?)?.toInt() ??
            DateTime.tryParse((s['start_date'] ?? '').toString())?.year ??
            0;
        out[id] = TeamSeasonOption(
          id: id,
          leagueName: (l['name'] ?? '').toString().trim(),
          year: year,
          isDefault: s['is_default'] == true,
        );
      }
      return out.values.toList()..sort(
        (a, b) =>
            a.leagueName.toLowerCase().compareTo(b.leagueName.toLowerCase()),
      );
    } catch (_) {
      return const [];
    }
  }

  /// Açılış seçimi: içinde bulunulan yılın sezonu (takım o yıl oynamıyorsa
  /// gelinen sezonun yılı, o da yoksa en yeni yıl); turnuva olarak gelinen
  /// turnuva, yoksa varsayılan, yoksa ilk.
  TeamSeasonOption _defaultSeasonPick(
    List<TeamSeasonOption> options,
    String widgetSeasonId,
  ) {
    final years = options.map((o) => o.year).toSet();
    final now = DateTime.now().year;
    final fromWidget = options.where((o) => o.id == widgetSeasonId).toList();
    final year = years.contains(now)
        ? now
        : fromWidget.isNotEmpty
        ? fromWidget.first.year
        : years.reduce(max);
    final inYear = options.where((o) => o.year == year).toList();
    return inYear.firstWhere(
      (o) => o.id == widgetSeasonId,
      orElse: () =>
          inYear.firstWhere((o) => o.isDefault, orElse: () => inYear.first),
    );
  }

  List<TeamSeasonOption> get _tournamentsOfSelectedYear =>
      _seasonOptions.where((o) => o.year == _selectedYear).toList();

  Future<void> _selectSeason(String seasonId) async {
    final id = seasonId.trim();
    if (id.isEmpty || id == _selectedTournamentId) return;
    final opt = _seasonOptions.where((o) => o.id == id).firstOrNull;
    setState(() {
      _selectedTournamentId = id;
      if (opt != null) _selectedYear = opt.year;
      _selectedPosition = null;
      _setPlayersStreamForTournament(id);
    });
    await _checkIfTeamManagerForTournament(id);
  }

  Future<void> _pickSeasonYear() async {
    final year = _selectedYear;
    if (year == null) return;
    final picked = await showSquadSeasonPicker(
      context: context,
      options: _seasonOptions,
      selectedYear: year,
    );
    if (picked == null || picked == year || !mounted) return;
    final inYear = _seasonOptions.where((o) => o.year == picked).toList();
    if (inYear.isEmpty) return;
    await _selectSeason(
      inYear.firstWhere((o) => o.isDefault, orElse: () => inYear.first).id,
    );
  }

  Future<void> _pickTournamentOfYear() async {
    final year = _selectedYear;
    if (year == null) return;
    final picked = await showSquadTournamentPicker(
      context: context,
      options: _tournamentsOfSelectedYear,
      selectedId: _selectedTournamentId,
      year: year,
    );
    if (picked == null || !mounted) return;
    await _selectSeason(picked);
  }

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
    final key = p.id;
    if (tId.isEmpty || key.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Silme için eksik bilgi.')));
      return;
    }
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Futbolcu Sil',
      message: _needsApproval
          ? '${p.name} oyuncusunu kadrodan çıkarma talebi bölge sorumlusunun '
                'onayına gönderilsin mi?'
          : '${p.name} oyuncusunu bu takımdan kaldırmak istiyor musunuz?',
      icon: Icons.person_remove_outlined,
    );
    if (ok != true || !mounted) return;
    if (_needsApproval) {
      try {
        await _approval.submit(
          type: PendingActionType.rosterRemove,
          seasonId: tId,
          teamId: widget.teamId,
          payload: {'player_id': p.id, 'player_name': p.name},
        );
        _reloadPending();
        if (!mounted) return;
        await _showRequestSent('Kadrodan çıkarma');
      } catch (e) {
        if (!mounted) return;
        await showAdminInfoDialog(
          context: context,
          title: 'Gönderilemedi',
          message: _requestError(e),
        );
      }
      return;
    }
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

    // Lig başladıysa ekleme yalnız transfer döneminde; dönem dışında yalnız
    // admin ve kurucu başkan (veritabanı da aynı kuralı uygular).
    if (!AppSession.of(context).value.isAdmin) {
      var allowed = true;
      try {
        allowed =
            await Supabase.instance.client.rpc(
              'roster_add_allowed',
              params: {'p_season_id': lid},
            ) !=
            false;
      } catch (_) {}
      if (!mounted) return;
      if (!allowed) {
        await showAdminInfoDialog(
          context: context,
          title: 'Kadroya ekleme kapalı',
          message:
              'Lig başladığı için kadroya ekleme yalnızca transfer döneminde '
              'yapılabilir. Dönem dışında yalnızca admin ve kurucu başkan '
              'ekleyebilir.',
        );
        return;
      }
    }

    final added = await showAdminPopup<bool>(
      context: context,
      builder: (_) => _SeasonPlayerPicker(
        service: svc,
        seasonId: lid,
        teamId: tid,
        displayPosition: _displayPosition,
        normalizeUrl: _normalizeUrl,
        requestApproval: _needsApproval ? _approval : null,
      ),
    );
    if (added != true || !mounted) return;
    if (_needsApproval) {
      _reloadPending();
      await _showRequestSent('Kadroya ekleme');
      return;
    }
    _refreshPlayersStreamForTournament(lid);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Seçilen futbolcular kadroya eklendi.')),
    );
  }

  /// Takım sorumlusunun onay bekleyen kadro talepleri; geri çekilebilir.
  Widget _pendingRequests(String seasonId) {
    return FutureBuilder<List<PendingAction>>(
      future: _pendingFor(seasonId),
      builder: (context, snap) {
        final items = snap.data ?? const <PendingAction>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return _SquadSection(
          title: 'Onay bekleyen talepler',
          count: items.length,
          countLabel: 'talep',
          children: [
            for (var i = 0; i < items.length; i++)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hourglass_top_rounded,
                      color: Color(0xFFF59E0B),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (items[i].payload['player_name'] ??
                                    items[i].newPlayerName ??
                                    'Futbolcu')
                                .toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${items[i].typeLabel} · bölge sorumlusu onayı bekleniyor',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _squadMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _withdrawRequest(items[i]),
                      child: const Text('Geri çek'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _withdrawRequest(PendingAction a) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Talebi geri çek',
      message: 'Bu talep geri çekilsin mi?',
      icon: Icons.undo_rounded,
    );
    if (ok != true || !mounted) return;
    try {
      await _approval.cancelAction(a.id);
    } catch (e) {
      if (!mounted) return;
      await showAdminInfoDialog(
        context: context,
        title: 'Geri çekilemedi',
        message: _requestError(e),
      );
    }
    _reloadPending();
  }

  Future<void> _promptJerseyNumberEdit({
    required PlayerModel player,
    required String leagueId,
    required String teamId,
    Set<int> taken = const {},
  }) async {
    final svc = _sbTeamService;
    if (svc == null) {
      if (!mounted) return;
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

    final input = await showSquadJerseyPicker(
      context: context,
      playerName: player.name.trim(),
      current: (player.number ?? '').trim(),
      taken: taken,
      palette: _palette,
    );
    if (input == null) return;

    final raw = input.replaceAll(RegExp(r'\D'), '').trim();
    // Boş bırakılırsa numara silinir.
    final n = int.tryParse(raw);
    if (n == null && raw.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Forma numarası geçersiz.')));
      return;
    }

    try {
      await svc.setJerseyNumber(player.id, tid, lid, n);
      if (!mounted) return;
      _refreshPlayersStreamForTournament(lid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Forma numarası güncellendi.')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Güncellenemedi: $msg')));
    }
  }

  bool _assigningJerseys = false;

  /// Forma numarası olmayan oyuncular varsa: "Otomatik ata" şeridi.
  Widget _autoJerseyBanner(List<PlayerModel> players, String seasonId) {
    final missing = [
      for (final p in players)
        if (int.tryParse((p.number ?? '').trim()) == null) p,
    ];
    if (missing.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tag_rounded, color: _squadMuted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${missing.length} oyuncunun forma numarası yok.',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _assigningJerseys
                ? null
                : () => _autoAssignJerseys(players, missing, seasonId),
            child: _assigningJerseys
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Otomatik ata',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }

  /// Numarasız oyunculara takımda boşta kalan en küçük numaralar verilir
  /// (kaleciler önce, sonra ada göre). Mevcut numaralara dokunulmaz.
  Future<void> _autoAssignJerseys(
    List<PlayerModel> all,
    List<PlayerModel> missing,
    String seasonId,
  ) async {
    final svc = _sbTeamService;
    if (svc == null) return;
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Forma No Ata',
      message:
          'Forma numarası olmayan ${missing.length} oyuncuya takımda boşta '
          'olan en küçük numaralar sırayla verilecek. Mevcut numaralar '
          'değişmez; numaraları sonradan tek tek değiştirebilirsiniz.',
      confirmLabel: 'ATA',
      destructive: false,
      icon: Icons.tag_rounded,
    );
    if (!ok || !mounted) return;
    final used = <int>{
      for (final p in all) ?int.tryParse((p.number ?? '').trim()),
    };
    bool isKeeper(PlayerModel p) => [
      p.mainPosition,
      p.position,
    ].any((v) => (v ?? '').toLowerCase().contains('kaleci'));
    final order = [...missing]
      ..sort((a, b) {
        final k = (isKeeper(a) ? 0 : 1).compareTo(isKeeper(b) ? 0 : 1);
        return k != 0 ? k : a.name.compareTo(b.name);
      });
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _assigningJerseys = true);
    var next = 1;
    var done = 0;
    String? error;
    for (final p in order) {
      while (used.contains(next)) {
        next++;
      }
      try {
        await svc.updateJerseyNumber(p.id, widget.teamId, seasonId, next);
        used.add(next);
        done++;
      } catch (e) {
        error = e.toString().replaceFirst('Exception: ', '').trim();
        break;
      }
    }
    if (!mounted) return;
    setState(() => _assigningJerseys = false);
    _refreshPlayersStreamForTournament(seasonId);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? '$done oyuncuya forma numarası verildi.'
              : '$done oyuncuya numara verildi, sonra hata oluştu: $error',
        ),
      ),
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
    PosterPlayer posterPlayer(PlayerModel p) {
      final parts = p.name.trim().split(RegExp(r'\s+'));
      return PosterPlayer(
        firstName: parts.length > 1
            ? parts.sublist(0, parts.length - 1).join(' ')
            : parts.first,
        lastName: parts.length > 1 ? parts.last : '',
        number: (p.number ?? '').trim(),
      );
    }

    // Mevkiye göre gruplar yalnız herkesin mevkisi girilmişse; tek bir
    // eksik bile varsa başlıksız tek liste (forma numarasına göre).
    final sections = _positionSections(players);
    final complete = sections.every((sec) => sec.key != _unknownPosition);
    final groups = <String, List<PosterPlayer>>{
      if (complete)
        for (final sec in sections)
          sec.key: [for (final p in sec.value) posterPlayer(p)]
      else
        '': [
          for (final p
              in [...players]..sort(
                (a, b) => (int.tryParse((a.number ?? '').trim()) ?? 999)
                    .compareTo(int.tryParse((b.number ?? '').trim()) ?? 999),
              ))
            posterPlayer(p),
        ],
    };
    final teamLogo = widget.teamLogoUrl.trim();
    final leagueLogo = (league?.logoUrl ?? '').trim();

    await showPosterPreview(
      context: context,
      fileName: 'kadro_${teamName.replaceAll(RegExp(r'\s+'), '_')}',
      imageUrls: [teamLogo, leagueLogo],
      // Sekmedeki "turnuva" sezon id'sidir.
      seasonId: tournamentId,
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

  Future<void> _openPlayerCard(PlayerModel rosterPlayer) {
    return showPlayerCard(
      context,
      playerKey: rosterPlayer.id,
      number: (rosterPlayer.number ?? '').trim(),
    );
  }

  void _prefetchPlayerPhotos(Iterable<PlayerModel> players) {
    final toFetch = <String>[];
    for (final p in players) {
      final phone = p.id.trim();
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
    _teamColors.then((c) {
      if (mounted) setState(() => _colorsResolved = c);
    });
  }

  @override
  void dispose() {
    _rosterSearchController.dispose();
    _rosterSearchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadTeamTournaments() async {
    if (!mounted) return;

    try {
      final optionsFuture = _fetchSeasonOptions();
      final tournaments = await _teamService.getTeamActiveTournaments(
        widget.teamId,
      );
      final options = await optionsFuture;

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

      int? year;
      if (options.isNotEmpty) {
        final pick = _defaultSeasonPick(options, widgetTournamentId);
        selected = pick.id;
        year = pick.year;
      }

      setState(() {
        _teamTournaments = tournaments;
        _seasonOptions = options;
        _selectedYear = year;
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
      if (_isTeamManager || !_directRoster) {
        setState(() {
          _isTeamManager = false;
          _directRoster = true;
        });
      }
      return;
    }
    final manages =
        session.managesTeam(seasonId, widget.teamId) ||
        (session.isManager && session.teamId?.trim() == widget.teamId.trim());
    var direct = false;
    if (session.hasManagementPanel) {
      try {
        direct =
            await Supabase.instance.client.rpc(
              'owns_season_team',
              params: {'p_season_id': seasonId, 'p_team_id': widget.teamId},
            ) ==
            true;
      } catch (_) {
        direct = false;
      }
    }
    if (!mounted) return;
    setState(() {
      _isTeamManager = manages || direct;
      _directRoster = direct;
    });
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
    if (effectiveTournamentId != null) _ensureAgeRules(effectiveTournamentId);
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
    // Geri düğmesi bantta (sol üst); futbolcu ekleme sağ altta.
    return BandBackPage(
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        extendBodyBehindAppBar: true,
        // Kadro sekmesinde sağ altta: büyüteç (arama kapalıyken) ve futbolcu
        // ekleme (yetkiliyse).
        floatingActionButton: effectiveTournamentId == null || _tab != 0
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!_rosterSearchOpen)
                    FloatingActionButton.small(
                      heroTag: null,
                      tooltip: 'Futbolcu ara',
                      backgroundColor: _squadAccent,
                      foregroundColor: Colors.white,
                      onPressed: () {
                        setState(() => _rosterSearchOpen = true);
                        revealSearchField(_rosterSearchFocus);
                      },
                      child: const Icon(Icons.search_rounded, size: 20),
                    ),
                  if (!_rosterSearchOpen && canAdd) const SizedBox(height: 12),
                  if (canAdd)
                    AdminBarAction(
                      icon: Icons.person_add_alt_1_rounded,
                      tooltip: 'Futbolcu ekle',
                      onPressed: () => _openExistingPlayerPicker(
                        leagueId: effectiveTournamentId,
                        teamId: widget.teamId,
                      ),
                    ).fab(),
                ],
              ),
        body: Stack(
          children: [
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
                              final searchedPlayers = q.isEmpty
                                  ? allPlayers
                                  : allPlayers
                                        .where(
                                          (p) =>
                                              p.name.toLowerCase().contains(q),
                                        )
                                        .toList();
                              final players = _selectedPosition == null
                                  ? searchedPlayers
                                  : searchedPlayers
                                        .where(
                                          (p) =>
                                              _positionGroup(p) ==
                                              _selectedPosition,
                                        )
                                        .toList();

                              // Bant ve sekmeler sabit; altı kayar.
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      8,
                                      10,
                                      0,
                                    ),
                                    child: FutureBuilder<(String?, String?, String?)>(
                                      future: _teamColors,
                                      builder: (context, colorSnap) =>
                                          _SquadSummaryCard(
                                            firstColor:
                                                widget.initialFirstColor ??
                                                colorSnap.data?.$1,
                                            secondColor:
                                                widget.initialSecondColor ??
                                                colorSnap.data?.$2,
                                            teamName: titleTeam,
                                            managerName:
                                                colorSnap.data?.$3 ?? '',
                                            logoUrl: widget.teamLogoUrl,
                                            tournamentName:
                                                _tournamentsOfSelectedYear
                                                    .where(
                                                      (o) =>
                                                          o.id ==
                                                          effectiveTournamentId,
                                                    )
                                                    .firstOrNull
                                                    ?.leagueName ??
                                                _tournamentNameById(
                                                  effectiveTournamentId,
                                                ),
                                            seasonLabel: _selectedYear == null
                                                ? null
                                                : '${_selectedYear!}',
                                            onPickSeason:
                                                _seasonOptions
                                                        .map((o) => o.year)
                                                        .toSet()
                                                        .length >
                                                    1
                                                ? _pickSeasonYear
                                                : null,
                                            extraTournaments: max(
                                              0,
                                              _tournamentsOfSelectedYear
                                                      .length -
                                                  1,
                                            ),
                                            onPickTournament:
                                                _tournamentsOfSelectedYear
                                                        .length >
                                                    1
                                                ? _pickTournamentOfYear
                                                : null,
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
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      8,
                                      10,
                                      0,
                                    ),
                                    child: _tabBar(allPlayers),
                                  ),
                                  Expanded(
                                    child: ListView(
                                      padding: EdgeInsets.fromLTRB(
                                        10,
                                        0,
                                        10,
                                        // Yüzen düğmeler son satırı örtmesin.
                                        canAdd ? 150 : 72,
                                      ),
                                      children: [
                                        if (_tab == 3) _warningsTab(allPlayers),
                                        if (_tab == 0) ...[
                                          const SizedBox(height: 8),
                                          _positionFilter(allPlayers),
                                        ],
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
                                          if (canAdd)
                                            _autoJerseyBanner(
                                              allPlayers,
                                              effectiveTournamentId,
                                            ),
                                          if (_needsApproval)
                                            _pendingRequests(
                                              effectiveTournamentId,
                                            ),
                                          if (_rosterSearchOpen) ...[
                                            const SizedBox(height: 10),
                                            _rosterSearchField(),
                                          ],
                                          const SizedBox(height: 4),
                                          if (players.isEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 32,
                                              ),
                                              child: Text(
                                                allPlayers.isEmpty
                                                    ? 'Henüz kadro girişi yapılmamış.'
                                                    : 'Aramanıza uygun futbolcu bulunamadı.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: _squadMuted,
                                                ),
                                              ),
                                            )
                                          else
                                            for (final section
                                                in _positionSections(players))
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
                                                      roster: allPlayers,
                                                      first: i == 0,
                                                      canAdd: canAdd,
                                                      tournamentId:
                                                          effectiveTournamentId,
                                                      consent: _consentCache.of(
                                                        allPlayers.map(
                                                          (p) => p.id,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                        ],
                                      ],
                                    ),
                                  ),
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
      ),
    );
  }

  /// Büyüteçle açılan ince arama alanı; kapatınca arama da temizlenir.
  Widget _rosterSearchField() {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _rosterSearchController,
        focusNode: _rosterSearchFocus,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        textInputAction: TextInputAction.search,
        onChanged: (v) => setState(() => _rosterQuery = v.trim().toLowerCase()),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Futbolcu ara',
          hintStyle: const TextStyle(color: _squadMuted, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: _squadMuted,
            size: 20,
          ),
          suffixIcon: IconButton(
            tooltip: 'Aramayı kapat',
            icon: const Icon(Icons.close_rounded, color: _squadMuted, size: 20),
            onPressed: () {
              _rosterSearchController.clear();
              _rosterSearchFocus.unfocus();
              setState(() {
                _rosterQuery = '';
                _rosterSearchOpen = false;
              });
            },
          ),
          filled: true,
          fillColor: const Color(0xFF1E293B).withValues(alpha: 0.9),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _squadAccent),
          ),
        ),
      ),
    );
  }

  /// Mevki süzgeci: seçim yoksa hepsi görünür; seçili mevkiye yeniden
  /// dokununca seçim kalkar.
  Widget _positionFilter(List<PlayerModel> players) {
    final sections = _positionSections(players);
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: _positionChip(sections[i])),
          ],
        ],
      ),
    );
  }

  Widget _positionChip(MapEntry<String, List<PlayerModel>> section) {
    final selected = _selectedPosition == section.key;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () =>
          setState(() => _selectedPosition = selected ? null : section.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? _squadAccent.withValues(alpha: 0.18)
              : _squadCard.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? _squadAccent.withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${section.key} (${section.value.length})',
            maxLines: 1,
            style: TextStyle(
              color: selected ? const Color(0xFF9BF3CE) : _squadMuted,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _squadRow(
    PlayerModel p, {
    required List<PlayerModel> roster,
    required bool first,
    required bool canAdd,
    required String tournamentId,
    Future<Map<String, ConsentStatus>>? consent,
  }) {
    final number = (p.number ?? '').trim();
    final age = _ageFromBirthDate(p.birthDate);
    final position = (p.mainPosition ?? p.position ?? '').trim();
    final sub = [
      if (position.isNotEmpty) position,
      if (age != null) '$age yaş',
    ].join(' · ');
    // Fotoğraf yalnız izin verilmişse dolu gelir (veritabanı gizler).
    final photo = (_playerPhotoUrlByPhone[p.id] ?? p.photoUrl ?? '').trim();
    final palette = _palette;
    Future<void> editJersey() => _promptJerseyNumberEdit(
      player: p,
      leagueId: tournamentId,
      teamId: widget.teamId,
      taken: {
        for (final o in roster)
          if (o.id != p.id) ?int.tryParse((o.number ?? '').trim()),
      },
    );

    Future<void> openActions() async {
      final action = await showSquadPlayerActions(
        context: context,
        name: p.name,
        subtitle: sub,
        photoUrl: photo,
        number: number,
        palette: palette,
        // Futbolcu bilgilerini yalnız admin düzenler (oyuncular kendi
        // hesaplarıyla kayıt olur).
        canEditInfo: AppSession.of(context).value.isAdmin,
        removeNeedsApproval: _needsApproval,
      );
      if (!mounted) return;
      switch (action) {
        case 'jersey':
          await editJersey();
        case 'card':
          await _openPlayerCard(p);
        case 'edit':
          await _openPlayerForm(editing: p);
        case 'remove':
          await _confirmAndRemovePlayer(p, tournamentId);
      }
    }

    return InkWell(
      onTap: () => _openPlayerCard(p),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: EdgeInsets.fromLTRB(10, 6, canAdd ? 0 : 10, 6),
        decoration: BoxDecoration(
          border: first
              ? null
              : Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
        ),
        child: Row(
          children: [
            SquadPlayerAvatar(name: p.name, photoUrl: photo),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      VerifiedBadgeFor(playerId: p.id, size: 15, leading: 4),
                      _ageTag(p) ?? const SizedBox.shrink(),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _squadMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      // KVKK durumu yalnız yetkiliye döner (takım sorumlusu
                      // ve üstü); oyuncuya onay vermesini hatırlatmak için.
                      if (consent != null)
                        FutureBuilder<Map<String, ConsentStatus>>(
                          future: consent,
                          builder: (context, snap) {
                            final st = snap.data?[p.id];
                            if (st == null || st.complete) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: EdgeInsets.only(
                                left: sub.isEmpty ? 0 : 6,
                              ),
                              child: ConsentChip(status: st),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: canAdd ? 'Forma no değiştir' : 'Forma no',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: canAdd ? editJersey : null,
                child: SquadJerseyCircle(number: number, palette: palette),
              ),
            ),
            // Düzenleme menüsü yalnız admin ve kadroyu yönetebilenlere
            // (takım sorumlusu, kurucu başkan, bölge sorumlusu).
            if (canAdd)
              IconButton(
                tooltip: 'Diğer işlemler',
                icon: const Icon(Icons.menu_rounded, color: _squadMuted),
                onPressed: openActions,
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
    'Kaleci': [],
    'Defans': ['Stoper', 'Sol Bek', 'Sağ Bek'],
    'Orta Saha': ['Defansif', 'Merkez', 'Ofansif', 'Sol Kanat', 'Sağ Kanat'],
    'Forvet': ['Santrfor', 'Sol Kanat Forvet', 'Sağ Kanat Forvet'],
  };
  static const _feet = <String>['Sağ', 'Sol', 'Her İkisi'];

  String _mainPosition = _unsetOption;
  String _subPosition = _unsetOption;
  String _preferredFoot = '';
  String? _existingPhotoUrl;

  /// Düzenlemede oyuncunun kayıtlı numarası (yetkiliye `player_phones` ile
  /// gelir; telefon tablodan okunmaz). Yüklenene kadar alan kapalı.
  String? _loadedPhone;
  bool _phoneReady = true;
  XFile? _pickedPhoto;
  bool _removePhoto = false;
  bool _saving = false;

  /// Açık sekme: 0 Kimlik, 1 Özellik, 2 Profil (fotoğraf).
  int _tab = 0;

  /// Düzenlemede açılıştaki kişisel bilgiler; yalnızca forma no değiştiyse
  /// oyuncu kaydına dokunulmaz (takım sorumlusu kişisel bilgileri
  /// değiştiremez, yalnızca forma numarasını değiştirebilir).
  String? _initialIdentity;

  String _identitySnapshot() => [
    _nameController.text.trim(),
    _surnameController.text.trim(),
    _birthDateController.text.trim(),
    _phoneController.text.trim(),
    _heightController.text.trim(),
    _weightController.text.trim(),
    _mainPosition,
    _subPosition,
    _preferredFoot,
  ].join('|');

  /// Hata popup'ın üstünde gösterilir (SnackBar popup'ın arkasında kalıyordu).
  /// [tab] verilirse hatalı alanın sekmesine geçilir.
  void _showError(String message, {int? tab}) {
    if (!mounted) return;
    if (tab != null && tab != _tab) setState(() => _tab = tab);
    showAdminInfoDialog(
      context: context,
      title: 'Kaydedilemedi',
      message: message,
    );
  }

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
      case 'DEF':
        return 'Stoper';
      case 'ORT':
        return 'Merkez';
      case 'FOR':
        return 'Santrfor';
    }
    // Tarafı bilinmeyen eski değer (Bek, Kanat) yeniden seçtirilir.
    return _unsetOption;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
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
      _existingPhotoUrl = (e.photoUrl ?? '').trim().isEmpty ? null : e.photoUrl;
      _initialIdentity = _identitySnapshot();
      _phoneReady = false;
      _loadPhone(e.id);
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _hydrateExistingPhotoFromIdentity(),
    );
  }

  /// Kayıtlı numarayı yetkiliye yükler; yetki yoksa ya da numara yoksa alan
  /// boş açılır. Numara değişmedikçe kaydederken gönderilmez.
  Future<void> _loadPhone(String playerId) async {
    String? phone;
    try {
      final rows = await Supabase.instance.client.rpc(
        'player_phones',
        params: {
          'p_ids': [playerId],
        },
      );
      if (rows is List && rows.isNotEmpty) {
        phone = (rows.first as Map)['phone']?.toString();
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loadedPhone = (phone ?? '').trim().isEmpty ? null : phone!.trim();
      if (_phoneController.text.trim().isEmpty && _loadedPhone != null) {
        _phoneController.text = PhoneMaskFormatter.formatFromRaw(_loadedPhone!);
        _initialIdentity = _identitySnapshot();
      }
      _phoneReady = true;
    });
  }

  Future<void> _hydrateExistingPhotoFromIdentity() async {
    if (!mounted) return;
    if (_pickedPhoto != null) return;
    if (_removePhoto) return;
    final id = (widget.editing?.id ?? '').trim();
    if (id.isEmpty) return;
    final player = await _teamService.getPlayerByPhoneOnce(id);
    final url = (player?.photoUrl ?? '').trim();
    if (!mounted) return;
    if (url.isEmpty) return;
    setState(() => _existingPhotoUrl = url);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
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
    final raw = await _picker.pickImage(source: ImageSource.gallery);
    if (raw == null) return;
    if (await raw.length() > 10 * 1024 * 1024) {
      if (!mounted) return;
      _showError(
        'Dosya boyutu çok yüksek (Max 10MB). Lütfen daha düşük boyutlu bir görsel seçiniz.',
      );
      return;
    }
    final bytes = await raw.readAsBytes();
    if (!mounted) return;
    _setPicked(await cropPortraitPhoto(context, bytes));
  }

  /// Seçili ya da kayıtlı fotoğrafın kadrajını yeniden ayarlar.
  Future<void> _reframePhoto() async {
    final XFile? picked;
    if (_pickedPhoto != null) {
      final bytes = await _pickedPhoto!.readAsBytes();
      if (!mounted) return;
      picked = await cropPortraitPhoto(context, bytes);
    } else {
      picked = await cropPortraitPhotoFromUrl(
        context,
        widget.normalizeUrl((_existingPhotoUrl ?? '').trim()),
      );
    }
    _setPicked(picked);
  }

  void _setPicked(XFile? picked) {
    if (picked == null || !mounted) return;
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

  Future<void> _save() async {
    final firstName = _nameController.text.trim();
    final surname = _surnameController.text.trim();
    if (firstName.isEmpty || surname.isEmpty) {
      _showError('Lütfen ad soyad girin.', tab: 0);
      return;
    }
    final fullName = '$firstName $surname'.trim();

    final number = _numberController.text.trim();
    final jerseyInt = number.isEmpty ? null : int.tryParse(number);
    if (number.isNotEmpty && jerseyInt == null) {
      _showError('Forma no sadece sayı olmalı.', tab: 1);
      return;
    }

    final birthDate = _birthDateController.text.trim();
    if (!_isValidBirthDate(birthDate)) {
      _showError('Doğum tarihi DD-MM-YYYY formatında olmalı.', tab: 0);
      return;
    }

    final rawPhone = _rawPhone();
    if (!_isValidPhoneRaw(rawPhone)) {
      _showError('Telefon no 10 haneli olmalı.', tab: 0);
      return;
    }
    final isEditing = widget.editing != null;
    final identityChanged =
        !isEditing ||
        _pickedPhoto != null ||
        _removePhoto ||
        _identitySnapshot() != _initialIdentity;
    if (!_phoneReady) return;
    // Numara yalnız değiştiyse yazılır (tablodan okunmadığı için).
    final phoneChanged = rawPhone != (_loadedPhone ?? '');

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
          ? (_subPosition == _unsetOption || _subPosition.isEmpty
                ? null
                : _subPosition)
          : null;
      var playerId = (widget.editing?.id ?? '').toString().trim();
      final finalPhotoUrl = uploadedPhotoUrl != null
          ? uploadedPhotoUrl.trim()
          : _removePhoto
          ? null
          : (_existingPhotoUrl ?? '').trim().isEmpty
          ? null
          : (_existingPhotoUrl ?? '').trim();
      if (!isEditing) {
        playerId =
            (await _teamService.upsertPlayerIdentity(
              phone: rawPhone.isEmpty ? null : rawPhone,
              name: fullName,
              birthDate: resolvedBirthDate,
              mainPosition: resolvedMainPosition,
              subPosition: resolvedSubPosition,
              photoUrl: finalPhotoUrl,
              preferredFoot: _preferredFoot.trim().isEmpty
                  ? null
                  : _preferredFoot.trim(),
              height: int.tryParse(
                _heightController.text.replaceAll(RegExp(r'\D'), '').trim(),
              ),
              weight: int.tryParse(
                _weightController.text.replaceAll(RegExp(r'\D'), '').trim(),
              ),
            )) ??
            '';
        if (playerId.isEmpty) {
          throw Exception('Oyuncu oluşturulamadı, lütfen tekrar deneyin.');
        }
      }
      // Yeni oyuncu tüm bilgileriyle açıldı; yalnız düzenlemede güncellenir.
      if (isEditing && identityChanged) {
        await _teamService.updatePlayer(
          playerId: playerId,
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
            if (isEditing && phoneChanged)
              'phone': rawPhone.isEmpty ? null : rawPhone,
            'height': int.tryParse(
              _heightController.text.replaceAll(RegExp(r'\D'), '').trim(),
            ),
            'weight': int.tryParse(
              _weightController.text.replaceAll(RegExp(r'\D'), '').trim(),
            ),
          },
        );
      }
      if (!widget.standalone) {
        final teamId = (widget.teamId ?? '').trim();
        final tournamentId = (widget.tournamentId ?? '').trim();
        if (teamId.isNotEmpty && tournamentId.isNotEmpty) {
          // Düzenlenen oyuncu zaten kadroda; kadro kaydı yeniden yazılmaz
          // (takım sorumlusunun yetkisi yalnızca forma numarasına yeter).
          if (!isEditing || sbTeamService == null) {
            await _teamService.upsertRosterEntry(
              tournamentId: tournamentId,
              teamId: teamId,
              playerPhone: playerId,
              playerName: fullName,
              jerseyNumber: sbTeamService == null ? number : null,
            );
          }

          if (sbTeamService != null) {
            final currentText = (widget.editing?.number ?? '')
                .toString()
                .trim();
            final currentInt = currentText.isEmpty
                ? null
                : int.tryParse(currentText);
            final jerseyChanged = currentInt != jerseyInt;
            if (jerseyChanged) {
              final pid = playerId;
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
          : msg.contains('güncelleme yetkisi')
          ? 'Futbolcunun kişisel bilgilerini (ad, doğum tarihi, telefon, '
                'fotoğraf vb.) yalnızca kurucu başkan veya bölge sorumlusu '
                'değiştirebilir. Forma numarasını değiştirebilirsiniz.'
          : msg.replaceFirst('Exception: ', '').trim();
      _showError(text);
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
    bool enabled = true,
  }) {
    return AdminFieldRow(
      icon: icon,
      label: label,
      trailing: trailing,
      child: TextField(
        controller: controller,
        enabled: enabled && !_saving,
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
            onPressed: _saving ? null : _reframePhoto,
            icon: const Icon(Icons.crop_rounded, size: 18),
            label: const Text('Kadrajı düzenle'),
            style: TextButton.styleFrom(foregroundColor: kAdminAccent),
          ),
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
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminDialogHeader(
                    icon: editing
                        ? Icons.manage_accounts_rounded
                        : Icons.person_add_alt_1_rounded,
                    title: editing ? 'Futbolcu Güncelle' : 'Futbolcu Ekle',
                  ),
                  const SizedBox(height: 14),
                  AdminFormTabs(
                    labels: const ['Kimlik', 'Özellik', 'Profil'],
                    selected: _tab,
                    onChanged: _saving ? null : (i) => setState(() => _tab = i),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  if (_tab == 2) Center(child: _photoCard()),
                  if (_tab == 0) ...[
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
                            enabled: _phoneReady,
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [PhoneMaskFormatter()],
                            prefixText: '0 ',
                            hint: '(5XX) XXX XX XX',
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Takım bilgisi yalnızca kadrodan açılınca (lisansta takım yok).
                  // Takım sorumlusu Takım Yönetimi'nden seçilir.
                  if (_tab == 1 && !widget.standalone)
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
                  if (_tab == 1)
                    AdminFormSection(
                      title: 'Özellik',
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
                                      final subs =
                                          _subPositionsByMain[v] ??
                                          const <String>[];
                                      _subPosition = subs.isEmpty
                                          ? ''
                                          : subs.first;
                                    },
                                  ),
                          ),
                          if (_isMainPositionSelected &&
                              (_subPositionsByMain[_mainPosition] ??
                                      const <String>[])
                                  .isNotEmpty)
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
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            hint: 'Örn. 178',
                          ),
                          _textRow(
                            icon: Icons.monitor_weight_outlined,
                            label: 'Kilo (kg)',
                            controller: _weightController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            hint: 'Örn. 80',
                          ),
                        ],
                      ),
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
  final ITeamService _teamService = ServiceLocator.teamService;
  final ILeagueService _leagueService = ServiceLocator.leagueService;

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _q = '';

  /// Arama alanı yalnız sağ alttaki büyüteçle açılır (kadro ekranındaki gibi).
  bool _searchOpen = false;

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
    // Liste sunucudan geliyor: ekleme / düzenleme sonrası yenilenir.
    if (mounted) _reload();
  }

  Future<void> _openPlayerCard(PlayerModel p) {
    return showPlayerCard(
      context,
      playerKey: p.id.trim(),
      number: (p.number ?? '').trim(),
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
                final leagues = [...?leaguesSnap.data];
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
    _debounce?.cancel();
    _scroll.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // Liste sunucuda süzülür ve sayfa sayfa gelir (license_list): telefona
  // tüm oyuncular inmez. Admin hepsini, kurucu başkan / bölge sorumlusu
  // yalnız kendi etkin turnuva / bölge kadrolarını görür.
  static const _pageSize = 50;
  final _scroll = ScrollController();
  List<PlayerModel> _rows = const [];
  Map<String, ConsentStatus> _consent = const {};
  Set<String> _free = const {};
  Set<String> _verifiedIds = const {};
  int _total = 0;
  bool _loading = false;
  bool _initial = true;
  Object? _error;
  Map<String, dynamic> _meta = const {};
  int _req = 0;
  Timer? _debounce;

  /// Filtre seçimi (bölüm → değer; yoksa bölümün varsayılanı).
  Map<String, String> _filter = const {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) _loadMore();
    });
    _reload();
  }

  Future<Map<String, dynamic>> _call(
    Map<String, String> filter, {
    int offset = 0,
    int limit = _pageSize,
  }) async {
    final r = await Supabase.instance.client.rpc(
      'license_list',
      params: {
        'p_filter': filter,
        'p_q': _q.trim(),
        'p_offset': offset,
        'p_limit': limit,
      },
    );
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  void _absorb(Map<String, dynamic> r, {required bool append}) {
    final rows = <PlayerModel>[];
    final consent = <String, ConsentStatus>{};
    final free = <String>{};
    final verified = <String>{};
    for (final any in (r['rows'] as List? ?? const [])) {
      final row = Map<String, dynamic>.from(any as Map);
      final id = (row['id'] ?? '').toString();
      final display = [
        (row['name'] ?? '').toString().trim(),
        (row['surname'] ?? '').toString().trim(),
      ].where((e) => e.isNotEmpty).join(' ');
      rows.add(
        PlayerModel.fromMap({
          ...row,
          if (display.isNotEmpty) 'name': display,
        }, id),
      );
      consent[id] = ConsentStatus(
        hasAccount: row['has_account'] == true,
        complete: row['kvkk'] == true,
      );
      if (row['in_roster'] != true) free.add(id);
      if (row['verified'] == true) verified.add(id);
    }
    _rows = append ? [..._rows, ...rows] : rows;
    _consent = append ? {..._consent, ...consent} : consent;
    _free = append ? {..._free, ...free} : free;
    _verifiedIds = append ? {..._verifiedIds, ...verified} : verified;
    _total = (r['total'] as num?)?.toInt() ?? _rows.length;
    if (!append) _meta = r;
  }

  /// Filtre ya da arama değişince ilk sayfa yeniden okunur.
  Future<void> _reload() async {
    final id = ++_req;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _call(_filter);
      if (!mounted || id != _req) return;
      setState(() {
        _absorb(r, append: false);
        _loading = false;
        _initial = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (!mounted || id != _req) return;
      setState(() {
        _error = e;
        _loading = false;
        _initial = false;
      });
    }
  }

  /// Liste sonuna yaklaşınca sonraki sayfa.
  Future<void> _loadMore() async {
    if (_loading || _rows.length >= _total) return;
    final id = _req;
    setState(() => _loading = true);
    try {
      final r = await _call(_filter, offset: _rows.length);
      if (!mounted || id != _req) return;
      setState(() {
        _absorb(r, append: true);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String v) {
    setState(() => _q = v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  List<ListFilterSection> _sections(bool isAdmin) {
    final leagues = Map<String, dynamic>.from(_meta['leagues'] as Map? ?? {});
    final ids = leagues.keys.toList()
      ..sort((a, b) => '${leagues[a]}'.compareTo('${leagues[b]}'));
    return [
      const ListFilterSection(
        key: 'roster',
        label: 'Kadro durumu',
        options: [('all', 'Tümü'), ('in', 'Kadroda'), ('free', 'Boşta')],
        defaultValue: 'in',
        hint: 'Boşta: hiçbir etkin turnuva kadrosunda olmayan oyuncu.',
      ),
      if (ids.length > 1)
        ListFilterSection(
          key: 'league',
          label: 'Turnuva',
          dropdown: true,
          options: [
            ('all', 'Tüm turnuvalar'),
            for (final id in ids) (id, '${leagues[id]}'),
          ],
          defaultValue: 'all',
        ),
      const ListFilterSection(
        key: 'profile',
        label: 'Kimlik',
        options: [('all', 'Tümü'), ('ver', 'Onaylı'), ('unv', 'Onaysız')],
        defaultValue: 'all',
      ),
      const ListFilterSection(
        key: 'account',
        label: 'Hesap',
        options: [('all', 'Tümü'), ('yes', 'Hesabı var'), ('no', 'Hesap yok')],
        defaultValue: 'all',
      ),
      const ListFilterSection(
        key: 'kvkk',
        label: 'KVKK onayı',
        options: [('all', 'Tümü'), ('ok', 'Onaylı'), ('wait', 'Bekliyor')],
        defaultValue: 'all',
      ),
    ];
  }

  /// Filtre penceresindeki sayılar: sunucu her bölüm için hesaplar.
  Future<ListFilterCounts> _counts(Map<String, String> v) async {
    final r = await _call(v, limit: 0);
    final facets = Map<String, dynamic>.from(r['facets'] as Map? ?? {});
    return ListFilterCounts(
      total: (r['total'] as num?)?.toInt() ?? 0,
      options: {
        for (final e in facets.entries)
          e.key: {
            for (final o in (e.value as Map? ?? {}).entries)
              o.key.toString(): (o.value as num).toInt(),
          },
      },
    );
  }

  Widget _serverList(bool isAdmin) {
    const accent = Color(0xFF10B981);
    if (_initial) {
      return const Center(child: CircularProgressIndicator(color: accent));
    }
    if (_error != null && _rows.isEmpty) {
      return Center(
        child: TextButton.icon(
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Liste yüklenemedi, tekrar dene'),
        ),
      );
    }
    final banner = Map<String, dynamic>.from(_meta['banner'] as Map? ?? {});
    final missing = (banner['missing'] as num?)?.toInt() ?? 0;
    final noAccount = (banner['no_account'] as num?)?.toInt() ?? 0;
    final head = (missing > 0 ? 1 : 0) + 1;
    final more = _rows.length < _total;
    return RefreshIndicator(
      onRefresh: _reload,
      color: accent,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        // Sağ alttaki düğmeler son kartı kapatmasın.
        padding: const EdgeInsets.only(
          bottom: kAdminFabClearance + 2 * kAdminFabStep,
        ),
        itemCount: head + (_rows.isEmpty ? 1 : _rows.length) + (more ? 1 : 0),
        itemBuilder: (context, i) {
          if (missing > 0 && i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ConsentSummaryBanner.counts(
                missing: missing,
                noAccount: noAccount,
              ),
            );
          }
          if (i == head - 1) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ListFilterBar(
                title: 'Futbolcuları filtrele',
                unit: 'futbolcu',
                sections: (_) => _sections(isAdmin),
                values: _filter,
                total: _total,
                counts: _counts,
                onChanged: (v) {
                  setState(() => _filter = v);
                  _reload();
                },
              ),
            );
          }
          if (_rows.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'Futbolcu bulunamadı.',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            );
          }
          final k = i - head;
          if (k >= _rows.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                ),
              ),
            );
          }
          final p = _rows[k];
          return _licenseCard(
            p,
            consent: _consent[p.id],
            free: _free.contains(p.id),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    final isAdmin = session.isAdmin;
    const accent = Color(0xFF10B981);

    return BandBackPage(
      subtitle: 'Lisans Yönetimi',
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        // Sağ altta: arama (kapalıyken), toplu yükleme (yalnız admin) ve
        // futbolcu ekleme (bölge sorumlusu ve üstü).
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!_searchOpen) ...[
              FloatingActionButton.small(
                heroTag: null,
                tooltip: 'Oyuncu ara',
                backgroundColor: accent,
                foregroundColor: Colors.white,
                onPressed: () {
                  setState(() => _searchOpen = true);
                  revealSearchField(_searchFocus);
                },
                child: const Icon(Icons.search_rounded, size: 20),
              ),
              const SizedBox(height: 12),
            ],
            if (isAdmin) ...[
              AdminBarAction(
                icon: Icons.upload_file_rounded,
                tooltip: 'Toplu Yükle (Excel)',
                onPressed: _openBulkUploadFlow,
              ).fab(small: true),
              const SizedBox(height: 12),
            ],
            // Futbolcular kendi hesaplarıyla kayıt olur; elle ekleme yalnız
            // admin.
            if (session.isAdmin)
              AdminBarAction(
                icon: Icons.person_add_alt_1_rounded,
                tooltip: 'Futbolcu Ekle',
                onPressed: _openPlayerForm,
              ).fab(),
          ],
        ),
        body: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(
                  children: [
                    if (_searchOpen) ...[
                      SizedBox(
                        height: 44,
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Oyuncu ara',
                            hintStyle: const TextStyle(color: Colors.white54),
                            prefixIcon: const Icon(Icons.search, color: accent),
                            suffixIcon: IconButton(
                              tooltip: 'Aramayı kapat',
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white54,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                _searchFocus.unfocus();
                                final had = _q.isNotEmpty;
                                setState(() {
                                  _q = '';
                                  _searchOpen = false;
                                });
                                if (had) _reload();
                              },
                            ),
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
                          onChanged: _onSearch,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Expanded(child: _serverList(isAdmin)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _licenseCard(
    PlayerModel p, {
    ConsentStatus? consent,
    bool free = false,
  }) {
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
                        VerifiedBadgeFor(playerId: p.id, size: 16, leading: 4),
                        if (consent != null && !consent.complete) ...[
                          const SizedBox(width: 6),
                          ConsentChip(status: consent),
                        ],
                        if (free) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22304A),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Boşta',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
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
              // Futbolcu bilgilerini yalnız admin düzenler.
              if (AppSession.of(context).value.isAdmin) ...[
                const SizedBox(width: 8),
                _SmallActionButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Düzenle',
                  color: Colors.white70,
                  onTap: () => _openPlayerForm(editing: p),
                ),
              ],
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
const _squadCard = Color(0xFF1E293B);

const _unknownPosition = 'Mevkisi belirtilmemiş';

const _positionOrder = [
  'Kaleci',
  'Defans',
  'Orta Saha',
  'Forvet',
  _unknownPosition,
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
  return _unknownPosition;
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
    this.countLabel = 'oyuncu',
    this.trailing,
  });

  final String title;
  final int count;
  final List<Widget> children;
  final String countLabel;

  /// Sağdaki sayı yerine gösterilir (ör. kontenjan "2 / 4").
  final Widget? trailing;

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
                trailing ??
                    Text(
                      '$count $countLabel',
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
    required this.managerName,
    required this.logoUrl,
    required this.players,
    required this.ageOf,
    required this.tournamentName,
    this.seasonLabel,
    this.onPickSeason,
    this.extraTournaments = 0,
    this.onPickTournament,
    this.firstColor,
    this.secondColor,
    this.onShare,
  });

  final String teamName;

  /// teams.manager_name; boşsa satır gösterilmez.
  final String managerName;
  final String logoUrl;
  final List<PlayerModel> players;
  final int? Function(PlayerModel) ageOf;

  /// Sol üstteki sezon düğmesi (ör. "2026 Sezonu"); null ise gizli.
  final String? seasonLabel;
  final VoidCallback? onPickSeason;

  /// Alt şeritteki turnuva; sezonda başka turnuva varsa şerit basılabilir.
  final String tournamentName;
  final int extraTournaments;
  final VoidCallback? onPickTournament;

  /// Takım renkleri (teams.first_color / second_color); yoksa yeşil tema.
  final String? firstColor;
  final String? secondColor;

  /// Kadro afişini paylaşır (sağ üstteki düğme).
  final VoidCallback? onShare;

  Widget _stat(String value, String label) {
    return Container(
      constraints: const BoxConstraints(minWidth: 52),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  /// Bandın köşesindeki yarı saydam hap düğme (sezon / paylaş).
  Widget _pill({required Widget child, VoidCallback? onTap, String? tooltip}) {
    final pill = Material(
      color: Colors.black.withValues(alpha: 0.28),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 34, minWidth: 34),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(widthFactor: 1, child: child),
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }

  @override
  Widget build(BuildContext context) {
    final ages = players.map(ageOf).whereType<int>().toList();
    final avgAge = ages.isEmpty
        ? '–'
        : (ages.reduce((a, b) => a + b) / ages.length).round().toString();
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
    final name = teamName.trim();
    // Uzun ad küçülür, en fazla iki satır.
    final nameSize = name.length > 26
        ? 15.0
        : name.length > 16
        ? 17.0
        : 20.0;

    // Takım renkli üst bant: soldan takımın ana rengi koyu zemine geçer
    // (maç detayı başlığıyla aynı dil); altta iki renkli ince şerit.
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tek satır: solda sezon, ortada oyuncu · logo · yaş, sağda
            // paylaş (bant dar kalsın).
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 76,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: seasonLabel == null
                          ? null
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _pill(
                                onTap: onPickSeason,
                                tooltip: 'Sezon seç',
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      seasonLabel!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (onPickSeason != null)
                                      const Icon(
                                        Icons.expand_more_rounded,
                                        size: 17,
                                        color: _squadAccent,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _stat('${players.length}', 'Oyuncu'),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 60,
                          height: 60,
                          child: logoUrl.trim().isNotEmpty
                              ? WebSafeImage(
                                  url: logoUrl,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.contain,
                                )
                              : Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        _stat(avgAge, 'Ort. yaş'),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 76,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: onShare == null
                          ? null
                          : _pill(
                              onTap: onShare,
                              tooltip: 'Kadro afişini paylaş',
                              child: const Icon(
                                Icons.ios_share_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Column(
                children: [
                  Text(
                    name.trUpper,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: nameSize,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 0.4,
                    ),
                  ),
                  if (managerName.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Takım Sorumlusu • ${managerName.trim()}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Material(
              color: const Color(0xFF0F172A).withValues(alpha: 0.55),
              child: InkWell(
                onTap: onPickTournament,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.emoji_events_outlined,
                        size: 17,
                        color: kAdminAmber,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          tournamentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (onPickTournament != null) ...[
                        if (extraTournaments > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '+$extraTournaments turnuva',
                            style: const TextStyle(
                              color: _squadMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: _squadAccent,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
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

/// Kadroya mevcut futbolcu ekleme popup'ı. En az 3 harf yazılınca arar;
/// sezonda başka bir takıma kayıtlı futbolcular kilitli gösterilir.
class _SeasonPlayerPicker extends StatefulWidget {
  const _SeasonPlayerPicker({
    required this.service,
    required this.seasonId,
    required this.teamId,
    required this.displayPosition,
    required this.normalizeUrl,
    this.requestApproval,
  });

  final SupabaseTeamService service;
  final String seasonId;
  final String teamId;
  final String Function(PlayerModel) displayPosition;
  final String Function(String) normalizeUrl;

  /// Verilirse seçilenler doğrudan eklenmez, her biri için onay talebi
  /// açılır (takım sorumlusu).
  final ApprovalService? requestApproval;

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
  List<({PlayerModel player, String? teamId, String? teamName, bool free})>
  _results = const [];

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
      final approval = widget.requestApproval;
      if (approval != null) {
        // Her oyuncu ayrı talep; biri için bekleyen talep varsa diğerleri
        // yine gönderilir.
        final failed = <String>[];
        var sent = 0;
        for (final p in [..._selected.values]) {
          try {
            await approval.submit(
              type: PendingActionType.rosterAdd,
              seasonId: widget.seasonId,
              teamId: widget.teamId,
              payload: {'player_id': p.id, 'player_name': p.name},
            );
            _selected.remove(p.id);
            sent++;
          } catch (e) {
            final msg = e.toString();
            failed.add(
              msg.contains('pending_actions_one_open_per_player') ||
                      msg.contains('23505')
                  ? '${p.name}: zaten onay bekleyen bir talep var'
                  : '${p.name}: ${msg.replaceFirst('Exception: ', '').trim()}',
            );
          }
        }
        if (failed.isNotEmpty) {
          if (!mounted) return;
          await showAdminInfoDialog(
            context: context,
            title: sent > 0
                ? 'Bazı talepler gönderilemedi'
                : 'Talep gönderilemedi',
            message: failed.join('\n'),
          );
          if (!mounted) return;
          if (sent == 0) {
            setState(() => _busy = false);
            return;
          }
        }
      } else {
        await widget.service.addMultiplePlayersToTeam(
          _selected.keys.toList(),
          widget.teamId,
          widget.seasonId,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      // Popup'ın üstünde göster (SnackBar arkada kalıyordu).
      await showAdminInfoDialog(
        context: context,
        title: widget.requestApproval != null
            ? 'Talep gönderilemedi'
            : 'Eklenemedi',
        message: msg,
      );
      if (mounted) setState(() => _busy = false);
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
                        widget.requestApproval != null
                            ? (_selected.isEmpty
                                  ? 'ONAYA GÖNDER'
                                  : 'ONAYA GÖNDER (${_selected.length})')
                            : _selected.isEmpty
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

  Widget _buildRow(
    ({PlayerModel player, String? teamId, String? teamName, bool free}) r,
  ) {
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (r.free) ...[
                            const SizedBox(width: 6),
                            const _FreeTag(),
                          ],
                        ],
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

/// "Boşta" etiketi: hiçbir etkin turnuva kadrosunda olmayan futbolcu.
class _FreeTag extends StatelessWidget {
  const _FreeTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFF22304A),
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Text(
      'Boşta',
      style: TextStyle(
        color: Color(0xFFCBD5E1),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Yanıp sönen simge (Uyarılar sekmesinde eksik varken).
class _BlinkingIcon extends StatefulWidget {
  const _BlinkingIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  State<_BlinkingIcon> createState() => _BlinkingIconState();
}

class _BlinkingIconState extends State<_BlinkingIcon>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_c),
      child: Icon(widget.icon, size: 21, color: widget.color),
    );
  }
}
