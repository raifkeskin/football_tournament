import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../models/season.dart';
import '../services/interfaces/i_league_service.dart';
import '../../match/models/match.dart';
import '../../team/models/team.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/resilient_stream.dart';
import '../../../core/utils/table_feed.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../../core/widgets/master_class_app_bar.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../team/screens/team_squad_screen.dart';
import '../../../core/utils/string_utils.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../widgets/league_owners_section.dart';

// Fikstür / Ana Sayfa ile ortak renkler
const _bgDark = Color(0xFF0F172A);
const _sheetBg = Color(0xFF1E293B);
const _accent = Color(0xFF10B981);
const _forest = Color(0xFF064E3B);

class SeasonManagementScreen extends StatelessWidget {
  const SeasonManagementScreen({
    super.key,
    required this.leagueId,
    required this.leagueName,
    required this.leagueLogoUrl,
  });

  final String leagueId;
  final String leagueName;
  final String leagueLogoUrl;

  SupabaseClient get _sb => Supabase.instance.client;

  Stream<List<Season>> _watchSeasons() {
    // Önce normal sorgu, canlı bağlantı arkadan (bkz. watchTableRows).
    return watchTableRows(
      _sb,
      table: 'seasons',
      column: 'league_id',
      value: leagueId,
      orderBy: 'start_date',
      ascending: false,
    ).map(
      (rows) => rows.cast<Map<String, dynamic>>().map(Season.fromJson).toList(),
    );
  }

  static String _tarihYaz(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  static String _dateOnly(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _openSeasonSheet(BuildContext context, {Season? season}) async {
    final isEdit = season != null;
    final messenger = ScaffoldMessenger.of(context);
    final nameController = TextEditingController(text: season?.name ?? '');
    final subtitleController = TextEditingController(
      text: (season?.subtitle ?? '').trim(),
    );
    final startDateController = TextEditingController(
      text: season?.startDate == null ? '' : _tarihYaz(season!.startDate!),
    );
    final endDateController = TextEditingController(
      text: season?.endDate == null ? '' : _tarihYaz(season!.endDate!),
    );
    final startingPlayerCountController = TextEditingController(
      text: (season?.startingPlayerCount ?? 11).toString(),
    );
    final subPlayerCountController = TextEditingController(
      text: (season?.subPlayerCount ?? 7).toString(),
    );
    // İl artık bölgede seçilir; eski sezonların şehir değeri korunur.
    final cityController = TextEditingController(
      text: (season?.city ?? '').trim(),
    );
    final countryController = TextEditingController(
      text: (season?.country ?? 'Türkiye').trim().isEmpty
          ? 'Türkiye'
          : (season?.country ?? 'Türkiye').trim(),
    );
    final transferStartController = TextEditingController(
      text: season?.transferStartDate == null
          ? ''
          : _tarihYaz(season!.transferStartDate!),
    );
    final transferEndController = TextEditingController(
      text: season?.transferEndDate == null
          ? ''
          : _tarihYaz(season!.transferEndDate!),
    );
    final teamsPerGroupController = TextEditingController(
      text: (season?.teamsPerGroup ?? 4).toString(),
    );
    final numberOfGroupsController = TextEditingController(
      text: (season?.numberOfGroups ?? 1).toString(),
    );
    final instagramController = TextEditingController(
      text: (season?.instagramUrl ?? '').trim(),
    );
    final youtubeController = TextEditingController(
      text: (season?.youtubeUrl ?? '').trim(),
    );
    final matchPeriodDurationController = TextEditingController(
      text: (season?.matchPeriodDuration ?? 25).toString(),
    );
    final numberOfPlayerChangesController = TextEditingController(
      text: (season?.numberOfPlayerChanges ?? 3).toString(),
    );

    DateTime? startDate = season?.startDate;
    DateTime? endDate = season?.endDate;
    DateTime? transferStartDate = season?.transferStartDate;
    DateTime? transferEndDate = season?.transferEndDate;
    var isActive = season?.isActive ?? true;
    var isDefault = season?.isDefault ?? false;
    var isDoubleRound = season?.isDoubleRound ?? false;
    var saving = false;

    Future<void> pickDate({
      required StateSetter setSheetState,
      required bool isStart,
    }) async {
      final now = DateTime.now();
      final initial = isStart
          ? (startDate ?? now)
          : (endDate ?? startDate ?? now);
      final picked = await showAppDatePicker(
        context: context,
        initialDate: initial,
        firstYear: now.year - 2,
        lastYear: now.year + 5,
      );
      if (picked == null) return;
      setSheetState(() {
        if (isStart) {
          startDate = picked;
          startDateController.text = _tarihYaz(picked);
        } else {
          endDate = picked;
          endDateController.text = _tarihYaz(picked);
        }
      });
    }

    Future<void> pickTransferDate({
      required StateSetter setSheetState,
      required bool isStart,
    }) async {
      final now = DateTime.now();
      final initial = isStart
          ? (transferStartDate ?? now)
          : (transferEndDate ?? transferStartDate ?? now);
      final picked = await showAppDatePicker(
        context: context,
        initialDate: initial,
        firstYear: now.year - 2,
        lastYear: now.year + 5,
      );
      if (picked == null) return;
      setSheetState(() {
        if (isStart) {
          transferStartDate = picked;
          transferStartController.text = _tarihYaz(picked);
        } else {
          transferEndDate = picked;
          transferEndController.text = _tarihYaz(picked);
        }
      });
    }

    Future<void> submit(
      BuildContext sheetContext,
      StateSetter setSheetState,
    ) async {
      final name = nameController.text.trim();
      final subtitle = subtitleController.text.trim();
      if (name.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Sezon adı zorunludur.')),
        );
        return;
      }
      if (startDate == null || endDate == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Başlangıç ve bitiş tarihi zorunludur.'),
          ),
        );
        return;
      }

      final built = Season(
        id: season?.id ?? '',
        leagueId: leagueId,
        name: name,
        subtitle: subtitle.isEmpty ? null : subtitle,
        startDate: startDate,
        endDate: endDate,
        startingPlayerCount:
            int.tryParse(startingPlayerCountController.text.trim()) ?? 11,
        subPlayerCount: int.tryParse(subPlayerCountController.text.trim()) ?? 7,
        city: cityController.text.trim().isEmpty
            ? null
            : cityController.text.trim(),
        country: countryController.text.trim().isEmpty
            ? 'Türkiye'
            : countryController.text.trim(),
        isActive: isActive,
        isDefault: isDefault,
        isDoubleRound: isDoubleRound,
        transferStartDate: transferStartDate,
        transferEndDate: transferEndDate,
        teamsPerGroup: int.tryParse(teamsPerGroupController.text.trim()) ?? 4,
        numberOfGroups: int.tryParse(numberOfGroupsController.text.trim()) ?? 1,
        instagramUrl: instagramController.text.trim().isEmpty
            ? null
            : instagramController.text.trim(),
        youtubeUrl: youtubeController.text.trim().isEmpty
            ? null
            : youtubeController.text.trim(),
        matchPeriodDuration:
            int.tryParse(matchPeriodDurationController.text.trim()) ?? 25,
        numberOfPlayerChanges:
            int.tryParse(numberOfPlayerChangesController.text.trim()) ?? 3,
      );

      setSheetState(() => saving = true);
      try {
        final payload = Map<String, dynamic>.from(built.toJson());
        payload.remove('id');
        payload['start_date'] = _dateOnly(startDate!);
        payload['end_date'] = _dateOnly(endDate!);

        String seasonId;
        if (isEdit) {
          await _sb.from('seasons').update(payload).eq('id', season.id);
          seasonId = season.id;
        } else {
          final res = await _sb
              .from('seasons')
              .insert(payload)
              .select('id')
              .single();
          seasonId = (res['id'] ?? '').toString().trim();
        }

        // Tek gruplu sezonda grup, turnuva adıyla otomatik oluşturulur.
        if (built.numberOfGroups == 1 && seasonId.isNotEmpty) {
          final existing = await _sb
              .from('groups')
              .select('id')
              .eq('season_id', seasonId)
              .limit(1);
          if ((existing as List).isEmpty) {
            await _sb.from('groups').insert({
              'season_id': seasonId,
              'name': leagueName.trim().isEmpty ? name : leagueName.trim(),
            });
          }
        }

        // Başarılı kayıtta sheet kapanır; kapanmış sheet'e setState yapılmaz.
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Güncellendi.' : 'Sezon oluşturuldu.'),
          ),
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
        if (sheetContext.mounted) setSheetState(() => saving = false);
      }
    }

    Widget textRow(
      IconData icon,
      String label,
      TextEditingController controller, {
      String? hint,
      bool number = false,
      TextInputType? keyboardType,
    }) {
      return AdminFieldRow(
        icon: icon,
        label: label,
        child: TextField(
          controller: controller,
          enabled: !saving,
          keyboardType: number ? TextInputType.number : keyboardType,
          inputFormatters: number
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          decoration: adminInlineInputDecoration(hint: hint),
        ),
      );
    }

    Widget dateRow(
      IconData icon,
      String label,
      TextEditingController controller,
      VoidCallback onTap,
    ) {
      return AdminSelectRow(
        icon: icon,
        label: label,
        value: controller.text,
        placeholder: 'Tarih seçin',
        onTap: saving ? null : onTap,
      );
    }

    Widget switchRow(
      IconData icon,
      String label,
      String hint,
      bool value,
      ValueChanged<bool> onChanged,
    ) {
      return AdminFieldRow(
        icon: icon,
        label: label,
        onTap: saving ? null : () => onChanged(!value),
        trailing: Switch(
          value: value,
          activeThumbColor: _accent,
          onChanged: saving ? null : onChanged,
        ),
        child: Text(
          hint,
          style: const TextStyle(color: kAdminMuted, fontSize: 13),
        ),
      );
    }

    await _showAdminSheet<void>(
      context: context,
      builder: (sheetContext, setSheetState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(
              icon: Icons.calendar_month_outlined,
              title: isEdit ? 'Sezon Düzenle' : 'Sezon Ekle',
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    AdminFormSection(
                      title: 'Genel',
                      child: AdminFieldGroup(
                        children: [
                          textRow(
                            Icons.emoji_events_outlined,
                            'Sezon Adı',
                            nameController,
                            hint: 'Örn. 2026-2027 Sezonu',
                          ),
                          textRow(
                            Icons.short_text_rounded,
                            'Alt Başlık',
                            subtitleController,
                            hint: 'İsteğe bağlı',
                          ),
                          textRow(
                            Icons.flag_outlined,
                            'Ülke',
                            countryController,
                            hint: 'Türkiye',
                          ),
                        ],
                      ),
                    ),
                    AdminFormSection(
                      title: 'Tarihler',
                      child: AdminFieldGroup(
                        children: [
                          dateRow(
                            Icons.play_circle_outline_rounded,
                            'Sezon Başlangıcı',
                            startDateController,
                            () => pickDate(
                              setSheetState: setSheetState,
                              isStart: true,
                            ),
                          ),
                          dateRow(
                            Icons.flag_circle_outlined,
                            'Sezon Bitişi',
                            endDateController,
                            () => pickDate(
                              setSheetState: setSheetState,
                              isStart: false,
                            ),
                          ),
                          dateRow(
                            Icons.swap_horiz_rounded,
                            'Transfer Başlangıcı',
                            transferStartController,
                            () => pickTransferDate(
                              setSheetState: setSheetState,
                              isStart: true,
                            ),
                          ),
                          dateRow(
                            Icons.event_busy_outlined,
                            'Transfer Bitişi',
                            transferEndController,
                            () => pickTransferDate(
                              setSheetState: setSheetState,
                              isStart: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AdminFormSection(
                      title: 'Maç ve Kadro',
                      child: AdminFieldGroup(
                        children: [
                          textRow(
                            Icons.groups_outlined,
                            'İlk 11 Oyuncu Sayısı',
                            startingPlayerCountController,
                            number: true,
                          ),
                          textRow(
                            Icons.event_seat_outlined,
                            'Yedek Oyuncu Sayısı',
                            subPlayerCountController,
                            number: true,
                          ),
                          textRow(
                            Icons.timer_outlined,
                            'Devre Süresi (dk)',
                            matchPeriodDurationController,
                            number: true,
                          ),
                          textRow(
                            Icons.swap_vert_rounded,
                            'Oyuncu Değişikliği Sınırı',
                            numberOfPlayerChangesController,
                            number: true,
                          ),
                        ],
                      ),
                    ),
                    AdminFormSection(
                      title: 'Gruplar',
                      child: AdminFieldGroup(
                        children: [
                          textRow(
                            Icons.shield_outlined,
                            'Toplam Takım Sayısı',
                            teamsPerGroupController,
                            number: true,
                          ),
                          textRow(
                            Icons.grid_view_rounded,
                            'Grup Sayısı',
                            numberOfGroupsController,
                            number: true,
                          ),
                          switchRow(
                            Icons.sync_alt_rounded,
                            'Rövanşlı',
                            isDoubleRound
                                ? 'Her eşleşme iki maç (rövanşlı)'
                                : 'Her eşleşme tek maç',
                            isDoubleRound,
                            (v) => setSheetState(() => isDoubleRound = v),
                          ),
                        ],
                      ),
                    ),
                    AdminFormSection(
                      title: 'Durum',
                      child: AdminFieldGroup(
                        children: [
                          switchRow(
                            Icons.check_circle_outline_rounded,
                            'Aktif',
                            'Sezon uygulamada görünür',
                            isActive,
                            (v) => setSheetState(() => isActive = v),
                          ),
                          switchRow(
                            Icons.star_outline_rounded,
                            'Varsayılan',
                            'Turnuva açılınca bu sezon seçilir',
                            isDefault,
                            (v) => setSheetState(() => isDefault = v),
                          ),
                        ],
                      ),
                    ),
                    AdminFormSection(
                      title: 'Sosyal Medya',
                      child: AdminFieldGroup(
                        children: [
                          textRow(
                            Icons.camera_alt_outlined,
                            'Instagram',
                            instagramController,
                            hint: 'https://instagram.com/...',
                            keyboardType: TextInputType.url,
                          ),
                          textRow(
                            Icons.smart_display_outlined,
                            'YouTube',
                            youtubeController,
                            hint: 'https://youtube.com/...',
                            keyboardType: TextInputType.url,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _SaveButton(
              label: isEdit ? 'GÜNCELLE' : 'KAYDET',
              saving: saving,
              onPressed: () => submit(sheetContext, setSheetState),
            ),
            const SizedBox(height: 10),
            _CancelButton(
              onPressed: saving ? null : () => Navigator.of(sheetContext).pop(),
            ),
          ],
        );
      },
    );

    _disposeControllersLater([
      nameController,
      subtitleController,
      startDateController,
      endDateController,
      startingPlayerCountController,
      subPlayerCountController,
      cityController,
      countryController,
      transferStartController,
      transferEndController,
      teamsPerGroupController,
      numberOfGroupsController,
      instagramController,
      youtubeController,
      matchPeriodDurationController,
      numberOfPlayerChangesController,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // Kurucu/admin tüm sezonları yönetir; bölge sorumlusu yalnızca kendi
    // bölgesinin sezonunu görür, sezon ekleyip düzenleyemez.
    final session = AppSession.of(context).value;
    final full = session.canManageLeague(leagueId);
    final regionSeasons = {for (final r in session.ownedRegions) r.seasonId};
    return _AdminPageScaffold(
      title: leagueName.trim().isEmpty ? 'Sezonlar' : leagueName,
      actions: [
        if (full)
          IconButton(
            onPressed: () => _openSeasonSheet(context),
            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            tooltip: 'Sezon Ekle',
          ),
      ],
      body: StreamBuilder<List<Season>>(
        stream: _watchSeasons(),
        builder: (_, snapshot) {
          if (snapshot.hasError) {
            return _EmptyText('Hata: ${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _accent),
            );
          }
          final seasons = [
            for (final s in snapshot.data ?? const <Season>[])
              if (full || regionSeasons.contains(s.id)) s,
          ];
          if (seasons.isEmpty) {
            return const _EmptyText('Sezon bulunamadı.');
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: seasons.length + (full ? 1 : 0),
            itemBuilder: (_, index) {
              if (index == seasons.length) {
                return _AddDashedButton(
                  label: 'Yeni Sezon Ekle',
                  onTap: () => _openSeasonSheet(context),
                );
              }
              final s = seasons[index];
              return _SeasonCard(
                season: s,
                onEdit: full
                    ? () => _openSeasonSheet(context, season: s)
                    : null,
                onTap: (hasRegions) {
                  // Bölgeli sezon: önce Bölgeler; bölgesiz: doğrudan Gruplar.
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => hasRegions || !full
                          ? SeasonRegionsScreen(
                              leagueId: leagueId,
                              seasonId: s.id,
                              seasonName: s.name,
                            )
                          : SeasonGroupsScreen(
                              leagueId: leagueId,
                              seasonId: s.id,
                              seasonName: s.name,
                            ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Takım seçicide gösterilen satır: tüm takımlar + bu sezondaki grup bilgisi.
class _TeamOption {
  const _TeamOption({
    required this.id,
    required this.name,
    required this.logoUrl,
    this.groupId,
    this.groupName,
  });

  final String id;
  final String name;
  final String logoUrl;
  final String? groupId;
  final String? groupName;
}

class SeasonGroupsScreen extends StatefulWidget {
  const SeasonGroupsScreen({
    super.key,
    required this.leagueId,
    required this.seasonId,
    required this.seasonName,
    this.regionId,
    this.regionName,
  });

  final String leagueId;
  final String seasonId;
  final String seasonName;

  /// Bölge modu: yalnızca bu bölgenin grupları ('' = bölgesiz gruplar).
  /// null: sezonun bölgesi yok, tüm gruplar.
  final String? regionId;
  final String? regionName;

  @override
  State<SeasonGroupsScreen> createState() => _SeasonGroupsScreenState();
}

class _SeasonGroupsScreenState extends State<SeasonGroupsScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;

  SupabaseClient get _sb => Supabase.instance.client;

  StreamSubscription<List<GroupModel>>? _groupsSub;
  List<GroupModel>? _groups;
  Object? _groupsError;
  Map<String, int> _teamCountByGroupId = const <String, int>{};
  _SeasonOverview? _overview;
  bool _busy = false;

  /// Sezonun bölgeleri (Turnuva > Sezon > Bölge > Grup).
  List<_Region> _regions = const <_Region>[];

  Future<void> _loadRegions() async {
    try {
      final rows = await _sb
          .from('season_regions')
          .select('id, name, city, sort_order')
          .eq('season_id', widget.seasonId)
          .order('sort_order', ascending: true)
          .order('name', ascending: true);
      if (!mounted) return;
      setState(() {
        _regions = [
          for (final r in rows)
            _Region(
              id: (r['id'] ?? '').toString(),
              name: (r['name'] ?? '').toString(),
            ),
        ];
      });
    } catch (e) {
      debugPrint('Bölgeler okunamadı: $e');
    }
  }

  String? _regionName(String? id) {
    for (final r in _regions) {
      if (r.id == id) return r.name;
    }
    return null;
  }

  /// Bölge seçimi (grup formunda). Döner: seçilen bölge id'si; '' = bölgesiz;
  /// null = vazgeçildi.
  Future<String?> _pickRegion(String? current) {
    return _showAdminSheet<String>(
      context: context,
      compact: true,
      builder: (sheetContext, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHeader(icon: Icons.map_outlined, title: 'Bölge Seç'),
          for (final r in [
            ..._regions,
            const _Region(id: '', name: 'Bölgesiz'),
          ])
            ListTile(
              title: Text(r.name, style: const TextStyle(color: Colors.white)),
              trailing: (current ?? '') == r.id
                  ? const Icon(Icons.check_rounded, color: _accent)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(r.id),
            ),
          const SizedBox(height: 10),
          _CancelButton(onPressed: () => Navigator.of(sheetContext).pop()),
        ],
      ),
    );
  }

  /// Bölge modunda grup ekranının sağ üstündeki "Sorumlular".
  Future<void> _openRegionOwners() async {
    final id = widget.regionId;
    if (id == null || id.isEmpty) return;
    await _showRegionOwnersSheet(
      context,
      _Region(id: id, name: widget.regionName ?? ''),
    );
  }

  /// Bölgesiz sezonda ilk bölgeyi ekler ve Bölgeler ekranına geçer.
  Future<void> _splitIntoRegions() async {
    final added = await _addRegion(
      context,
      seasonId: widget.seasonId,
      existing: _regions,
    );
    if (!added || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SeasonRegionsScreen(
          leagueId: widget.leagueId,
          seasonId: widget.seasonId,
          seasonName: widget.seasonName,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Stream'ler build içinde değil burada bir kez dinlenir; aksi halde her
    // rebuild'de yeni realtime aboneliği açılıyordu.
    _groupsSub =
        resilientStream(
          () => _leagueService.watchGroups(widget.seasonId),
        ).listen(
          (groups) {
            if (!mounted) return;
            setState(() {
              _groups = groups;
              _groupsError = null;
            });
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() => _groupsError = e);
          },
        );
    _refreshTeamCounts();
    _loadRegions();
  }

  @override
  void dispose() {
    _groupsSub?.cancel();
    super.dispose();
  }

  /// Grup başına takım sayısını `season_teams` tablosundan doğrudan çeker.
  /// Realtime'a güvenilmez; her kayıttan sonra çağrılır.
  Future<void> _refreshTeamCounts() async {
    final sid = widget.seasonId.trim();
    if (sid.isEmpty) {
      return;
    }
    try {
      final rows = await _sb
          .from('season_teams')
          .select('group_id')
          .eq('season_id', sid);
      final counts = <String, int>{};
      for (final any in rows) {
        final gid = ((any as Map)['group_id'] ?? '').toString().trim();
        if (gid.isEmpty) continue;
        counts[gid] = (counts[gid] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() => _teamCountByGroupId = counts);
      // Kart özetleri (maçlar, lider, avatarlar); hata olursa kartlar sade kalır.
      _loadSeasonOverview(sid).then((o) {
        if (mounted) setState(() => _overview = o);
      }, onError: (_) {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Takım sayıları alınamadı: $e')));
    }
  }

  String _formatGroupName(String? input) {
    final raw = (input ?? '').trim();
    if (raw.isEmpty) return '';
    var cleaned = raw.replaceAll(
      RegExp(r'\bgrub(?:u)?\b|\bgrup(?:u)?\b', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return '';
    return '$cleaned Grubu';
  }

  /// Seçici için takımları getirir: admin tümünü; kurucu / bölge sorumlusu
  /// bu turnuvada yer almış ve henüz hiçbir sezona bağlanmamış takımları
  /// (başka turnuvaların takımları listelenmez; bkz. list_linkable_teams).
  Future<List<_TeamOption>?> _loadTeamOptions() async {
    setState(() => _busy = true);
    try {
      final teamsRes =
          await _sb.rpc(
                'list_linkable_teams',
                params: {'p_season_id': widget.seasonId.trim()},
              )
              as List;
      final linksRes = await _sb
          .from('season_teams')
          .select('team_id, group_id')
          .eq('season_id', widget.seasonId.trim());

      final groupNameById = <String, String>{
        for (final g in _groups ?? const <GroupModel>[]) g.id: g.name,
      };
      final groupIdByTeam = <String, String>{};
      for (final any in linksRes) {
        final row = Map<String, dynamic>.from(any as Map);
        final tid = (row['team_id'] ?? '').toString().trim();
        final gid = (row['group_id'] ?? '').toString().trim();
        if (tid.isNotEmpty && gid.isNotEmpty) groupIdByTeam[tid] = gid;
      }

      final options = <_TeamOption>[];
      for (final any in teamsRes) {
        final t = Team.fromMap(Map<String, dynamic>.from(any as Map));
        if (t.id.trim().isEmpty) continue;
        final gid = groupIdByTeam[t.id];
        options.add(
          _TeamOption(
            id: t.id,
            name: t.name.trim().isEmpty ? t.id : t.name.trim(),
            logoUrl: t.logoUrl,
            groupId: gid,
            groupName: gid == null ? null : groupNameById[gid],
          ),
        );
      }
      return options;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Takımlar yüklenemedi: $e')));
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Takımları bu sezonun ilgili grubuna bağlar / gruptan çıkarır.
  /// Hatalar yutulmaz; çağıran tarafa iletilir.
  /// `season_teams` tablosunda group_name kolonu yok; grup adı `groups`
  /// tablosundan group_id ile okunur.
  Future<void> _assignTeamsToGroup({
    required String groupId,
    required Set<String> add,
    required Set<String> remove,
  }) async {
    final sid = widget.seasonId.trim();
    for (final teamId in add) {
      final updated = await _sb
          .from('season_teams')
          .update({'group_id': groupId})
          .eq('season_id', sid)
          .eq('team_id', teamId)
          .select('id');
      if (updated.isEmpty) {
        await _sb.from('season_teams').insert({
          'season_id': sid,
          'team_id': teamId,
          'group_id': groupId,
        });
      }
    }
    if (remove.isNotEmpty) {
      await _sb
          .from('season_teams')
          .update({'group_id': null})
          .eq('season_id', sid)
          .eq('group_id', groupId)
          .inFilter('team_id', remove.toList());
    }
  }

  Future<Set<String>?> _pickTeams({
    required List<_TeamOption> options,
    required Set<String> initial,
    String? currentGroupId,
  }) async {
    // Seçim ve arama durumu builder dışında tutulur; klavye açılınca sheet
    // yeniden build edildiğinde seçimler sıfırlanmaz.
    final working = <String>{...initial};
    final qController = TextEditingController();

    final picked = await _showAdminSheet<Set<String>>(
      context: context,
      builder: (sheetContext, setPickerState) {
        final q = _norm(qController.text);
        final filtered = options.where((t) {
          if (q.isEmpty) return true;
          return _norm(t.name).contains(q);
        }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(
              icon: Icons.playlist_add_check_outlined,
              title: 'Takım Seç',
              subtitle: '${working.length} takım seçildi',
            ),
            TextField(
              controller: qController,
              decoration: const InputDecoration(
                labelText: 'Takım Ara',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setPickerState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? _EmptyText(
                      options.isEmpty
                          ? 'Kayıtlı takım yok. Önce Takım Yönetimi’nden takım ekleyin.'
                          : 'Takım bulunamadı.',
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final t = filtered[index];
                        final inOtherGroup =
                            (t.groupId ?? '').isNotEmpty &&
                            t.groupId != currentGroupId;
                        return CheckboxListTile(
                          value: working.contains(t.id),
                          activeColor: _accent,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          onChanged: (val) {
                            setPickerState(() {
                              if (val == true) {
                                working.add(t.id);
                              } else {
                                working.remove(t.id);
                              }
                            });
                          },
                          title: Text(
                            t.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: inOtherGroup
                              ? Text(
                                  '${_formatGroupName(t.groupName).isEmpty ? 'Başka bir grupta' : _formatGroupName(t.groupName)} • seçilirse taşınır',
                                  style: const TextStyle(
                                    color: Color(0xFFF59E0B),
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                          secondary: WebSafeImage(
                            url: t.logoUrl,
                            width: 32,
                            height: 32,
                            borderRadius: BorderRadius.circular(8),
                            fallbackIconSize: 16,
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            _SaveButton(
              label: 'SEÇİMİ ONAYLA',
              onPressed: () =>
                  Navigator.of(sheetContext).pop(<String>{...working}),
            ),
            const SizedBox(height: 10),
            _CancelButton(onPressed: () => Navigator.of(sheetContext).pop()),
          ],
        );
      },
    );

    _disposeControllersLater([qController]);
    return picked;
  }

  Future<void> _openAddGroupSheet() async {
    final messenger = ScaffoldMessenger.of(context);
    final nameController = TextEditingController();
    final selectedTeamIds = <String>{};
    List<_TeamOption>? options;
    var saving = false;
    final regionId = (widget.regionId ?? '').isEmpty ? null : widget.regionId;

    Future<void> openTeamPicker(StateSetter setSheetState) async {
      options ??= await _loadTeamOptions();
      final opts = options;
      if (opts == null || !mounted) return;
      final picked = await _pickTeams(options: opts, initial: selectedTeamIds);
      if (picked == null) return;
      setSheetState(() {
        selectedTeamIds
          ..clear()
          ..addAll(picked);
      });
    }

    Future<void> submit(
      BuildContext sheetContext,
      StateSetter setSheetState,
    ) async {
      final name = nameController.text.trim();
      if (name.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Grup adı zorunludur.')),
        );
        return;
      }
      setSheetState(() => saving = true);
      try {
        final res = await _sb
            .from('groups')
            .insert({
              'season_id': widget.seasonId,
              'name': name,
              'region_id': regionId,
            })
            .select('id')
            .single();
        final groupId = (res['id'] ?? '').toString().trim();
        if (groupId.isEmpty) throw Exception('Grup oluşturulamadı.');

        await _assignTeamsToGroup(
          groupId: groupId,
          add: selectedTeamIds,
          remove: const <String>{},
        );

        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        messenger.showSnackBar(const SnackBar(content: Text('Grup eklendi.')));
        await _refreshTeamCounts();
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
        if (sheetContext.mounted) setSheetState(() => saving = false);
      }
    }

    await _showAdminSheet<void>(
      context: context,
      compact: true,
      builder: (sheetContext, setSheetState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHeader(icon: Icons.groups_outlined, title: 'Grup Ekle'),
            AdminFormSection(
              title: 'Grup',
              child: AdminFieldGroup(
                children: [
                  _groupNameRow(nameController, enabled: !saving),
                  AdminSelectRow(
                    icon: Icons.playlist_add_check_outlined,
                    label: 'Takımlar',
                    value: selectedTeamIds.isEmpty
                        ? null
                        : '${selectedTeamIds.length} takım seçildi',
                    placeholder: 'Takım ekle / çıkar',
                    onTap: saving ? null : () => openTeamPicker(setSheetState),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _SaveButton(
              label: 'KAYDET',
              saving: saving,
              onPressed: () => submit(sheetContext, setSheetState),
            ),
            const SizedBox(height: 10),
            _CancelButton(
              onPressed: saving ? null : () => Navigator.of(sheetContext).pop(),
            ),
          ],
        );
      },
    );

    _disposeControllersLater([nameController]);
  }

  /// Grup adı satırı (en fazla 40 karakter).
  Widget _groupNameRow(TextEditingController c, {required bool enabled}) {
    return AdminFieldRow(
      icon: Icons.label_outline_rounded,
      label: 'Grup Adı',
      child: TextField(
        controller: c,
        enabled: enabled,
        maxLength: 40,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        decoration: adminInlineInputDecoration(
          hint: 'Örn. Avrupa Yakası',
        ).copyWith(counterText: ''),
      ),
    );
  }

  Future<void> _openEditGroupSheet(GroupModel g) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: g.name.trim());
    var saving = false;
    var regionId = g.regionId;

    Future<void> submit(
      BuildContext sheetContext,
      StateSetter setSheetState,
    ) async {
      final next = controller.text.trim();
      if (next.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Grup adı zorunludur.')),
        );
        return;
      }
      setSheetState(() => saving = true);
      try {
        // Grup adı yalnızca `groups` tablosunda tutulur; takımlar gruba
        // `season_teams.group_id` ile bağlı olduğundan ek güncelleme gerekmez.
        await _sb
            .from('groups')
            .update({'name': next, 'region_id': regionId})
            .eq('id', g.id);

        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        messenger.showSnackBar(const SnackBar(content: Text('Güncellendi.')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
        if (sheetContext.mounted) setSheetState(() => saving = false);
      }
    }

    await _showAdminSheet<void>(
      context: context,
      compact: true,
      builder: (sheetContext, setSheetState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHeader(
              icon: Icons.edit_outlined,
              title: 'Grup Düzenle',
            ),
            AdminFormSection(
              title: 'Grup',
              child: AdminFieldGroup(
                children: [
                  _groupNameRow(controller, enabled: !saving),
                  if (_regions.isNotEmpty &&
                      AppSession.of(
                        context,
                      ).value.canManageLeague(widget.leagueId))
                    AdminSelectRow(
                      icon: Icons.map_outlined,
                      label: 'Bölge',
                      value: _regionName(regionId),
                      placeholder: 'Bölgesiz',
                      onTap: saving
                          ? null
                          : () async {
                              final r = await _pickRegion(regionId);
                              if (r == null) return;
                              setSheetState(
                                () => regionId = r.isEmpty ? null : r,
                              );
                            },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _SaveButton(
              label: 'KAYDET',
              saving: saving,
              onPressed: () => submit(sheetContext, setSheetState),
            ),
            const SizedBox(height: 10),
            _CancelButton(
              onPressed: saving ? null : () => Navigator.of(sheetContext).pop(),
            ),
          ],
        );
      },
    );

    _disposeControllersLater([controller]);
  }

  Future<void> _openTeamAssignSheet(GroupModel group) async {
    final messenger = ScaffoldMessenger.of(context);

    final options = await _loadTeamOptions();
    if (options == null || !mounted) return;

    final prev = <String>{
      for (final t in options)
        if (t.groupId == group.id) t.id,
    };
    final picked = await _pickTeams(
      options: options,
      initial: prev,
      currentGroupId: group.id,
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await _assignTeamsToGroup(
        groupId: group.id,
        add: picked.difference(prev),
        remove: prev.difference(picked),
      );
      messenger.showSnackBar(const SnackBar(content: Text('Kaydedildi.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refreshTeamCounts();
  }

  Future<void> _openTeams({String? initialGroupName}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeamListScreen(
          seasonId: widget.seasonId,
          seasonName: widget.seasonName,
          initialGroupName: initialGroupName,
        ),
      ),
    );
    await _refreshTeamCounts();
  }

  Widget _buildBody() {
    if (_groupsError != null) {
      return _EmptyText('Hata: $_groupsError');
    }
    final loaded = _groups;
    if (loaded == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    final regionIds = {for (final r in _regions) r.id};
    final rid = widget.regionId;
    final groups = [
      for (final g in loaded)
        if (rid == null ||
            (rid.isEmpty ? !regionIds.contains(g.regionId) : g.regionId == rid))
          g,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Expanded(
              child: _EmptyText(
                'Grup bulunamadı.\nSağ üstteki + ile grup ekleyebilirsiniz.',
              ),
            ),
            if (rid == null) _SplitRegionsHint(onTap: _splitIntoRegions),
          ],
        ),
      );
    }

    final teamCountByGroupId = _teamCountByGroupId;
    Widget card(GroupModel g) => _GroupCard(
      name: g.name.trim().isEmpty ? g.id : g.name,
      teamCount: teamCountByGroupId[g.id] ?? 0,
      overview: _overview?.group(g.id),
      onEdit: _busy ? null : () => _openEditGroupSheet(g),
      onAssignTeams: _busy ? null : () => _openTeamAssignSheet(g),
      onTap: () => _openTeams(initialGroupName: _formatGroupName(g.name)),
    );
    return RefreshIndicator(
      color: _accent,
      onRefresh: _refreshTeamCounts,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          for (final g in groups) card(g),
          _AllTeamsLink(count: _overview?.teamCount, onTap: () => _openTeams()),
          if (rid == null) ...[
            const SizedBox(height: 14),
            _SplitRegionsHint(onTap: _splitIntoRegions),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AdminPageScaffold(
      title: (widget.regionName ?? '').trim().isNotEmpty
          ? widget.regionName!
          : widget.seasonName.trim().isEmpty
          ? 'Gruplar'
          : widget.seasonName,
      actions: [
        if ((widget.regionId ?? '').isNotEmpty &&
            AppSession.of(context).value.canManageLeague(widget.leagueId))
          IconButton(
            onPressed: _busy ? null : _openRegionOwners,
            icon: const Icon(
              Icons.manage_accounts_outlined,
              color: Colors.white,
              size: 24,
            ),
            tooltip: 'Bölge Sorumluları',
          ),
        IconButton(
          onPressed: _busy ? null : _openAddGroupSheet,
          icon: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
          tooltip: 'Grup Ekle',
        ),
      ],
      body: Column(
        children: [
          if (_busy)
            const LinearProgressIndicator(
              minHeight: 2,
              color: _accent,
              backgroundColor: Colors.transparent,
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

class TeamListScreen extends StatefulWidget {
  const TeamListScreen({
    super.key,
    required this.seasonId,
    required this.seasonName,
    this.initialGroupName,
  });

  final String seasonId;
  final String seasonName;
  final String? initialGroupName;

  @override
  State<TeamListScreen> createState() => _TeamListScreenState();
}

class _TeamListScreenState extends State<TeamListScreen> {
  final _queryController = TextEditingController();
  late Future<_SeasonOverview> _overview = _loadSeasonOverview(widget.seasonId);
  String _query = '';

  String _formatGroupName(String? input) {
    final raw = (input ?? '').trim();
    if (raw.isEmpty) return '';
    var cleaned = raw.replaceAll(
      RegExp(r'\bgrub(?:u)?\b|\bgrup(?:u)?\b', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return '';
    return '$cleaned Grubu';
  }

  Future<void> _reload() async {
    final next = _loadSeasonOverview(widget.seasonId);
    setState(() => _overview = next);
    await next;
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _openSquad(_TeamStanding t) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeamSquadScreen(
          teamId: t.id,
          tournamentId: widget.seasonId,
          teamName: t.name,
          teamLogoUrl: t.logoUrl,
        ),
      ),
    );
    // Kadro değişmiş olabilir.
    if (mounted) _reload();
  }

  Widget _teamRow(
    _TeamStanding t, {
    required bool first,
    required bool ranked,
  }) {
    final av = t.goalDiff > 0 ? '+${t.goalDiff}' : '${t.goalDiff}';
    final sub = ranked
        ? '${t.points} P · ${t.played} maç · AV $av'
        : '${t.played} maç';
    return InkWell(
      onTap: () => _openSquad(t),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: first
              ? null
              : Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
        ),
        child: Row(
          children: [
            if (ranked) ...[
              SizedBox(
                width: 22,
                child: Text(
                  '${t.rank}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            _TeamAvatar(name: t.name, logoUrl: t.logoUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            t.rosterCount == 0
                ? const _Pill('Kadro yok', _amber)
                : _Pill('${t.rosterCount} oyuncu', _accent),
          ],
        ),
      ),
    );
  }

  Widget _section(
    String title,
    List<_TeamStanding> teams, {
    required bool ranked,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _trUpper(title),
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Text(
                  '${teams.length} takım',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: _listCardDecoration(),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (var i = 0; i < teams.length; i++)
                    _teamRow(teams[i], first: i == 0, ranked: ranked),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onlyGroup = (widget.initialGroupName ?? '').trim();
    return _AdminPageScaffold(
      title: widget.seasonName.trim().isEmpty ? 'Takımlar' : widget.seasonName,
      body: FutureBuilder<_SeasonOverview>(
        future: _overview,
        builder: (context, snap) {
          if (snap.hasError) {
            return _EmptyText('Takımlar yüklenemedi: ${snap.error}');
          }
          final o = snap.data;
          if (o == null) {
            return const Center(
              child: CircularProgressIndicator(color: _accent),
            );
          }
          final q = _norm(_query);
          bool match(_TeamStanding t) => q.isEmpty || _norm(t.name).contains(q);

          final sections = <Widget>[];
          var visibleCount = 0;
          var missing = 0;
          for (final g in o.groups) {
            if (onlyGroup.isNotEmpty && _formatGroupName(g.name) != onlyGroup) {
              continue;
            }
            final teams = g.teams.where(match).toList();
            if (teams.isEmpty) continue;
            visibleCount += teams.length;
            missing += teams.where((t) => t.rosterCount == 0).length;
            sections.add(_section(g.name, teams, ranked: true));
          }

          return RefreshIndicator(
            color: _accent,
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                TextField(
                  controller: _queryController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Takım ara',
                    prefixIcon: const Icon(Icons.search, color: _muted),
                    filled: true,
                    fillColor: _sheetBg.withValues(alpha: 0.9),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _accent),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                if (missing > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _amber.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: _amber,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$missing takımın kadrosu henüz girilmedi.',
                            style: const TextStyle(
                              color: Color(0xFFFDE68A),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (visibleCount == 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: _EmptyText('Takım bulunamadı.'),
                  )
                else
                  ...sections,
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ortak yardımcılar (Fikstür / Ana Sayfa görünümüyle uyumlu)
// ---------------------------------------------------------------------------

String _norm(String input) {
  return input.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().trim();
}

/// Sheet kapanış animasyonu sürerken TextField'lar controller'ı kullanmaya
/// devam eder; hemen dispose etmek "used after being disposed" hatası verir.
void _disposeControllersLater(List<TextEditingController> controllers) {
  Future<void>.delayed(const Duration(milliseconds: 600), () {
    for (final c in controllers) {
      c.dispose();
    }
  });
}

/// Fikstür ekranındaki ortak popup tasarımı: ortada açılan, lacivert →
/// zümrüt yeşili gradient arka planlı dialog.
/// [compact] true ise içerik kadar yer kaplar; false ise liste/form içeren
/// popup'lar için sabit yükseklik verilir (içerikte Expanded kullanılabilir).
Future<T?> _showAdminSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext sheetContext, StateSetter setSheetState)
  builder,
  bool compact = false,
}) {
  return showDialog<T>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        // MediaQuery burada okunur: klavye açılınca yalnızca bu builder
        // yeniden çalışır, dışarıdaki durum korunur.
        final mq = MediaQuery.of(context);
        final available =
            mq.size.height - mq.viewInsets.bottom - mq.padding.vertical - 48;
        final content = builder(sheetContext, setSheetState);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Container(
            constraints: BoxConstraints(maxHeight: available),
            height: compact ? null : (available * 0.9).clamp(320.0, 720.0),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_sheetBg, _forest],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 15,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: compact ? SingleChildScrollView(child: content) : content,
          ),
        );
      },
    ),
  );
}

class _AdminPageScaffold extends StatelessWidget {
  const _AdminPageScaffold({
    required this.title,
    required this.body,
    this.actions,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      extendBodyBehindAppBar: true,
      appBar: MasterClassAppBar(title: title, actions: actions),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.15,
              child: Image.asset(
                'assets/images/background_ball.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
          SafeArea(child: body),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: _accent, size: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(color: Colors.white24, height: 1),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.label,
    required this.onPressed,
    this.saving = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: saving ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _accent.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text(
        'VAZGEÇ',
        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Liste özetleri: sezon / grup / takım kartlarındaki sayılar ve puan durumu.
// Sezon başına tek seferde 4 sorgu; ekran açılınca ve yenilemede okunur.
// ---------------------------------------------------------------------------

class _TeamStanding {
  _TeamStanding({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.groupId,
  });

  final String id;
  final String name;
  final String logoUrl;
  final String? groupId;
  int played = 0;
  int points = 0;
  int goalsFor = 0;
  int goalsAgainst = 0;
  int rank = 0;
  int rosterCount = 0;

  int get goalDiff => goalsFor - goalsAgainst;
}

class _GroupOverview {
  _GroupOverview({required this.id, required this.name, this.regionId});

  final String id;
  final String name;
  final String? regionId;
  final List<_TeamStanding> teams = [];
  int matchesTotal = 0;
  int matchesPlayed = 0;

  _TeamStanding? get leader =>
      teams.isEmpty || teams.first.played == 0 ? null : teams.first;
}

class _SeasonOverview {
  const _SeasonOverview({
    required this.groups,
    required this.ungrouped,
    required this.matchesTotal,
    required this.matchesPlayed,
    this.regions = const <_Region>[],
  });

  const _SeasonOverview.empty()
    : groups = const <_GroupOverview>[],
      ungrouped = const <_TeamStanding>[],
      matchesTotal = 0,
      matchesPlayed = 0,
      regions = const <_Region>[];

  /// Sezonun bölgeleri (sıralı).
  final List<_Region> regions;

  /// Ada göre sıralı gruplar; takımlar puan durumuna göre sıralı.
  final List<_GroupOverview> groups;
  final List<_TeamStanding> ungrouped;
  final int matchesTotal;
  final int matchesPlayed;

  /// Gruba atanmış takımlar (gruptan çıkarılanlar sayılmaz).
  int get teamCount => groups.fold<int>(0, (n, g) => n + g.teams.length);

  _GroupOverview? group(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }
}

Future<_SeasonOverview> _loadSeasonOverview(String seasonId) async {
  final sid = seasonId.trim();
  final sb = Supabase.instance.client;
  final results = await Future.wait<List<dynamic>>([
    sb.from('groups').select('id, name, region_id').eq('season_id', sid),
    sb
        .from('season_teams')
        .select('team_id, group_id, teams(name, logo_url)')
        .eq('season_id', sid),
    sb
        .from('matches')
        .select(
          'group_id, home_team_id, away_team_id, home_score, away_score, status',
        )
        .eq('season_id', sid),
    sb
        .from('season_team_players')
        .select('team_id, is_active')
        .eq('season_id', sid),
    sb
        .from('season_regions')
        .select('id, name')
        .eq('season_id', sid)
        .order('sort_order', ascending: true)
        .order('name', ascending: true),
  ]);
  String s(dynamic v) => (v ?? '').toString().trim();

  final groupsById = <String, _GroupOverview>{};
  for (final any in results[0]) {
    final r = any as Map;
    final id = s(r['id']);
    if (id.isNotEmpty)
      groupsById[id] = _GroupOverview(
        id: id,
        name: s(r['name']),
        regionId: s(r['region_id']).isEmpty ? null : s(r['region_id']),
      );
  }

  final teamsById = <String, _TeamStanding>{};
  for (final any in results[1]) {
    final r = any as Map;
    final id = s(r['team_id']);
    if (id.isEmpty) continue;
    final t = r['teams'] is Map ? r['teams'] as Map : const {};
    final gid = s(r['group_id']);
    teamsById[id] = _TeamStanding(
      id: id,
      name: s(t['name']).isEmpty ? id : s(t['name']),
      logoUrl: s(t['logo_url']),
      groupId: gid.isEmpty || !groupsById.containsKey(gid) ? null : gid,
    );
  }

  var total = 0;
  var played = 0;
  for (final any in results[2]) {
    final r = any as Map;
    total++;
    final g = groupsById[s(r['group_id'])];
    if (g != null) g.matchesTotal++;
    if (s(r['status']) != 'finished') continue;
    played++;
    if (g != null) g.matchesPlayed++;
    final hs = (r['home_score'] as num?)?.toInt() ?? 0;
    final as = (r['away_score'] as num?)?.toInt() ?? 0;
    void apply(String teamId, int gf, int ga) {
      final t = teamsById[teamId];
      if (t == null) return;
      t.played++;
      t.goalsFor += gf;
      t.goalsAgainst += ga;
      t.points += gf > ga ? 3 : (gf == ga ? 1 : 0);
    }

    apply(s(r['home_team_id']), hs, as);
    apply(s(r['away_team_id']), as, hs);
  }

  for (final any in results[3]) {
    final r = any as Map;
    if (r['is_active'] == false) continue;
    teamsById[s(r['team_id'])]?.rosterCount++;
  }

  int byStanding(_TeamStanding a, _TeamStanding b) {
    final c = b.points.compareTo(a.points);
    if (c != 0) return c;
    final d = b.goalDiff.compareTo(a.goalDiff);
    if (d != 0) return d;
    final f = b.goalsFor.compareTo(a.goalsFor);
    if (f != 0) return f;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  final ungrouped = <_TeamStanding>[];
  for (final t in teamsById.values) {
    final g = t.groupId == null ? null : groupsById[t.groupId];
    (g?.teams ?? ungrouped).add(t);
  }
  for (final g in groupsById.values) {
    g.teams.sort(byStanding);
    for (var i = 0; i < g.teams.length; i++) {
      g.teams[i].rank = i + 1;
    }
  }
  ungrouped.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );

  final groups = groupsById.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return _SeasonOverview(
    groups: groups,
    ungrouped: ungrouped,
    matchesTotal: total,
    matchesPlayed: played,
    regions: [
      for (final any in results[4])
        _Region(id: s((any as Map)['id']), name: s(any['name'])),
    ],
  );
}

const _amber = Color(0xFFFBBF24);
const _muted = Color(0xFF94A3B8);

BoxDecoration _listCardDecoration({bool highlight = false}) => BoxDecoration(
  color: _sheetBg.withValues(alpha: 0.94),
  borderRadius: BorderRadius.circular(18),
  border: Border.all(
    color: highlight
        ? _accent.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.08),
  ),
);

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label, this.suffix});

  final String value;
  final String label;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _bgDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              children: [
                if (suffix != null)
                  TextSpan(
                    text: suffix,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.fraction,
  });

  final String label;
  final String value;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 6,
            color: _accent,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ],
    );
  }
}

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.take(2).map((w) => w.characters.first).join().trUpper;
}

/// Takım logosu; yoksa baş harfler.
class _TeamAvatar extends StatelessWidget {
  const _TeamAvatar({
    required this.name,
    required this.logoUrl,
    this.size = 40,
    this.circle = false,
  });

  final String name;
  final String logoUrl;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final radius = circle ? size / 2 : 12.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _forest,
        borderRadius: BorderRadius.circular(radius),
        border: circle ? Border.all(color: _sheetBg, width: 2) : null,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: logoUrl.trim().isNotEmpty
          ? WebSafeImage(url: logoUrl, width: size, height: size)
          : Text(
              _initials(name),
              style: TextStyle(
                color: const Color(0xFF6EE7B7),
                fontSize: size * 0.33,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

/// Sezon kartı: durum, ilerleme, grup / takım / maç sayıları.
class _SeasonCard extends StatefulWidget {
  const _SeasonCard({
    required this.season,
    required this.onTap,
    required this.onEdit,
  });

  final Season season;

  /// Sezonun bölgesi var mı bilgisiyle çağrılır.
  final void Function(bool hasRegions) onTap;

  /// null: düzenleme yetkisi yok (bölge sorumlusu).
  final VoidCallback? onEdit;

  @override
  State<_SeasonCard> createState() => _SeasonCardState();
}

class _SeasonCardState extends State<_SeasonCard> {
  late Future<_SeasonOverview> _overview = _loadSeasonOverview(
    widget.season.id,
  );

  @override
  void didUpdateWidget(covariant _SeasonCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.season.id != widget.season.id) {
      _overview = _loadSeasonOverview(widget.season.id);
    }
  }

  String _fmt(DateTime? d) {
    if (d == null) return '-';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.season;
    final now = DateTime.now();
    final start = s.startDate;
    final end = s.endDate;
    double? progress;
    if (start != null && end != null && end.isAfter(start)) {
      progress =
          now.difference(start).inMinutes / end.difference(start).inMinutes;
      progress = progress.clamp(0.0, 1.0);
    }
    final (statusText, statusColor) = !s.isActive
        ? ('Pasif', _muted)
        : (start != null && now.isBefore(start))
        ? ('Başlamadı', _amber)
        : (end != null && now.isAfter(end))
        ? ('Tamamlandı', _muted)
        : ('Devam ediyor', const Color(0xFF93C5FD));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () async {
            final o = await _overview.catchError(
              (_) => const _SeasonOverview.empty(),
            );
            widget.onTap(o.regions.isNotEmpty);
          },
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: _listCardDecoration(highlight: s.isDefault),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.calendar_month_outlined,
                        color: _accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (s.isDefault)
                                const _Pill('Varsayılan', _accent),
                              _Pill(statusText, statusColor),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (widget.onEdit != null)
                      IconButton(
                        tooltip: 'Düzenle',
                        onPressed: widget.onEdit,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                        ),
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _ProgressRow(
                  label: '${_fmt(start)} – ${_fmt(end)}',
                  value: progress == null ? '' : '%${(progress * 100).round()}',
                  fraction: progress ?? 0,
                ),
                const SizedBox(height: 14),
                FutureBuilder<_SeasonOverview>(
                  future: _overview,
                  builder: (context, snap) {
                    final o = snap.data;
                    String v(int? n) => n == null ? '–' : '$n';
                    final stats = Row(
                      children: [
                        Expanded(
                          child: _StatBox(
                            value: v(o?.groups.length),
                            label: 'Grup',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatBox(
                            value: v(o?.teamCount),
                            label: 'Takım',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatBox(
                            value: v(o?.matchesPlayed),
                            suffix: o == null ? null : ' / ${o.matchesTotal}',
                            label: 'Maç oynandı',
                          ),
                        ),
                      ],
                    );
                    final regions = o?.regions ?? const <_Region>[];
                    if (regions.isEmpty) return stats;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final r in regions)
                              _Pill(r.name, const Color(0xFF93C5FD)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        stats,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                const SizedBox(height: 10),
                const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Bölgeleri, grupları ve takımları yönet',
                        style: TextStyle(
                          color: _accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: _accent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bölge ekle: il listeden seçilir (İstanbul iki yakaya ayrılır).
/// Eklendiyse true.
Future<bool> _addRegion(
  BuildContext context, {
  required String seasonId,
  required List<_Region> existing,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final qController = TextEditingController();
  final taken = {for (final r in existing) r.name};
  final picked = await _showAdminSheet<String>(
    context: context,
    builder: (sheetContext, setPickerState) {
      final q = _norm(qController.text);
      final items = kRegionChoices
          .where((c) => !taken.contains(c))
          .where((c) => q.isEmpty || _norm(c).contains(q))
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHeader(
            icon: Icons.add_location_alt_outlined,
            title: 'Bölge Ekle',
          ),
          TextField(
            controller: qController,
            decoration: const InputDecoration(
              labelText: 'İl Ara',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setPickerState(() {}),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? const _EmptyText('Sonuç bulunamadı.')
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final c = items[index];
                      return ListTile(
                        title: Text(
                          c,
                          style: const TextStyle(color: Colors.white),
                        ),
                        onTap: () => Navigator.of(sheetContext).pop(c),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          _CancelButton(onPressed: () => Navigator.of(sheetContext).pop()),
        ],
      );
    },
  );
  _disposeControllersLater([qController]);
  if (picked == null) return false;
  try {
    await Supabase.instance.client.from('season_regions').insert({
      'season_id': seasonId,
      'name': picked,
      'city': picked.split(' (').first,
      'sort_order': existing.length + 1,
    });
    messenger.showSnackBar(SnackBar(content: Text('$picked bölgesi eklendi.')));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
    return false;
  }
}

/// Bölge sorumluları penceresi.
Future<void> _showRegionOwnersSheet(BuildContext context, _Region region) {
  return _showAdminSheet<void>(
    context: context,
    compact: true,
    builder: (sheetContext, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHeader(icon: Icons.map_outlined, title: region.name),
        Flexible(
          child: SingleChildScrollView(
            child: LeagueOwnersSection.region(regionId: region.id),
          ),
        ),
        const SizedBox(height: 10),
        _CancelButton(onPressed: () => Navigator.of(sheetContext).pop()),
      ],
    ),
  );
}

/// Bölgesiz sezonun grup ekranında "Bölgelere ayır" girişi.
class _SplitRegionsHint extends StatelessWidget {
  const _SplitRegionsHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: const Row(
          children: [
            Icon(Icons.add_location_alt_outlined, color: _accent),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bölgelere ayır',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Sezon farklı illerde oynanıyorsa (ör. İstanbul (Avrupa), '
                    'Ankara) bölge ekleyin; her bölgenin kendi sorumlusu olur.',
                    style: TextStyle(color: _muted, fontSize: 12, height: 1.3),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _muted),
          ],
        ),
      ),
    );
  }
}

/// Sezonun bölgeleri: Turnuva > Sezon > Bölge > Grup. Bölgeye dokununca o
/// bölgenin grupları açılır.
class SeasonRegionsScreen extends StatefulWidget {
  const SeasonRegionsScreen({
    super.key,
    required this.leagueId,
    required this.seasonId,
    required this.seasonName,
  });

  final String leagueId;
  final String seasonId;
  final String seasonName;

  @override
  State<SeasonRegionsScreen> createState() => _SeasonRegionsScreenState();
}

class _SeasonRegionsScreenState extends State<SeasonRegionsScreen> {
  late Future<_SeasonOverview> _overview = _loadSeasonOverview(widget.seasonId);
  Map<String, List<String>> _ownerNames = const {};

  @override
  void initState() {
    super.initState();
    _loadOwners();
  }

  void _reload() {
    setState(() {
      _overview = _loadSeasonOverview(widget.seasonId);
    });
    _loadOwners();
  }

  Future<void> _loadOwners() async {
    final o = await _overview.catchError((_) => const _SeasonOverview.empty());
    final sb = Supabase.instance.client;
    final names = <String, List<String>>{};
    for (final r in o.regions) {
      try {
        final rows = await sb.rpc(
          'list_region_owners',
          params: {'p_region_id': r.id},
        );
        names[r.id] = [
          for (final x in rows as List) (x['full_name'] ?? '').toString(),
        ];
      } catch (_) {}
    }
    if (mounted) setState(() => _ownerNames = names);
  }

  Future<void> _add(List<_Region> existing) async {
    final added = await _addRegion(
      context,
      seasonId: widget.seasonId,
      existing: existing,
    );
    if (added && mounted) _reload();
  }

  Future<void> _openGroups({
    required String regionId,
    required String name,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeasonGroupsScreen(
          leagueId: widget.leagueId,
          seasonId: widget.seasonId,
          seasonName: widget.seasonName,
          regionId: regionId,
          regionName: name,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _delete(_Region r, int groupCount) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Bölgeyi Kaldır',
      message:
          '${r.name} kaldırılacak. Bölgedeki $groupCount grup ve maçları '
          'silinmez, "Bölgesiz gruplar"a geçer; bölge sorumlularının yetkisi '
          'kalkar.',
      confirmLabel: 'KALDIR',
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    try {
      await Supabase.instance.client
          .from('season_regions')
          .delete()
          .eq('id', r.id);
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  /// Kurucu/admin mi? Değilse bölge sorumlusu: yalnızca kendi bölgeleri.
  bool get _full =>
      AppSession.of(context).value.canManageLeague(widget.leagueId);

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    final full = _full;
    final mine = {
      for (final r in session.regionsInSeason(widget.seasonId)) r.id,
    };
    return FutureBuilder<_SeasonOverview>(
      future: _overview,
      builder: (context, snap) {
        final o = snap.data;
        final regions = [
          for (final r in o?.regions ?? const <_Region>[])
            if (full || mine.contains(r.id)) r,
        ];
        return _AdminPageScaffold(
          title: widget.seasonName.trim().isEmpty
              ? 'Bölgeler'
              : widget.seasonName,
          actions: [
            if (full)
              IconButton(
                onPressed: o == null ? null : () => _add(regions),
                icon: const Icon(
                  Icons.add_location_alt_outlined,
                  color: Colors.white,
                  size: 26,
                ),
                tooltip: 'Bölge Ekle',
              ),
          ],
          body: snap.hasError
              ? _EmptyText('Hata: ${snap.error}')
              : o == null
              ? const Center(child: CircularProgressIndicator(color: _accent))
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: () async => _reload(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      for (final r in regions)
                        _regionCard(
                          o,
                          r,
                          o.groups.where((g) => g.regionId == r.id).toList(),
                        ),
                      if (full)
                        () {
                          final ids = {for (final r in regions) r.id};
                          final rest = o.groups
                              .where((g) => !ids.contains(g.regionId))
                              .toList();
                          if (rest.isEmpty) return const SizedBox.shrink();
                          return _regionCard(
                            o,
                            const _Region(id: '', name: 'Bölgesiz gruplar'),
                            rest,
                          );
                        }(),
                      if (full)
                        _AddDashedButton(
                          label: 'Bölge Ekle',
                          onTap: () => _add(regions),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _regionCard(
    _SeasonOverview o,
    _Region r,
    List<_GroupOverview> groups,
  ) {
    final teams = groups.fold<int>(0, (n, g) => n + g.teams.length);
    final total = groups.fold<int>(0, (n, g) => n + g.matchesTotal);
    final played = groups.fold<int>(0, (n, g) => n + g.matchesPlayed);
    final isReal = r.id.isNotEmpty;
    final full = _full;
    final owners = _ownerNames[r.id] ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _openGroups(regionId: r.id, name: r.name),
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: _listCardDecoration(highlight: false),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isReal
                            ? Icons.map_outlined
                            : Icons.layers_clear_outlined,
                        color: _accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        r.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (isReal && full)
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white70,
                        ),
                        color: _sheetBg,
                        onSelected: (v) async {
                          if (v == 'owners') {
                            await _showRegionOwnersSheet(context, r);
                            _loadOwners();
                          } else if (v == 'delete') {
                            await _delete(r, groups.length);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'owners',
                            child: Text(
                              'Bölge Sorumluları',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              'Bölgeyi Kaldır',
                              style: TextStyle(color: Color(0xFFF87171)),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatBox(value: '${groups.length}', label: 'Grup'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatBox(value: '$teams', label: 'Takım'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatBox(
                        value: '$played',
                        suffix: ' / $total',
                        label: 'Maç oynandı',
                      ),
                    ),
                  ],
                ),
                if (isReal) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: !full
                        ? null
                        : () async {
                            await _showRegionOwnersSheet(context, r);
                            _loadOwners();
                          },
                    child: Row(
                      children: [
                        Icon(
                          Icons.manage_accounts_outlined,
                          size: 18,
                          color: owners.isEmpty ? _amber : _muted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            owners.isEmpty
                                ? 'Bölge sorumlusu atanmadı · eklemek için dokunun'
                                : 'Sorumlu: ${owners.join(', ')}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: owners.isEmpty ? _amber : _muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sezon bölgesi (ör. İstanbul (Avrupa)).
class _Region {
  const _Region({required this.id, required this.name});

  final String id;
  final String name;
}

/// Bölge seçenekleri: 81 il; İstanbul Avrupa ve Anadolu yakası olarak ikiye
/// ayrılır.
final List<String> kRegionChoices = [
  for (final c in AppConstants.turkeyCities)
    if (c == 'İstanbul') ...['İstanbul (Avrupa)', 'İstanbul (Anadolu)'] else c,
];

/// Grup kartı: takım avatarları, oynanan maç oranı ve lider.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.name,
    required this.teamCount,
    required this.overview,
    required this.onTap,
    required this.onEdit,
    required this.onAssignTeams,
  });

  final String name;
  final int teamCount;
  final _GroupOverview? overview;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onAssignTeams;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final teams = o?.teams ?? const <_TeamStanding>[];
    final leader = o?.leader;
    const shown = 5;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: _listCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$teamCount takım',
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Düzenle',
                      onPressed: onEdit,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                      ),
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Takım Ekle/Çıkar',
                      onPressed: onAssignTeams,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                      ),
                      icon: const Icon(
                        Icons.group_add_outlined,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
                if (teams.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        height: 30,
                        width: 30 + 22.0 * (teams.take(shown).length - 1),
                        child: Stack(
                          children: [
                            for (var i = 0; i < teams.take(shown).length; i++)
                              Positioned(
                                left: 22.0 * i,
                                child: _TeamAvatar(
                                  name: teams[i].name,
                                  logoUrl: teams[i].logoUrl,
                                  size: 30,
                                  circle: true,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (teams.length > shown) ...[
                        const SizedBox(width: 8),
                        Text(
                          '+${teams.length - shown}',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                if (o != null && o.matchesTotal > 0) ...[
                  const SizedBox(height: 14),
                  _ProgressRow(
                    label: 'Maçlar',
                    value: '${o.matchesPlayed} / ${o.matchesTotal} oynandı',
                    fraction: o.matchesPlayed / o.matchesTotal,
                  ),
                ],
                if (leader != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _bgDark.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_outlined,
                          color: _amber,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: 'Lider: ',
                              style: const TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 13,
                              ),
                              children: [
                                TextSpan(
                                  text: leader.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${leader.points} P',
                          style: const TextStyle(
                            color: _amber,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Listenin sonundaki kesik çizgili "ekle" butonu.
class _AddDashedButton extends StatelessWidget {
  const _AddDashedButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        foregroundColor: const Color(0xFFCBD5E1),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      onPressed: onTap,
      icon: const Icon(Icons.add_rounded),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

/// Grup listesinin altındaki "Sezondaki tüm takımlar" girişi.
class _AllTeamsLink extends StatelessWidget {
  const _AllTeamsLink({required this.count, required this.onTap});

  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Sezondaki tüm takımlar',
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  children: [
                    if (count != null)
                      TextSpan(
                        text: ' ($count)',
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }
}

/// Türkçe büyük harf (Dart'ın toUpperCase'i i → I yapar, İ değil).
String _trUpper(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
