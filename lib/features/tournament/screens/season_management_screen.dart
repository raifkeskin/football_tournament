import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_constants.dart';
import '../models/season.dart';
import '../services/interfaces/i_league_service.dart';
import '../../match/models/match.dart';
import '../../team/models/team.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/master_class_app_bar.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../team/screens/team_squad_screen.dart';

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
    return _sb
        .from('seasons')
        .stream(primaryKey: ['id'])
        .eq('league_id', leagueId)
        .order('start_date', ascending: false)
        .map(
          (rows) =>
              rows.cast<Map<String, dynamic>>().map(Season.fromJson).toList(),
        );
  }

  static String _fmt(DateTime? date) {
    if (date == null) return '-';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
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
    var saving = false;

    Future<void> pickTurkeyCity({required StateSetter setSheetState}) async {
      final qController = TextEditingController();
      final picked = await _showAdminSheet<String>(
        context: context,
        builder: (sheetContext, setPickerState) {
          final q = _norm(qController.text);
          final items = AppConstants.turkeyCities.where((c) {
            if (q.isEmpty) return true;
            return _norm(c).contains(q);
          }).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHeader(
                icon: Icons.location_city_outlined,
                title: 'Şehir Seç',
              ),
              TextField(
                controller: qController,
                decoration: const InputDecoration(
                  labelText: 'Şehir Ara',
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
      if (picked == null) return;
      setSheetState(() => cityController.text = picked);
    }

    Future<void> pickDate({
      required StateSetter setSheetState,
      required bool isStart,
    }) async {
      final now = DateTime.now();
      final initial = isStart
          ? (startDate ?? now)
          : (endDate ?? startDate ?? now);
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 5),
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
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 5),
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

        if (isEdit) {
          await _sb.from('seasons').update(payload).eq('id', season.id);
        } else {
          await _sb.from('seasons').insert(payload);
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

    Widget numberField(TextEditingController controller, String label) {
      return TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        enabled: !saving,
      );
    }

    Widget dateField(
      TextEditingController controller,
      String label,
      VoidCallback onTap,
    ) {
      return TextField(
        controller: controller,
        readOnly: true,
        onTap: saving ? null : onTap,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_month_outlined),
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
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Sezon Adı'),
                      enabled: !saving,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subtitleController,
                      decoration: const InputDecoration(
                        labelText: 'Alt Başlık',
                      ),
                      enabled: !saving,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: dateField(
                            startDateController,
                            'Başlangıç',
                            () => pickDate(
                              setSheetState: setSheetState,
                              isStart: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: dateField(
                            endDateController,
                            'Bitiş',
                            () => pickDate(
                              setSheetState: setSheetState,
                              isStart: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: numberField(
                            startingPlayerCountController,
                            'Başlangıç Oyuncu',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: numberField(
                            subPlayerCountController,
                            'Yedek Oyuncu',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: countryController,
                            decoration: const InputDecoration(
                              labelText: 'Ülke',
                            ),
                            enabled: !saving,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: cityController,
                            readOnly: true,
                            onTap: saving
                                ? null
                                : () => pickTurkeyCity(
                                    setSheetState: setSheetState,
                                  ),
                            decoration: const InputDecoration(
                              labelText: 'Şehir',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: _accent,
                      title: const Text(
                        'Aktif',
                        style: TextStyle(color: Colors.white),
                      ),
                      value: isActive,
                      onChanged: saving
                          ? null
                          : (v) => setSheetState(() => isActive = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: _accent,
                      title: const Text(
                        'Varsayılan',
                        style: TextStyle(color: Colors.white),
                      ),
                      value: isDefault,
                      onChanged: saving
                          ? null
                          : (v) => setSheetState(() => isDefault = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: numberField(
                            teamsPerGroupController,
                            'Toplam Takım Sayısı',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: numberField(
                            numberOfGroupsController,
                            'Grup Sayısı',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: numberField(
                            matchPeriodDurationController,
                            'Maç Süresi',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: numberField(
                            numberOfPlayerChangesController,
                            'Oyuncu Değişiklik Sınırı',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: dateField(
                            transferStartController,
                            'Transfer Başlangıç',
                            () => pickTransferDate(
                              setSheetState: setSheetState,
                              isStart: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: dateField(
                            transferEndController,
                            'Transfer Bitiş',
                            () => pickTransferDate(
                              setSheetState: setSheetState,
                              isStart: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: instagramController,
                      decoration: const InputDecoration(
                        labelText: 'Instagram URL',
                      ),
                      enabled: !saving,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: youtubeController,
                      decoration: const InputDecoration(
                        labelText: 'YouTube URL',
                      ),
                      enabled: !saving,
                    ),
                    const SizedBox(height: 16),
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
    return _AdminPageScaffold(
      title: leagueName.trim().isEmpty ? 'Sezonlar' : leagueName,
      actions: [
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
          final seasons = snapshot.data ?? const <Season>[];
          if (seasons.isEmpty) {
            return const _EmptyText('Sezon bulunamadı.');
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: seasons.length,
            itemBuilder: (_, index) {
              final s = seasons[index];
              final dateRange = '${_fmt(s.startDate)} - ${_fmt(s.endDate)}';
              final location = [
                if ((s.city ?? '').trim().isNotEmpty) s.city!.trim(),
                s.country.trim(),
              ].where((e) => e.isNotEmpty).join(' • ');
              return _AdminListCard(
                icon: Icons.calendar_month_outlined,
                title: s.name,
                subtitle: location.isEmpty
                    ? dateRange
                    : '$dateRange\n$location',
                badge: s.isDefault ? 'Varsayılan' : null,
                trailing: [
                  IconButton(
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: Colors.white54,
                    ),
                    tooltip: 'Düzenle',
                    onPressed: () => _openSeasonSheet(context, season: s),
                  ),
                ],
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SeasonGroupsScreen(
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
  });

  final String leagueId;
  final String seasonId;
  final String seasonName;

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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Stream'ler build içinde değil burada bir kez dinlenir; aksi halde her
    // rebuild'de yeni realtime aboneliği açılıyordu.
    _groupsSub = _leagueService
        .watchGroups(widget.seasonId)
        .listen(
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
    if (sid.isEmpty || AppConfig.activeDatabase != DatabaseType.supabase) {
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

  bool _ensureSupabase() {
    if (AppConfig.activeDatabase == DatabaseType.supabase) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bu işlem bu veritabanı modunda desteklenmiyor.'),
      ),
    );
    return false;
  }

  /// Seçici için TÜM takımları getirir. Önceden yalnızca `season_teams`
  /// tablosunda bu sezona bağlı takımlar listeleniyordu; yeni bir sezonda bu
  /// liste boş olduğundan "Takım bulunamadı." görünüyordu.
  Future<List<_TeamOption>?> _loadTeamOptions() async {
    setState(() => _busy = true);
    try {
      final teamsRes = await _sb
          .from('teams')
          .select()
          .order('name', ascending: true);
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
    if (!_ensureSupabase()) return;

    final messenger = ScaffoldMessenger.of(context);
    final nameController = TextEditingController();
    final selectedTeamIds = <String>{};
    List<_TeamOption>? options;
    var saving = false;

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
            .insert({'season_id': widget.seasonId, 'name': name})
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
            TextField(
              controller: nameController,
              enabled: !saving,
              maxLength: 10,
              decoration: const InputDecoration(labelText: 'Grup Adı'),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: saving ? null : () => openTeamPicker(setSheetState),
              icon: const Icon(Icons.playlist_add_check_outlined),
              label: Text(
                'Takım Ekle/Çıkar'
                '${selectedTeamIds.isEmpty ? '' : ' (${selectedTeamIds.length})'}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 24),
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

  Future<void> _openEditGroupSheet(GroupModel g) async {
    if (!_ensureSupabase()) return;

    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: g.name.trim());
    var saving = false;

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
        await _sb.from('groups').update({'name': next}).eq('id', g.id);

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
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Grup Adı'),
              enabled: !saving,
            ),
            const SizedBox(height: 24),
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
    if (!_ensureSupabase()) return;
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

  Widget _buildBody() {
    if (_groupsError != null) {
      return _EmptyText('Hata: $_groupsError');
    }
    final loaded = _groups;
    if (loaded == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    final groups = [...loaded]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (groups.isEmpty) {
      return const _EmptyText(
        'Grup bulunamadı.\nSağ üstteki + ile grup ekleyebilirsiniz.',
      );
    }

    final teamCountByGroupId = _teamCountByGroupId;

    return RefreshIndicator(
      color: _accent,
      onRefresh: _refreshTeamCounts,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          for (final g in groups)
            _AdminListCard(
              icon: Icons.groups_outlined,
              title: g.name.trim().isEmpty ? g.id : g.name,
              subtitle: '${teamCountByGroupId[g.id] ?? 0} takım',
              trailing: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white54),
                  tooltip: 'Düzenle',
                  onPressed: _busy ? null : () => _openEditGroupSheet(g),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.playlist_add_check_outlined,
                    color: _accent,
                  ),
                  tooltip: 'Takım Ekle/Çıkar',
                  onPressed: _busy ? null : () => _openTeamAssignSheet(g),
                ),
              ],
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TeamListScreen(
                      seasonId: widget.seasonId,
                      seasonName: widget.seasonName,
                      initialGroupName: _formatGroupName(g.name),
                    ),
                  ),
                );
                await _refreshTeamCounts();
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AdminPageScaffold(
      title: widget.seasonName.trim().isEmpty ? 'Gruplar' : widget.seasonName,
      actions: [
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
  final ITeamService _teamService = ServiceLocator.teamService;
  final _teamNameQueryController = TextEditingController();
  late final Stream<List<Team>> _teamsStream = _watchTeams();
  String _teamNameQuery = '';
  String _selectedGroup = '__ALL__';

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

  Stream<List<Team>> _watchTeams() {
    final sid = widget.seasonId.trim();
    if (sid.isEmpty) return Stream.value(const <Team>[]);
    return _teamService.watchAllTeams(caller: 'TeamListScreen').map((all) {
      final filtered = all
          .where((t) => (t.seasonId ?? '').trim() == sid)
          .toList();
      filtered.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return filtered;
    });
  }

  @override
  void initState() {
    super.initState();
    final g = (widget.initialGroupName ?? '').trim();
    if (g.isNotEmpty) _selectedGroup = g;
  }

  @override
  void dispose() {
    _teamNameQueryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AdminPageScaffold(
      title: widget.seasonName.trim().isEmpty ? 'Takımlar' : widget.seasonName,
      body: StreamBuilder<List<Team>>(
        stream: _teamsStream,
        initialData: const <Team>[],
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _EmptyText('Hata: ${snapshot.error}');
          }
          final teams = snapshot.data ?? const <Team>[];
          final qName = _norm(_teamNameQuery);
          final groupOptions =
              teams
                  .map((t) => _formatGroupName(t.groupName))
                  .where((g) => g.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          final effectiveGroup =
              _selectedGroup == '__ALL__' ||
                  groupOptions.contains(_selectedGroup)
              ? _selectedGroup
              : '__ALL__';
          if (effectiveGroup != _selectedGroup && teams.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _selectedGroup = '__ALL__');
            });
          }

          final filtered = teams.where((t) {
            final groupName = _formatGroupName(t.groupName);
            final teamName = _norm(t.name);
            final okGroup =
                effectiveGroup == '__ALL__' || groupName == effectiveGroup;
            final okName = qName.isEmpty || teamName.contains(qName);
            return okGroup && okName;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(effectiveGroup),
                        initialValue: effectiveGroup,
                        dropdownColor: _sheetBg,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Grup',
                          prefixIcon: Icon(Icons.groups_outlined),
                        ),
                        items: <DropdownMenuItem<String>>[
                          const DropdownMenuItem(
                            value: '__ALL__',
                            child: Text('Tümü'),
                          ),
                          for (final g in groupOptions)
                            DropdownMenuItem(
                              value: g,
                              child: Text(
                                g,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _selectedGroup = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _teamNameQueryController,
                        decoration: const InputDecoration(
                          labelText: 'Takım Adı',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setState(() => _teamNameQuery = v),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const _EmptyText('Takım bulunamadı.')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final t = filtered[index];
                          final groupLabel = _formatGroupName(t.groupName);
                          return _AdminListCard(
                            leading: t.logoUrl.trim().isNotEmpty
                                ? WebSafeImage(
                                    url: t.logoUrl,
                                    width: 28,
                                    height: 28,
                                    borderRadius: BorderRadius.circular(8),
                                    fallbackIconSize: 16,
                                  )
                                : null,
                            icon: Icons.shield_outlined,
                            title: t.name.trim().isEmpty ? t.id : t.name,
                            subtitle: groupLabel.isEmpty ? null : groupLabel,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => TeamSquadScreen(
                                    teamId: t.id,
                                    tournamentId: widget.seasonId,
                                    teamName: t.name.trim().isEmpty
                                        ? t.id
                                        : t.name,
                                    teamLogoUrl: t.logoUrl,
                                  ),
                                ),
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

class _AdminListCard extends StatelessWidget {
  const _AdminListCard({
    required this.icon,
    required this.title,
    this.leading,
    this.subtitle,
    this.badge,
    this.trailing = const <Widget>[],
    this.onTap,
  });

  final IconData icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? badge;
  final List<Widget> trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: leading ?? Icon(icon, color: _accent, size: 22),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...trailing,
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.chevron_right_rounded, color: Colors.white24),
            ),
          ],
        ),
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
