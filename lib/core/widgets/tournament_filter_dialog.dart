import 'package:flutter/material.dart';

import '../../features/match/models/match.dart';
import '../../features/tournament/models/league.dart';
import '../../features/tournament/models/season.dart';
import 'admin_form.dart';
import 'admin_page.dart';

typedef WeekInfo = ({int? maxWeek, int? nextWeek});

/// Filtre panelinin döndürdüğü seçim.
class TournamentFilter {
  const TournamentFilter({
    this.leagueId,
    this.seasonId,
    this.groupId,
    this.week,
  });

  final String? leagueId;
  final String? seasonId;
  final String? groupId;
  final int? week;
}

/// Puan Durumu / Fikstür / İstatistik ekranlarının ortak filtre paneli.
///
/// Seçimler panel içinde taslak tutulur; ekrana yalnızca "Filtreleri Uygula"
/// ile yansır (dışarı dokunup kapatınca `null` döner). Sezon ve grup listeleri
/// panelde seçili turnuva/sezona göre canlı yüklenir.
Future<TournamentFilter?> showTournamentFilterDialog({
  required BuildContext context,
  required List<League> leagues,
  required TournamentFilter initial,
  required Stream<List<Season>> Function(String leagueId) watchSeasons,
  Stream<List<GroupModel>> Function(String seasonId)? watchGroups,
  Future<WeekInfo> Function(String leagueId, String seasonId, String? groupId)?
  loadWeekInfo,
}) {
  return showDialog<TournamentFilter>(
    context: context,
    builder: (_) => _TournamentFilterDialog(
      leagues: leagues,
      initial: initial,
      watchSeasons: watchSeasons,
      watchGroups: watchGroups,
      loadWeekInfo: loadWeekInfo,
    ),
  );
}

class _TournamentFilterDialog extends StatefulWidget {
  const _TournamentFilterDialog({
    required this.leagues,
    required this.initial,
    required this.watchSeasons,
    this.watchGroups,
    this.loadWeekInfo,
  });

  final List<League> leagues;
  final TournamentFilter initial;
  final Stream<List<Season>> Function(String leagueId) watchSeasons;
  final Stream<List<GroupModel>> Function(String seasonId)? watchGroups;
  final Future<WeekInfo> Function(
    String leagueId,
    String seasonId,
    String? groupId,
  )?
  loadWeekInfo;

  @override
  State<_TournamentFilterDialog> createState() =>
      _TournamentFilterDialogState();
}

class _TournamentFilterDialogState extends State<_TournamentFilterDialog> {
  String? _leagueId;
  String? _seasonId;
  String? _groupId;
  int? _week;

  String? _seasonsFor;
  Stream<List<Season>>? _seasonsStream;
  String? _groupsFor;
  Stream<List<GroupModel>>? _groupsStream;
  final Map<String, Future<WeekInfo>> _weekInfo = {};

  @override
  void initState() {
    super.initState();
    _leagueId = widget.initial.leagueId;
    _seasonId = widget.initial.seasonId;
    _groupId = widget.initial.groupId;
    _week = widget.initial.week;
  }

  Stream<List<Season>> _seasons(String leagueId) {
    if (_seasonsFor != leagueId || _seasonsStream == null) {
      _seasonsFor = leagueId;
      _seasonsStream = widget.watchSeasons(leagueId);
    }
    return _seasonsStream!;
  }

  Stream<List<GroupModel>> _groups(String seasonId) {
    if (_groupsFor != seasonId || _groupsStream == null) {
      _groupsFor = seasonId;
      _groupsStream = widget.watchGroups!(seasonId);
    }
    return _groupsStream!;
  }

  static String _defaultSeasonId(List<Season> seasons) {
    for (final s in seasons) {
      if (s.isDefault) return s.id;
    }
    for (final s in seasons) {
      if (s.isActive) return s.id;
    }
    return seasons.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AdminDialogCloseOverlay(
        onClose: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: adminDialogDecoration(),
          child: StreamBuilder<List<Season>>(
            stream: _leagueId == null
                ? Stream.value(const <Season>[])
                : _seasons(_leagueId!),
            builder: (context, seasonSnap) {
              // Akış değişince StreamBuilder yeni veri gelene kadar önceki
              // turnuvanın sezonlarını tutar; beklerken boş kabul et.
              final seasonsLoading =
                  seasonSnap.connectionState == ConnectionState.waiting;
              final seasons = seasonsLoading
                  ? const <Season>[]
                  : (seasonSnap.data ?? const <Season>[]);
              // Turnuva değişince geçersiz kalan sezon seçimi varsayılana çekilir.
              final seasonId = seasons.any((s) => s.id == _seasonId)
                  ? _seasonId
                  : (seasons.isNotEmpty ? _defaultSeasonId(seasons) : null);
              if (!seasonsLoading && seasonId != _seasonId) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _seasonId = seasonId;
                    _groupId = null;
                    _week = null;
                  });
                });
              }

              return StreamBuilder<List<GroupModel>>(
                stream: seasonId == null || widget.watchGroups == null
                    ? Stream.value(const <GroupModel>[])
                    : _groups(seasonId),
                builder: (context, groupSnap) {
                  final groupsLoading =
                      groupSnap.connectionState == ConnectionState.waiting;
                  final groups = groupsLoading
                      ? <GroupModel>[]
                      : [...(groupSnap.data ?? const <GroupModel>[])];
                  groups.sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );
                  final groupNameById = <String, String>{
                    for (final e in groups.indexed)
                      e.$2.id: e.$2.name.trim().isNotEmpty
                          ? e.$2.name.trim()
                          : 'Grup ${e.$1 + 1}',
                  };
                  // "Tüm gruplar" seçeneği yok; seçim yoksa ilk grup.
                  final groupId = groupNameById.containsKey(_groupId)
                      ? _groupId
                      : (groups.isEmpty ? null : groups.first.id);

                  final ready =
                      seasonId != null &&
                      !groupsLoading &&
                      seasonId == _seasonId;
                  final seasonName = seasons
                      .where((s) => s.id == seasonId)
                      .firstOrNull
                      ?.name;

                  // Satırlar seçime göre kaybolmaz (yükleniyor / tek grup
                  // durumunda kilitli gösterilir); pencere boyu sabit kalır ve
                  // "Filtreleri Uygula" yerinden oynamaz.
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AdminDialogHeader(
                        icon: Icons.tune_rounded,
                        title: 'Filtrele',
                      ),
                      const SizedBox(height: 16),
                      AdminFieldGroup(
                        children: [
                          _leagueRow(),
                          AdminSelectRow(
                            icon: Icons.calendar_month_outlined,
                            label: 'Sezon',
                            value: seasonName,
                            placeholder: _leagueId == null
                                ? 'Önce turnuva seçin'
                                : (seasonsLoading
                                      ? 'Yükleniyor…'
                                      : 'Sezon yok'),
                            loading: _leagueId != null && seasonsLoading,
                            onTap: seasons.length < 2
                                ? null
                                : () async {
                                    final picked =
                                        await showAdminOptionPicker<Season>(
                                          context: context,
                                          title: 'Sezon Seç',
                                          items: seasons,
                                          labelBuilder: (s) => s.name,
                                          selected: seasons
                                              .where((s) => s.id == seasonId)
                                              .firstOrNull,
                                        );
                                    if (picked == null ||
                                        picked.id == _seasonId ||
                                        !mounted) {
                                      return;
                                    }
                                    setState(() {
                                      _seasonId = picked.id;
                                      _groupId = null;
                                      _week = null;
                                    });
                                  },
                          ),
                          if (widget.watchGroups != null)
                            AdminSelectRow(
                              icon: Icons.workspaces_outline,
                              label: 'Grup',
                              value: groups.length > 1
                                  ? groupNameById[groupId]
                                  : null,
                              placeholder: groupsLoading && seasonId != null
                                  ? 'Yükleniyor…'
                                  : 'Tek grup',
                              loading: groupsLoading && seasonId != null,
                              onTap: groups.length < 2
                                  ? null
                                  : () async {
                                      final picked =
                                          await showAdminOptionPicker<String>(
                                            context: context,
                                            title: 'Grup Seç',
                                            items: groups
                                                .map((g) => g.id)
                                                .toList(),
                                            labelBuilder: (id) =>
                                                groupNameById[id] ?? '',
                                            selected: groupId,
                                          );
                                      if (picked == null || !mounted) return;
                                      if (picked == groupId) return;
                                      setState(() {
                                        _groupId = picked;
                                        _week = null;
                                      });
                                    },
                            ),
                          if (widget.loadWeekInfo != null)
                            ready
                                ? _weekRow(_leagueId!, seasonId, groupId)
                                : const AdminSelectRow(
                                    icon: Icons.event_note_outlined,
                                    label: 'Hafta',
                                    value: null,
                                    placeholder: 'Yükleniyor…',
                                    loading: true,
                                    onTap: null,
                                  ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      AdminPrimaryButton(
                        label: 'FİLTRELERİ UYGULA',
                        onPressed: !ready
                            ? null
                            : () => Navigator.pop(
                                context,
                                TournamentFilter(
                                  leagueId: _leagueId,
                                  seasonId: seasonId,
                                  groupId: groupId,
                                  week: _week,
                                ),
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _leagueRow() {
    final leagues = widget.leagues;
    final name = leagues.where((l) => l.id == _leagueId).firstOrNull?.name;
    return AdminSelectRow(
      icon: Icons.emoji_events_outlined,
      label: 'Turnuva',
      value: name,
      placeholder: 'Turnuva seçin',
      onTap: () async {
        final picked = await showAdminOptionPicker<League>(
          context: context,
          title: 'Turnuva Seç',
          items: leagues,
          labelBuilder: (l) => l.name,
          selected: leagues.where((l) => l.id == _leagueId).firstOrNull,
        );
        if (picked == null || picked.id == _leagueId || !mounted) return;
        setState(() {
          _leagueId = picked.id;
          _seasonId = null;
          _groupId = null;
          _week = null;
        });
      },
    );
  }

  Widget _weekRow(String leagueId, String seasonId, String? groupId) {
    final key = '$leagueId|$seasonId|${groupId ?? ''}';
    return FutureBuilder<WeekInfo>(
      key: ValueKey(key),
      future: _weekInfo.putIfAbsent(
        key,
        () => widget.loadWeekInfo!(leagueId, seasonId, groupId),
      ),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const AdminSelectRow(
            icon: Icons.event_note_outlined,
            label: 'Hafta',
            value: null,
            placeholder: 'Yükleniyor…',
            loading: true,
            onTap: null,
          );
        }
        final info = snap.data!;
        final maxWeek = (info.maxWeek ?? 30) > 0 ? (info.maxWeek ?? 30) : 1;
        final weeks = [for (var i = 1; i <= maxWeek; i++) i];
        final defaultWeek = weeks.contains(info.nextWeek)
            ? info.nextWeek!
            : weeks.first;
        final week = weeks.contains(_week) ? _week! : defaultWeek;
        return AdminSelectRow(
          icon: Icons.event_note_outlined,
          label: 'Hafta',
          value: '$week. Hafta',
          placeholder: 'Hafta seçin',
          onTap: () async {
            final picked = await showAdminOptionPicker<int>(
              context: context,
              title: 'Hafta Seç',
              items: weeks,
              labelBuilder: (w) => '$w. Hafta',
              selected: week,
            );
            if (picked == null || !mounted) return;
            setState(() => _week = picked);
          },
        );
      },
    );
  }
}
