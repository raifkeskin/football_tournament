import 'package:flutter/material.dart';

import '../../features/match/models/match.dart';
import '../../features/tournament/models/league.dart';
import '../../features/tournament/models/season.dart';
import 'custom_popup_selector.dart';

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
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E293B), Color(0xFF064E3B)],
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
                final groupId = groupNameById.containsKey(_groupId)
                    ? _groupId
                    : null;

                final ready =
                    seasonId != null && !groupsLoading && seasonId == _seasonId;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _leagueSelector(),
                    const SizedBox(height: 12),
                    if (seasons.isNotEmpty) ...[
                      CustomPopupSelector<String>(
                        label: 'Sezon',
                        selectedValue: seasonId,
                        items: seasons.map((s) => s.id).toList(),
                        labelBuilder: (id) => seasons
                            .firstWhere(
                              (s) => s.id == id,
                              orElse: () => seasons.first,
                            )
                            .name,
                        onChanged: (val) {
                          if (val == null || val == _seasonId) return;
                          setState(() {
                            _seasonId = val;
                            _groupId = null;
                            _week = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (groups.length > 1) ...[
                      CustomPopupSelector<String?>(
                        label: 'Grup',
                        selectedValue: groupId,
                        items: [null, ...groups.map((g) => g.id)],
                        labelBuilder: (id) => id == null
                            ? 'Tüm Gruplar'
                            : (groupNameById[id] ?? ''),
                        onChanged: (val) {
                          if (val == _groupId) return;
                          setState(() {
                            _groupId = val;
                            _week = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (widget.loadWeekInfo != null && ready)
                      _weekSelector(_leagueId!, seasonId, groupId),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          disabledBackgroundColor: const Color(
                            0xFF10B981,
                          ).withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
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
                        child: const Text(
                          'Filtreleri Uygula',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
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
    );
  }

  Widget _leagueSelector() {
    final leagues = widget.leagues;
    return CustomPopupSelector<String>(
      label: 'Turnuva',
      selectedValue: _leagueId,
      items: leagues.map((l) => l.id).toList(),
      labelBuilder: (id) => leagues
          .firstWhere((l) => l.id == id, orElse: () => leagues.first)
          .name,
      onChanged: (val) {
        if (val == null || val == _leagueId) return;
        setState(() {
          _leagueId = val;
          _seasonId = null;
          _groupId = null;
          _week = null;
        });
      },
    );
  }

  Widget _weekSelector(String leagueId, String seasonId, String? groupId) {
    final key = '$leagueId|$seasonId|${groupId ?? ''}';
    return FutureBuilder<WeekInfo>(
      key: ValueKey(key),
      future: _weekInfo.putIfAbsent(
        key,
        () => widget.loadWeekInfo!(leagueId, seasonId, groupId),
      ),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final info = snap.data!;
        final maxWeek = (info.maxWeek ?? 30) > 0 ? (info.maxWeek ?? 30) : 1;
        final weeks = [for (var i = 1; i <= maxWeek; i++) i];
        final defaultWeek = weeks.contains(info.nextWeek)
            ? info.nextWeek!
            : weeks.first;
        final week = weeks.contains(_week) ? _week! : defaultWeek;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CustomPopupSelector<int>(
            label: 'Hafta',
            selectedValue: week,
            items: weeks,
            labelBuilder: (w) => '$w. Hafta',
            onChanged: (val) => setState(() => _week = val),
          ),
        );
      },
    );
  }
}
