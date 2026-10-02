import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/match.dart';
import '../../team/models/team.dart';
import '../../../core/services/app_session.dart';
import '../services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';

class AdminMatchEventScreen extends StatefulWidget {
  final MatchModel match;
  const AdminMatchEventScreen({super.key, required this.match});

  @override
  State<AdminMatchEventScreen> createState() => _AdminMatchEventScreenState();
}

class _AdminMatchEventScreenState extends State<AdminMatchEventScreen> {
  final _minuteController = TextEditingController();
  final IMatchService _matchService = ServiceLocator.matchService;
  final ITeamService _teamService = ServiceLocator.teamService;
  String _eventType = 'goal';
  String? _teamId;
  LineupPlayer? _selectedPlayer;
  LineupPlayer? _selectedAssist;
  LineupPlayer? _selectedSubIn;
  bool _isOwnGoal = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _teamId = widget.match.homeTeamId;
  }

  @override
  void dispose() {
    _minuteController.dispose();
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
    _PickerOption('assist', 'Asist'),
    _PickerOption('yellow_card', 'Sarı Kart'),
    _PickerOption('red_card', 'Kırmızı Kart'),
    _PickerOption('man_of_the_match', 'Maçın Adamı'),
    _PickerOption('substitution', 'Oyuncu Değişikliği'),
  ];

  static IconData _eventIcon(String type) => switch (type) {
    'goal' => Icons.sports_soccer_rounded,
    'assist' => Icons.handshake_outlined,
    'yellow_card' || 'red_card' => Icons.style_outlined,
    'man_of_the_match' => Icons.star_outline_rounded,
    'substitution' => Icons.swap_horiz_rounded,
    _ => Icons.flag_outlined,
  };

  Future<void> _addEvent() async {
    final player = _selectedPlayer;
    final minuteStr = _minuteController.text.trim();
    if (player == null || minuteStr.isEmpty) {
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
    if (minute == null) return;

    setState(() => _isLoading = true);
    try {
      final event = MatchEvent(
        id: '',
        matchId: widget.match.id,
        leagueId: widget.match.leagueId,
        teamId: _teamId!,
        eventType: _eventType,
        minute: minute,
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
          const SizedBox(height: 18),
          AdminSecondaryButton(
            label: 'KAPAT',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
    }
    return StreamBuilder<List<Team>>(
      stream: _teamService.watchAllTeams(),
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
          stream: (_teamId ?? '').trim().isEmpty
              ? const Stream<List<MatchRosterModel>>.empty()
              : _matchService.watchMatchRosters(widget.match.id, _teamId!),
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
              stream: (_teamId ?? '').trim().isEmpty
                  ? const Stream<List<PlayerModel>>.empty()
                  : _teamService.watchPlayers(
                      teamId: _teamId!,
                      tournamentId: widget.match.seasonId,
                    ),
              builder: (context, playersSnap) {
                final allPlayers = playersSnap.data ?? const <PlayerModel>[];
                final players = _toLineupPlayers(
                  allPlayers
                      .where((p) => rosterPlayerIds.contains(p.id))
                      .toList(),
                );
                final startingPlayers = _toLineupPlayers(
                  allPlayers.where((p) => startingIds.contains(p.id)).toList(),
                );
                final subsPlayers = _toLineupPlayers(
                  allPlayers.where((p) => subIds.contains(p.id)).toList(),
                );
                final enabled = players.isNotEmpty && !_isLoading;

                if (enabled &&
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

                return _frame(
                  children: [
                    AdminDialogHeader(
                      icon: Icons.sports_soccer_rounded,
                      title: 'Maç Olayı Ekle',
                      subtitle:
                          '${shortTeamName(homeName)} - ${shortTeamName(awayName)}',
                    ),
                    const SizedBox(height: 18),
                    AdminFieldGroup(
                      children: [
                        AdminSelectRow(
                          icon: _eventIcon(_eventType),
                          label: 'Olay Türü',
                          value: eventLabel,
                          placeholder: 'Seçiniz',
                          onTap: _isLoading
                              ? null
                              : () async {
                                  final picked = await _pick<String>(
                                    title: 'Olay Türü',
                                    selected: _eventType,
                                    options: _eventTypes,
                                  );
                                  if (picked == null || !mounted) return;
                                  setState(() {
                                    _eventType = picked;
                                    if (picked != 'goal') {
                                      _selectedAssist = null;
                                      _isOwnGoal = false;
                                    }
                                    if (picked != 'substitution') {
                                      _selectedSubIn = null;
                                    }
                                  });
                                },
                        ),
                        AdminSelectRow(
                          icon: Icons.shield_outlined,
                          label: 'Takım',
                          value: _teamId == widget.match.homeTeamId
                              ? homeName
                              : awayName,
                          placeholder: 'Seçiniz',
                          onTap: _isLoading
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
                          onTap: enabled
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
                            onTap: _isLoading
                                ? null
                                : () => setState(() {
                                    _isOwnGoal = !_isOwnGoal;
                                    if (_isOwnGoal) _selectedAssist = null;
                                  }),
                            trailing: Switch(
                              value: _isOwnGoal,
                              activeThumbColor: kAdminAccent,
                              onChanged: _isLoading
                                  ? null
                                  : (v) => setState(() {
                                      _isOwnGoal = v;
                                      if (v) _selectedAssist = null;
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
                    const SizedBox(height: 10),
                    AdminSecondaryButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pop(context),
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

  /// Ortak popup çerçevesi; klavye açılınca içerik kaydırılabilir.
  Widget _frame({required List<Widget> children}) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
    );
  }
}

class _PickerOption<T> {
  const _PickerOption(this.value, this.label);
  final T value;
  final String label;
}
