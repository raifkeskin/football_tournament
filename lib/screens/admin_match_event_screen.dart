import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/match.dart';
import '../services/app_session.dart';
import '../services/database_service.dart';

class AdminMatchEventScreen extends StatefulWidget {
  final MatchModel match;
  const AdminMatchEventScreen({super.key, required this.match});

  @override
  State<AdminMatchEventScreen> createState() => _AdminMatchEventScreenState();
}

class _AdminMatchEventScreenState extends State<AdminMatchEventScreen> {
  final _minuteController = TextEditingController();
  final _dbService = DatabaseService();
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

  List<LineupPlayer> _playersFromLineup(String? teamId) {
    if (teamId == null) return const <LineupPlayer>[];
    final lineup = teamId == widget.match.homeTeamId
        ? widget.match.homeLineupDetail
        : teamId == widget.match.awayTeamId
        ? widget.match.awayLineupDetail
        : null;
    if (lineup == null) return const <LineupPlayer>[];
    final list = [...lineup.starting, ...lineup.subs];
    final seen = <String>{};
    final unique = <LineupPlayer>[];
    for (final p in list) {
      final key = p.name.trim();
      if (key.isEmpty) continue;
      if (seen.add(key)) unique.add(p);
    }
    unique.sort((a, b) {
      final an = int.tryParse((a.number ?? '').trim()) ?? 9999;
      final bn = int.tryParse((b.number ?? '').trim()) ?? 9999;
      final cmp = an.compareTo(bn);
      if (cmp != 0) return cmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return unique;
  }

  List<LineupPlayer> _startingFromLineup(String? teamId) {
    if (teamId == null) return const <LineupPlayer>[];
    final lineup = teamId == widget.match.homeTeamId
        ? widget.match.homeLineupDetail
        : teamId == widget.match.awayTeamId
        ? widget.match.awayLineupDetail
        : null;
    if (lineup == null) return const <LineupPlayer>[];
    final list = [...lineup.starting];
    final seen = <String>{};
    final unique = <LineupPlayer>[];
    for (final p in list) {
      final key = p.name.trim();
      if (key.isEmpty) continue;
      if (seen.add(key)) unique.add(p);
    }
    unique.sort((a, b) {
      final an = int.tryParse((a.number ?? '').trim()) ?? 9999;
      final bn = int.tryParse((b.number ?? '').trim()) ?? 9999;
      final cmp = an.compareTo(bn);
      if (cmp != 0) return cmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return unique;
  }

  List<LineupPlayer> _subsFromLineup(String? teamId) {
    if (teamId == null) return const <LineupPlayer>[];
    final lineup = teamId == widget.match.homeTeamId
        ? widget.match.homeLineupDetail
        : teamId == widget.match.awayTeamId
        ? widget.match.awayLineupDetail
        : null;
    if (lineup == null) return const <LineupPlayer>[];
    final list = [...lineup.subs];
    final seen = <String>{};
    final unique = <LineupPlayer>[];
    for (final p in list) {
      final key = p.name.trim();
      if (key.isEmpty) continue;
      if (seen.add(key)) unique.add(p);
    }
    unique.sort((a, b) {
      final an = int.tryParse((a.number ?? '').trim()) ?? 9999;
      final bn = int.tryParse((b.number ?? '').trim()) ?? 9999;
      final cmp = an.compareTo(bn);
      if (cmp != 0) return cmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return unique;
  }

  String _labelFor(LineupPlayer p) {
    final n = (p.number ?? '').trim();
    final number = n.isEmpty ? '-' : n;
    return '$number - ${p.name}';
  }

  Future<T?> _pickFromSheet<T>({
    required String title,
    required List<_PickerOption<T>> options,
    T? selected,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final opt = options[index];
                      final isSelected = selected != null && opt.value == selected;
                      return Material(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(context, opt.value),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    opt.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF2E7D32),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _selectorTile({
    required String label,
    required String valueText,
    required VoidCallback? onTap,
    String? helperText,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: cs.surfaceContainerLow,
          elevation: 0.5,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      valueText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color:
                            onTap == null ? cs.onSurfaceVariant : cs.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    color: onTap == null ? cs.onSurfaceVariant : cs.onSurface,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

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
        tournamentId: widget.match.leagueId,
        teamId: _teamId!,
        eventType: _eventType,
        minute: minute,
        playerName: player.name.trim(),
        playerPhone: player.playerId.trim().isEmpty ? null : player.playerId.trim(),
        assistPlayerName: _eventType == 'goal' && !_isOwnGoal ? _selectedAssist?.name.trim() : null,
        assistPlayerPhone: _eventType == 'goal' && !_isOwnGoal
            ? (_selectedAssist?.playerId.trim().isEmpty ?? true
                  ? null
                  : _selectedAssist!.playerId.trim())
            : null,
        subInPlayerName: _eventType == 'substitution' ? _selectedSubIn?.name.trim() : null,
        subInPlayerPhone: _eventType == 'substitution'
            ? (_selectedSubIn?.playerId.trim().isEmpty ?? true
                  ? null
                  : _selectedSubIn!.playerId.trim())
            : null,
        type: _eventType,
        isOwnGoal: _eventType == 'goal' ? _isOwnGoal : false,
      );

      await _dbService.addMatchEvent(event);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
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
    final isAdmin = AppSession.of(context).value.isAdmin;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Maç Olayları')),
        body: const Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final players = _playersFromLineup(_teamId);
    final startingPlayers = _startingFromLineup(_teamId);
    final subsPlayers = _subsFromLineup(_teamId);
    final enabled = players.isNotEmpty && !_isLoading;
    if (enabled && _selectedPlayer != null) {
      final exists = players.any((p) => p.playerId == _selectedPlayer!.playerId);
      if (!exists) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _selectedPlayer = null);
        });
      }
    }
    if (_eventType != 'goal' && _selectedAssist != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedAssist = null);
      });
    }
    if (_eventType != 'goal' && _isOwnGoal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _isOwnGoal = false);
      });
    }
    if (_eventType != 'substitution' && _selectedSubIn != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedSubIn = null);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Maç Olayı Ekle')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _selectorTile(
                  label: 'Takım Seçimi',
                  valueText: _teamId == widget.match.homeTeamId
                      ? widget.match.homeTeamName
                      : widget.match.awayTeamName,
                  onTap: _isLoading
                      ? null
                      : () async {
                          final picked = await _pickFromSheet<String>(
                            title: 'Takım Seçimi',
                            selected: _teamId,
                            options: [
                              _PickerOption(
                                widget.match.homeTeamId,
                                widget.match.homeTeamName,
                              ),
                              _PickerOption(
                                widget.match.awayTeamId,
                                widget.match.awayTeamName,
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
                const SizedBox(height: 12),
                _selectorTile(
                  label: _eventType == 'substitution'
                      ? 'Çıkan Oyuncu'
                      : 'Futbolcu Seçimi',
                  valueText: _selectedPlayer == null
                      ? (players.isEmpty ? 'Önce esame/kadro girin' : 'Seçiniz')
                      : _labelFor(_selectedPlayer!),
                  onTap: enabled
                      ? () async {
                          final picked = await _pickFromSheet<LineupPlayer>(
                            title: 'Futbolcu Seçimi',
                            selected: _selectedPlayer,
                            options: [
                              for (final p in (_eventType == 'substitution'
                                  ? startingPlayers
                                  : players))
                                _PickerOption(p, _labelFor(p)),
                            ],
                          );
                          if (picked == null || !mounted) return;
                          setState(() => _selectedPlayer = picked);
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                Visibility(
                  visible: _eventType == 'substitution',
                  child: _selectorTile(
                    label: 'Giren Oyuncu',
                    valueText: _selectedSubIn == null
                        ? (subsPlayers.isEmpty ? 'Yedek yok' : 'Seçiniz')
                        : _labelFor(_selectedSubIn!),
                    onTap: (subsPlayers.isNotEmpty && !_isLoading)
                        ? () async {
                            final picked = await _pickFromSheet<LineupPlayer>(
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
                ),
                if (_eventType == 'substitution') const SizedBox(height: 12),
                _ModernInput(
                  label: 'Dakika',
                  controller: _minuteController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                ),
                const SizedBox(height: 12),
                _selectorTile(
                  label: 'Olay Türü',
                  valueText: _eventType == 'goal'
                      ? 'Gol'
                      : _eventType == 'assist'
                      ? 'Asist'
                      : _eventType == 'yellow_card'
                      ? 'Sarı Kart'
                      : _eventType == 'man_of_the_match'
                      ? 'Maçın Adamı'
                      : _eventType == 'substitution'
                      ? 'Oyuncu Değişikliği'
                      : 'Kırmızı Kart',
                  onTap: _isLoading
                      ? null
                      : () async {
                          final picked = await _pickFromSheet<String>(
                            title: 'Olay Türü',
                            selected: _eventType,
                            options: const [
                              _PickerOption('goal', 'Gol'),
                              _PickerOption('assist', 'Asist'),
                              _PickerOption('yellow_card', 'Sarı Kart'),
                              _PickerOption('red_card', 'Kırmızı Kart'),
                              _PickerOption('man_of_the_match', 'Maçın Adamı'),
                              _PickerOption('substitution', 'Oyuncu Değişikliği'),
                            ],
                          );
                          if (picked == null || !mounted) return;
                          setState(() {
                            _eventType = picked;
                            if (_eventType != 'goal') _selectedAssist = null;
                            if (_eventType != 'goal') _isOwnGoal = false;
                            if (_eventType != 'substitution') _selectedSubIn = null;
                          });
                        },
                ),
                const SizedBox(height: 12),
                Visibility(
                  visible: _eventType == 'goal',
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    elevation: 0.5,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Kendi kalesine (KK)',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Switch(
                            value: _isOwnGoal,
                            onChanged: _isLoading
                                ? null
                                : (v) => setState(() {
                                    _isOwnGoal = v;
                                    if (_isOwnGoal) _selectedAssist = null;
                                  }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_eventType == 'goal') const SizedBox(height: 12),
                Visibility(
                  visible: _eventType == 'goal' && !_isOwnGoal,
                  child: _selectorTile(
                    label: 'Asist Yapan',
                    valueText: _selectedAssist == null
                        ? 'Seçiniz'
                        : _labelFor(_selectedAssist!),
                    onTap: enabled
                        ? () async {
                            final picked = await _pickFromSheet<LineupPlayer>(
                              title: 'Asist Yapan',
                              selected: _selectedAssist,
                              options: [
                                for (final p in players)
                                  _PickerOption(p, _labelFor(p)),
                              ],
                            );
                            if (picked == null || !mounted) return;
                            setState(() => _selectedAssist = picked);
                          }
                        : null,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _addEvent,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  child: const Text('Kaydet'),
                ),
              ],
            ),
    );
  }
}

class _PickerOption<T> {
  const _PickerOption(this.value, this.label);
  final T value;
  final String label;
}

class _ModernInput extends StatelessWidget {
  const _ModernInput({
    required this.label,
    required this.controller,
    required this.keyboardType,
    required this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: cs.surfaceContainerLow,
          elevation: 0.5,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}
