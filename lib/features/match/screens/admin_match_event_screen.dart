import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/match.dart';
import '../../team/models/team.dart';
import '../../../core/services/app_session.dart';
import '../services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../utils/match_clock.dart';
import '../utils/minute_label.dart';
import '../utils/season_match_settings.dart';

class AdminMatchEventScreen extends StatefulWidget {
  final MatchModel match;

  /// Dolu ise form bu olayı düzenler: oyuncu, asist, giren oyuncu ve dakika
  /// değişir; tür, takım ve skoru etkileyen seçimler kilitli kalır.
  final MatchEvent? event;
  const AdminMatchEventScreen({super.key, required this.match, this.event});

  @override
  State<AdminMatchEventScreen> createState() => _AdminMatchEventScreenState();
}

class _AdminMatchEventScreenState extends State<AdminMatchEventScreen> {
  final _minuteController = TextEditingController();

  /// Canlı maçta otomatik yazılan dakika (değiştirilmediyse form boş sayılır).
  String _autoMinute = '';

  /// Uzatma dakikası girişi: devre sonu (1. yarı / maç sonu) + uzatma.
  bool _stoppage = false;
  bool _stoppageSecondHalf = false;
  final _addedController = TextEditingController();
  String _autoAdded = '';

  int get _period =>
      SeasonMatchSettings.cached(widget.match.seasonId)?.periodMinutes ??
      MatchClock.periodOf(widget.match.seasonId);
  final IMatchService _matchService = ServiceLocator.matchService;
  final ITeamService _teamService = ServiceLocator.teamService;
  String _eventType = 'goal';

  /// Golden yararlanan takım (kendi kalesine golde de skor bu takıma yazılır).
  String? _teamId;
  LineupPlayer? _selectedPlayer;
  LineupPlayer? _selectedAssist;
  LineupPlayer? _selectedSubIn;
  bool _isOwnGoal = false;

  /// Penaltı olayının sonucu: true gol, false kaçtı.
  bool _penaltyScored = true;

  /// VAR: iptal edilecek gol ve seçilebilecek goller (tür seçilince yüklenir).
  MatchEvent? _cancelGoal;
  Future<List<MatchEvent>>? _goals;
  bool _isLoading = false;

  /// Sezonda gol/kart dakikası tutuluyor mu? Tutulmuyorsa (halısaha) dakika
  /// alanı gösterilmez, olay dakikasız kaydedilir.
  late bool _tracksMinutes =
      SeasonMatchSettings.cached(widget.match.seasonId)?.tracksGoalMinutes ??
      true;

  /// Olayı yapan oyuncunun takımı: kendi kalesine golde rakip takım.
  /// match_events.team_id oyuncunun takımıdır; skor rakibe yazılır.
  String? get _playerTeamId {
    if (_eventType != 'goal' || !_isOwnGoal) return _teamId;
    final m = widget.match;
    return _teamId == m.homeTeamId ? m.awayTeamId : m.homeTeamId;
  }

  bool get _editing => widget.event != null;

  /// Kartta oyuncu değişmez: ceza olay girilirken oyuncuya yazılır.
  bool get _playerLocked =>
      _editing &&
      (_eventType == 'yellow_card' ||
          _eventType == 'red_card' ||
          _eventType == 'red_card_cancelled');

  /// Düzenlenen uzatmalı olayın devre sonu ilk/ikinci devre değilse aynen
  /// korunur (ör. eski süreyle girilmiş 45+2').
  int? _stoppageBase;

  /// Düzenlemede asist/giren oyuncu adları kadro yüklenince bulunur.
  String? _pendingAssistId;
  String? _pendingSubInId;

  void _fillFrom(MatchEvent e) {
    final penalty =
        (e.eventType == 'goal' && e.isPenalty) ||
        e.eventType == 'penalty_missed';
    _eventType = penalty ? 'penalty' : e.eventType;
    _penaltyScored = e.eventType != 'penalty_missed';
    _isOwnGoal = e.isOwnGoal;
    final m = widget.match;
    // Kendi kalesine golde form golü yazılan (rakip) takımı tutar.
    _teamId = e.isOwnGoal
        ? (e.teamId == m.homeTeamId ? m.awayTeamId : m.homeTeamId)
        : e.teamId;
    final pid = (e.playerId ?? '').trim();
    if (pid.isNotEmpty || e.eventName.trim().isNotEmpty) {
      _selectedPlayer = LineupPlayer(playerId: pid, name: e.eventName.trim());
    }
    _pendingAssistId = e.assistPlayerId;
    _pendingSubInId = e.subInPlayerId;
    final added = e.addedMinute ?? 0;
    if (added > 0) {
      _stoppage = true;
      _stoppageSecondHalf = e.minute == _period * 2;
      if (e.minute != _period && e.minute != _period * 2) {
        _stoppageBase = e.minute;
      }
      _addedController.text = _autoAdded = '$added';
    } else if ((e.minute ?? 0) > 0 && e.minute != 999) {
      _minuteController.text = _autoMinute = '${e.minute}';
    }
  }

  /// Listeden adı/numarası belli oyuncuyu bulur (yoksa elimizdekini korur).
  LineupPlayer? _resolve(List<LineupPlayer> list, String? id) {
    final key = (id ?? '').trim();
    if (key.isEmpty) return null;
    return list.where((p) => p.playerId == key).firstOrNull;
  }

  /// Maçta oyundan çıkan / kırmızı kart gören ve oyuna giren oyuncular.
  Set<String> _sentOff = const {};
  Set<String> _subbedIn = const {};

  Future<void> _loadPitchState() async {
    try {
      final rows = await Supabase.instance.client
          .from('match_events')
          .select('id, event_type, player_id, sub_in_player_id')
          .eq('match_id', widget.match.id);
      final off = <String>{}, inn = <String>{};
      final yellows = <String, int>{};
      for (final e in rows) {
        // Düzenlenen olay kendi listesini daraltmasın.
        if (e['id']?.toString() == widget.event?.id) continue;
        final pid = e['player_id']?.toString() ?? '';
        switch (e['event_type']) {
          case 'substitution':
            off.add(pid);
            final i = e['sub_in_player_id']?.toString() ?? '';
            if (i.isNotEmpty) inn.add(i);
          case 'red_card':
            off.add(pid);
          case 'yellow_card':
            yellows[pid] = (yellows[pid] ?? 0) + 1;
            if (yellows[pid]! >= 2) off.add(pid);
        }
      }
      if (mounted) {
        setState(() {
          _sentOff = off;
          _subbedIn = inn;
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadPitchState();
    _teamId = widget.match.homeTeamId;
    final editing = widget.event;
    if (editing != null) {
      _fillFrom(editing);
      _initialSnapshot = _snapshot();
      SeasonMatchSettings.of(widget.match.seasonId).then((s) {
        if (mounted && s.tracksGoalMinutes != _tracksMinutes) {
          setState(() => _tracksMinutes = s.tracksGoalMinutes);
        }
      });
      return;
    }
    // Canlı maçta dakika saatten gelir; sorumlu isterse değiştirir.
    final live = MatchClock.liveMinuteParts(widget.match);
    if (live != null) {
      final added = live.added;
      if (added == null) {
        _minuteController.text = _autoMinute = '${live.minute}';
      } else {
        // Devre bitirilmeden süre aştıysa uzatma: 30+2'.
        _stoppage = true;
        _stoppageSecondHalf = widget.match.secondHalfAt != null;
        _addedController.text = _autoAdded = '$added';
      }
    }
    SeasonMatchSettings.of(widget.match.seasonId).then((s) {
      if (mounted && s.tracksGoalMinutes != _tracksMinutes) {
        setState(() => _tracksMinutes = s.tracksGoalMinutes);
      }
    });
  }

  @override
  void dispose() {
    _minuteController.dispose();
    _addedController.dispose();
    super.dispose();
  }

  String _playerKey(PlayerModel p) {
    return p.id.trim();
  }

  List<LineupPlayer> _toLineupPlayers(List<PlayerModel> players) {
    final list = <LineupPlayer>[];
    for (final p in players) {
      final key = _playerKey(p);
      final name = p.name.trim();
      if (key.isEmpty || name.isEmpty) continue;
      list.add(LineupPlayer(playerId: key, name: name, number: p.number));
    }
    list.sort((a, b) {
      final an = int.tryParse((a.number ?? '').trim()) ?? 9999;
      final bn = int.tryParse((b.number ?? '').trim()) ?? 9999;
      final cmp = an.compareTo(bn);
      if (cmp != 0) return cmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  String _labelFor(LineupPlayer p) {
    final n = (p.number ?? '').trim();
    final number = n.isEmpty ? '-' : n;
    return '$number - ${p.name}';
  }

  Future<T?> _pick<T>({
    required String title,
    required List<_PickerOption<T>> options,
    T? selected,
  }) async {
    final picked = await showAdminOptionPicker<_PickerOption<T>>(
      context: context,
      title: title,
      items: options,
      labelBuilder: (o) => o.label,
      selected: options.where((o) => o.value == selected).firstOrNull,
      emptyText: 'Seçenek yok.',
    );
    return picked?.value;
  }

  static const _eventTypes = [
    _PickerOption('goal', 'Gol'),
    _PickerOption('penalty', 'Penaltı'),
    _PickerOption('yellow_card', 'Sarı Kart'),
    _PickerOption('red_card', 'Kırmızı Kart'),
    _PickerOption('man_of_the_match', 'Maçın Adamı'),
    _PickerOption('substitution', 'Oyuncu Değişikliği'),
    _PickerOption('var_cancel', 'VAR: Gol İptali'),
  ];

  static IconData _eventIcon(String type) => switch (type) {
    'goal' => Icons.sports_soccer_rounded,
    'penalty' => Icons.adjust_rounded,
    'assist' => Icons.handshake_outlined,
    'yellow_card' || 'red_card' => Icons.style_outlined,
    'man_of_the_match' => Icons.star_outline_rounded,
    'substitution' => Icons.swap_horiz_rounded,
    'var_cancel' => Icons.tv_off_rounded,
    _ => Icons.flag_outlined,
  };

  Future<void> _addEvent() async {
    final player = _selectedPlayer;
    final isMotm = _eventType == 'man_of_the_match';
    // Maçın adamı maç bittikten sonra seçilir; dakikası yoktur (sona sıralanır).
    final stoppage = !isMotm && _tracksMinutes && _stoppage;
    final minuteStr = isMotm
        ? '999'
        : stoppage
        ? '${_stoppageBase ?? (_stoppageSecondHalf ? _period * 2 : _period)}'
        : _minuteController.text.trim();
    final added = stoppage ? int.tryParse(_addedController.text.trim()) : null;
    if (stoppage && (added == null || added < 1 || added > 30)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uzatma dakikasını girin (1-30).')),
      );
      return;
    }
    if (isMotm && !_editing && widget.match.status != MatchStatus.finished) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maçın adamı maç bittikten sonra seçilebilir.'),
        ),
      );
      return;
    }
    if (player == null || (_tracksMinutes && minuteStr.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tüm alanları doldurun.')),
      );
      return;
    }
    if (_eventType == 'substitution' && _selectedSubIn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen giren oyuncuyu seçin.')),
      );
      return;
    }

    final minute = int.tryParse(minuteStr);
    if (_tracksMinutes && minute == null) return;

    setState(() => _isLoading = true);
    final editing = widget.event;
    if (editing != null) {
      try {
        // Maçın adamı dakikası değişmez (999: sona sıralanır).
        await _matchService.updateMatchEvent(
          MatchEvent(
            id: editing.id,
            matchId: editing.matchId,
            teamId: editing.teamId,
            eventType: editing.eventType,
            minute: isMotm ? editing.minute : minute,
            addedMinute: isMotm ? editing.addedMinute : added,
            eventName: player.name.trim(),
            playerId: player.playerId.trim().isEmpty
                ? null
                : player.playerId.trim(),
            assistPlayerId: editing.eventType == 'goal' && !_isOwnGoal
                ? _selectedAssist?.playerId.trim()
                : editing.assistPlayerId,
            subInPlayerId: editing.eventType == 'substitution'
                ? _selectedSubIn?.playerId.trim()
                : editing.subInPlayerId,
            isOwnGoal: editing.isOwnGoal,
            isPenalty: editing.isPenalty,
          ),
        );
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Olay güncellendi.'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }
    try {
      final event = MatchEvent(
        id: '',
        matchId: widget.match.id,
        leagueId: widget.match.leagueId,
        teamId: _playerTeamId!,
        // Penaltı: gol olursa penaltı işaretli gol, kaçarsa ayrı olay.
        eventType: _eventType == 'penalty'
            ? (_penaltyScored ? 'goal' : 'penalty_missed')
            : _eventType,
        minute: minute,
        addedMinute: added,
        eventName: player.name.trim(),
        playerId: player.playerId.trim().isEmpty
            ? null
            : player.playerId.trim(),
        assistPlayerId: _eventType == 'goal' && !_isOwnGoal
            ? _selectedAssist?.playerId.trim().toString()
            : null,
        subInPlayerId: _eventType == 'substitution'
            ? (_selectedSubIn?.playerId.trim().isEmpty ?? true
                  ? null
                  : _selectedSubIn!.playerId.trim())
            : null,
        isOwnGoal: _eventType == 'goal' ? _isOwnGoal : false,
        isPenalty: _eventType == 'penalty' && _penaltyScored,
      );

      await _matchService.addMatchEvent(event);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Olay başarıyla kaydedildi.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// "41' Erol Sancaklı (K.K.) · Gaziosmanpaşa Autur"
  String _goalLabel(MatchEvent g, String homeName, String awayName) {
    final min = g.minute == null
        ? ''
        : '${minuteLabel(g.minute, g.addedMinute)} ';
    final name = g.eventName.trim().isEmpty ? 'Gol' : g.eventName.trim();
    final tag = g.isOwnGoal
        ? ' (K.K.)'
        : g.isPenalty
        ? ' (P)'
        : '';
    final team = g.teamId == widget.match.homeTeamId ? homeName : awayName;
    return '$min$name$tag · ${shortTeamName(team)}';
  }

  /// VAR: seçilen gol son bir onaydan sonra iptal edilir; skor ve bildirim
  /// veritabanında güncellenir.
  Future<void> _cancelGoalFlow(String label) async {
    final goal = _cancelGoal;
    if (goal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen iptal edilecek golü seçin.')),
      );
      return;
    }
    final ok = await showVarConfirmDialog(
      context,
      title: 'VAR: Gol İptali',
      subject: label,
      message:
          'Bu gol iptal edilecek. Skor güncellenir ve maçı takip edenlere '
          'bildirim gider.',
    );
    if (ok != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _matchService.setGoalCancelled(goal.id, cancelled: true);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Gol VAR kararıyla iptal edildi.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    // Admin, turnuva sahibi ve maçın gözlemcisi olay girebilir.
    final canManage =
        session.canManageLeague(widget.match.leagueId) ||
        (widget.match.observerId != null &&
            widget.match.observerId == session.user?.id);
    if (!canManage) {
      return _frame(
        children: [
          const AdminDialogHeader(
            icon: Icons.lock_outline_rounded,
            title: 'Maç Olayları',
          ),
          const SizedBox(height: 18),
          const Text(
            'Bu işlem için yetkiniz yok.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ],
      );
    }
    return StreamBuilder<List<Team>>(
      stream: _teamService.watchSeasonTeams(widget.match.seasonId),
      builder: (context, teamsSnap) {
        final nameById = <String, String>{};
        if (teamsSnap.hasData) {
          for (final t in teamsSnap.data!) {
            nameById[t.id] = t.name;
          }
        }
        final homeName =
            (nameById[widget.match.homeTeamId] ?? '').trim().isEmpty
            ? 'Ev Sahibi'
            : (nameById[widget.match.homeTeamId] ?? '').trim();
        final awayName =
            (nameById[widget.match.awayTeamId] ?? '').trim().isEmpty
            ? 'Deplasman'
            : (nameById[widget.match.awayTeamId] ?? '').trim();

        return StreamBuilder<List<MatchRosterModel>>(
          stream: (_playerTeamId ?? '').trim().isEmpty
              ? const Stream<List<MatchRosterModel>>.empty()
              : _matchService.watchMatchRosters(
                  widget.match.id,
                  _playerTeamId!,
                ),
          builder: (context, rosterSnap) {
            final rosters = rosterSnap.data ?? [];
            final rosterPlayerIds = rosters.map((r) => r.playerId).toSet();
            final startingIds = rosters
                .where((r) => r.isStarting)
                .map((r) => r.playerId)
                .toSet();
            final subIds = rosters
                .where((r) => !r.isStarting)
                .map((r) => r.playerId)
                .toSet();

            return StreamBuilder<List<PlayerModel>>(
              stream: (_playerTeamId ?? '').trim().isEmpty
                  ? const Stream<List<PlayerModel>>.empty()
                  : _teamService.watchPlayers(
                      teamId: _playerTeamId!,
                      tournamentId: widget.match.seasonId,
                    ),
              builder: (context, playersSnap) {
                final allPlayers = playersSnap.data ?? const <PlayerModel>[];
                final players = _toLineupPlayers(
                  allPlayers
                      .where((p) => rosterPlayerIds.contains(p.id))
                      .toList(),
                );
                // Değişiklikte çıkan: sahadakiler (ilk 11 − çıkanlar − atılanlar
                // + girenler); giren: henüz oyuna girmemiş yedekler.
                final startingPlayers = _toLineupPlayers(
                  allPlayers
                      .where(
                        (p) =>
                            (startingIds.contains(p.id) ||
                                _subbedIn.contains(p.id)) &&
                            !_sentOff.contains(p.id),
                      )
                      .toList(),
                );
                final subsPlayers = _toLineupPlayers(
                  allPlayers
                      .where(
                        (p) =>
                            subIds.contains(p.id) &&
                            !_subbedIn.contains(p.id) &&
                            !_sentOff.contains(p.id),
                      )
                      .toList(),
                );
                final enabled = players.isNotEmpty && !_isLoading;

                // Düzenlemede kayıtlı asist / giren oyuncu kadrodan bulunur;
                // seçili oyuncu adı/numarasıyla güncellenir.
                if (_editing && players.isNotEmpty) {
                  final assist = _resolve(players, _pendingAssistId);
                  final subIn =
                      _resolve(subsPlayers, _pendingSubInId) ??
                      _resolve(players, _pendingSubInId);
                  final current = _resolve(players, _selectedPlayer?.playerId);
                  final refresh =
                      current != null &&
                      (current.number != _selectedPlayer!.number ||
                          current.name != _selectedPlayer!.name);
                  if (_pendingAssistId != null ||
                      _pendingSubInId != null ||
                      refresh) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        if (_pendingAssistId != null) _selectedAssist = assist;
                        if (_pendingSubInId != null) _selectedSubIn = subIn;
                        _pendingAssistId = _pendingSubInId = null;
                        if (current != null) _selectedPlayer = current;
                      });
                    });
                  }
                }

                if (!_editing &&
                    enabled &&
                    _selectedPlayer != null &&
                    !players.any(
                      (p) => p.playerId == _selectedPlayer!.playerId,
                    )) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _selectedPlayer = null);
                  });
                }

                final isGoal = _eventType == 'goal';
                final isSub = _eventType == 'substitution';
                final eventLabel = _eventTypes
                    .firstWhere(
                      (o) => o.value == _eventType,
                      orElse: () => _eventTypes.first,
                    )
                    .label;

                final typeRow = AdminSelectRow(
                  icon: _eventIcon(_eventType),
                  label: 'Olay Türü',
                  value: eventLabel,
                  placeholder: 'Seçiniz',
                  onTap: _isLoading || _editing
                      ? null
                      : () async {
                          final picked = await _pick<String>(
                            title: 'Olay Türü',
                            selected: _eventType,
                            options: [
                              for (final o in _eventTypes)
                                if ((o.value != 'man_of_the_match' ||
                                        widget.match.status ==
                                            MatchStatus.finished) &&
                                    // VAR yalnız başlamış maçta.
                                    (o.value != 'var_cancel' ||
                                        widget.match.status !=
                                            MatchStatus.notStarted))
                                  o,
                            ],
                          );
                          if (picked == null || !mounted) return;
                          setState(() {
                            _eventType = picked;
                            _cancelGoal = null;
                            if (picked == 'var_cancel') {
                              _goals = _matchService.fetchGoalEvents(
                                widget.match.id,
                              );
                            }
                            if (picked != 'goal') {
                              _selectedAssist = null;
                              _isOwnGoal = false;
                              _penaltyScored = true;
                            }
                            if (picked != 'substitution') {
                              _selectedSubIn = null;
                            }
                          });
                        },
                );

                if (_eventType == 'var_cancel') {
                  return FutureBuilder<List<MatchEvent>>(
                    future: _goals,
                    builder: (context, goalsSnap) {
                      final goals = goalsSnap.data ?? const <MatchEvent>[];
                      final label = _cancelGoal == null
                          ? null
                          : _goalLabel(_cancelGoal!, homeName, awayName);
                      return _frame(
                        children: [
                          AdminDialogHeader(
                            icon: Icons.tv_off_rounded,
                            title: 'VAR: Gol İptali',
                            subtitle:
                                '${shortTeamName(homeName)} - ${shortTeamName(awayName)}',
                          ),
                          const SizedBox(height: 18),
                          AdminFieldGroup(
                            children: [
                              typeRow,
                              AdminSelectRow(
                                icon: Icons.sports_soccer_rounded,
                                label: 'İptal Edilecek Gol',
                                value: label,
                                placeholder:
                                    goalsSnap.connectionState !=
                                        ConnectionState.done
                                    ? 'Yükleniyor…'
                                    : goals.isEmpty
                                    ? 'Maçta gol yok'
                                    : 'Seçiniz',
                                onTap: goals.isEmpty || _isLoading
                                    ? null
                                    : () async {
                                        final picked = await _pick<MatchEvent>(
                                          title: 'İptal Edilecek Gol',
                                          selected: _cancelGoal,
                                          options: [
                                            for (final g in goals)
                                              _PickerOption(
                                                g,
                                                _goalLabel(
                                                  g,
                                                  homeName,
                                                  awayName,
                                                ),
                                              ),
                                          ],
                                        );
                                        if (picked == null || !mounted) {
                                          return;
                                        }
                                        setState(() => _cancelGoal = picked);
                                      },
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          AdminPrimaryButton(
                            label: 'GOLÜ İPTAL ET',
                            busy: _isLoading,
                            onPressed: () => _cancelGoalFlow(label ?? ''),
                          ),
                        ],
                      );
                    },
                  );
                }

                return _frame(
                  children: [
                    AdminDialogHeader(
                      icon: _editing
                          ? Icons.edit_rounded
                          : Icons.sports_soccer_rounded,
                      title: _editing
                          ? 'Maç Olayını Düzenle'
                          : 'Maç Olayı Ekle',
                      subtitle:
                          '${shortTeamName(homeName)} - ${shortTeamName(awayName)}',
                    ),
                    const SizedBox(height: 18),
                    AdminFieldGroup(
                      children: [
                        typeRow,
                        AdminSelectRow(
                          icon: Icons.shield_outlined,
                          label: isGoal ? 'Golü Atan Takım' : 'Takım',
                          value: _teamId == widget.match.homeTeamId
                              ? homeName
                              : awayName,
                          placeholder: 'Seçiniz',
                          onTap: _isLoading || _editing
                              ? null
                              : () async {
                                  final picked = await _pick<String>(
                                    title: 'Takım',
                                    selected: _teamId,
                                    options: [
                                      _PickerOption(
                                        widget.match.homeTeamId,
                                        homeName,
                                      ),
                                      _PickerOption(
                                        widget.match.awayTeamId,
                                        awayName,
                                      ),
                                    ],
                                  );
                                  if (picked == null || !mounted) return;
                                  setState(() {
                                    _teamId = picked;
                                    _selectedPlayer = null;
                                    _selectedAssist = null;
                                    _selectedSubIn = null;
                                    _isOwnGoal = false;
                                    _penaltyScored = true;
                                  });
                                },
                        ),
                        AdminSelectRow(
                          icon: Icons.person_outline_rounded,
                          label: isSub ? 'Çıkan Oyuncu' : 'Futbolcu',
                          value: _selectedPlayer == null
                              ? null
                              : _labelFor(_selectedPlayer!),
                          placeholder: players.isEmpty
                              ? 'Kadroda oyuncu yok'
                              : 'Seçiniz',
                          onTap: enabled && !_playerLocked
                              ? () async {
                                  final picked = await _pick<LineupPlayer>(
                                    title: isSub ? 'Çıkan Oyuncu' : 'Futbolcu',
                                    selected: _selectedPlayer,
                                    options: [
                                      for (final p
                                          in isSub ? startingPlayers : players)
                                        _PickerOption(p, _labelFor(p)),
                                    ],
                                  );
                                  if (picked == null || !mounted) return;
                                  setState(() => _selectedPlayer = picked);
                                }
                              : null,
                        ),
                        if (isSub)
                          AdminSelectRow(
                            icon: Icons.login_rounded,
                            label: 'Giren Oyuncu',
                            value: _selectedSubIn == null
                                ? null
                                : _labelFor(_selectedSubIn!),
                            placeholder: subsPlayers.isEmpty
                                ? 'Yedek yok'
                                : 'Seçiniz',
                            onTap: (subsPlayers.isNotEmpty && !_isLoading)
                                ? () async {
                                    final picked = await _pick<LineupPlayer>(
                                      title: 'Giren Oyuncu',
                                      selected: _selectedSubIn,
                                      options: [
                                        for (final p in subsPlayers)
                                          _PickerOption(p, _labelFor(p)),
                                      ],
                                    );
                                    if (picked == null || !mounted) return;
                                    setState(() => _selectedSubIn = picked);
                                  }
                                : null,
                          ),
                        if (_eventType != 'man_of_the_match' && _tracksMinutes)
                          AdminFieldRow(
                            icon: Icons.more_time_rounded,
                            label: 'Uzatma Dakikası',
                            onTap: _isLoading
                                ? null
                                : () => setState(() => _stoppage = !_stoppage),
                            trailing: Switch(
                              value: _stoppage,
                              activeThumbColor: kAdminAccent,
                              onChanged: _isLoading
                                  ? null
                                  : (v) => setState(() => _stoppage = v),
                            ),
                            child: Text(
                              _stoppage ? 'Devre sonu + uzatma' : 'Normal süre',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (_eventType != 'man_of_the_match' &&
                            _tracksMinutes &&
                            _stoppage)
                          AdminFieldRow(
                            icon: Icons.timer_outlined,
                            label: 'Uzatma',
                            child: Row(
                              children: [
                                if (_stoppageBase != null) ...[
                                  ChoiceChip(
                                    label: Text('$_stoppageBase+'),
                                    selected: true,
                                    onSelected: null,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                for (final second in [false, true]) ...[
                                  ChoiceChip(
                                    label: Text(
                                      "${second ? _period * 2 : _period}+",
                                    ),
                                    selected:
                                        _stoppageBase == null &&
                                        _stoppageSecondHalf == second,
                                    onSelected: _isLoading
                                        ? null
                                        : (_) => setState(() {
                                            _stoppageSecondHalf = second;
                                            _stoppageBase = null;
                                          }),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: TextField(
                                    controller: _addedController,
                                    enabled: !_isLoading,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(2),
                                    ],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    decoration: adminInlineInputDecoration(
                                      hint: 'Örn. 2',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_eventType != 'man_of_the_match' &&
                            _tracksMinutes &&
                            !_stoppage)
                          AdminFieldRow(
                            icon: Icons.timer_outlined,
                            label: 'Dakika',
                            child: TextField(
                              controller: _minuteController,
                              enabled: !_isLoading,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: adminInlineInputDecoration(
                                hint: 'Örn. 23',
                              ),
                            ),
                          ),
                        if (isGoal)
                          AdminFieldRow(
                            icon: Icons.u_turn_left_rounded,
                            label: 'Kendi Kalesine',
                            onTap: _isLoading || _editing
                                ? null
                                : () => setState(() {
                                    _isOwnGoal = !_isOwnGoal;
                                    // Oyuncu listesi rakip takıma geçer.
                                    _selectedPlayer = null;
                                    _selectedAssist = null;
                                  }),
                            trailing: Switch(
                              value: _isOwnGoal,
                              activeThumbColor: kAdminAccent,
                              onChanged: _isLoading || _editing
                                  ? null
                                  : (v) => setState(() {
                                      _isOwnGoal = v;
                                      _selectedPlayer = null;
                                      _selectedAssist = null;
                                    }),
                            ),
                            child: Text(
                              _isOwnGoal ? 'Evet' : 'Hayır',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (_eventType == 'penalty')
                          AdminSelectRow(
                            icon: Icons.adjust_rounded,
                            label: 'Sonuç',
                            value: _penaltyScored ? 'Gol' : 'Kaçtı',
                            placeholder: 'Seçiniz',
                            onTap: _isLoading || _editing
                                ? null
                                : () async {
                                    final picked = await _pick<bool>(
                                      title: 'Penaltı Sonucu',
                                      selected: _penaltyScored,
                                      options: const [
                                        _PickerOption(true, 'Gol'),
                                        _PickerOption(false, 'Kaçtı'),
                                      ],
                                    );
                                    if (picked == null || !mounted) return;
                                    setState(() => _penaltyScored = picked);
                                  },
                          ),
                        if (isGoal && !_isOwnGoal)
                          AdminSelectRow(
                            icon: Icons.handshake_outlined,
                            label: 'Asist (İsteğe Bağlı)',
                            value: _selectedAssist == null
                                ? null
                                : _labelFor(_selectedAssist!),
                            placeholder: 'Yok',
                            onClear: () =>
                                setState(() => _selectedAssist = null),
                            onTap: enabled
                                ? () async {
                                    final picked = await _pick<LineupPlayer>(
                                      title: 'Asist Yapan',
                                      selected: _selectedAssist,
                                      options: [
                                        for (final p in players)
                                          if (_selectedPlayer == null ||
                                              p.playerId !=
                                                  _selectedPlayer!.playerId)
                                            _PickerOption(p, _labelFor(p)),
                                      ],
                                    );
                                    if (picked == null || !mounted) return;
                                    setState(() => _selectedAssist = picked);
                                  }
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    AdminPrimaryButton(
                      label: 'KAYDET',
                      busy: _isLoading,
                      onPressed: _addEvent,
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// Düzenlemede açılıştaki değerler (kaydedilmemiş değişikliği bulmak için).
  String _initialSnapshot = '';

  String _snapshot() => [
    _minuteController.text.trim(),
    _addedController.text.trim(),
    _stoppage,
    _stoppageSecondHalf,
    _stoppageBase,
    _selectedPlayer?.playerId,
    _selectedAssist?.playerId ?? _pendingAssistId,
    _selectedSubIn?.playerId ?? _pendingSubInId,
  ].join('|');

  /// Formda girilmiş ama kaydedilmemiş bir şey var mı?
  bool get _isDirty => _editing
      ? _snapshot() != _initialSnapshot
      : (_minuteController.text.trim().isNotEmpty &&
                _minuteController.text.trim() != _autoMinute) ||
            (_addedController.text.trim().isNotEmpty &&
                _addedController.text.trim() != _autoAdded) ||
            _selectedPlayer != null ||
            _selectedAssist != null ||
            _selectedSubIn != null ||
            _isOwnGoal ||
            _eventType != 'goal' ||
            _teamId != widget.match.homeTeamId;

  /// Boşluğa dokunma, geri tuşu ya da kapat: kaydedilmemiş değişiklik
  /// varsa önce onay ister.
  Future<void> _confirmClose() async {
    if (_isLoading) return;
    if (!_isDirty) {
      Navigator.pop(context);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Değişiklik kaydedilmedi'),
        content: const Text(
          'Girdiğiniz bilgiler kaydedilmedi. Çıkmak istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çık'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  /// Ortak popup çerçevesi; klavye açılınca içerik kaydırılabilir.
  Widget _frame({required List<Widget> children}) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose();
      },
      child: _dialog(children),
    );
  }

  Widget _dialog(List<Widget> children) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AdminDialogCloseOverlay(
        onClose: _isLoading ? null : _confirmClose,
        child: Container(
          decoration: adminDialogDecoration(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerOption<T> {
  const _PickerOption(this.value, this.label);
  final T value;
  final String label;
}

/// VAR kararı onayı: üstte olay, altta kırmızı İPTAL ve yeşil ONAYLA.
/// Onaylanırsa true döner.
Future<bool> showVarConfirmDialog(
  BuildContext context, {
  required String title,
  required String subject,
  required String message,
}) async {
  Widget button(String label, Color color, bool value, BuildContext ctx) =>
      Expanded(
        child: SizedBox(
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, value),
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      );
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: adminDialogDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminDialogHeader(icon: Icons.tv_off_rounded, title: title),
            const SizedBox(height: 16),
            if (subject.isNotEmpty) ...[
              Text(
                subject,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                button('İPTAL', const Color(0xFFDC2626), false, ctx),
                const SizedBox(width: 12),
                button('ONAYLA', kAdminAccent, true, ctx),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}
