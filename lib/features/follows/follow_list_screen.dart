import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/app_session.dart';
import '../../core/services/follows.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/web_safe_image.dart';
import '../player/widgets/player_card.dart';
import '../team/screens/team_squad_screen.dart';

/// Takip Listem: yıldızlanan turnuvalar, takımlar ve futbolcular; yıldıza
/// dokununca takip bırakılır. Kişinin kendi takımı "OTOMATİK" (bırakılamaz).
class FollowListScreen extends StatefulWidget {
  const FollowListScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'FollowListScreen'),
      builder: (_) => const FollowListScreen(),
    ),
  );

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _Item {
  const _Item(this.id, this.name, this.logo);
  final String id;
  final String name;
  final String logo;
}

class _FollowListScreenState extends State<FollowListScreen> {
  static const _green = Color(0xFF34D399);
  static const _muted = Color(0xFF94A3B8);

  SupabaseClient get _sb => Supabase.instance.client;

  /// 0 Tümü, 1 Turnuva, 2 Takım, 3 Futbolcu.
  int _tab = 0;
  bool _loading = true;
  final _leagues = <String, _Item>{};
  final _teams = <String, _Item>{};
  final _players = <String, _Item>{};
  final _own = <_Item>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Follows.load(force: true);
    if (!mounted) return;
    final session = AppSession.of(context).value;
    final ownIds = <String>{
      for (final m in session.managedTeams) m.teamId,
      ?session.teamId,
    };
    final teamIds = {...Follows.teams.value, ...ownIds}.toList();
    try {
      final res = await Future.wait([
        Follows.leagues.value.isEmpty
            ? Future.value(const <Map<String, dynamic>>[])
            : _sb
                  .from('leagues')
                  .select('id, name, logo_url')
                  .inFilter('id', Follows.leagues.value.toList()),
        teamIds.isEmpty
            ? Future.value(const <Map<String, dynamic>>[])
            : _sb
                  .from('teams')
                  .select('id, name, logo_url')
                  .inFilter('id', teamIds),
        Follows.players.value.isEmpty
            ? Future.value(const <Map<String, dynamic>>[])
            : _sb
                  .from('players')
                  .select('id, name, surname, photo_url')
                  .inFilter('id', Follows.players.value.toList()),
      ]);
      String s(Object? v) => (v ?? '').toString().trim();
      _leagues
        ..clear()
        ..addAll({
          for (final r in res[0])
            s(r['id']): _Item(s(r['id']), s(r['name']), s(r['logo_url'])),
        });
      _teams.clear();
      _own.clear();
      for (final r in res[1]) {
        final it = _Item(s(r['id']), s(r['name']), s(r['logo_url']));
        if (ownIds.contains(it.id)) {
          _own.add(it);
        } else {
          _teams[it.id] = it;
        }
      }
      _players
        ..clear()
        ..addAll({
          for (final r in res[2])
            s(r['id']): _Item(
              s(r['id']),
              '${s(r['name'])} ${s(r['surname'])}'.trim(),
              s(r['photo_url']),
            ),
        });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openTeam(_Item t) async {
    String? seasonId;
    try {
      final row = await _sb
          .from('season_teams')
          .select('season_id')
          .eq('team_id', t.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      seasonId = row?['season_id']?.toString();
    } catch (_) {}
    if (!mounted || seasonId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'TeamSquadScreen'),
        builder: (_) => TeamSquadScreen(
          teamId: t.id,
          tournamentId: seasonId!,
          teamName: t.name,
          teamLogoUrl: t.logo,
        ),
      ),
    );
  }

  Widget _avatar(_Item it, {bool round = true}) {
    final fallback = Container(
      alignment: Alignment.center,
      color: const Color(0xFF1E293B),
      child: Text(
        it.name.isEmpty ? '?' : it.name.characters.first,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(round ? 20 : 10),
      child: SizedBox(
        width: 40,
        height: 40,
        child: it.logo.isEmpty
            ? fallback
            : WebSafeImage(url: it.logo, fit: BoxFit.cover),
      ),
    );
  }

  Widget _row(
    _Item it, {
    required FollowKind kind,
    VoidCallback? onTap,
    bool own = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF131D33),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF1F2A40)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                _avatar(it, round: kind != FollowKind.player),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      if (own)
                        const Text(
                          'Takımın',
                          style: TextStyle(
                            color: _green,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                if (own)
                  Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'OTOMATİK',
                      style: TextStyle(
                        color: Color(0xFF04291C),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  FollowStar(kind: kind, id: it.id),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
          child: Text(
            title,
            style: const TextStyle(
              color: _green,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
        ),
        ...rows,
      ],
    );
  }

  Widget _chip(int i, String label, int count) {
    final on = _tab == i;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: on ? const Color(0xFF10B981) : const Color(0xFF131D33),
          shape: StadiumBorder(
            side: BorderSide(
              color: on ? Colors.transparent : const Color(0xFF263248),
            ),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _tab = i),
            child: SizedBox(
              height: 36,
              child: Center(
                child: Text(
                  '$label $count',
                  style: TextStyle(
                    color: on ? const Color(0xFF04291C) : Colors.white70,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Takip Listem',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: Listenable.merge([
                Follows.leagues,
                Follows.teams,
                Follows.players,
              ]),
              builder: (context, _) {
                // Yıldızı kaldırılan satır listeden düşer.
                final leagues = [
                  for (final id in Follows.leagues.value) ?_leagues[id],
                ];
                final teams = [
                  for (final id in Follows.teams.value) ?_teams[id],
                ];
                final players = [
                  for (final id in Follows.players.value) ?_players[id],
                ];
                final total = leagues.length + teams.length + players.length;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Row(
                      children: [
                        _chip(0, 'Tümü', total),
                        _chip(1, 'Turnuva', leagues.length),
                        _chip(2, 'Takım', teams.length + _own.length),
                        _chip(3, 'Futbolcu', players.length),
                      ],
                    ),
                    if (total == 0 && _own.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(8, 32, 8, 0),
                        child: Text(
                          'Henüz takip ettiğin yok. Turnuva seçicide, takım '
                          'sayfasında ya da futbolcu profilinde yıldıza '
                          'dokunarak ekleyebilirsin.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted, height: 1.4),
                        ),
                      ),
                    if (_tab == 0 || _tab == 1)
                      _section('TURNUVALAR', [
                        for (final l in leagues)
                          _row(l, kind: FollowKind.league),
                      ]),
                    if (_tab == 0 || _tab == 2)
                      _section('TAKIMLAR', [
                        for (final t in _own)
                          _row(
                            t,
                            kind: FollowKind.team,
                            own: true,
                            onTap: () => _openTeam(t),
                          ),
                        for (final t in teams)
                          _row(
                            t,
                            kind: FollowKind.team,
                            onTap: () => _openTeam(t),
                          ),
                      ]),
                    if (_tab == 0 || _tab == 3)
                      _section('FUTBOLCULAR', [
                        for (final p in players)
                          _row(
                            p,
                            kind: FollowKind.player,
                            onTap: () =>
                                showPlayerCard(context, playerKey: p.id),
                          ),
                      ]),
                  ],
                );
              },
            ),
    );
  }
}
