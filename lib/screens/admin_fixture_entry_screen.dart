import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/league.dart';
import '../models/match.dart';
import '../models/team.dart';
import '../services/database_service.dart';

class AdminFixtureEntryScreen extends StatefulWidget {
  const AdminFixtureEntryScreen({super.key});

  @override
  State<AdminFixtureEntryScreen> createState() =>
      _AdminFixtureEntryScreenState();
}

class _AdminFixtureEntryScreenState extends State<AdminFixtureEntryScreen> {
  final _dbService = DatabaseService();
  String? _selectedLeagueId;
  String? _selectedGroupId;
  String? _homeTeamId;
  String? _awayTeamId;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fikstür / Maç Planlama')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Turnuva
                StreamBuilder<QuerySnapshot>(
                  stream: _dbService.getLeagues(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox();
                    final leagues =
                        snapshot.data!.docs
                            .map(
                              (doc) => League.fromMap({
                                ...doc.data() as Map<String, dynamic>,
                                'id': doc.id,
                              }),
                            )
                            .toList()
                          ..sort(
                            (a, b) => a.name.toLowerCase().compareTo(
                              b.name.toLowerCase(),
                            ),
                          );
                    return DropdownButtonFormField<String>(
                      initialValue: _selectedLeagueId,
                      decoration: const InputDecoration(labelText: 'Turnuva'),
                      items: leagues
                          .map(
                            (l) => DropdownMenuItem(
                              value: l.id,
                              child: Text(l.name),
                            ),
                          )
                          .toList(),
                      onChanged: (val) => setState(() {
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
                    stream: _dbService.getGroups(_selectedLeagueId!),
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
                        items: groups
                            .map(
                              (g) => DropdownMenuItem(
                                value: g.id,
                                child: Text(g.name),
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
                    stream: _dbService.getTeamsByGroup(_selectedGroupId!),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      final teams = snapshot.data!;
                      return Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _homeTeamId,
                            decoration: const InputDecoration(labelText: 'Ev Sahibi'),
                            items: teams
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text(t.name),
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
                            items: teams
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text(t.name),
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

                // 4. Tarih & Saat
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickTime,
                        icon: const Icon(Icons.access_time),
                        label: Text(_selectedTime.format(context)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                ElevatedButton(
                  onPressed: _saveFixture,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Maçı Kaydet / Planla'),
                ),
              ],
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
      final matchDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      // Takım isimlerini ve logolarını çek (MatchModel için gerekli)
      final homeSnap = await FirebaseFirestore.instance
          .collection('teams')
          .doc(_homeTeamId)
          .get();
      final awaySnap = await FirebaseFirestore.instance
          .collection('teams')
          .doc(_awayTeamId)
          .get();

      final homeData = homeSnap.data()!;
      final awayData = awaySnap.data()!;

      String logoFrom(Map<String, dynamic> data) {
        final raw = (data['logoUrl'] ?? data['logo'] ?? '').toString().trim();
        if (raw.isEmpty) return '';
        if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
        return 'https://$raw';
      }

      final match = MatchModel(
        id: '',
        leagueId: _selectedLeagueId!,
        groupId: _selectedGroupId!,
        homeTeamId: _homeTeamId!,
        homeTeamName: homeData['name'],
        homeTeamLogoUrl: logoFrom(homeData),
        awayTeamId: _awayTeamId!,
        awayTeamName: awayData['name'],
        awayTeamLogoUrl: logoFrom(awayData),
        homeScore: 0,
        awayScore: 0,
        matchDate: matchDateTime,
        dateString:
            "${matchDateTime.year}-${matchDateTime.month.toString().padLeft(2, '0')}-${matchDateTime.day.toString().padLeft(2, '0')}",
        status: MatchStatus.notStarted,
      );

      await _dbService.addMatch(match);
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
