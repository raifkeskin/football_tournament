import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/service_locator.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/admin_page.dart';
import '../models/match.dart';
import '../utils/match_clock.dart';
import '../utils/minute_label.dart';
import '../utils/season_match_settings.dart';

/// Canlı maçta olay girişi: alttaki takım butonuyla (GOL / KART / DEĞ.)
/// olay ve takım tek dokunuşta seçilir; sonra her ekranda tek soru gelir
/// (golcü → asist, renk → oyuncu, çıkan → giren). Son seçimde kaydedilir,
/// "Geri al" ile silinebilir. Penaltı, maçın adamı ve VAR ☰ menüsünde kalır.
class QuickEventBar extends StatelessWidget {
  const QuickEventBar({
    super.key,
    required this.match,
    required this.homeName,
    required this.awayName,
  });

  final MatchModel match;
  final String homeName;
  final String awayName;

  @override
  Widget build(BuildContext context) {
    Widget side(String teamId, String name) {
      Widget button(
        String label,
        _Kind kind, {
        IconData? icon,
        bool primary = false,
      }) => SizedBox(
        height: primary ? 48 : 40,
        child: Material(
          color: primary ? kAdminAccent : const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: primary
                ? BorderSide.none
                : BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _open(context, teamId, kind),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: primary ? 20 : 17,
                    color: primary ? const Color(0xFF04130D) : Colors.white,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: primary ? const Color(0xFF04130D) : Colors.white,
                    fontSize: primary ? 16 : 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            shortTeamName(name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          button(
            'GOL',
            _Kind.goal,
            icon: Icons.sports_soccer_rounded,
            primary: true,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: button('KART', _Kind.card)),
              const SizedBox(width: 6),
              Expanded(
                child: button('DEĞ.', _Kind.sub, icon: Icons.swap_vert_rounded),
              ),
            ],
          ),
        ],
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF111A2E),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: side(match.homeTeamId, homeName)),
            // İki takımın butonları arasında ince ayraç.
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: Colors.white.withValues(alpha: 0.12),
            ),
            Expanded(child: side(match.awayTeamId, awayName)),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String teamId, _Kind kind) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showModalBottomSheet<MatchEvent>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickEventSheet(
        match: match,
        teamId: teamId,
        teamName: teamId == match.homeTeamId ? homeName : awayName,
        rivalName: teamId == match.homeTeamId ? awayName : homeName,
        kind: kind,
      ),
    );
    if (saved == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text('Kaydedildi: ${_describe(saved)}'),
          action: SnackBarAction(
            label: 'GERİ AL',
            onPressed: () => _undo(messenger, saved),
          ),
        ),
      );
  }

  Future<void> _undo(ScaffoldMessengerState messenger, MatchEvent e) async {
    try {
      // Az önce eklenen olay: aynı maç, oyuncu ve türdeki en yeni kayıt.
      var q = Supabase.instance.client
          .from('match_events')
          .select('id')
          .eq('match_id', e.matchId)
          .eq('event_type', e.eventType);
      if (e.playerId != null) q = q.eq('player_id', e.playerId!);
      final rows = await q.order('created_at', ascending: false).limit(1);
      if (rows.isEmpty) return;
      await ServiceLocator.matchService.deleteMatchEvent(
        rows.first['id'].toString(),
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Olay geri alındı.')),
      );
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('Geri alınamadı: $err')));
    }
  }

  static String _describe(MatchEvent e) {
    final min = e.minute == null
        ? ''
        : '${minuteLabel(e.minute, e.addedMinute)} ';
    return switch (e.eventType) {
      'goal' =>
        '$min${e.isOwnGoal ? 'Kendi kalesine' : 'Gol'} · ${e.eventName}',
      'yellow_card' => '${min}Sarı kart · ${e.eventName}',
      'red_card' => '${min}Kırmızı kart · ${e.eventName}',
      'substitution' => '${min}Değişiklik · ${e.eventName} çıktı',
      _ => '$min${e.eventName}',
    };
  }
}

enum _Kind { goal, card, sub }

/// Seçilebilir oyuncu: kadrodaki id, ad ve forma numarası.
class _Pick {
  const _Pick(this.id, this.name, this.number);
  final String id;
  final String name;
  final String number;
}

/// Maçtaki bir takımın sahadaki ve kenardaki oyuncuları (olaylara göre).
class _Squad {
  const _Squad(this.onPitch, this.bench);
  final List<_Pick> onPitch;
  final List<_Pick> bench;
}

class _QuickEventSheet extends StatefulWidget {
  const _QuickEventSheet({
    required this.match,
    required this.teamId,
    required this.teamName,
    required this.rivalName,
    required this.kind,
  });

  final MatchModel match;
  final String teamId;
  final String teamName;
  final String rivalName;
  final _Kind kind;

  @override
  State<_QuickEventSheet> createState() => _QuickEventSheetState();
}

class _QuickEventSheetState extends State<_QuickEventSheet> {
  late final Future<Map<String, _Squad>> _squads = _loadSquads();

  /// Kart rengi: 'yellow_card' / 'red_card'.
  String? _card;
  _Pick? _player;

  /// Gol türü: normal, 'pen' (penaltı golü), 'miss' (penaltı kaçtı) ya da
  /// 'own' (rakip kendi kalesine; oyuncu rakip takımdan seçilir).
  String _goalMode = 'normal';
  bool get _ownGoal => _goalMode == 'own';
  bool _saving = false;

  late final bool _tracksMinutes =
      SeasonMatchSettings.cached(widget.match.seasonId)?.tracksGoalMinutes ??
      true;
  late int _minute;
  int? _added;

  MatchModel get m => widget.match;
  String get _rivalId =>
      widget.teamId == m.homeTeamId ? m.awayTeamId : m.homeTeamId;

  @override
  void initState() {
    super.initState();
    final live = MatchClock.liveMinuteParts(m);
    final period = MatchClock.periodOf(m.seasonId);
    if (live != null) {
      _minute = live.minute;
      _added = live.added;
    } else {
      // Devre arası: ilk yarının sonu.
      _minute = m.status == MatchStatus.halftime ? period : 1;
    }
  }

  /// İki takımın sahadakileri: ilk 11 − çıkanlar − kırmızı kart + girenler;
  /// kenardakiler: henüz oyuna girmemiş yedekler.
  Future<Map<String, _Squad>> _loadSquads() async {
    final client = Supabase.instance.client;
    final teamIds = [m.homeTeamId, m.awayTeamId];
    final results = await Future.wait([
      client
          .from('match_events')
          .select('event_type, team_id, player_id, sub_in_player_id')
          .eq('match_id', m.id),
      client
          .from('match_rosters')
          .select(
            'team_id, player_id, is_starting, jersey_number, '
            'players(name, surname)',
          )
          .eq('match_id', m.id),
      client
          .from('season_team_players')
          .select('player_id, jersey_number')
          .eq('season_id', m.seasonId)
          .inFilter('team_id', teamIds),
    ]);
    final events = results[0];
    final rosters = results[1];
    final seasonNo = {
      for (final r in results[2])
        r['player_id'].toString(): (r['jersey_number'] ?? '').toString(),
    };
    final result = <String, _Squad>{};
    for (final teamId in teamIds) {
      final out = <String>{};
      final inn = <String>{};
      final yellows = <String, int>{};
      for (final e in events) {
        if (e['team_id']?.toString() != teamId) continue;
        final pid = e['player_id']?.toString() ?? '';
        switch (e['event_type']) {
          case 'substitution':
            out.add(pid);
            final i = e['sub_in_player_id']?.toString() ?? '';
            if (i.isNotEmpty) inn.add(i);
          case 'red_card':
            out.add(pid);
          case 'yellow_card':
            yellows[pid] = (yellows[pid] ?? 0) + 1;
            if (yellows[pid]! >= 2) out.add(pid);
        }
      }
      _Pick pick(Map<String, dynamic> r) {
        final id = r['player_id'].toString();
        final p = r['players'] as Map<String, dynamic>?;
        final name = '${p?['name'] ?? ''} ${p?['surname'] ?? ''}'.trim();
        final no = (r['jersey_number'] ?? seasonNo[id] ?? '').toString();
        return _Pick(id, name.isEmpty ? '-' : name, no.trim());
      }

      int byNumber(_Pick a, _Pick b) {
        final c = (int.tryParse(a.number) ?? 999).compareTo(
          int.tryParse(b.number) ?? 999,
        );
        return c != 0 ? c : a.name.compareTo(b.name);
      }

      final onPitch = <_Pick>[];
      final bench = <_Pick>[];
      for (final r in rosters) {
        if (r['team_id']?.toString() != teamId) continue;
        final id = r['player_id'].toString();
        if (out.contains(id)) continue;
        if (r['is_starting'] == true || inn.contains(id)) {
          onPitch.add(pick(r));
        } else {
          bench.add(pick(r));
        }
      }
      result[teamId] = _Squad(onPitch..sort(byNumber), bench..sort(byNumber));
    }
    return result;
  }

  /// Adımlar: 3 parça (takım butonu + iki soru).
  int get _step => switch (widget.kind) {
    _Kind.card => 1 + (_card != null ? 1 : 0),
    _ => 1 + (_player != null ? 1 : 0),
  };

  String get _title {
    final team = shortTeamName(widget.teamName);
    switch (widget.kind) {
      case _Kind.goal:
        if (_player == null) {
          return switch (_goalMode) {
            'own' =>
              '${shortTeamName(widget.rivalName)} · Kendi kalesine atan?',
            'pen' => '$team · Penaltıyı kim attı?',
            'miss' => '$team · Penaltıyı kim kaçırdı?',
            _ => '$team · Golü kim attı?',
          };
        }
        return 'Asisti kim yaptı?';
      case _Kind.card:
        if (_card == null) return '$team · Kart';
        return '$team · Kime ${_card == 'red_card' ? 'kırmızı' : 'sarı'}?';
      case _Kind.sub:
        return _player == null ? '$team · Kim çıktı?' : 'Yerine kim girdi?';
    }
  }

  void _back() => setState(() {
    if (_player != null) {
      _player = null;
    } else if (_card != null) {
      _card = null;
    } else if (_goalMode != 'normal') {
      _goalMode = 'normal';
    }
  });

  bool get _canGoBack =>
      _player != null || _card != null || _goalMode != 'normal';

  Future<void> _save({_Pick? assist, _Pick? subIn}) async {
    final p = _player;
    if (p == null || _saving) return;
    setState(() => _saving = true);
    final type = switch (widget.kind) {
      _Kind.goal => _goalMode == 'miss' ? 'penalty_missed' : 'goal',
      _Kind.card => _card!,
      _Kind.sub => 'substitution',
    };
    final event = MatchEvent(
      id: '',
      matchId: m.id,
      leagueId: m.leagueId,
      // Kendi kalesine golde olay, oyuncunun (rakip) takımına yazılır.
      teamId: _ownGoal ? _rivalId : widget.teamId,
      eventType: type,
      minute: _tracksMinutes ? _minute : null,
      addedMinute: _tracksMinutes ? _added : null,
      eventName: p.name,
      playerId: p.id,
      assistPlayerId: assist?.id,
      subInPlayerId: subIn?.id,
      isOwnGoal: _ownGoal,
      isPenalty: _goalMode == 'pen',
    );
    try {
      await ServiceLocator.matchService.addMatchEvent(event);
      if (mounted) Navigator.pop(context, event);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  void _onPick(_Pick p) {
    switch (widget.kind) {
      case _Kind.card:
        _player = p;
        _save();
      case _Kind.goal:
        // Penaltı ve kendi kalesine golde asist sorulmaz.
        if (_goalMode != 'normal') {
          _player = p;
          _save();
        } else if (_player == null) {
          setState(() => _player = p);
        } else {
          _save(assist: p);
        }
      case _Kind.sub:
        if (_player == null) {
          setState(() => _player = p);
        } else {
          _save(subIn: p);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: height * 0.88),
      decoration: const BoxDecoration(
        color: Color(0xFF111A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            _progress(),
            _crumbs(),
            if (_tracksMinutes) _clock(),
            Flexible(
              child: FutureBuilder<Map<String, _Squad>>(
                future: _squads,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Kadro yüklenemedi: ${snap.error}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                    child: _body(snap.data!),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
    child: Row(
      children: [
        if (_canGoBack)
          _iconButton(Icons.arrow_back_rounded, 'Geri', _back)
        else
          const SizedBox(width: 40),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _title,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _iconButton(Icons.close_rounded, 'Kapat', () => Navigator.pop(context)),
      ],
    ),
  );

  Widget _iconButton(IconData icon, String tip, VoidCallback onTap) => SizedBox(
    width: 40,
    height: 40,
    child: Material(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: IconButton(
        tooltip: tip,
        onPressed: _saving ? null : onTap,
        icon: Icon(icon, size: 20, color: Colors.white),
      ),
    ),
  );

  Widget _progress() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
    child: Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i < _step
                    ? kAdminAccent
                    : Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _crumbs() {
    final kind = switch (widget.kind) {
      _Kind.goal => switch (_goalMode) {
        'own' => 'Kendi kalesine',
        'pen' => 'Penaltı golü',
        'miss' => 'Penaltı kaçtı',
        _ => 'Gol',
      },
      _Kind.card =>
        _card == null
            ? 'Kart'
            : _card == 'red_card'
            ? 'Kırmızı'
            : 'Sarı',
      _Kind.sub => 'Değişiklik',
    };
    final items = [
      '${shortTeamName(widget.teamName)} · $kind',
      if (_player != null)
        '${widget.kind == _Kind.sub ? '↓ ' : ''}${_player!.name}',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Text(
                t,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Dakika saatten gelir; −1 / +1 ile düzeltilir (uzatmada uzatma değişir).
  Widget _clock() {
    void shift(int d) => setState(() {
      if (_added != null) {
        _added = (_added! + d).clamp(1, 30);
      } else {
        _minute = (_minute + d).clamp(1, 200);
      }
    });
    Widget small(String label, int d) => SizedBox(
      height: 30,
      child: OutlinedButton(
        onPressed: _saving ? null : () => shift(d),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Dakika',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(width: 8),
          Text(
            minuteLabel(_minute, _added),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          small('−1', -1),
          const SizedBox(width: 6),
          small('+1', 1),
        ],
      ),
    );
  }

  Widget _body(Map<String, _Squad> squads) {
    final own = squads[widget.teamId]!;
    final rival = squads[_rivalId]!;
    switch (widget.kind) {
      case _Kind.card:
        if (_card == null) {
          return Row(
            children: [
              Expanded(
                child: _bigChoice(
                  'Sarı',
                  const Color(0xFFFACC15),
                  () => setState(() => _card = 'yellow_card'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _bigChoice(
                  'Kırmızı',
                  const Color(0xFFEF4444),
                  () => setState(() => _card = 'red_card'),
                ),
              ),
            ],
          );
        }
        return _grid(own.onPitch);
      case _Kind.goal:
        if (_player == null) {
          Widget mode(String key, String label, IconData icon) => ChoiceChip(
            avatar: Icon(icon, size: 16),
            label: Text(label),
            selected: _goalMode == key,
            onSelected: _saving
                ? null
                : (on) => setState(() => _goalMode = on ? key : 'normal'),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  mode('pen', 'Penaltı golü', Icons.adjust_rounded),
                  mode('miss', 'Penaltı kaçtı', Icons.close_rounded),
                  mode(
                    'own',
                    'Rakip kendi kalesine',
                    Icons.u_turn_left_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _grid(_ownGoal ? rival.onPitch : own.onPitch),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: _saving ? null : () => _save(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Asist yok · Kaydet',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _grid([
              for (final p in own.onPitch)
                if (p.id != _player!.id) p,
            ]),
          ],
        );
      case _Kind.sub:
        return _grid(
          _player == null ? own.onPitch : own.bench,
          empty: _player == null ? 'Sahada oyuncu yok.' : 'Girecek yedek yok.',
        );
    }
  }

  Widget _bigChoice(String label, Color color, VoidCallback onTap) => SizedBox(
    height: 90,
    child: Material(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _saving ? null : onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _grid(List<_Pick> list, {String empty = 'Sahada oyuncu yok.'}) {
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          empty,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.25,
      children: [
        for (final p in list)
          Material(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _saving ? null : () => _onPick(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p.number.isEmpty ? '-' : p.number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
