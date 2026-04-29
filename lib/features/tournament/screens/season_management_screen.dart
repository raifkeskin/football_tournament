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
import '../../../core/widgets/web_safe_image.dart';
import '../../team/screens/team_squad_screen.dart';

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

    String _norm(String input) {
      return input
          .replaceAll('İ', 'i')
          .replaceAll('I', 'ı')
          .toLowerCase()
          .trim();
    }

    Future<void> _pickTurkeyCity({
      required void Function(void Function()) setSheetState,
    }) async {
      final picked = await showModalBottomSheet<String>(
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
        builder: (context) {
          final viewInsets = MediaQuery.of(context).viewInsets;
          final h = MediaQuery.of(context).size.height * 0.8;
          final qController = TextEditingController();
          return StatefulBuilder(
            builder: (context, setPickerState) {
              final q = _norm(qController.text);
              final items = AppConstants.turkeyCities.where((c) {
                if (q.isEmpty) return true;
                return _norm(c).contains(q);
              }).toList();
              return SizedBox(
                height: h,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    16 + viewInsets.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox(
                          width: 148,
                          height: 148,
                          child: ClipOval(
                            child: Container(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.location_city_outlined,
                                size: 44,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: qController,
                        decoration: const InputDecoration(
                          labelText: 'Şehir Ara',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setPickerState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: items.isEmpty
                            ? const Center(child: Text('Sonuç bulunamadı.'))
                            : ListView.builder(
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final c = items[index];
                                  return ListTile(
                                    title: Text(c),
                                    onTap: () => Navigator.of(context).pop(c),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'VAZGEÇ',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      if (picked == null) return;
      setSheetState(() => cityController.text = picked);
    }

    Future<void> pickDate({
      required void Function(void Function()) setSheetState,
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
      required void Function(void Function()) setSheetState,
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

    Future<void> submit(void Function(void Function()) setSheetState) async {
      final name = nameController.text.trim();
      final subtitle = subtitleController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sezon adı zorunludur.')));
        return;
      }
      if (startDate == null || endDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
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
        if (transferStartDate != null) {
          payload['transfer_start_date'] = _dateOnly(transferStartDate!);
        }
        if (transferEndDate != null) {
          payload['transfer_end_date'] = _dateOnly(transferEndDate!);
        }

        if (isEdit) {
          await _sb.from('seasons').update(payload).eq('id', season!.id);
        } else {
          await _sb.from('seasons').insert(payload);
        }

        if (!context.mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Güncellendi.' : 'Sezon oluşturuldu.'),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      } finally {
        if (context.mounted) setSheetState(() => saving = false);
      }
    }

    await showModalBottomSheet<void>(
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
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        final h = MediaQuery.of(context).size.height * 0.8;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SizedBox(
                height: h,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    16 + viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isEdit ? 'Sezon Düzenle' : 'Sezon Ekle',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: SizedBox(
                            width: 148,
                            height: 148,
                            child: ClipOval(
                              child: Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.calendar_month_outlined,
                                  size: 44,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Sezon Adı',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !saving,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: subtitleController,
                          decoration: const InputDecoration(
                            labelText: 'Alt Başlık',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !saving,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: startDateController,
                                readOnly: true,
                                onTap: saving
                                    ? null
                                    : () => pickDate(
                                        setSheetState: setSheetState,
                                        isStart: true,
                                      ),
                                decoration: const InputDecoration(
                                  labelText: 'Başlangıç',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(
                                    Icons.calendar_month_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: endDateController,
                                readOnly: true,
                                onTap: saving
                                    ? null
                                    : () => pickDate(
                                        setSheetState: setSheetState,
                                        isStart: false,
                                      ),
                                decoration: const InputDecoration(
                                  labelText: 'Bitiş',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(
                                    Icons.calendar_month_outlined,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: startingPlayerCountController,
                                decoration: const InputDecoration(
                                  labelText: 'Başlangıç Oyuncu',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                enabled: !saving,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: subPlayerCountController,
                                decoration: const InputDecoration(
                                  labelText: 'Yedek Oyuncu',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                enabled: !saving,
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
                                  border: OutlineInputBorder(),
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
                                    : () => _pickTurkeyCity(
                                        setSheetState: setSheetState,
                                      ),
                                decoration: const InputDecoration(
                                  labelText: 'Şehir',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.search),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Varsayılan'),
                          value: isDefault,
                          onChanged: saving
                              ? null
                              : (v) => setSheetState(() => isDefault = v),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: teamsPerGroupController,
                                decoration: const InputDecoration(
                                  labelText: 'Toplam Takım Sayısı',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                enabled: !saving,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: numberOfGroupsController,
                                decoration: const InputDecoration(
                                  labelText: 'Grup Sayısı',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                enabled: !saving,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: matchPeriodDurationController,
                                decoration: const InputDecoration(
                                  labelText: 'Maç Süresi',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                enabled: !saving,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: numberOfPlayerChangesController,
                                decoration: const InputDecoration(
                                  labelText: 'Oyuncu Değişiklik Sınırı',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                enabled: !saving,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: transferStartController,
                                readOnly: true,
                                onTap: saving
                                    ? null
                                    : () => pickTransferDate(
                                        setSheetState: setSheetState,
                                        isStart: true,
                                      ),
                                decoration: const InputDecoration(
                                  labelText: 'Transfer Başlangıç',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(
                                    Icons.calendar_month_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: transferEndController,
                                readOnly: true,
                                onTap: saving
                                    ? null
                                    : () => pickTransferDate(
                                        setSheetState: setSheetState,
                                        isStart: false,
                                      ),
                                decoration: const InputDecoration(
                                  labelText: 'Transfer Bitiş',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(
                                    Icons.calendar_month_outlined,
                                  ),
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
                            border: OutlineInputBorder(),
                          ),
                          enabled: !saving,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: youtubeController,
                          decoration: const InputDecoration(
                            labelText: 'YouTube URL',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !saving,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: saving
                                ? null
                                : () => submit(setSheetState),
                            child: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    isEdit ? 'GÜNCELLE' : 'KAYDET',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text(
                              'VAZGEÇ',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    subtitleController.dispose();
    startDateController.dispose();
    endDateController.dispose();
    startingPlayerCountController.dispose();
    subPlayerCountController.dispose();
    cityController.dispose();
    countryController.dispose();
    transferStartController.dispose();
    transferEndController.dispose();
    teamsPerGroupController.dispose();
    numberOfGroupsController.dispose();
    instagramController.dispose();
    youtubeController.dispose();
    matchPeriodDurationController.dispose();
    numberOfPlayerChangesController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('$leagueName Sezonları'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => _openSeasonSheet(context),
            icon: const Icon(Icons.add),
            tooltip: 'Sezon Ekle',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const SizedBox(height: 12),
          StreamBuilder<List<Season>>(
            stream: _watchSeasons(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final seasons = snapshot.data ?? const <Season>[];
              if (seasons.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Sezon bulunamadı.')),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: seasons.length,
                itemBuilder: (context, index) {
                  final s = seasons[index];
                  final dateRange = '${_fmt(s.startDate)} - ${_fmt(s.endDate)}';
                  final location = [
                    if ((s.city ?? '').trim().isNotEmpty) s.city!.trim(),
                    s.country.trim(),
                  ].join(' • ');
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      leading: Icon(
                        Icons.calendar_month_outlined,
                        color: cs.onSurfaceVariant,
                      ),
                      title: Text(
                        s.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        location.trim().isEmpty
                            ? dateRange
                            : '$dateRange\n$location',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Düzenle',
                        onPressed: () => _openSeasonSheet(context, season: s),
                      ),
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
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
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
  final ITeamService _teamService = ServiceLocator.teamService;

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

  Stream<List<Team>> _watchSeasonTeams() {
    final sid = widget.seasonId.trim();
    if (sid.isEmpty) return const Stream<List<Team>>.empty();
    return _teamService.watchAllTeams(caller: 'SeasonGroupsScreen').map((all) {
      return all.where((t) => (t.seasonId ?? '').trim() == sid).toList();
    });
  }

  Future<void> _openAddGroupSheet({
    required List<Team> seasonTeams,
  }) async {
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu işlem bu veritabanı modunda desteklenmiyor.'),
        ),
      );
      return;
    }

    final nameController = TextEditingController();
    final selectedTeamIds = <String>{};
    final qController = TextEditingController();
    var saving = false;

    String norm(String input) {
      return input
          .replaceAll('İ', 'i')
          .replaceAll('I', 'ı')
          .toLowerCase()
          .trim();
    }

    Future<void> openTeamPicker(void Function(void Function()) setSheetState) async {
      final picked = await showModalBottomSheet<Set<String>>(
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
        builder: (context) {
          final viewInsets = MediaQuery.of(context).viewInsets;
          final h = MediaQuery.of(context).size.height * 0.8;
          final working = <String>{...selectedTeamIds};
          return StatefulBuilder(
            builder: (context, setPickerState) {
              final q = norm(qController.text);
              final filtered = seasonTeams.where((t) {
                if (q.isEmpty) return true;
                return norm(t.name).contains(q);
              }).toList()
                ..sort(
                  (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );
              return SizedBox(
                height: h,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    16 + viewInsets.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox(
                          width: 148,
                          height: 148,
                          child: ClipOval(
                            child: Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: Icon(
                                Icons.playlist_add_check_outlined,
                                size: 44,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: qController,
                        decoration: const InputDecoration(
                          labelText: 'Takım Ara',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setPickerState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(child: Text('Takım bulunamadı.'))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final t = filtered[index];
                                  final checked = working.contains(t.id);
                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    child: CheckboxListTile(
                                      value: checked,
                                      onChanged: (val) {
                                        setPickerState(() {
                                          if (val == true) {
                                            working.add(t.id);
                                          } else {
                                            working.remove(t.id);
                                          }
                                        });
                                      },
                                      title: Text(t.name),
                                      secondary: SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: WebSafeImage(
                                          url: t.logoUrl,
                                          width: 30,
                                          height: 30,
                                          borderRadius: BorderRadius.circular(6),
                                          fallbackIconSize: 16,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(working),
                          child: const Text(
                            'KAYDET',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'VAZGEÇ',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      if (picked == null) return;
      setSheetState(() {
        selectedTeamIds
          ..clear()
          ..addAll(picked);
      });
    }

    Future<void> submit(void Function(void Function()) setSheetState) async {
      final name = nameController.text.trim();
      if (name.isEmpty) return;
      setSheetState(() => saving = true);
      try {
        final res = await Supabase.instance.client
            .from('groups')
            .insert({'season_id': widget.seasonId, 'name': name})
            .select('id')
            .single();
        final groupId = (res['id'] ?? '').toString().trim();
        if (groupId.isEmpty) throw Exception('Grup oluşturulamadı.');

        for (final id in selectedTeamIds) {
          await _teamService.updateTeam(
            id,
            {'groupId': groupId, 'groupName': name},
            caller: 'SeasonGroupsScreen.addGroup',
          );
        }

        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Grup eklendi.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      } finally {
        if (mounted) setSheetState(() => saving = false);
      }
    }

    await showModalBottomSheet<void>(
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
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        final h = MediaQuery.of(context).size.height * 0.8;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final disabled = saving;
            return SizedBox(
              height: h,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SizedBox(
                        width: 148,
                        height: 148,
                        child: ClipOval(
                          child: Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: Icon(
                              Icons.groups_outlined,
                              size: 44,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      enabled: !disabled,
                      maxLength: 10,
                      decoration: const InputDecoration(
                        labelText: 'Grup Adı',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: disabled ? null : () => openTeamPicker(setSheetState),
                      icon: const Icon(Icons.playlist_add_check_outlined),
                      label: Text(
                        'Takım Ekle/Çıkar'
                        '${selectedTeamIds.isEmpty ? '' : ' (${selectedTeamIds.length})'}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: disabled ? null : () => submit(setSheetState),
                        child: disabled
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(
                                'KAYDET',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: disabled ? null : () => Navigator.of(context).pop(),
                        child: const Text(
                          'VAZGEÇ',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    qController.dispose();
  }

  Future<void> _openEditGroupSheet(GroupModel g) async {
    final controller = TextEditingController(text: g.name.trim());
    var saving = false;

    Future<void> submit(void Function(void Function()) setSheetState) async {
      final next = controller.text.trim();
      if (next.isEmpty) return;
      setSheetState(() => saving = true);
      try {
        if (AppConfig.activeDatabase != DatabaseType.supabase) {
          if (!mounted) return;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bu işlem bu veritabanı modunda desteklenmiyor.'),
            ),
          );
          return;
        }
        await Supabase.instance.client
            .from('groups')
            .update({'name': next})
            .eq('id', g.id);
        await Supabase.instance.client
            .from('teams')
            .update({'group_name': next})
            .eq('group_id', g.id);

        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Güncellendi.')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      } finally {
        if (mounted) setSheetState(() => saving = false);
      }
    }

    await showModalBottomSheet<void>(
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
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        final h = MediaQuery.of(context).size.height * 0.8;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: h,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: SizedBox(
                        width: 148,
                        height: 148,
                        child: ClipOval(
                          child: Container(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.edit_outlined,
                              size: 44,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Grup Adı',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !saving,
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: saving ? null : () => submit(setSheetState),
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'KAYDET',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text(
                          'VAZGEÇ',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _openTeamAssignSheet({
    required GroupModel group,
    required List<Team> seasonTeams,
  }) async {
    final selected = <String>{};
    for (final t in seasonTeams) {
      if ((t.groupId ?? '').trim() == group.id.trim()) selected.add(t.id);
    }
    final qController = TextEditingController();
    var saving = false;

    String norm(String input) {
      return input
          .replaceAll('İ', 'i')
          .replaceAll('I', 'ı')
          .toLowerCase()
          .trim();
    }

    Future<void> submit(void Function(void Function()) setSheetState) async {
      setSheetState(() => saving = true);
      try {
        final prev = <String>{};
        for (final t in seasonTeams) {
          if ((t.groupId ?? '').trim() == group.id.trim()) prev.add(t.id);
        }
        final toAdd = selected.difference(prev).toList();
        final toRemove = prev.difference(selected).toList();

        for (final id in toAdd) {
          await _teamService.updateTeam(id, {
            'groupId': group.id,
            'groupName': group.name,
          }, caller: 'SeasonGroupsScreen.assignTeam');
        }
        for (final id in toRemove) {
          await _teamService.updateTeam(id, {
            'groupId': null,
            'groupName': null,
          }, caller: 'SeasonGroupsScreen.assignTeam');
        }

        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Kaydedildi.')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      } finally {
        if (mounted) setSheetState(() => saving = false);
      }
    }

    await showModalBottomSheet<void>(
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
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        final h = MediaQuery.of(context).size.height * 0.8;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final q = norm(qController.text);
            final list =
                seasonTeams.where((t) {
                  if (q.isEmpty) return true;
                  return norm(t.name).contains(q);
                }).toList()..sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );

            return SizedBox(
              height: h,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    TextField(
                      controller: qController,
                      decoration: const InputDecoration(
                        labelText: 'Takım Ara',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setSheetState(() {}),
                      enabled: !saving,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(child: Text('Takım bulunamadı.'))
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (context, index) {
                                final t = list[index];
                                final isSelected = selected.contains(t.id);
                                return CheckboxListTile(
                                  value: isSelected,
                                  onChanged: saving
                                      ? null
                                      : (v) {
                                          setSheetState(() {
                                            if (v == true) {
                                              selected.add(t.id);
                                            } else {
                                              selected.remove(t.id);
                                            }
                                          });
                                        },
                                  title: Text(
                                    t.name.trim().isEmpty ? t.id : t.name,
                                  ),
                                  secondary: t.logoUrl.trim().isNotEmpty
                                      ? WebSafeImage(
                                          url: t.logoUrl,
                                          width: 32,
                                          height: 32,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          fallbackIconSize: 16,
                                        )
                                      : const Icon(Icons.shield_outlined),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: saving ? null : () => submit(setSheetState),
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'KAYDET',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text(
                          'VAZGEÇ',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    qController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.seasonName.trim().isEmpty ? 'Gruplar' : widget.seasonName,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () async {
              final seasonTeams = await _watchSeasonTeams().first;
              if (!mounted) return;
              await _openAddGroupSheet(seasonTeams: seasonTeams);
            },
            icon: const Icon(Icons.add),
            tooltip: 'Grup Ekle',
          ),
        ],
      ),
      body: StreamBuilder<List<GroupModel>>(
        stream: _leagueService.watchGroups(widget.seasonId),
        builder: (context, groupsSnap) {
          if (groupsSnap.connectionState == ConnectionState.waiting &&
              !groupsSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (groupsSnap.hasError) {
            return Center(child: Text('Hata: ${groupsSnap.error}'));
          }
          final groups = (groupsSnap.data ?? const <GroupModel>[])
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
          return StreamBuilder<List<Team>>(
            stream: _watchSeasonTeams(),
            initialData: const <Team>[],
            builder: (context, teamsSnap) {
              final seasonTeams = teamsSnap.data ?? const <Team>[];
              final teamCountByGroupId = <String, int>{};
              for (final t in seasonTeams) {
                final gid = (t.groupId ?? '').trim();
                if (gid.isEmpty) continue;
                teamCountByGroupId[gid] = (teamCountByGroupId[gid] ?? 0) + 1;
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (groups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Grup bulunamadı.')),
                    )
                  else
                    for (final g in groups)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          leading: const Icon(Icons.groups_outlined),
                          title: Text(g.name.trim().isEmpty ? g.id : g.name),
                          subtitle: Text(
                            '${teamCountByGroupId[g.id] ?? 0} takım',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Düzenle',
                                onPressed: () => _openEditGroupSheet(g),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.playlist_add_check_outlined,
                                ),
                                tooltip: 'Takım Ekle/Çıkar',
                                onPressed: () => _openTeamAssignSheet(
                                  group: g,
                                  seasonTeams: seasonTeams,
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => TeamListScreen(
                                  seasonId: widget.seasonId,
                                  seasonName: widget.seasonName,
                                  initialGroupName: _formatGroupName(g.name),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                ],
              );
            },
          );
        },
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
  String _teamNameQuery = '';
  String _selectedGroup = '__ALL__';

  String _norm(String input) {
    return input.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().trim();
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.seasonName.trim().isEmpty ? 'Takımlar' : widget.seasonName,
        ),
      ),
      body: StreamBuilder<List<Team>>(
        stream: _watchTeams(),
        initialData: const <Team>[],
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
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
          if (effectiveGroup != _selectedGroup) {
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
                        value: effectiveGroup,
                        decoration: const InputDecoration(
                          labelText: 'Grup',
                          prefixIcon: Icon(Icons.groups_outlined),
                          border: OutlineInputBorder(),
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
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _teamNameQuery = v),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Takım bulunamadı.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final t = filtered[index];
                          final groupLabel = _formatGroupName(t.groupName);
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 2,
                              ),
                              leading: t.logoUrl.trim().isNotEmpty
                                  ? WebSafeImage(
                                      url: t.logoUrl,
                                      width: 36,
                                      height: 36,
                                      borderRadius: BorderRadius.circular(10),
                                      fallbackIconSize: 18,
                                    )
                                  : Icon(
                                      Icons.shield_outlined,
                                      color: cs.onSurfaceVariant,
                                    ),
                              title: Text(
                                t.name.trim().isEmpty ? t.id : t.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (groupLabel.isNotEmpty) ...[
                                    Text(
                                      groupLabel,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
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
                            ),
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
