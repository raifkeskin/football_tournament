import 'package:flutter/material.dart';
import '../models/league.dart';
import '../models/league_extras.dart';
import '../models/match.dart';
import '../models/team.dart';
import '../services/app_session.dart';
import '../services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../services/interfaces/i_team_service.dart';
import '../services/service_locator.dart';

class AdminFixtureEntryScreen extends StatefulWidget {
  const AdminFixtureEntryScreen({
    super.key,
    this.initialLeagueId,
    this.lockLeagueSelection = false,
  });

  final String? initialLeagueId;
  final bool lockLeagueSelection;

  @override
  State<AdminFixtureEntryScreen> createState() =>
      _AdminFixtureEntryScreenState();
}

class _AdminFixtureEntryScreenState extends State<AdminFixtureEntryScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final IMatchService _matchService = ServiceLocator.matchService;
  final ITeamService _teamService = ServiceLocator.teamService;
  String? _selectedLeagueId;
  String? _selectedGroupId;
  String? _homeTeamId;
  String? _awayTeamId;
  String? _selectedPitchId;
  String? _selectedPitchName;
  bool _unknownDateTime = false;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialLeagueId ?? '').trim();
    if (initial.isNotEmpty) {
      _selectedLeagueId = initial;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fikstür Planlama')),
        body: const Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    const headerForest = Color(0xFF064E3B);
    final base = Theme.of(context);
    final themed = base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        labelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        hintStyle: const TextStyle(color: Colors.white70),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Fikstür Planlama')),
      backgroundColor: const Color(0xFF0F172A),
      body: Theme(
        data: themed,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                // 1. Turnuva
                StreamBuilder<List<League>>(
                  stream: _leagueService.watchLeagues(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox();
                    final leagues = snapshot.data ?? const <League>[];
                    return DropdownButtonFormField<String>(
                      initialValue: _selectedLeagueId,
                      decoration: const InputDecoration(labelText: 'Turnuva'),
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      items: leagues
                          .map(
                            (l) => DropdownMenuItem(
                              value: l.id,
                              child: Text(
                                l.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: widget.lockLeagueSelection
                          ? null
                          : (val) => setState(() {
                                _selectedLeagueId = val;
                                _selectedGroupId = null;
                              }),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // 2. Grup
                if (_selectedLeagueId != null)
                  StreamBuilder<List<GroupModel>>(
                    stream: _leagueService.watchGroups(_selectedLeagueId!),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      final groups = [...snapshot.data!]
                        ..sort(
                          (a, b) => a.name.toLowerCase().compareTo(
                            b.name.toLowerCase(),
                          ),
                        );
                      return DropdownButtonFormField<String>(
                        initialValue: _selectedGroupId,
                        decoration: const InputDecoration(labelText: 'Grup'),
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        items: groups
                            .map(
                              (g) => DropdownMenuItem(
                                value: g.id,
                                child: Text(
                                  g.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) => setState(() {
                          _selectedGroupId = val;
                          _homeTeamId = null;
                          _awayTeamId = null;
                        }),
                        menuMaxHeight: 360,
                      );
                    },
                  ),
                const SizedBox(height: 16),

                // 3. Takımlar
                if (_selectedGroupId != null)
                  StreamBuilder<List<Team>>(
                    stream: _teamService.watchTeamsByGroup(_selectedGroupId!),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      final teams = snapshot.data!;
                      return Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _homeTeamId,
                            decoration: const InputDecoration(labelText: 'Ev Sahibi'),
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            items: teams
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text(
                                      t.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _homeTeamId = val),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _awayTeamId,
                            decoration: const InputDecoration(labelText: 'Deplasman'),
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            items: teams
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text(
                                      t.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _awayTeamId = val),
                          ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 16),

                StreamBuilder<List<Pitch>>(
                  stream: _leagueService.watchPitches(),
                  builder: (context, snapshot) {
                    final pitches = snapshot.data ?? const <Pitch>[];
                    return DropdownButtonFormField<String?>(
                      key: ValueKey(_selectedPitchId),
                      initialValue: _selectedPitchId,
                      decoration: const InputDecoration(labelText: 'Saha Seç'),
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'Saha Seçilmedi',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        for (final p in pitches)
                          DropdownMenuItem<String?>(
                            value: p.id,
                            child: Text(
                              p.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        final selected = pitches.where((e) => e.id == v).toList(growable: false);
                        final name = selected.isEmpty ? '' : selected.first.name.trim();
                        setState(() {
                          _selectedPitchId = v;
                          _selectedPitchName = v == null || name.isEmpty ? null : name;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  value: _unknownDateTime,
                  onChanged: (v) => setState(() => _unknownDateTime = v),
                  title: const Text(
                    'Tarih ve saat belirlenmedi',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // 4. Tarih & Saat
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _unknownDateTime ? null : _pickDate,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _unknownDateTime ? null : _pickTime,
                        icon: const Icon(Icons.access_time),
                        label: Text(
                          _selectedTime.format(context),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                ElevatedButton(
                  onPressed: _saveFixture,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: headerForest,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  child: const Text('Maçı Kaydet / Planla'),
                ),
              ],
            ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _saveFixture() async {
    if (_selectedLeagueId == null ||
        _selectedGroupId == null ||
        _homeTeamId == null ||
        _awayTeamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tüm alanları seçin.')),
      );
      return;
    }
    if (_homeTeamId == _awayTeamId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ev sahibi ve deplasman aynı olamaz.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final matchDateTime = _unknownDateTime
          ? null
          : DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              _selectedTime.hour,
              _selectedTime.minute,
            );

      // Takım isimlerini ve logolarını çek (MatchModel için gerekli)
      final home = await _teamService.getTeamOnce(_homeTeamId!);
      final away = await _teamService.getTeamOnce(_awayTeamId!);
      if (home == null || away == null) {
        throw Exception('Takım bilgisi alınamadı.');
      }

      String logoFromTeam(Team team) {
        final raw = team.logoUrl.trim();
        if (raw.isEmpty) return '';
        if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
        return 'https://$raw';
      }

      final match = MatchModel(
        id: '',
        leagueId: _selectedLeagueId!,
        groupId: _selectedGroupId!,
        homeTeamId: _homeTeamId!,
        homeTeamName: home.name,
        homeTeamLogoUrl: logoFromTeam(home),
        awayTeamId: _awayTeamId!,
        awayTeamName: away.name,
        awayTeamLogoUrl: logoFromTeam(away),
        homeScore: 0,
        awayScore: 0,
        matchDate: matchDateTime == null
            ? null
            : "${matchDateTime.year}-${matchDateTime.month.toString().padLeft(2, '0')}-${matchDateTime.day.toString().padLeft(2, '0')}",
        matchTime: matchDateTime == null
            ? null
            : '${matchDateTime.hour.toString().padLeft(2, '0')}:${matchDateTime.minute.toString().padLeft(2, '0')}',
        pitchId: _selectedPitchId,
        pitchName: _selectedPitchName,
        status: MatchStatus.notStarted,
      );

      await _matchService.addMatch(match);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maç başarıyla planlandı.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
