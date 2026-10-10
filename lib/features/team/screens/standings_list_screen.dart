import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/global_filter.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../tournament/models/league.dart';
import '../../tournament/models/season.dart';
import '../../tournament/screens/tournament_hub_screen.dart';

/// Menüdeki Puan Durumu: kişinin görebildiği aktif turnuvalar (misafire
/// hepsi). Birden fazla grubu olan turnuvada her grup ayrı satır
/// ("Turnuva - Grup"), tek gruplu turnuvada yalnızca turnuva adı. Satıra
/// basınca Turnuva Sayfası'nın Puan Durumu sekmesi açılır.
class StandingsListScreen extends StatefulWidget {
  const StandingsListScreen({super.key});

  @override
  State<StandingsListScreen> createState() => _StandingsListScreenState();
}

class _Row {
  const _Row({
    required this.league,
    required this.seasonId,
    required this.groupId,
    this.groupName,
  });

  final League league;
  final String seasonId;
  final String groupId;

  /// Sezonda birden fazla grup varsa grubun adı (turnuva adının altında).
  final String? groupName;
}

class _StandingsListScreenState extends State<StandingsListScreen> {
  late final Stream<List<League>> _leagues = ServiceLocator.leagueService
      .watchLeagues();

  /// Son liste: ekran yeniden açılınca beklemeden görünür.
  static List<_Row>? _cache;
  String? _key;
  Future<List<_Row>>? _rows;

  Future<List<_Row>> _load(List<League> leagues) async {
    final sb = Supabase.instance.client;
    final ids = [for (final l in leagues) l.id];
    final seasons =
        (await sb.from('seasons').select().inFilter('league_id', ids))
            .map((r) => Season.fromMap(r))
            .toList();
    // Her turnuvanın varsayılan (aktif) sezonu.
    final seasonOf = <String, String>{};
    for (final l in leagues) {
      final own = seasons.where((s) => s.leagueId == l.id).toList()
        ..sort(
          (a, b) => (b.startDate ?? DateTime(0)).compareTo(
            a.startDate ?? DateTime(0),
          ),
        );
      if (own.isNotEmpty) seasonOf[l.id] = pickDefaultSeasonId(own);
    }
    final groups = seasonOf.isEmpty
        ? const <Map<String, dynamic>>[]
        : await sb
              .from('groups')
              .select('id, name, season_id')
              .inFilter('season_id', seasonOf.values.toList())
              .order('name');
    final rows = <_Row>[];
    for (final l in leagues) {
      final sId = seasonOf[l.id];
      if (sId == null) continue;
      final own = groups.where((g) => g['season_id'].toString() == sId);
      for (final g in own) {
        final name = (g['name'] ?? '').toString().trim();
        rows.add(
          _Row(
            league: l,
            seasonId: sId,
            groupId: g['id'].toString(),
            groupName: own.length > 1 && name.isNotEmpty ? name : null,
          ),
        );
      }
    }
    _cache = rows;
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    // Başlık yok: menü düğmesi ve turnuva kimliği üst bantta.
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<League>>(
          stream: _leagues,
          builder: (context, snap) {
            final leagues = snap.data;
            if (leagues != null) {
              final key = [for (final l in leagues) l.id].join(',');
              if (key != _key) {
                _key = key;
                _rows = _load(leagues);
              }
            }
            return FutureBuilder<List<_Row>>(
              future: _rows,
              initialData: _cache,
              builder: (context, rowsSnap) {
                final rows = rowsSnap.data;
                if (rows == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (rows.isEmpty) {
                  return const Center(
                    child: Text(
                      'Görüntülenecek turnuva yok.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _RowCard(row: rows[i]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Liste satırı: ince koyu şerit; turnuva logosu şeridin solundan taşar
/// (büyük), satırlar arasındaki boşluk logonun alttaki satıra değmemesi
/// için yeterli.
class _RowCard extends StatelessWidget {
  const _RowCard({required this.row});

  final _Row row;

  static const _logo = 54.0;
  static const _rowHeight = 46.0;

  @override
  Widget build(BuildContext context) {
    final logo = row.league.logoUrl.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: _logo,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: [
            Positioned(
              left: _logo / 2,
              right: 0,
              height: _rowHeight,
              child: Material(
                color: const Color(0xFF1E293B).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => TournamentHubScreen.open(
                    context,
                    leagueId: row.league.id,
                    seasonId: row.seasonId,
                    groupId: row.groupId,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: _logo / 2 + 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.league.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                              if (row.groupName != null)
                                Text(
                                  row.groupName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Logo şeridin dışına taşar; dokunuş satıra gider.
            IgnorePointer(
              child: SizedBox(
                width: _logo,
                height: _logo,
                child: logo.isNotEmpty
                    ? WebSafeImage(
                        url: logo,
                        width: _logo,
                        height: _logo,
                        fit: BoxFit.contain,
                        fallbackIconSize: 26,
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF1E293B),
                        ),
                        child: const Icon(
                          Icons.emoji_events_outlined,
                          color: Color(0xFFF59E0B),
                          size: 28,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
