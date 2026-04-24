import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/match.dart';
import '../services/interfaces/i_match_service.dart';
import '../services/interfaces/i_team_service.dart';
import '../services/service_locator.dart';
import '../widgets/web_safe_image.dart';

class FormationPlayer {
  final String id;
  final String name;
  final String number;
  final String? position;
  final String? photoUrl;

  const FormationPlayer({
    required this.id,
    required this.name,
    required this.number,
    this.position,
    this.photoUrl,
  });

  FormationPlayer copyWith({
    String? id,
    String? name,
    String? number,
    String? position,
    String? photoUrl,
  }) {
    return FormationPlayer(
      id: id ?? this.id,
      name: name ?? this.name,
      number: number ?? this.number,
      position: position ?? this.position,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}

class FormationTab extends StatefulWidget {
  final String matchId;
  final String tournamentId;
  final String homeTeamId;
  final String awayTeamId;
  final bool isTeamManager;
  final List<FormationPlayer> homePlayers;
  final List<FormationPlayer> awayPlayers;
  final String initialHomeFormation;
  final String initialAwayFormation;
  final List<String> initialHomeOrder;
  final List<String> initialAwayOrder;

  const FormationTab({
    super.key,
    required this.matchId,
    required this.tournamentId,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.isTeamManager,
    required this.homePlayers,
    required this.awayPlayers,
    this.initialHomeFormation = '4-4-2',
    this.initialAwayFormation = '4-4-2',
    this.initialHomeOrder = const <String>[],
    this.initialAwayOrder = const <String>[],
  });

  factory FormationTab.fromMatch({
    Key? key,
    required MatchModel match,
    required bool isTeamManager,
  }) {
    List<FormationPlayer> mapLineup(MatchLineup? detail, List<String> phones) {
      if (detail != null && detail.starting.isNotEmpty) {
        return detail.starting
            .map(
              (p) => FormationPlayer(
                id: p.playerId,
                name: p.name,
                number: (p.number ?? '').toString(),
              ),
            )
            .toList();
      }
      if (phones.isNotEmpty) {
        return phones
            .map(
              (phone) => FormationPlayer(
                id: phone,
                name: phone,
                number: '',
              ),
            )
            .toList();
      }
      return const <FormationPlayer>[];
    }

    final home = mapLineup(match.homeLineupDetail, match.homeLineup);
    final away = mapLineup(match.awayLineupDetail, match.awayLineup);

    return FormationTab(
      key: key,
      matchId: match.id,
      tournamentId: match.leagueId,
      homeTeamId: match.homeTeamId,
      awayTeamId: match.awayTeamId,
      isTeamManager: isTeamManager,
      homePlayers: home,
      awayPlayers: away,
      initialHomeFormation: match.homeFormation ?? '4-4-2',
      initialAwayFormation: match.awayFormation ?? '4-4-2',
      initialHomeOrder: match.homeFormationOrder,
      initialAwayOrder: match.awayFormationOrder,
    );
  }

  @override
  State<FormationTab> createState() => _FormationTabState();
}

class _FormationTabState extends State<FormationTab> {
  final IMatchService _matchService = ServiceLocator.matchService;
  final ITeamService _teamService = ServiceLocator.teamService;
  Timer? _persistTimer;

  late String _homeFormation;
  late String _awayFormation;

  late List<FormationPlayer> _homePlayers;
  late List<FormationPlayer> _awayPlayers;
  late List<FormationPlayer> _homeDefault;
  late List<FormationPlayer> _awayDefault;

  String _compactName(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty) return '';
    final parts = s.split(' ').where((e) => e.trim().isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return _cap(parts.first);
    final first = _cap(parts.first);
    final last = parts.last.trim();
    final initial = last.isEmpty ? '' : _cap(last.substring(0, 1));
    if (initial.isEmpty) return first;
    return '$first $initial.';
  }

  String _cap(String v) {
    final s = v.trim();
    if (s.isEmpty) return '';
    if (s.length == 1) return s.toUpperCase();
    return s.substring(0, 1).toUpperCase() + s.substring(1).toLowerCase();
  }

  List<FormationPlayer> _applyOrder(
    List<FormationPlayer> players,
    List<String> order,
  ) {
    if (order.isEmpty) return players;
    final byId = <String, FormationPlayer>{
      for (final p in players) p.id: p,
    };
    final used = <String>{};
    final out = <FormationPlayer>[];
    for (final id in order) {
      final key = id.trim();
      final p = byId[key];
      if (p == null) continue;
      if (used.contains(key)) continue;
      used.add(key);
      out.add(p);
    }
    for (final p in players) {
      if (!used.contains(p.id)) out.add(p);
    }
    return out;
  }

  List<FormationPlayer> _ensureEleven(List<FormationPlayer> players, {required bool isHome}) {
    var list = players;
    if (list.length > 11) {
      list = list.sublist(0, 11);
    } else if (list.length < 11) {
      final missing = 11 - list.length;
      list = [
        ...list,
        ...List<FormationPlayer>.generate(
          missing,
          (i) => FormationPlayer(
            id: '${isHome ? 'home' : 'away'}_placeholder_$i',
            name: 'Oyuncu',
            number: '${i + 1}',
            position: null,
            photoUrl: null,
          ),
        ),
      ];
    }
    return list;
  }

  List<FormationPlayer> _enrichFromRoster(
    List<FormationPlayer> base,
    Map<String, PlayerModel> rosterById,
  ) {
    return base.map((p) {
      final r = rosterById[p.id];
      if (r == null) return p;
      final name = (p.name.trim().isEmpty || p.name.trim() == p.id || p.name.trim() == 'Oyuncu')
          ? r.name
          : p.name;
      final number = (p.number.trim().isEmpty) ? (r.number ?? '') : p.number;
      final position = (r.mainPosition ?? r.position)?.trim();
      final photoUrl = (r.photoUrl ?? '').trim();
      return p.copyWith(
        name: name,
        number: number,
        position: position != null && position.isNotEmpty ? position : null,
        photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
      );
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _homeFormation = widget.initialHomeFormation;
    _awayFormation = widget.initialAwayFormation;

    _homePlayers = _applyOrder(
      List<FormationPlayer>.from(widget.homePlayers),
      widget.initialHomeOrder,
    );
    _awayPlayers = _applyOrder(
      List<FormationPlayer>.from(widget.awayPlayers),
      widget.initialAwayOrder,
    );

    _homePlayers = _ensureEleven(_homePlayers, isHome: true);
    _awayPlayers = _ensureEleven(_awayPlayers, isHome: false);

    _homeDefault = _homePlayers.map((e) => e.copyWith()).toList();
    _awayDefault = _awayPlayers.map((e) => e.copyWith()).toList();
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }

  void _schedulePersist({required bool home, required bool away}) {
    if (!widget.isTeamManager) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 450), () async {
      final homeOrder = _homePlayers.map((e) => e.id).toList();
      final awayOrder = _awayPlayers.map((e) => e.id).toList();
      try {
        await _matchService.updateMatchFormationState(
          matchId: widget.matchId,
          homeFormation: home ? _homeFormation : null,
          awayFormation: away ? _awayFormation : null,
          homeOrder: home ? homeOrder : null,
          awayOrder: away ? awayOrder : null,
        );
      } catch (_) {}
    });
  }

  void _swapPlayers(bool isHome, int fromIndex, int toIndex) {
    if (!widget.isTeamManager) return;
    if (fromIndex == toIndex) return;
    setState(() {
      final list = isHome ? _homePlayers : _awayPlayers;
      final tmp = list[fromIndex];
      list[fromIndex] = list[toIndex];
      list[toIndex] = tmp;
    });
    _schedulePersist(home: isHome, away: !isHome);
  }

  void _resetPositions() {
    setState(() {
      _homePlayers = _homeDefault.map((e) => e.copyWith()).toList();
      _awayPlayers = _awayDefault.map((e) => e.copyWith()).toList();
    });
    _schedulePersist(home: true, away: true);
  }

  @override
  Widget build(BuildContext context) {
    final formations = FormationLayout.availableFormations;

    return StreamBuilder<List<PlayerModel>>(
      stream: _teamService.watchPlayers(
        teamId: widget.homeTeamId,
        tournamentId: widget.tournamentId,
      ),
      builder: (context, homeSnap) {
        final homeRoster = homeSnap.data ?? const <PlayerModel>[];
        final homeById = <String, PlayerModel>{
          for (final p in homeRoster)
            ((p.phone ?? '').trim().isNotEmpty ? p.phone!.trim() : p.id.trim()): p,
        };

        return StreamBuilder<List<PlayerModel>>(
          stream: _teamService.watchPlayers(
            teamId: widget.awayTeamId,
            tournamentId: widget.tournamentId,
          ),
          builder: (context, awaySnap) {
            final awayRoster = awaySnap.data ?? const <PlayerModel>[];
            final awayById = <String, PlayerModel>{
              for (final p in awayRoster)
                ((p.phone ?? '').trim().isNotEmpty ? p.phone!.trim() : p.id.trim()): p,
            };

            final homePlayers = _enrichFromRoster(_homePlayers, homeById);
            final awayPlayers = _enrichFromRoster(_awayPlayers, awayById);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  _buildPitchSection(
                    context: context,
                    isHome: true,
                    players: homePlayers,
                    formation: _homeFormation,
                    onFormationChanged: widget.isTeamManager
                        ? (val) {
                            setState(() {
                              _homeFormation = val;
                            });
                            _schedulePersist(home: true, away: false);
                          }
                        : null,
                    formations: formations,
                    isTeamManager: widget.isTeamManager,
                  ),
                  const SizedBox(height: 32),
                  const SizedBox(height: 12),
                  _buildPitchSection(
                    context: context,
                    isHome: false,
                    players: awayPlayers,
                    formation: _awayFormation,
                    onFormationChanged: widget.isTeamManager
                        ? (val) {
                            setState(() {
                              _awayFormation = val;
                            });
                            _schedulePersist(home: false, away: true);
                          }
                        : null,
                    formations: formations,
                    isTeamManager: widget.isTeamManager,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _resetPositions,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Konumları Sıfırla'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPitchSection({
    required BuildContext context,
    required bool isHome,
    required List<FormationPlayer> players,
    required String formation,
    required List<String> formations,
    required bool isTeamManager,
    required ValueChanged<String>? onFormationChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 6 / 5,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final coords = FormationLayout.coordinatesForHalf(
                formation,
                goalAtTop: isHome,
              );

              return ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    CustomPaint(
                      size: Size.infinite,
                      painter: HalfPitchPainter(goalAtTop: isHome),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _FormationPanel(
                        value: formation,
                        isEditable: isTeamManager,
                        items: formations,
                        onChanged: onFormationChanged,
                      ),
                    ),
                    ...coords.asMap().entries.map(
                      (entry) {
                        final index = entry.key;
                        final pos = entry.value;
                        final player = players[index];

                        const tokenW = 52.0;
                        final left = pos.dx * constraints.maxWidth - (tokenW / 2);
                        final top = pos.dy * constraints.maxHeight - (tokenW / 2);

                        final token = _PlayerToken(
                          number: player.number,
                          name: _compactName(player.name),
                          position: player.position,
                          photoUrl: player.photoUrl,
                          isHome: isHome,
                        );

                        final draggableChild = isTeamManager
                            ? Draggable<_DragData>(
                                data: _DragData(
                                  isHome: isHome,
                                  index: index,
                                ),
                                feedback: Material(
                                  type: MaterialType.transparency,
                                  child: _PlayerToken(
                                    number: player.number,
                                    name: _compactName(player.name),
                                    position: player.position,
                                    photoUrl: player.photoUrl,
                                    isHome: isHome,
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.4,
                                  child: token,
                                ),
                                child: token,
                              )
                            : token;

                        return Positioned(
                          left: left.clamp(0.0, constraints.maxWidth - tokenW),
                          top: top.clamp(0.0, constraints.maxHeight - tokenW),
                          width: tokenW,
                          child: DragTarget<_DragData>(
                            onWillAccept: (data) {
                              if (!isTeamManager) return false;
                              if (data == null) return false;
                              return data.isHome == isHome;
                            },
                            onAccept: (data) {
                              _swapPlayers(isHome, data.index, index);
                            },
                            builder: (context, candidateData, rejectedData) {
                              return draggableChild;
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FormationPanel extends StatelessWidget {
  final String value;
  final bool isEditable;
  final List<String> items;
  final ValueChanged<String>? onChanged;

  const _FormationPanel({
    required this.value,
    required this.isEditable,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = items.contains(value) ? value : items.first;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 96),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: isEditable
              ? DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: v,
                    isDense: true,
                    dropdownColor: cs.surface,
                    iconEnabledColor: Colors.white,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                    items: items
                        .map(
                          (f) => DropdownMenuItem(
                            value: f,
                            child: Text(f),
                          ),
                        )
                        .toList(),
                    onChanged: (nv) {
                      if (nv == null) return;
                      onChanged?.call(nv);
                    },
                  ),
                )
              : Text(
                  v,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
        ),
      ),
    );
  }
}

class _DragData {
  final bool isHome;
  final int index;

  _DragData({
    required this.isHome,
    required this.index,
  });
}

class _PlayerToken extends StatelessWidget {
  final String number;
  final String name;
  final String? position;
  final String? photoUrl;
  final bool isHome;

  const _PlayerToken({
    required this.number,
    required this.name,
    required this.position,
    required this.photoUrl,
    required this.isHome,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isHome ? Colors.green.shade700 : Colors.blue.shade700;
    final img = (photoUrl ?? '').trim();
    final pos = (position ?? '').trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          child: img.isEmpty
              ? Text(
                  number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    WebSafeImage(
                      url: img,
                      width: 28,
                      height: 28,
                      isCircle: true,
                      fit: BoxFit.cover,
                      fallbackIconSize: 14,
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        margin: const EdgeInsets.only(right: 1, bottom: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          number,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        if (pos.isNotEmpty) ...[
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Text(
              pos,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 7,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
        const SizedBox(height: 2),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class HalfPitchPainter extends CustomPainter {
  final bool goalAtTop;

  HalfPitchPainter({required this.goalAtTop});

  @override
  void paint(Canvas canvas, Size size) {
    final baseGreen = const Color(0xFF15803D);
    final lightGreen = const Color(0xFF16A34A);
    final stripeWidth = size.width / 6;

    for (int i = 0; i < 6; i++) {
      final paint = Paint()
        ..color = i.isEven ? baseGreen : lightGreen;
      final rect = Rect.fromLTWH(
        i * stripeWidth,
        0,
        stripeWidth,
        size.height,
      );
      canvas.drawRect(rect, paint);
    }

    final linePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final pitchRect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    canvas.drawRect(pitchRect, linePaint);

    final centerX = pitchRect.center.dx;

    final goalLineY = goalAtTop ? pitchRect.top : pitchRect.bottom;
    final centerLineY = goalAtTop ? pitchRect.bottom : pitchRect.top;

    canvas.drawLine(
      Offset(pitchRect.left, centerLineY),
      Offset(pitchRect.right, centerLineY),
      linePaint,
    );

    final r = pitchRect.height * 0.22;
    final circleRect = Rect.fromCircle(center: Offset(centerX, centerLineY), radius: r);
    final start = goalAtTop ? math.pi : 0.0;
    final sweep = goalAtTop ? -math.pi : math.pi;
    canvas.drawArc(circleRect, start, sweep, false, linePaint);

    final penaltyBoxWidth = pitchRect.width * 0.62;
    final penaltyBoxHeight = pitchRect.height * 0.46;
    final sixBoxWidth = pitchRect.width * 0.32;
    final sixBoxHeight = pitchRect.height * 0.22;

    final pbTop = goalAtTop ? pitchRect.top : (pitchRect.bottom - penaltyBoxHeight);
    final sbTop = goalAtTop ? pitchRect.top : (pitchRect.bottom - sixBoxHeight);

    final penaltyBox = Rect.fromLTWH(
      centerX - penaltyBoxWidth / 2,
      pbTop,
      penaltyBoxWidth,
      penaltyBoxHeight,
    );
    final sixBox = Rect.fromLTWH(
      centerX - sixBoxWidth / 2,
      sbTop,
      sixBoxWidth,
      sixBoxHeight,
    );

    canvas.drawRect(penaltyBox, linePaint);
    canvas.drawRect(sixBox, linePaint);
  }

  @override
  bool shouldRepaint(covariant HalfPitchPainter oldDelegate) =>
      oldDelegate.goalAtTop != goalAtTop;
}

class FormationLayout {
  static const List<String> availableFormations = [
    '4-4-2',
    '4-2-3-1',
    '4-3-3',
    '3-5-2',
  ];

  static List<int> _parseFormation(String formation) {
    final s = formation.trim();
    if (s.isEmpty) return const <int>[];
    final parts = s.split('-').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final out = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n <= 0) return const <int>[];
      out.add(n);
    }
    return out;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static List<Offset> coordinatesForHalf(String formation, {required bool goalAtTop}) {
    final parsed = _parseFormation(formation);
    final lines = parsed.isEmpty ? const <int>[4, 4, 2] : parsed;

    final out = <Offset>[];
    final gkY = goalAtTop ? 0.16 : 0.84;
    out.add(const Offset(0.5, 0).translate(0, gkY));

    final n = lines.length;
    final startY = goalAtTop ? 0.28 : 0.72;
    final endY = goalAtTop ? 0.94 : 0.06;

    for (int li = 0; li < n; li++) {
      final count = lines[li];
      final t = n == 1 ? 0.5 : (li / (n - 1));
      final y = _lerp(startY, endY, t);
      for (int i = 0; i < count; i++) {
        final x = (i + 1) / (count + 1);
        out.add(Offset(x, y));
      }
    }

    if (out.length > 11) return out.sublist(0, 11);
    if (out.length < 11) {
      final missing = 11 - out.length;
      for (int i = 0; i < missing; i++) {
        out.add(Offset(0.5, goalAtTop ? 0.6 : 0.4));
      }
    }
    return out;
  }
}
