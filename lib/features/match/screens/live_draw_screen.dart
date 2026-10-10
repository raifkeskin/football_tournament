import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/global_filter.dart';
import '../../../core/utils/team_colors.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../tournament/screens/tournament_hub_screen.dart';
import '../services/live_draw_service.dart';

const _bg = Color(0xFF0F172A);
const _card = Color(0xFF131C2E);
const _card2 = Color(0xFF1A2438);
const _muted = Color(0xFF94A3B8);
const _accent = Color(0xFF10B981);
const _live = Color(0xFFEF4444);
const _gold = Color(0xFFFBBF24);

/// Kuradaki takımın görünümü.
class _DrawTeam {
  const _DrawTeam(this.name, this.logo, this.color);
  final String name;
  final String logo;
  final Color color;

  String get initials => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w.characters.first.toUpperCase())
      .join();
}

Future<Map<String, _DrawTeam>> _loadTeams(List<String> ids) async {
  if (ids.isEmpty) return const {};
  final rows = await Supabase.instance.client
      .from('teams')
      .select('id, name, logo_url, first_color')
      .inFilter('id', ids);
  return {
    for (final r in rows)
      r['id'].toString(): _DrawTeam(
        (r['name'] ?? '').toString().trim(),
        (r['logo_url'] ?? '').toString().trim(),
        parseHexColor(r['first_color']?.toString()) ?? const Color(0xFF334155),
      ),
  };
}

/// Turnuva logoları (kura görseli için); oturum boyunca bir kez okunur.
final Map<String, Future<String>> _logoCache = {};

Future<String> _leagueLogo(String leagueId) =>
    _logoCache.putIfAbsent(leagueId, () async {
      try {
        final r = await Supabase.instance.client
            .from('leagues')
            .select('logo_url')
            .eq('id', leagueId)
            .maybeSingle();
        return (r?['logo_url'] ?? '').toString().trim();
      } catch (_) {
        return '';
      }
    });

String _two(int v) => v.toString().padLeft(2, '0');

String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String _dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'BUGÜN ${_clock(t)}';
  if (diff == 1) return 'YARIN ${_clock(t)}';
  return '${t.day}.${_two(t.month)} ${_clock(t)}';
}

/// Canlı kura ekranı: geri sayım → takımların tek tek açıklanması → sonuç.
/// Açıklama zamanları sunucudan gelir; herkes aynı anı görür.
class LiveDrawScreen extends StatefulWidget {
  const LiveDrawScreen({super.key, required this.drawId});

  final String drawId;

  @override
  State<LiveDrawScreen> createState() => _LiveDrawScreenState();
}

class _LiveDrawScreenState extends State<LiveDrawScreen> {
  final _svc = LiveDrawService.instance;
  LiveDrawState? _state;
  Map<String, _DrawTeam> _teams = const {};
  Object? _error;
  Timer? _poll;
  Timer? _tick;
  RealtimeChannel? _presence;
  int _viewers = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _joinPresence();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    final p = _presence;
    if (p != null) Supabase.instance.client.removeChannel(p);
    super.dispose();
  }

  /// İzleyici sayısı: aynı kanaldaki herkes (giriş yapmamış olanlar dahil).
  void _joinPresence() {
    try {
      final ch = Supabase.instance.client.channel('live-draw-${widget.drawId}');
      ch
          .onPresenceSync((_) {
            final n = ch.presenceState().fold<int>(
              0,
              (a, s) => a + s.presences.length,
            );
            if (mounted) setState(() => _viewers = n);
          })
          .subscribe((status, _) async {
            if (status == RealtimeSubscribeStatus.subscribed) {
              await ch.track({'at': DateTime.now().toIso8601String()});
            }
          });
      _presence = ch;
    } catch (_) {}
  }

  Future<void> _fetch() async {
    try {
      final s = await _svc.fetch(widget.drawId);
      if (!mounted) return;
      if (s != null && _teams.isEmpty) {
        final teams = await _loadTeams(s.teamIds);
        if (!mounted) return;
        _teams = teams;
      }
      setState(() {
        _state = s;
        _error = null;
      });
      _schedule();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      _poll?.cancel();
      _poll = Timer(const Duration(seconds: 3), _fetch);
    }
  }

  /// Bir sonraki açıklama anında yeniden sorar.
  void _schedule() {
    _poll?.cancel();
    final s = _state;
    if (s == null || s.done || s.cancelled) return;
    Duration wait;
    if (s.notStarted) {
      final ms = s.startAt.difference(s.serverNow).inMilliseconds + 200;
      wait = Duration(milliseconds: ms.clamp(300, 30000));
    } else if (s.nextIn != null) {
      wait = Duration(
        milliseconds: (s.nextIn! * 1000 + 150).round().clamp(300, 10000),
      );
    } else {
      final ms = s.endAt.difference(s.serverNow).inMilliseconds + 600;
      wait = Duration(milliseconds: ms.clamp(500, 10000));
    }
    _poll = Timer(wait, _fetch);
  }

  _DrawTeam _team(String id) =>
      _teams[id] ?? const _DrawTeam('Takım', '', Color(0xFF334155));

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text(
          'Canlı Kura',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (s != null && s.live)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Center(child: LiveBadge()),
            ),
        ],
      ),
      body: s == null
          ? Center(
              child: _error != null
                  ? const Text(
                      'Kura yüklenemedi, tekrar deneniyor…',
                      style: TextStyle(color: Colors.white70),
                    )
                  : const CircularProgressIndicator(color: _accent),
            )
          : s.cancelled
          ? const Center(
              child: Text(
                'Bu kura çekimi iptal edildi.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : s.notStarted
          ? _countdown(s)
          : s.done
          ? _doneView(s)
          : _liveView(s),
    );
  }

  // ---- Geri sayım -------------------------------------------------------

  Widget _countdown(LiveDrawState s) {
    final left = s.startAt.difference(s.serverNow);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeroCard(
          badge: _SoonBadge(text: _dayLabel(s.startAt)),
          height: 170,
          leagueId: s.leagueId,
        ),
        const SizedBox(height: 16),
        Text(
          s.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Kura başladığında takımlar burada tek tek açıklanacak. '
          'Ekranı açık tutman yeterli.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 18),
        _CountdownBoxes(left: left),
        if (_viewers > 1) ...[
          const SizedBox(height: 14),
          Text(
            '$_viewers kişi bekliyor',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12.5),
          ),
        ],
        if (AppSession.of(context).value.canManageLeague(s.leagueId)) ...[
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => _cancel(s),
            style: TextButton.styleFrom(foregroundColor: _live),
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Kurayı iptal et'),
          ),
        ],
      ],
    );
  }

  /// Fikstürü kuranın turnuva / sezon / grubuyla (bölgesiyle) açar.
  Future<void> _openFixture(LiveDrawState s) async {
    String? groupId;
    final first = s.revealed.isEmpty ? null : s.revealed.first;
    if (first != null && first.away != null) {
      try {
        final r = await Supabase.instance.client
            .from('matches')
            .select('group_id')
            .eq('season_id', s.seasonId)
            .eq('home_team_id', first.home)
            .eq('away_team_id', first.away!)
            .order('created_at', ascending: false)
            .limit(1);
        if (r.isNotEmpty) groupId = r.first['group_id']?.toString();
      } catch (_) {}
    }
    if (!mounted) return;
    GlobalFilter.setLeague(s.leagueId);
    if (s.seasonId.isNotEmpty) GlobalFilter.setSeason(s.seasonId);
    if (groupId != null) GlobalFilter.setGroup(groupId);
    // Kuranın fikstürü: Turnuva Sayfası'nın Fikstür sekmesi.
    final nav = Navigator.of(context)..popUntil((r) => r.isFirst);
    await TournamentHubScreen.open(
      nav.context,
      leagueId: s.leagueId,
      seasonId: s.seasonId.isEmpty ? null : s.seasonId,
      groupId: groupId,
      initialTab: TournamentHubTab.fixture,
    );
  }

  Future<void> _cancel(LiveDrawState s) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Kurayı iptal et',
      message:
          'Canlı kura iptal edilir ve haberi yayından kalkar. Sonra yeniden '
          'kura çekebilirsin.',
      confirmLabel: 'İPTAL ET',
    );
    if (!ok || !mounted) return;
    try {
      await _svc.cancel(s.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('İptal edilemedi: $e')));
    }
  }

  // ---- Canlı -----------------------------------------------------------

  Widget _liveView(LiveDrawState s) {
    final cur = s.current;
    final last = s.revealed.isEmpty ? null : s.revealed.last;
    final shown = cur ?? last;
    final week = shown?.week ?? 0;
    final remaining = s.endAt.difference(s.serverNow);
    final rem = remaining.isNegative ? Duration.zero : remaining;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            gradient: const RadialGradient(
              center: Alignment.topCenter,
              radius: 1.2,
              colors: [Color(0x2EEF4444), Color(0xFF0B1220)],
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_viewers > 0) ...[
                    const Icon(
                      Icons.visibility_outlined,
                      size: 14,
                      color: _muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_viewers',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${s.startWeek + week}. HAFTA',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Slot(
                      side: 'EV SAHİBİ',
                      team: shown == null ? null : _team(shown.home),
                      teamKey: shown?.home,
                    ),
                  ),
                  const SizedBox(
                    width: 40,
                    child: Text(
                      'VS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _gold,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Slot(
                      side: 'DEPLASMAN',
                      team: shown?.away == null ? null : _team(shown!.away!),
                      teamKey: shown?.away,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(
                    end: s.total == 0 ? 0 : s.revealed.length / s.total,
                  ),
                  duration: const Duration(milliseconds: 400),
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    color: _live,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${s.revealed.length} / ${s.total} maç',
                    style: const TextStyle(color: _muted, fontSize: 11.5),
                  ),
                  Text(
                    'kalan ~${rem.inMinutes} dk ${rem.inSeconds % 60} sn',
                    style: const TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _WeekList(
            state: s,
            team: _team,
            newestFirst: true,
            highlightLast: cur == null,
          ),
        ),
      ],
    );
  }

  // ---- Sonuç -----------------------------------------------------------

  Widget _doneView(LiveDrawState s) {
    final weeks = {for (final p in s.revealed) p.week}.length;
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B4A35), Color(0xFF062A1E)],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Kura tamamlandı',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Fikstür yayınlandı · ${s.title}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(
            children: [
              _Stat(value: '$weeks', label: 'hafta'),
              const SizedBox(width: 8),
              _Stat(value: '${s.total}', label: 'maç'),
              const SizedBox(width: 8),
              _Stat(value: '${s.teamIds.length}', label: 'takım'),
            ],
          ),
        ),
        Expanded(
          child: _WeekList(state: s, team: _team, newestFirst: false),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => _openFixture(s),
                child: const Text(
                  'FİKSTÜRE GİT',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Ev sahibi / deplasman yuvası: açıklanınca takım "düşerek" yerine oturur.
class _Slot extends StatelessWidget {
  const _Slot({required this.side, required this.team, required this.teamKey});

  final String side;
  final _DrawTeam? team;
  final String? teamKey;

  @override
  Widget build(BuildContext context) {
    final t = team;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 124,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: t == null
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.transparent,
          width: 1.5,
        ),
        gradient: t == null
            ? null
            : RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 0.9,
                colors: [t.color.withValues(alpha: 0.38), _card],
              ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 7,
            child: Text(
              side,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 550),
            switchInCurve: Curves.elasticOut,
            transitionBuilder: (child, a) => ScaleTransition(
              scale: Tween(begin: 0.4, end: 1.0).animate(a),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: t == null
                ? Text(
                    '?',
                    key: const ValueKey('q'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.18),
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : Column(
                    key: ValueKey(teamKey),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      _Crest(team: t, size: 56),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          t.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Takım logosu; yoksa takım renginde baş harfler.
class _Crest extends StatelessWidget {
  const _Crest({required this.team, required this.size});
  final _DrawTeam team;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (team.logo.isNotEmpty) {
      return WebSafeImage(
        url: team.logo,
        width: size,
        height: size,
        fit: BoxFit.contain,
        fallbackIconSize: size * 0.5,
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: team.color,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        team.initials,
        style: TextStyle(
          color: team.color.computeLuminance() > 0.5
              ? const Color(0xFF1F2937)
              : Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.32,
        ),
      ),
    );
  }
}

/// Açıklanan eşleşmeler, haftalara göre.
class _WeekList extends StatelessWidget {
  const _WeekList({
    required this.state,
    required this.team,
    required this.newestFirst,
    this.highlightLast = false,
  });

  final LiveDrawState state;
  final _DrawTeam Function(String id) team;
  final bool newestFirst;
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    final byWeek = <int, List<LiveDrawPair>>{};
    for (final p in state.revealed) {
      byWeek.putIfAbsent(p.week, () => []).add(p);
    }
    final weeks = byWeek.keys.toList()..sort();
    final ordered = newestFirst ? weeks.reversed.toList() : weeks;
    final last = state.revealed.isEmpty ? null : state.revealed.last;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      children: [
        for (final w in ordered)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${state.startWeek + w}. HAFTA',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                for (final p
                    in (newestFirst ? byWeek[w]!.reversed : byWeek[w]!))
                  _MatchRow(
                    home: team(p.home),
                    away: team(p.away ?? ''),
                    fresh: highlightLast && p == last,
                  ),
                if (state.byes[w] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 2),
                    child: Text(
                      'Bay: ${team(state.byes[w]!).name}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _muted, fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.home,
    required this.away,
    required this.fresh,
  });

  final _DrawTeam home;
  final _DrawTeam away;
  final bool fresh;

  Widget _dot(Color c) => Container(
    width: 9,
    height: 9,
    margin: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
  );

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      decoration: BoxDecoration(
        color: fresh ? _live.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    home.name,
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
                _dot(home.color),
              ],
            ),
          ),
          const SizedBox(
            width: 14,
            child: Text(
              '-',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                _dot(away.color),
                Flexible(
                  child: Text(
                    away.name,
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _CountdownBoxes extends StatelessWidget {
  const _CountdownBoxes({required this.left});
  final Duration left;

  @override
  Widget build(BuildContext context) {
    final l = left.isNegative ? Duration.zero : left;
    final parts = <(String, String)>[
      if (l.inDays > 0) (_two(l.inDays), 'gün'),
      (_two(l.inHours % 24), 'saat'),
      (_two(l.inMinutes % 60), 'dakika'),
      (_two(l.inSeconds % 60), 'saniye'),
    ];
    return Row(
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: _card2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    parts[i].$1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    parts[i].$2,
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Kartın üst görseli: gece mavisi zemin, iki renkli ışık ve kura kâsesi.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.badge, this.height = 150, this.leagueId});
  final Widget badge;
  final double height;

  /// Turnuvanın logosu ortada; logo yoksa kura kâsesi.
  final String? leagueId;

  @override
  Widget build(BuildContext context) {
    final logoSize = height * 0.5;
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1F3A), Color(0xFF070B18)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GlowPainter())),
          Center(
            child: leagueId == null
                ? _Bowl(size: height * 0.46)
                : FutureBuilder<String>(
                    future: _leagueLogo(leagueId!),
                    builder: (context, snap) {
                      final url = snap.data ?? '';
                      if (url.isEmpty) {
                        // Okunurken boş; logo yoksa kâse.
                        return snap.connectionState == ConnectionState.done
                            ? _Bowl(size: height * 0.46)
                            : SizedBox(width: logoSize, height: logoSize);
                      }
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WebSafeImage(
                            url: url,
                            width: logoSize,
                            height: logoSize,
                            fit: BoxFit.contain,
                            fallbackIconSize: logoSize * 0.4,
                          ),
                          SizedBox(width: height * 0.08),
                          _Bowl(size: height * 0.32),
                        ],
                      );
                    },
                  ),
          ),
          Positioned(left: 12, top: 12, child: badge),
        ],
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    void glow(Offset c, Color color) {
      final r = size.width * 0.32;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(
      Offset(size.width * 0.25, size.height * 0.6),
      _accent.withValues(alpha: 0.35),
    );
    glow(
      Offset(size.width * 0.75, size.height * 0.6),
      _live.withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => false;
}

/// Kura kâsesi: içinde iki top.
class _Bowl extends StatelessWidget {
  const _Bowl({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final ball = size * 0.26;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white70, width: 3),
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [
            Colors.white.withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: size * 0.2,
            top: size * 0.42,
            child: _ball(ball, const Color(0xFF22C55E)),
          ),
          Positioned(
            right: size * 0.2,
            top: size * 0.34,
            child: _ball(ball, const Color(0xFFF8FAFC)),
          ),
        ],
      ),
    );
  }

  Widget _ball(double s, Color c) => Container(
    width: s,
    height: s,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );
}

/// Yanıp sönen kırmızı CANLI rozeti.
class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key});

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _live,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 1.0, end: 0.2).animate(_c),
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'CANLI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoonBadge extends StatelessWidget {
  const _SoonBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: _gold,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneBadge extends StatelessWidget {
  const _DoneBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _accent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'SONUÇLAR',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Haberler akışındaki canlı kura kartı: başlamadan geri sayım, çekim
/// sırasında CANLI ve ilerleme, sonra "Kura sonuçları". Dokununca kura
/// ekranı açılır.
class LiveDrawNewsCard extends StatefulWidget {
  const LiveDrawNewsCard({
    super.key,
    required this.drawId,
    required this.content,
  });

  final String drawId;

  /// Haber metni (ilk satır başlık, kalanı açıklama).
  final String content;

  @override
  State<LiveDrawNewsCard> createState() => _LiveDrawNewsCardState();
}

class _LiveDrawNewsCardState extends State<LiveDrawNewsCard> {
  /// Son bilinen durumlar: kart yeniden kurulunca (sekme, yenileme) eski
  /// "YAKINDA" görünümü bir an bile çıkmasın.
  static final _known = <String, LiveDrawState>{};

  LiveDrawState? _s;
  Timer? _tick;
  int _sinceFetch = 0;

  /// Durum henüz alınamadı (ağ hatası): kart haber metniyle gösterilir.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _s = _known[widget.drawId];
    _fetch();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _sinceFetch++;
      final s = _s;
      // Canlıyken 5 sn'de bir, başlama/bitiş anı gelince hemen yenilenir.
      final due =
          s == null ||
          (s.live && _sinceFetch >= 5) ||
          (s.notStarted && !s.serverNow.isBefore(s.startAt)) ||
          (s.live && !s.serverNow.isBefore(s.endAt));
      if (due && !(s?.done ?? false) && !(s?.cancelled ?? false)) _fetch();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    _sinceFetch = 0;
    try {
      final s = await LiveDrawService.instance.fetch(widget.drawId);
      if (s != null) _known[widget.drawId] = s;
      if (mounted) {
        setState(() {
          if (s != null) _s = s;
          _failed = s == null;
        });
      }
    } catch (_) {
      if (mounted && _s == null) setState(() => _failed = true);
    }
  }

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'LiveDrawScreen'),
        builder: (_) => LiveDrawScreen(drawId: widget.drawId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    // Durum gelmeden yazı yok (yanlış "YAKINDA" görünmesin): boş çerçeve.
    if (s == null && !_failed) {
      return Container(
        height: 290,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
      );
    }
    final lines = widget.content.trim().split('\n');
    final title = lines.first.trim();
    final body = lines.skip(1).join('\n').trim();
    final Widget badge;
    String headline = title;
    String sub = body;
    String cta = 'İZLE';
    var ctaFilled = true;
    if (s == null || s.notStarted) {
      badge = _SoonBadge(text: s == null ? 'YAKINDA' : _dayLabel(s.startAt));
      cta = 'KURA SAYFASINI AÇ';
      ctaFilled = false;
    } else if (s.done) {
      badge = const _DoneBadge();
      headline = 'Kura sonuçları';
      sub = '${s.title} · Fikstür yayında';
      cta = 'SONUÇLARI GÖR';
      ctaFilled = false;
    } else {
      badge = const LiveBadge();
      final w =
          (s.current ?? (s.revealed.isEmpty ? null : s.revealed.last))?.week;
      if (w != null) headline = '$title · ${s.startWeek + w}. Hafta';
      sub = '${s.revealed.length} / ${s.total} maç çekildi';
    }

    final live = s != null && s.live;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: live
            ? [
                BoxShadow(
                  color: _live.withValues(alpha: 0.45),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Material(
        color: _card,
        clipBehavior: Clip.antiAlias,
        // Çekim sürerken kırmızı kenarlıkla öne çıkar.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: live ? _live : Colors.white.withValues(alpha: 0.08),
            width: live ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: _open,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeroCard(
                badge: badge,
                height: s != null && s.live ? 120 : 140,
                leagueId: s?.leagueId,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      headline,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (s != null && s.notStarted) ...[
                      const SizedBox(height: 10),
                      _CountdownBoxes(left: s.startAt.difference(s.serverNow)),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ctaFilled ? _live : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: ctaFilled
                            ? null
                            : Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                      ),
                      child: Text(
                        cta,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
