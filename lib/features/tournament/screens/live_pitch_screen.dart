part of 'formation_tab.dart';

/// Tam ekran yatay saha: canlı maçta gol, kart, değişiklik ve puan olayı
/// hızlı girişi (web Yönetim Masası akışı). Oyuncuya dokun → büyük
/// düğmeler; gol → asisti yapan takım arkadaşına dokun; değişiklik →
/// yedeğe dokun ya da yedeği sahadaki oyuncunun üstüne sürükle. Her
/// kayıttan sonra altta GERİ AL. Kurallar veritabanında (çıkan/atılan
/// oyuncuya olay girilmez; sezonda tekrar giriş kapalıysa çıkan oyuncu
/// yedeklerde kilitli).
Future<void> openLivePitch(
  BuildContext context, {
  required MatchModel match,
  required String homeName,
  required String awayName,
  Color? homeColor,
  Color? awayColor,
  Future<void> Function(BuildContext context, String teamId)? onMoments,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _LivePitchScreen(
      match: match,
      homeName: homeName,
      awayName: awayName,
      homeColor: homeColor ?? _accent,
      awayColor: awayColor ?? const Color(0xFF3B82F6),
      onMoments: onMoments,
    ),
  ),
);

class _LivePitchScreen extends StatefulWidget {
  const _LivePitchScreen({
    required this.match,
    required this.homeName,
    required this.awayName,
    required this.homeColor,
    required this.awayColor,
    this.onMoments,
  });

  final MatchModel match;
  final String homeName;
  final String awayName;
  final Color homeColor;
  final Color awayColor;
  final Future<void> Function(BuildContext context, String teamId)? onMoments;

  @override
  State<_LivePitchScreen> createState() => _LivePitchScreenState();
}

/// Ekrandaki seçim adımı.
enum _LiveStep { menu, assist, subIn, subOut }

class _LivePitchScreenState extends State<_LivePitchScreen> {
  late final Stream<MatchModel> _matchStream = ServiceLocator.matchService
      .watchMatch(widget.match.id);
  late final Stream<List<Map<String, dynamic>>> _events = ServiceLocator
      .matchService
      .watchInlineMatchEvents(widget.match.id);
  late MatchModel _m = widget.match;

  /// Akışlar bir kez açılır (her olayda yeniden abone olunmasın).
  late final Map<String, Stream<List<PlayerModel>>> _players = {
    for (final t in [widget.match.homeTeamId, widget.match.awayTeamId])
      t: ServiceLocator.teamService.watchPlayers(
        teamId: t,
        tournamentId: widget.match.seasonId,
        matchId: widget.match.id,
      ),
  };
  late final Map<String, Stream<List<MatchRosterModel>>> _rosters = {
    for (final t in [widget.match.homeTeamId, widget.match.awayTeamId])
      t: ServiceLocator.matchService.watchMatchRosters(widget.match.id, t),
  };
  Timer? _tick;
  bool _rolling = false;
  bool _tracksMinutes = true;

  /// Seçili oyuncu (sahada ya da yedekte) ve adım.
  String? _team;
  String? _player;
  _LiveStep? _step;
  bool _saving = false;

  /// Elle yazılan dakika (yoksa maç saatinden).
  ({int minute, int? added})? _manualMinute;

  /// Son kayıt: GERİ AL için.
  ({String id, String label})? _last;
  Timer? _lastTimer;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _m.status == MatchStatus.live) setState(() {});
    });
    SeasonMatchSettings.of(widget.match.seasonId).then((s) {
      if (mounted) {
        setState(() {
          _rolling = s.rollingSubs;
          _tracksMinutes = s.tracksGoalMinutes;
        });
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _lastTimer?.cancel();
    if (!kIsWeb) {
      // Dikeye döndürüp serbest bırak (iOS yatayda kalmasın).
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]).then((_) => SystemChrome.setPreferredOrientations(const []));
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _clear() => setState(() {
    _team = null;
    _player = null;
    _step = null;
  });

  ({int minute, int? added})? get _autoMinute {
    final live = MatchClock.liveMinuteParts(_m);
    if (live != null) return live;
    if (_m.status == MatchStatus.halftime) {
      return (minute: MatchClock.periodOf(_m.seasonId), added: null);
    }
    return null;
  }

  ({int minute, int? added})? get _minute => _manualMinute ?? _autoMinute;

  Future<void> _editMinute() async {
    final cur = _minute;
    final v = await showMinuteInputDialog(
      context,
      title: 'Olay dakikası',
      minute: cur?.minute,
      added: cur?.added,
    );
    if (v != null && mounted) setState(() => _manualMinute = v);
  }

  Future<void> _save({
    required String type,
    required String teamId,
    required _PitchPlayer player,
    String? assistId,
    String? subInId,
    bool own = false,
    bool pen = false,
    required String label,
  }) async {
    if (_saving) return;
    var minute = _minute;
    if (_tracksMinutes && minute == null) {
      minute = await showMinuteInputDialog(
        context,
        title: 'Olay dakikası',
        hint: 'Maç saati çalışmıyor; dakikayı yazın.',
      );
      if (minute == null || !mounted) return;
      setState(() => _manualMinute = minute);
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ServiceLocator.matchService.addMatchEvent(
        MatchEvent(
          id: '',
          matchId: _m.id,
          leagueId: _m.leagueId,
          teamId: teamId,
          eventType: type,
          minute: _tracksMinutes ? minute?.minute : null,
          addedMinute: _tracksMinutes ? minute?.added : null,
          eventName: player.name,
          playerId: player.id,
          assistPlayerId: assistId,
          subInPlayerId: subInId,
          isOwnGoal: own,
          isPenalty: pen,
        ),
      );
      final row = await Supabase.instance.client
          .from('match_events')
          .select('id')
          .eq('match_id', _m.id)
          .eq('player_id', player.id)
          .eq('event_type', type)
          .order('created_at', ascending: false)
          .limit(1);
      if (!mounted) return;
      _lastTimer?.cancel();
      setState(() {
        _saving = false;
        _team = null;
        _player = null;
        _step = null;
        _last = row.isEmpty
            ? null
            : (id: row.first['id'].toString(), label: label);
      });
      _lastTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _last = null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is PostgrestException ? e.message : 'Kaydedilemedi: $e',
          ),
        ),
      );
    }
  }

  Future<void> _undo() async {
    final last = _last;
    if (last == null) return;
    _lastTimer?.cancel();
    setState(() => _last = null);
    try {
      await ServiceLocator.matchService.deleteMatchEvent(last.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Geri alınamadı: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: StreamBuilder<MatchModel>(
        stream: _matchStream,
        initialData: widget.match,
        builder: (context, ms) {
          _m = ms.data ?? _m;
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _events,
            builder: (context, es) {
              final ins = MatchInsights.build(
                match: _m,
                events: es.data ?? const [],
                moments: const [],
                rules: const RatingRules(enabled: false, values: {}),
                matchMinutes: 90,
              );
              return _side(
                _m.homeTeamId,
                ins,
                (home) => _side(
                  _m.awayTeamId,
                  ins,
                  (away) => LayoutBuilder(
                    builder: (context, c) {
                      final body = _body(ins, home, away);
                      // Web'de ya da yön kilitlenmediyse dikey ekranda
                      // döndürülerek gösterilir.
                      if (c.maxWidth >= c.maxHeight) return body;
                      return RotatedBox(quarterTurns: 1, child: body);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Takımın sahadaki dizilişi (değişiklikler işlenmiş) ve esamesi.
  Widget _side(
    String teamId,
    MatchInsights ins,
    Widget Function(_LiveSide side) builder,
  ) {
    return StreamBuilder<List<PlayerModel>>(
      stream: _players[teamId],
      builder: (context, ps) => StreamBuilder<List<MatchRosterModel>>(
        stream: _rosters[teamId],
        builder: (context, rs) {
          final players = {
            for (final p in ps.data ?? const <PlayerModel>[]) p.id: p,
          };
          final rosters = rs.data ?? const <MatchRosterModel>[];
          final layout = _withSubs(
            _computeLayout(
              rosters.where((r) => r.isStarting).toList(),
              players,
              formation: teamId == _m.homeTeamId
                  ? _m.homeFormation
                  : _m.awayFormation,
            ),
            ins,
            rosters,
            players,
          );
          final onPitch = {
            for (final l in layout?.lines ?? const <List<_PitchPlayer>>[])
              for (final p in l) p.id,
          };
          final bench = <_PitchPlayer>[
            for (final r in rosters)
              if (!onPitch.contains(r.playerId))
                _PitchPlayer(
                  id: r.playerId,
                  name: (players[r.playerId]?.name ?? '').trim().isEmpty
                      ? '-'
                      : players[r.playerId]!.name,
                  number: (r.jerseyNumber ?? players[r.playerId]?.number ?? '')
                      .trim(),
                  line: positionLineOf(
                    players[r.playerId]?.mainPosition,
                    players[r.playerId]?.position,
                  ),
                  wide: false,
                  isCaptain: r.isCaptain,
                  photoUrl: players[r.playerId]?.photoUrl,
                ),
          ]..sort((a, b) => _jersey(a.number).compareTo(_jersey(b.number)));
          return builder(
            _LiveSide(teamId: teamId, layout: layout, bench: bench),
          );
        },
      ),
    );
  }

  bool _sentOff(PlayerMarks k) => k.reds.isNotEmpty || k.yellows.length >= 2;

  /// Yedek oyuna girebilir mi (atılmadı; çıktıysa sezonda tekrar giriş açık).
  bool _canEnter(MatchInsights ins, String id) {
    final k = ins.of(id);
    if (_sentOff(k)) return false;
    return _rolling || !k.subbedOut;
  }

  Widget _body(MatchInsights ins, _LiveSide home, _LiveSide away) {
    return SafeArea(
      child: Column(
        children: [
          _topBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _benchColumn(ins, home, widget.homeColor),
                Expanded(child: _pitchArea(ins, home, away)),
                _benchColumn(ins, away, widget.awayColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    final mn = _minute;
    final live = _m.status == MatchStatus.live;
    String name(String n) => shortTeamName(n);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Kapat',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    name(widget.homeName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_m.homeScore} - ${_m.awayScore}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    name(widget.awayName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_tracksMinutes)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ActionChip(
                onPressed: _editMinute,
                avatar: Icon(
                  live ? Icons.timer_outlined : Icons.edit_outlined,
                  size: 16,
                  color: live ? _accent : Colors.white70,
                ),
                label: Text(
                  mn == null
                      ? 'Dakika'
                      : "${mn.minute}${mn.added == null ? '' : '+${mn.added}'}'",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                side: BorderSide(
                  color: _manualMinute != null ? _accent : Colors.white24,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _benchColumn(MatchInsights ins, _LiveSide side, Color color) {
    final pickingIn =
        _step == _LiveStep.subIn && _team == side.teamId && _player != null;
    final others = _step != null && !pickingIn;
    final ready = [
      for (final p in side.bench)
        if (_canEnter(ins, p.id)) p,
    ];
    final locked = [
      for (final p in side.bench)
        if (!_canEnter(ins, p.id)) p,
    ];
    return Container(
      width: 96,
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: pickingIn
            ? color.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pickingIn ? color : Colors.white.withValues(alpha: 0.08),
          width: pickingIn ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'YEDEKLER',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final p in ready)
                  _benchChip(
                    ins,
                    side.teamId,
                    p,
                    color,
                    enabled: !others || _team == side.teamId,
                    highlight: pickingIn,
                  ),
                for (final p in locked)
                  _benchChip(ins, side.teamId, p, color, enabled: false),
                if (side.bench.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Yedek yok',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _benchChip(
    MatchInsights ins,
    String teamId,
    _PitchPlayer p,
    Color color, {
    required bool enabled,
    bool highlight = false,
  }) {
    final k = ins.of(p.id);
    final chosen = _player == p.id;
    final light = color.computeLuminance() > 0.5;
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      decoration: BoxDecoration(
        color: chosen
            ? color.withValues(alpha: 0.35)
            : highlight
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: chosen ? color : Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              p.number.isEmpty ? '-' : p.number,
              style: TextStyle(
                color: light ? const Color(0xFF111827) : Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              shortPlayerName(p.name),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
          if (k.subbedOut)
            const Icon(
              Icons.arrow_downward_rounded,
              size: 13,
              color: Color(0xFFEF4444),
            )
          else if (_sentOff(k))
            const CardIcon(red: true),
        ],
      ),
    );
    if (!enabled) {
      // Oyundan çıkan (tekrar giriş kapalı) ya da atılan: koyu, seçilemez.
      return Opacity(
        opacity: 0.3,
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Colors.grey,
            BlendMode.saturation,
          ),
          child: chip,
        ),
      );
    }
    final feedback = Material(
      color: Colors.transparent,
      child: SizedBox(width: 86, child: chip),
    );
    return LongPressDraggable<(String, String)>(
      data: (teamId, p.id),
      delay: const Duration(milliseconds: 160),
      feedback: feedback,
      childWhenDragging: Opacity(opacity: 0.35, child: chip),
      onDragStarted: () => setState(() {
        _team = teamId;
        _player = p.id;
        _step = _LiveStep.subOut;
      }),
      onDraggableCanceled: (_, _) {
        if (_step == _LiveStep.subOut) _clear();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tapBench(ins, teamId, p),
        child: chip,
      ),
    );
  }

  void _tapBench(MatchInsights ins, String teamId, _PitchPlayer p) {
    if (_saving) return;
    // Sahadaki oyuncu seçiliyken yedeğe dokunma: değişiklik kaydı.
    if (_step == _LiveStep.subIn && _team == teamId && _player != null) {
      final out = _findOnPitch(teamId, _player!);
      if (out != null) {
        _save(
          type: 'substitution',
          teamId: teamId,
          player: out,
          subInId: p.id,
          label: '${shortPlayerName(p.name)} ↔ ${shortPlayerName(out.name)}',
        );
      }
      return;
    }
    if (_step == _LiveStep.subOut && _player == p.id) return _clear();
    // Önce yedek: çıkacak oyuncu sorulur.
    setState(() {
      _team = teamId;
      _player = p.id;
      _step = _LiveStep.subOut;
    });
  }

  _LiveSide? _sideHome;
  _LiveSide? _sideAway;

  _PitchPlayer? _findOnPitch(String teamId, String id) {
    final s = teamId == _m.homeTeamId ? _sideHome : _sideAway;
    for (final l in s?.layout?.lines ?? const <List<_PitchPlayer>>[]) {
      for (final p in l) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  _PitchPlayer? _findBench(String teamId, String id) {
    final s = teamId == _m.homeTeamId ? _sideHome : _sideAway;
    for (final p in s?.bench ?? const <_PitchPlayer>[]) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _tapPitch(MatchInsights ins, String teamId, _PitchPlayer p) {
    if (_saving) return;
    final step = _step;
    final sel = _player;
    if (step == _LiveStep.assist && sel != null) {
      if (teamId != _team || p.id == sel) return;
      final scorer = _findOnPitch(teamId, sel);
      if (scorer == null) return;
      _save(
        type: 'goal',
        teamId: teamId,
        player: scorer,
        assistId: p.id,
        label:
            'Gol · ${shortPlayerName(scorer.name)} '
            '(asist ${shortPlayerName(p.name)})',
      );
      return;
    }
    if (step == _LiveStep.subOut && sel != null) {
      if (teamId != _team) return;
      final inn = _findBench(teamId, sel);
      if (inn == null) return;
      _save(
        type: 'substitution',
        teamId: teamId,
        player: p,
        subInId: inn.id,
        label: '${shortPlayerName(inn.name)} ↔ ${shortPlayerName(p.name)}',
      );
      return;
    }
    if (sel == p.id) return _clear();
    setState(() {
      _team = teamId;
      _player = p.id;
      _step = _LiveStep.menu;
    });
  }

  Widget _pitchArea(MatchInsights ins, _LiveSide home, _LiveSide away) {
    _sideHome = home;
    _sideAway = away;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth, h = c.maxHeight;
            // Telefonda dar, tablette büyük oyuncu.
            final scale = (h / 420).clamp(0.72, 1.35);
            final tokenW = 78.0 * scale;
            final children = <Widget>[
              Positioned.fill(
                child: RotatedBox(
                  quarterTurns: 1,
                  child: CustomPaint(painter: _FullPitchPainter()),
                ),
              ),
            ];
            Offset? menuAt;
            for (final (side, left) in [(home, true), (away, false)]) {
              final layout = side.layout;
              if (layout == null) continue;
              final lines = layout.lines;
              final n = lines.length - 1;
              final color = left ? widget.homeColor : widget.awayColor;
              for (var li = 0; li < lines.length; li++) {
                for (var i = 0; i < lines[li].length; i++) {
                  final p = lines[li][i];
                  final o = pitchSlot(
                    li: li,
                    i: i,
                    n: lines[li].length,
                    outfieldLines: n,
                  );
                  // Yarım saha (dikey) → yatay: ev sahibi solda, kalesi
                  // solda; deplasman sağda.
                  final x = 0.03 + (1 - o.dy) * 0.45;
                  final pos = left
                      ? Offset(x * w, (1 - o.dx) * h)
                      : Offset((1 - x) * w, o.dx * h);
                  final k = ins.of(p.id);
                  final off = _sentOff(k);
                  final chosen = _player == p.id && _team == side.teamId;
                  if (chosen && _step == _LiveStep.menu) menuAt = pos;
                  final dim = switch (_step) {
                    null => off,
                    _LiveStep.menu => !chosen,
                    _LiveStep.assist => side.teamId != _team || chosen || off,
                    _LiveStep.subOut => side.teamId != _team || off,
                    _LiveStep.subIn => !chosen,
                  };
                  Widget token = _PlayerToken(
                    player: p,
                    color: li == 0 ? const Color(0xFFF59E0B) : color,
                    marks: k,
                    compact: true,
                  );
                  if (chosen) {
                    token = DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white, width: 2),
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      child: token,
                    );
                  }
                  token = AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: dim ? 0.32 : 1,
                    child: token,
                  );
                  final target = DragTarget<(String, String)>(
                    onWillAcceptWithDetails: (d) =>
                        !off &&
                        d.data.$1 == side.teamId &&
                        _canEnter(ins, d.data.$2),
                    onAcceptWithDetails: (d) {
                      final inn = _findBench(side.teamId, d.data.$2);
                      if (inn == null) return;
                      _save(
                        type: 'substitution',
                        teamId: side.teamId,
                        player: p,
                        subInId: inn.id,
                        label:
                            '${shortPlayerName(inn.name)} ↔ '
                            '${shortPlayerName(p.name)}',
                      );
                    },
                    builder: (context, cand, _) => Transform.scale(
                      scale: cand.isNotEmpty ? scale * 1.15 : scale,
                      child: token,
                    ),
                  );
                  children.add(
                    Positioned(
                      left: (pos.dx - tokenW / 2).clamp(0.0, w - tokenW),
                      top: (pos.dy - 30 * scale).clamp(0.0, h - 66 * scale),
                      width: tokenW,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: off
                            ? null
                            : () => _tapPitch(ins, side.teamId, p),
                        child: target,
                      ),
                    ),
                  );
                }
              }
            }
            if (home.layout == null && away.layout == null) {
              children.add(
                const Center(
                  child: Text(
                    'İlk 11 girilmemiş.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              );
            }
            final at = menuAt;
            if (at != null && _player != null && _team != null) {
              children.add(_menu(at, w, h, scale));
            }
            final hint = _hintBar();
            if (hint != null) {
              children.add(Positioned(left: 8, right: 8, top: 8, child: hint));
            }
            final last = _last;
            if (last != null) {
              children.add(
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: _undoBar(last),
                ),
              );
            }
            if (_saving) {
              children.add(
                const Positioned(
                  right: 10,
                  bottom: 10,
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              );
            }
            return Stack(clipBehavior: Clip.none, children: children);
          },
        ),
      ),
    );
  }

  /// Seçili oyuncunun yanında büyük olay düğmeleri.
  Widget _menu(Offset at, double w, double h, double scale) {
    final teamId = _team!;
    final p = _findOnPitch(teamId, _player!);
    if (p == null) return const SizedBox.shrink();
    const bw = 132.0;
    final buttons = <(String, IconData?, Widget?, Color, VoidCallback)>[
      (
        'GOL',
        Icons.sports_soccer_rounded,
        null,
        _accent,
        () => setState(() => _step = _LiveStep.assist),
      ),
      (
        'SARI',
        null,
        const CardIcon(red: false),
        const Color(0xFFFACC15),
        () => _save(
          type: 'yellow_card',
          teamId: teamId,
          player: p,
          label: 'Sarı kart · ${shortPlayerName(p.name)}',
        ),
      ),
      (
        'KIRMIZI',
        null,
        const CardIcon(red: true),
        const Color(0xFFEF4444),
        () => _save(
          type: 'red_card',
          teamId: teamId,
          player: p,
          label: 'Kırmızı kart · ${shortPlayerName(p.name)}',
        ),
      ),
      (
        'DEĞİŞİKLİK',
        Icons.swap_horiz_rounded,
        null,
        const Color(0xFF38BDF8),
        () => setState(() => _step = _LiveStep.subIn),
      ),
      if (widget.onMoments != null)
        (
          'OLAY',
          Icons.add_circle_outline_rounded,
          null,
          const Color(0xFFA78BFA),
          () async {
            _clear();
            await widget.onMoments!(context, teamId);
          },
        ),
    ];
    final menuH = 34.0 + buttons.length * 48.0;
    final toRight = at.dx < w / 2;
    final left = toRight
        ? (at.dx + 40 * scale).clamp(6.0, w - bw - 6)
        : (at.dx - 40 * scale - bw).clamp(6.0, w - bw - 6);
    final top = (at.dy - menuH / 2).clamp(6.0, (h - menuH - 6).clamp(6.0, h));
    return Positioned(
      left: left,
      top: top,
      width: bw,
      child: Material(
        color: const Color(0xF20F172A),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                child: Text(
                  '${p.number.isEmpty ? '' : '${p.number} · '}'
                  '${shortPlayerName(p.name)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
              for (final (label, icon, iconW, color, onTap) in buttons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SizedBox(
                    height: 44,
                    child: Material(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _saving ? null : onTap,
                        child: Row(
                          children: [
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 20,
                              child: Center(
                                child:
                                    iconW ?? Icon(icon, size: 20, color: color),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Gol / değişiklik adımında üstte yönerge ve kısayollar.
  Widget? _hintBar() {
    final step = _step;
    final teamId = _team;
    final sel = _player;
    if (step == null || step == _LiveStep.menu || teamId == null) return null;
    if (sel == null) return null;
    final p = step == _LiveStep.subOut
        ? _findBench(teamId, sel)
        : _findOnPitch(teamId, sel);
    if (p == null) return null;
    final name = shortPlayerName(p.name);
    final text = switch (step) {
      _LiveStep.assist => 'Gol $name · asisti yapana dokunun',
      _LiveStep.subIn => '$name çıkıyor · girecek yedeğe dokunun',
      _LiveStep.subOut => '$name giriyor · çıkacak oyuncuya dokunun',
      _LiveStep.menu => '',
    };
    Widget btn(String label, VoidCallback onTap, {bool primary = false}) =>
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: SizedBox(
            height: 34,
            child: FilledButton(
              onPressed: _saving ? null : onTap,
              style: FilledButton.styleFrom(
                backgroundColor: primary
                    ? _accent
                    : Colors.white.withValues(alpha: 0.12),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              child: Text(label),
            ),
          ),
        );
    return Material(
      color: const Color(0xF20F172A),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (step == _LiveStep.assist) ...[
              btn(
                'Asistsiz',
                () => _save(
                  type: 'goal',
                  teamId: teamId,
                  player: p,
                  label: 'Gol · $name',
                ),
                primary: true,
              ),
              btn(
                'Penaltı',
                () => _save(
                  type: 'goal',
                  teamId: teamId,
                  player: p,
                  pen: true,
                  label: 'Penaltı golü · $name',
                ),
              ),
              btn(
                'Kendi kalesine',
                () => _save(
                  type: 'goal',
                  teamId: teamId,
                  player: p,
                  own: true,
                  label: 'Kendi kalesine · $name',
                ),
              ),
            ],
            btn('İptal', _clear),
          ],
        ),
      ),
    );
  }

  Widget _undoBar(({String id, String label}) last) => Center(
    child: Material(
      color: const Color(0xFF1E293B),
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: _accent, size: 18),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                last.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: _undo,
              child: const Text(
                'GERİ AL',
                style: TextStyle(
                  color: Color(0xFFFBBF24),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Bir takımın canlı dizilişi ve kenardakileri.
class _LiveSide {
  const _LiveSide({
    required this.teamId,
    required this.layout,
    required this.bench,
  });

  final String teamId;
  final _Layout? layout;
  final List<_PitchPlayer> bench;
}
