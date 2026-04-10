import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/match.dart';
import '../services/database_service.dart';

class AdminMatchLineupScreen extends StatefulWidget {
  const AdminMatchLineupScreen({
    super.key,
    required this.match,
    required this.isHome,
    this.initialTabIndex = 0,
  });

  final MatchModel match;
  final bool isHome;
  final int initialTabIndex;

  @override
  State<AdminMatchLineupScreen> createState() => _AdminMatchLineupScreenState();
}

class _LineupEntry {
  _LineupEntry({required this.playerId, required this.name, this.number});

  final String playerId;
  final String name;
  String? number;
}

class _AdminMatchLineupScreenState extends State<AdminMatchLineupScreen>
    with SingleTickerProviderStateMixin {
  final _dbService = DatabaseService();

  bool _saving = false;
  String? _activeNumberEditPlayerId;

  late final TabController _tabController;
  final List<_LineupEntry> _starting = [];
  final List<_LineupEntry> _subs = [];
  final Map<String, TextEditingController> _numberControllers = {};
  final Map<String, FocusNode> _numberFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );

    final existing = widget.isHome
        ? widget.match.homeLineup
        : widget.match.awayLineup;
    for (final p in existing?.starting ?? const <LineupPlayer>[]) {
      _starting.add(
        _LineupEntry(playerId: p.playerId, name: p.name, number: p.number),
      );
    }
    for (final p in existing?.subs ?? const <LineupPlayer>[]) {
      _subs.add(
        _LineupEntry(playerId: p.playerId, name: p.name, number: p.number),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _numberControllers.values) {
      c.dispose();
    }
    for (final f in _numberFocusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerForPlayer(String playerId, String? initialNumber) {
    return _numberControllers.putIfAbsent(
      playerId,
      () => TextEditingController(text: (initialNumber ?? '').trim()),
    );
  }

  TextEditingController _syncControllerText(
    String playerId,
    String? initialNumber,
  ) {
    final text = (initialNumber ?? '').trim();
    final c = _controllerForPlayer(playerId, text);
    if (c.text != text) c.text = text;
    return c;
  }

  FocusNode _focusNodeFor(String playerId) {
    return _numberFocusNodes.putIfAbsent(playerId, () => FocusNode());
  }

  bool _isSelectedInStarting(String playerId) =>
      _starting.any((e) => e.playerId == playerId);
  bool _isSelectedInSubs(String playerId) =>
      _subs.any((e) => e.playerId == playerId);

  void _removeFrom(List<_LineupEntry> list, String playerId) {
    setState(() {
      list.removeWhere((e) => e.playerId == playerId);
      if (_activeNumberEditPlayerId == playerId) {
        _activeNumberEditPlayerId = null;
      }
    });
  }

  void _addToStarting(PlayerModel p) {
    if (_isSelectedInStarting(p.id) || _isSelectedInSubs(p.id)) return;
    if (_starting.length >= 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İlk 11 en fazla 11 kişi olabilir.')),
      );
      return;
    }
    setState(
      () => _starting.add(
        _LineupEntry(playerId: p.id, name: p.name, number: p.number),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _syncControllerText(p.id, p.number);
      setState(() => _activeNumberEditPlayerId = p.id);
      _focusNodeFor(p.id).requestFocus();
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
    });
  }

  void _addToSubs(PlayerModel p) {
    if (_isSelectedInSubs(p.id) || _isSelectedInStarting(p.id)) return;
    if (_subs.length >= 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yedekler en fazla 7 kişi olabilir.')),
      );
      return;
    }
    setState(
      () => _subs.add(
        _LineupEntry(playerId: p.id, name: p.name, number: p.number),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _syncControllerText(p.id, p.number);
      setState(() => _activeNumberEditPlayerId = p.id);
      _focusNodeFor(p.id).requestFocus();
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
    });
  }

  Future<void> _save() async {
    if (_starting.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İlk 11 için tam 11 kişi seçmelisiniz.')),
      );
      return;
    }
    if (_subs.length > 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yedekler en fazla 7 kişi olabilir.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      for (final e in [..._starting, ..._subs]) {
        final c = _numberControllers[e.playerId];
        if (c != null) e.number = c.text.trim().isEmpty ? null : c.text.trim();
      }

      final lineup = MatchLineup(
        starting: _starting
            .map(
              (e) => LineupPlayer(
                playerId: e.playerId,
                name: e.name,
                number: e.number,
              ),
            )
            .toList(),
        subs: _subs
            .map(
              (e) => LineupPlayer(
                playerId: e.playerId,
                name: e.name,
                number: e.number,
              ),
            )
            .toList(),
      );

      await _dbService.updateMatchLineup(
        matchId: widget.match.id,
        isHome: widget.isHome,
        lineup: lineup,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _availableList(
    List<PlayerModel> players, {
    required bool isStartingTab,
  }) {
    final otherSelectedIds = (isStartingTab ? _subs : _starting)
        .map((e) => e.playerId)
        .toSet();
    final selectedIds = (isStartingTab ? _starting : _subs)
        .map((e) => e.playerId)
        .toSet();
    final selectedNumberById = {
      for (final e in (isStartingTab ? _starting : _subs)) e.playerId: e.number,
    };

    final filtered = isStartingTab
        ? [...players]
        : players.where((p) => !_isSelectedInStarting(p.id)).toList();

    final sorted = [...filtered]
      ..sort((a, b) {
        final an = int.tryParse((a.number ?? '').trim()) ?? 9999;
        final bn = int.tryParse((b.number ?? '').trim()) ?? 9999;
        return an.compareTo(bn);
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Oyuncu Listesi',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  'Seçilen: ${selectedIds.length}/${isStartingTab ? 11 : 7}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (sorted.isEmpty)
              const Text('Bu takımın oyuncu listesi boş.')
            else
              for (final p in sorted)
                InkWell(
                  onTap: _saving
                      ? null
                      : () {
                          if (otherSelectedIds.contains(p.id)) return;
                          if (p.suspendedMatches > 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Bu oyuncu ${p.suspendedMatches} maç cezalıdır, kadroya eklenemez!',
                                ),
                              ),
                            );
                            return;
                          }
                          if (selectedIds.contains(p.id)) {
                            _removeFrom(isStartingTab ? _starting : _subs, p.id);
                            return;
                          }
                          if (isStartingTab) {
                            _addToStarting(p);
                          } else {
                            _addToSubs(p);
                          }
                        },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selectedIds.contains(p.id)
                            ? Colors.green.shade100
                            : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          if (selectedIds.contains(p.id))
                            SizedBox(
                              width: 56,
                              child: TextField(
                                controller: _controllerForPlayer(
                                  p.id,
                                  selectedNumberById[p.id] ?? p.number,
                                ),
                                focusNode: _focusNodeFor(p.id),
                                enabled: !_saving,
                                decoration: InputDecoration(
                                  isDense: true,
                                  counterText: '',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(2),
                                ],
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            SizedBox(
                              width: 56,
                              child: Text(
                                (p.number ?? '').trim(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: (p.suspendedMatches > 0 ||
                                        otherSelectedIds.contains(p.id))
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (p.suspendedMatches > 0 || otherSelectedIds.contains(p.id))
                            Icon(
                              p.suspendedMatches > 0
                                  ? Icons.lock_outline
                                  : Icons.block_rounded,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            )
                          else if (selectedIds.contains(p.id))
                            Icon(
                              Icons.check_circle_rounded,
                              color: Colors.green.shade800,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teamName = widget.isHome
        ? widget.match.homeTeamName
        : widget.match.awayTeamName;
    final teamId = widget.isHome
        ? widget.match.homeTeamId
        : widget.match.awayTeamId;

    return Scaffold(
      appBar: AppBar(
        title: Text('Kadro: $teamName'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'İlk 11'),
            Tab(text: 'Yedekler'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _saving
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Kaydet',
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                  ),
          ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StreamBuilder<List<PlayerModel>>(
        stream: _dbService.getPlayers(teamId),
        builder: (context, snapshot) {
          final players = snapshot.data ?? const <PlayerModel>[];
          return TabBarView(
            controller: _tabController,
            children: [
              ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _availableList(players, isStartingTab: true),
                ],
              ),
              ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _availableList(players, isStartingTab: false),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
