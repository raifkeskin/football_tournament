import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/service_locator.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/admin_page.dart';
import '../models/match.dart';
import '../utils/match_clock.dart';
import '../utils/minute_label.dart';
import '../utils/season_match_settings.dart';
import 'minute_input_dialog.dart';

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
    this.onMoment,
  });

  final MatchModel match;
  final String homeName;
  final String awayName;

  /// Verilirse KART / DEĞ. yanında OLAY: puana etki eden an (takıma göre).
  final void Function(String teamId)? onMoment;

  @override
  Widget build(BuildContext context) {
    Widget side(String teamId, String name) {
      Widget button(
        String label,
        _Kind? kind, {
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
            onTap: () => kind == null
                ? onMoment?.call(teamId)
                : _open(context, teamId, kind),
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
                child: button(
                  'DEĞ.',
                  _Kind.sub,
                  icon: onMoment == null ? Icons.swap_vert_rounded : null,
                ),
              ),
              if (onMoment != null) ...[
                const SizedBox(width: 6),
                Expanded(child: button('OLAY', null)),
              ],
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
    _showSaved(messenger, saved);
  }
}

/// "Kaydedildi" bildirimi; GERİ AL ile olay silinir.
void _showSaved(ScaffoldMessengerState messenger, MatchEvent saved) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        // Düğmeli SnackBar varsayılan olarak kalıcı; kendiliğinden kapansın.
        persist: false,
        duration: const Duration(seconds: 3),
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
    messenger.showSnackBar(const SnackBar(content: Text('Olay geri alındı.')));
  } catch (err) {
    messenger.showSnackBar(SnackBar(content: Text('Geri alınamadı: $err')));
  }
}

String _describe(MatchEvent e) {
  final min = e.minute == null
      ? ''
      : '${minuteLabel(e.minute, e.addedMinute)} ';
  return switch (e.eventType) {
    'goal' => '$min${e.isOwnGoal ? 'Kendi kalesine' : 'Gol'} · ${e.eventName}',
    'yellow_card' => '${min}Sarı kart · ${e.eventName}',
    'red_card' => '${min}Kırmızı kart · ${e.eventName}',
    'substitution' => '${min}Değişiklik · ${e.eventName} çıktı',
    _ => '$min${e.eventName}',
  };
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
  const _Squad(this.onPitch, this.bench, [this.locked = const []]);
  final List<_Pick> onPitch;
  final List<_Pick> bench;

  /// Kenarda ama oyuna giremeyenler: oyundan çıkanlar (sezonda tekrar giriş
  /// kapalıysa). Değişiklik listesinde soluk ve seçilemez görünür.
  final List<_Pick> locked;
}

/// Olay girişinin tek kuralı (Detay alt düğmeleri ve dizilişte oyuncuya
/// dokunma aynı listeyi kullanır; veritabanındaki match_on_pitch_at ile
/// aynı). Sahadakiler: ilk 11, sonra olaylar sırayla (değişiklikte çıkan
/// iner giren çıkar; kırmızı ya da ikinci sarı gören iner). Kenardakiler:
/// sahada olmayan, atılmamış oyuncular; çıkmış olan, sezonda tekrar giriş
/// açık değilse kilitli.
Future<Map<String, _Squad>> _loadSquads(MatchModel m) async {
  final client = Supabase.instance.client;
  final teamIds = [m.homeTeamId, m.awayTeamId];
  final results = await Future.wait([
    client
        .from('match_events')
        .select('event_type, team_id, player_id, sub_in_player_id')
        .eq('match_id', m.id)
        .order('minute', nullsFirst: false)
        .order('created_at'),
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
  final rolling = (await SeasonMatchSettings.of(m.seasonId)).rollingSubs;
  final events = results[0];
  final rosters = results[1];
  final seasonNo = {
    for (final r in results[2])
      r['player_id'].toString(): (r['jersey_number'] ?? '').toString(),
  };
  final result = <String, _Squad>{};
  for (final teamId in teamIds) {
    final on = <String>{
      for (final r in rosters)
        if (r['team_id']?.toString() == teamId && r['is_starting'] == true)
          r['player_id'].toString(),
    };
    final sentOff = <String>{};
    final subbedOut = <String>{};
    final yellows = <String, int>{};
    for (final e in events) {
      if (e['team_id']?.toString() != teamId) continue;
      final pid = e['player_id']?.toString() ?? '';
      switch (e['event_type']) {
        case 'substitution':
          on.remove(pid);
          subbedOut.add(pid);
          final i = e['sub_in_player_id']?.toString() ?? '';
          if (i.isNotEmpty) on.add(i);
        case 'red_card':
          on.remove(pid);
          sentOff.add(pid);
        case 'yellow_card':
          yellows[pid] = (yellows[pid] ?? 0) + 1;
          if (yellows[pid]! >= 2) {
            on.remove(pid);
            sentOff.add(pid);
          }
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
    final locked = <_Pick>[];
    for (final r in rosters) {
      if (r['team_id']?.toString() != teamId) continue;
      final id = r['player_id'].toString();
      if (on.contains(id)) {
        onPitch.add(pick(r));
      } else if (sentOff.contains(id)) {
        continue;
      } else if (subbedOut.contains(id) && !rolling) {
        locked.add(pick(r));
      } else {
        bench.add(pick(r));
      }
    }
    result[teamId] = _Squad(
      onPitch..sort(byNumber),
      bench..sort(byNumber),
      locked..sort(byNumber),
    );
  }
  return result;
}

class _QuickEventSheet extends StatefulWidget {
  const _QuickEventSheet({
    required this.match,
    required this.teamId,
    required this.teamName,
    required this.rivalName,
    required this.kind,
    this.preset,
  });

  final MatchModel match;
  final String teamId;
  final String teamName;
  final String rivalName;
  final _Kind kind;

  /// Dizilişte dokunulan oyuncu: ilk soru atlanır (ör. çıkan belli,
  /// yalnız giren sorulur).
  final _Pick? preset;

  @override
  State<_QuickEventSheet> createState() => _QuickEventSheetState();
}

class _QuickEventSheetState extends State<_QuickEventSheet> {
  late final Future<Map<String, _Squad>> _squads = _loadSquads(widget.match);

  /// Kart rengi: 'yellow_card' / 'red_card'.
  String? _card;
  late _Pick? _player = widget.preset;

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
  Future<void> _typeMinute() async {
    final v = await showMinuteInputDialog(
      context,
      title: 'Dakika',
      minute: _minute,
      added: _added,
    );
    if (v == null || !mounted) return;
    setState(() {
      _minute = v.minute;
      _added = v.added;
    });
  }

  /// Dakika: ±1 ya da dokununca elle yazılır (canlıda sayaçtan gelir).
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
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _saving ? null : _typeMinute,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kAdminAccent.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    minuteLabel(_minute, _added),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_rounded, size: 14, color: kAdminAccent),
                ],
              ),
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
          locked: _player == null ? const [] : own.locked,
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

  Widget _grid(
    List<_Pick> list, {
    List<_Pick> locked = const [],
    String empty = 'Sahada oyuncu yok.',
  }) {
    if (list.isEmpty && locked.isEmpty) {
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
        for (final p in [...list, ...locked])
          Opacity(
            opacity: locked.contains(p) ? 0.35 : 1,
            child: Material(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _saving || locked.contains(p) ? null : () => _onPick(p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
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
          ),
      ],
    );
  }
}

/// Canlı maçta dizilişteki oyuncuya dokununca: olay seçilir, gol ve kart
/// hemen kaydedilir (oyuncu + olay = iki dokunuş). Değişiklikte yalnız
/// giren oyuncu sorulur. Dakika maç saatinden alınır.
Future<void> showPlayerQuickEvent(
  BuildContext context, {
  required MatchModel match,
  required String teamId,
  required String playerId,
  required String playerName,
  required String number,
  required String homeName,
  required String awayName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final live = MatchClock.liveMinuteParts(match);
  final minute =
      live?.minute ??
      (match.status == MatchStatus.halftime
          ? MatchClock.periodOf(match.seasonId)
          : 1);
  final added = live?.added;
  final tracks =
      SeasonMatchSettings.cached(match.seasonId)?.tracksGoalMinutes ?? true;
  // Detaydaki alt düğmelerle aynı kural: yalnız o an sahada olan oyuncuya
  // gol, kart ve değişiklik girilir (kırmızı kart / iki sarı / oyundan
  // çıkan oyuncuya yalnız "Olay ekle" ile puan olayı).
  final Map<String, _Squad> squads;
  try {
    squads = await _loadSquads(match);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Kadro yüklenemedi: $e')));
    return;
  }
  if (!context.mounted) return;
  final onPitch = squads[teamId]?.onPitch.any((p) => p.id == playerId) ?? false;
  if (!onPitch) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$playerName şu an oyunda değil (kırmızı kart, iki sarı ya da '
            'oyundan çıktı). Bu oyuncuya yalnız "Olay ekle" ile puan olayı '
            'girilebilir.',
          ),
        ),
      );
    return;
  }
  final kind = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _PlayerEventChooser(
      name: playerName,
      number: number,
      minute: tracks ? minuteLabel(minute, added) : null,
    ),
  );
  if (kind == null || !context.mounted) return;
  if (kind == 'substitution' || kind == 'goal') {
    // Golde asist, değişiklikte giren oyuncu Detaydaki aynı ekranda sorulur.
    final saved = await showModalBottomSheet<MatchEvent>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickEventSheet(
        match: match,
        teamId: teamId,
        teamName: teamId == match.homeTeamId ? homeName : awayName,
        rivalName: teamId == match.homeTeamId ? awayName : homeName,
        kind: kind == 'goal' ? _Kind.goal : _Kind.sub,
        preset: _Pick(playerId, playerName, number),
      ),
    );
    if (saved != null) _showSaved(messenger, saved);
    return;
  }
  final event = MatchEvent(
    id: '',
    matchId: match.id,
    leagueId: match.leagueId,
    teamId: teamId,
    eventType: kind,
    minute: tracks ? minute : null,
    addedMinute: tracks ? added : null,
    eventName: playerName,
    playerId: playerId,
  );
  try {
    await ServiceLocator.matchService.addMatchEvent(event);
    _showSaved(messenger, event);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
  }
}

class _PlayerEventChooser extends StatelessWidget {
  const _PlayerEventChooser({
    required this.name,
    required this.number,
    this.minute,
  });

  final String name;
  final String number;
  final String? minute;

  @override
  Widget build(BuildContext context) {
    Widget choice(String label, String kind, Widget icon, Color color) =>
        Expanded(
          child: Material(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: color.withValues(alpha: 0.5)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.pop(context, kind),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    Widget card(Color c) => Container(
      width: 16,
      height: 22,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                [if (number.isNotEmpty) number, name, ?minute].join(' · '),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Hangi olay?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  choice(
                    'GOL',
                    'goal',
                    const Icon(
                      Icons.sports_soccer_rounded,
                      color: kAdminAccent,
                      size: 24,
                    ),
                    kAdminAccent,
                  ),
                  const SizedBox(width: 8),
                  choice(
                    'SARI KART',
                    'yellow_card',
                    card(const Color(0xFFFACC15)),
                    const Color(0xFFFACC15),
                  ),
                  const SizedBox(width: 8),
                  choice(
                    'KIRMIZI KART',
                    'red_card',
                    card(const Color(0xFFEF4444)),
                    const Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 8),
                  choice(
                    'OYUNDAN ÇIKTI',
                    'substitution',
                    const Icon(
                      Icons.swap_vert_rounded,
                      color: Color(0xFF60A5FA),
                      size: 24,
                    ),
                    const Color(0xFF60A5FA),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
