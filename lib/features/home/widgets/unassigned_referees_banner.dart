import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../match/models/match.dart';
import '../../match/screens/match_details_screen.dart';
import '../../referees/referee_service.dart';

/// 5 gün içinde oynanacak, hakemi atanmamış maç.
class _Unassigned {
  _Unassigned(Map<String, dynamic> r)
    : id = r['id'].toString(),
      home = (r['home_name'] ?? 'Ev Sahibi').toString(),
      away = (r['away_name'] ?? 'Deplasman').toString(),
      date = DateTime.tryParse((r['match_date'] ?? '').toString()),
      time = (r['match_time'] ?? '').toString();

  final String id;
  final String home;
  final String away;
  final DateTime? date;
  final String time;

  String get when {
    final d = date;
    final t = time.length >= 5 ? time.substring(0, 5) : time;
    if (d == null) return t;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} $t'.trim();
  }
}

/// Ana sayfada maçın yöneticilerine (admin, kurucu, bölge sorumlusu)
/// "N maçta hakem atanmadı" uyarısı; maça dokununca Hakem Ata penceresi
/// açık maç detayı. Hakem atanınca kendiliğinden kaybolur.
class UnassignedRefereesBanner extends StatefulWidget {
  const UnassignedRefereesBanner({super.key, required this.leagueId});

  final String leagueId;

  static final refresh = ValueNotifier<int>(0);

  @override
  State<UnassignedRefereesBanner> createState() =>
      _UnassignedRefereesBannerState();
}

class _UnassignedRefereesBannerState extends State<UnassignedRefereesBanner> {
  static const _yellow = Color(0xFFFACC15);
  static final Map<String, List<_Unassigned>> _cache = {};

  List<_Unassigned> _items = const [];
  bool _canSee = false;

  @override
  void initState() {
    super.initState();
    _items = _cache[widget.leagueId] ?? const [];
    UnassignedRefereesBanner.refresh.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppSession.of(context).value;
    final canSee =
        (s.isAdmin || s.isLeagueOwner || s.ownedRegions.isNotEmpty) &&
        RefereeService.enabledFor(isAdmin: s.isAdmin);
    if (canSee != _canSee) {
      _canSee = canSee;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant UnassignedRefereesBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leagueId != widget.leagueId) {
      _items = _cache[widget.leagueId] ?? const [];
      _load();
    }
  }

  @override
  void dispose() {
    UnassignedRefereesBanner.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!_canSee) {
      if (_items.isNotEmpty && mounted) setState(() => _items = const []);
      return;
    }
    final league = widget.leagueId;
    try {
      final rows = await Supabase.instance.client.rpc(
        'unassigned_referee_matches',
        params: {'p_league_id': league},
      );
      final list = [
        for (final r in (rows as List? ?? const []))
          _Unassigned(Map<String, dynamic>.from(r as Map)),
      ];
      _cache[league] = list;
      if (mounted && league == widget.leagueId) setState(() => _items = list);
    } catch (_) {
      // Uyarı gösterilemezse ana sayfa etkilenmez.
    }
  }

  Future<void> _openMatch(_Unassigned u) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final isAdmin = AppSession.of(context).value.isAdmin;
    try {
      final row = await Supabase.instance.client
          .from('matches')
          .select()
          .eq('id', u.id)
          .single();
      await nav.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'MatchDetailsScreen'),
          builder: (_) => MatchDetailsScreen(
            match: MatchModel.fromMap(row, u.id),
            isAdmin: isAdmin,
            openRefereePicker: true,
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Maç açılamadı: $e')));
    }
    await _load();
  }

  Future<void> _openList() async {
    final picked = await showModalBottomSheet<_Unassigned>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(c).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Text(
                  'Hakemi atanmamış maçlar',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final u = _items[i];
                    return Material(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onTap: () => Navigator.pop(c, u),
                        leading: const Icon(
                          Icons.sports_rounded,
                          color: _yellow,
                        ),
                        title: Text(
                          '${u.home} – ${u.away}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          u.when,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                        trailing: const Text(
                          'Ata ›',
                          style: TextStyle(
                            color: _yellow,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) await _openMatch(picked);
  }

  @override
  Widget build(BuildContext context) {
    if (!_canSee || _items.isEmpty) return const SizedBox.shrink();
    final n = _items.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Material(
        color: _yellow.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: n == 1 ? () => _openMatch(_items.first) : _openList,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _yellow.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: _yellow,
                  child: Icon(
                    Icons.sports_rounded,
                    size: 17,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n == 1
                            ? 'Maça hakem atanmadı'
                            : '$n maçta hakem atanmadı',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n == 1
                            ? '${_items.first.home} – ${_items.first.away} · '
                                  '${_items.first.when}'
                            : 'Önümüzdeki 5 gün · dokun, hakemleri ata',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: _yellow),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
