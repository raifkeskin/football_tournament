import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/global_filter.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/master_class_app_bar.dart';
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
    required this.title,
  });

  final League league;
  final String seasonId;
  final String groupId;
  final String title;
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
    final seasons = (await sb.from('seasons').select().inFilter('league_id', ids))
        .map((r) => Season.fromMap(r))
        .toList();
    // Her turnuvanın varsayılan (aktif) sezonu.
    final seasonOf = <String, String>{};
    for (final l in leagues) {
      final own = seasons.where((s) => s.leagueId == l.id).toList()
        ..sort((a, b) => (b.startDate ?? DateTime(0)).compareTo(
          a.startDate ?? DateTime(0),
        ));
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
            title: own.length > 1 && name.isNotEmpty
                ? '${l.name} - $name'
                : l.name,
          ),
        );
      }
    }
    _cache = rows;
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      extendBodyBehindAppBar: true,
      appBar: const MasterClassAppBar(title: 'Puan Durumu'),
      body: SafeArea(
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
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

class _RowCard extends StatelessWidget {
  const _RowCard({required this.row});

  final _Row row;

  @override
  Widget build(BuildContext context) {
    final logo = row.league.logoUrl.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => TournamentHubScreen.open(
            context,
            leagueId: row.league.id,
            seasonId: row.seasonId,
            groupId: row.groupId,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: logo.isNotEmpty
                      ? WebSafeImage(
                          url: logo,
                          width: 40,
                          height: 40,
                          borderRadius: BorderRadius.circular(10),
                          fallbackIconSize: 20,
                        )
                      : const Icon(
                          Icons.emoji_events_outlined,
                          color: Color(0xFFF59E0B),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    row.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
