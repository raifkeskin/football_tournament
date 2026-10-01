import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../tournament/models/league.dart';
import '../../tournament/models/league_extras.dart';
import '../models/match.dart';
import '../../team/models/team.dart';
import '../../../core/services/app_session.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/app_date_picker.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

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
  final SupabaseClient _sb = Supabase.instance.client;
  late final Stream<List<League>> _leaguesStream = _leagueService
      .watchLeagues();
  late final Stream<List<Pitch>> _pitchesStream = _leagueService
      .watchPitches();

  String? _selectedLeagueId;
  String? _selectedSeasonId;
  String? _selectedGroupId;
  String? _homeTeamId;
  String? _awayTeamId;
  String? _selectedPitchId;
  String? _selectedPitchName;
  bool _unknownDateTime = false;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isLoading = false;
  final _weekController = TextEditingController();

  List<League> _leagues = const [];
  List<AdminOption> _seasons = const [];
  List<AdminOption> _groups = const [];
  List<Team> _teams = const [];
  bool _loadingSeasons = false;
  bool _loadingGroups = false;
  bool _loadingTeams = false;

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialLeagueId ?? '').trim();
    if (initial.isNotEmpty) _selectLeague(initial);
  }

  @override
  void dispose() {
    _weekController.dispose();
    super.dispose();
  }

  /// Fikstür ekranı maçları haftaya göre listeler; hafta boş olan maç hiçbir
  /// haftada görünmez. Varsayılan olarak turnuvadaki son haftanın bir sonrası.
  Future<void> _prefillWeek(String leagueId) async {
    final maxWeek = await _matchService.getFixtureMaxWeek(leagueId);
    if (!mounted || _selectedLeagueId != leagueId) return;
    setState(() => _weekController.text = '${(maxWeek ?? 0) + 1}');
  }

  // Turnuva → Sezon → Grup → Takımlar zinciri. Her adımda tek seçenek (ya da
  // varsayılan sezon) varsa otomatik seçilir ve bir sonraki adım yüklenir.

  Future<void> _selectLeague(String leagueId) async {
    setState(() {
      _selectedLeagueId = leagueId;
      _selectedSeasonId = null;
      _selectedGroupId = null;
      _homeTeamId = null;
      _awayTeamId = null;
      _seasons = const [];
      _groups = const [];
      _teams = const [];
      _loadingSeasons = true;
    });
    _prefillWeek(leagueId);
    try {
      final rows = await _sb
          .from('seasons')
          .select('id, name, is_default')
          .eq('league_id', leagueId)
          .order('start_date', ascending: false);
      if (!mounted || _selectedLeagueId != leagueId) return;
      final seasons = [
        for (final r in rows)
          (
            id: (r['id'] ?? '').toString(),
            name: (r['name'] ?? '').toString().trim(),
            isDefault: r['is_default'] == true,
          ),
      ];
      setState(() {
        _seasons = seasons;
        _loadingSeasons = false;
      });
      final auto = autoPickOption(seasons);
      if (auto != null) _selectSeason(auto);
    } catch (e) {
      if (!mounted || _selectedLeagueId != leagueId) return;
      setState(() => _loadingSeasons = false);
      _showError('Sezonlar yüklenemedi: $e');
    }
  }

  Future<void> _selectSeason(String seasonId) async {
    setState(() {
      _selectedSeasonId = seasonId;
      _selectedGroupId = null;
      _homeTeamId = null;
      _awayTeamId = null;
      _groups = const [];
      _teams = const [];
      _loadingGroups = true;
    });
    try {
      final rows = await _sb
          .from('groups')
          .select('id, name')
          .eq('season_id', seasonId)
          .order('name', ascending: true);
      if (!mounted || _selectedSeasonId != seasonId) return;
      final groups = [
        for (final r in rows)
          (
            id: (r['id'] ?? '').toString(),
            name: (r['name'] ?? '').toString().trim(),
            isDefault: false,
          ),
      ];
      setState(() {
        _groups = groups;
        _loadingGroups = false;
      });
      final auto = autoPickOption(groups);
      if (auto != null) _selectGroup(auto);
    } catch (e) {
      if (!mounted || _selectedSeasonId != seasonId) return;
      setState(() => _loadingGroups = false);
      _showError('Gruplar yüklenemedi: $e');
    }
  }

  Future<void> _selectGroup(String groupId) async {
    setState(() {
      _selectedGroupId = groupId;
      _homeTeamId = null;
      _awayTeamId = null;
      _teams = const [];
      _loadingTeams = true;
    });
    try {
      final teams = await _teamService.watchTeamsByGroup(groupId).first;
      if (!mounted || _selectedGroupId != groupId) return;
      setState(() {
        _teams = teams;
        _loadingTeams = false;
      });
    } catch (e) {
      if (!mounted || _selectedGroupId != groupId) return;
      setState(() => _loadingTeams = false);
      _showError('Takımlar yüklenemedi: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String? _nameOf(List<AdminOption> options, String? id) {
    for (final o in options) {
      if (o.id == id) return o.name;
    }
    return null;
  }

  String? _teamName(String? id) {
    for (final t in _teams) {
      if (t.id == id) return t.name;
    }
    return null;
  }

  Future<void> _pickOption({
    required String title,
    required List<AdminOption> options,
    required String? selected,
    required void Function(String id) onPicked,
  }) async {
    final picked = await showAdminOptionPicker<String>(
      context: context,
      title: title,
      items: options.map((o) => o.id).toList(),
      labelBuilder: (id) => _nameOf(options, id) ?? '',
      selected: selected,
    );
    if (picked != null && picked != selected) onPicked(picked);
  }

  Future<void> _pickTeam({required bool home}) async {
    final other = home ? _awayTeamId : _homeTeamId;
    final options = [
      for (final t in _teams)
        if (t.id != other) (id: t.id, name: t.name, isDefault: false),
    ];
    await _pickOption(
      title: home ? 'Ev Sahibi Seçin' : 'Deplasman Seçin',
      options: options,
      selected: home ? _homeTeamId : _awayTeamId,
      onPicked: (id) => setState(() {
        if (home) {
          _homeTeamId = id;
        } else {
          _awayTeamId = id;
        }
      }),
    );
  }

  void _stepWeek(int delta) {
    final current = int.tryParse(_weekController.text.trim()) ?? 0;
    final next = (current + delta).clamp(1, 999);
    setState(() => _weekController.text = '$next');
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    if (!isAdmin) {
      return const AdminPageScaffold(
        title: 'Fikstür Planlama',
        body: Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    final leagueChosen = _selectedLeagueId != null;
    final seasonChosen = _selectedSeasonId != null;
    final groupChosen = _selectedGroupId != null;

    return AdminPageScaffold(
      title: 'Fikstür Planlama',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kAdminAccent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                AdminFormSection(
                  title: 'Turnuva',
                  child: StreamBuilder<List<League>>(
                    stream: _leaguesStream,
                    builder: (context, snapshot) {
                      _leagues = snapshot.data ?? _leagues;
                      final leagueOptions = [
                        for (final l in _leagues)
                          (id: l.id, name: l.name, isDefault: false),
                      ];
                      return AdminFieldGroup(
                        children: [
                          AdminSelectRow(
                            icon: Icons.emoji_events_outlined,
                            label: 'Turnuva',
                            value: _nameOf(leagueOptions, _selectedLeagueId),
                            placeholder: 'Turnuva seçin',
                            locked: widget.lockLeagueSelection,
                            loading: !snapshot.hasData,
                            onTap: () => _pickOption(
                              title: 'Turnuva Seçin',
                              options: leagueOptions,
                              selected: _selectedLeagueId,
                              onPicked: _selectLeague,
                            ),
                          ),
                          AdminSelectRow(
                            icon: Icons.calendar_month_outlined,
                            label: 'Sezon',
                            value: _nameOf(_seasons, _selectedSeasonId),
                            placeholder: leagueChosen
                                ? (_seasons.isEmpty && !_loadingSeasons
                                      ? 'Bu turnuvada sezon yok'
                                      : 'Sezon seçin')
                                : 'Önce turnuva seçin',
                            loading: _loadingSeasons,
                            onTap: leagueChosen && _seasons.isNotEmpty
                                ? () => _pickOption(
                                    title: 'Sezon Seçin',
                                    options: _seasons,
                                    selected: _selectedSeasonId,
                                    onPicked: _selectSeason,
                                  )
                                : null,
                          ),
                          AdminSelectRow(
                            icon: Icons.grid_view_rounded,
                            label: 'Grup',
                            value: _nameOf(_groups, _selectedGroupId),
                            placeholder: seasonChosen
                                ? (_groups.isEmpty && !_loadingGroups
                                      ? 'Bu sezonda grup yok'
                                      : 'Grup seçin')
                                : 'Önce sezon seçin',
                            loading: _loadingGroups,
                            onTap: seasonChosen && _groups.isNotEmpty
                                ? () => _pickOption(
                                    title: 'Grup Seçin',
                                    options: _groups,
                                    selected: _selectedGroupId,
                                    onPicked: _selectGroup,
                                  )
                                : null,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                AdminFormSection(
                  title: 'Eşleşme',
                  child: AdminFieldGroup(
                    children: [
                      AdminSelectRow(
                        icon: Icons.home_outlined,
                        label: 'Ev Sahibi',
                        value: _teamName(_homeTeamId),
                        placeholder: groupChosen
                            ? 'Takım seçin'
                            : 'Önce grup seçin',
                        loading: _loadingTeams,
                        onTap: groupChosen && _teams.isNotEmpty
                            ? () => _pickTeam(home: true)
                            : null,
                      ),
                      AdminSelectRow(
                        icon: Icons.flight_takeoff_rounded,
                        label: 'Deplasman',
                        value: _teamName(_awayTeamId),
                        placeholder: groupChosen
                            ? 'Takım seçin'
                            : 'Önce grup seçin',
                        loading: _loadingTeams,
                        onTap: groupChosen && _teams.isNotEmpty
                            ? () => _pickTeam(home: false)
                            : null,
                      ),
                    ],
                  ),
                ),
                AdminFormSection(
                  title: 'Hafta ve Saha',
                  child: AdminFieldGroup(
                    children: [
                      AdminFieldRow(
                        icon: Icons.format_list_numbered_rounded,
                        label: 'Hafta',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _StepButton(
                              icon: Icons.remove_rounded,
                              onTap: () => _stepWeek(-1),
                            ),
                            SizedBox(
                              width: 52,
                              child: TextField(
                                controller: _weekController,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(3),
                                ],
                                cursorColor: kAdminAccent,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  hintText: '-',
                                  hintStyle: TextStyle(color: Colors.white38),
                                ),
                              ),
                            ),
                            _StepButton(
                              icon: Icons.add_rounded,
                              onTap: () => _stepWeek(1),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Maç haftası',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      StreamBuilder<List<Pitch>>(
                        stream: _pitchesStream,
                        builder: (context, snapshot) {
                          final pitches = snapshot.data ?? const <Pitch>[];
                          // '' = "Saha Seçilmedi"
                          final options = <AdminOption>[
                            (id: '', name: 'Saha Seçilmedi', isDefault: false),
                            for (final p in pitches)
                              (id: p.id, name: p.name, isDefault: false),
                          ];
                          return AdminSelectRow(
                            icon: Icons.stadium_outlined,
                            label: 'Saha',
                            value: _selectedPitchName,
                            placeholder: 'Saha seçilmedi',
                            onTap: () => _pickOption(
                              title: 'Saha Seçin',
                              options: options,
                              selected: _selectedPitchId ?? '',
                              onPicked: (id) => setState(() {
                                final name = (_nameOf(options, id) ?? '')
                                    .trim();
                                _selectedPitchId = id.isEmpty ? null : id;
                                _selectedPitchName = id.isEmpty || name.isEmpty
                                    ? null
                                    : name;
                              }),
                            ),
                            onClear: () => setState(() {
                              _selectedPitchId = null;
                              _selectedPitchName = null;
                            }),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                AdminFormSection(
                  title: 'Tarih ve Saat',
                  child: AdminFieldGroup(
                    children: [
                      AdminFieldRow(
                        icon: Icons.event_busy_outlined,
                        label: 'Planlama',
                        onTap: () => setState(
                          () => _unknownDateTime = !_unknownDateTime,
                        ),
                        trailing: Switch.adaptive(
                          value: _unknownDateTime,
                          activeTrackColor: kAdminAccent,
                          onChanged: (v) =>
                              setState(() => _unknownDateTime = v),
                        ),
                        child: const Text(
                          'Tarih ve saat belirlenmedi',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      AdminSelectRow(
                        icon: Icons.calendar_today_outlined,
                        label: 'Tarih',
                        value:
                            '${_two(_selectedDate.day)}.${_two(_selectedDate.month)}.${_selectedDate.year}',
                        placeholder: '',
                        onTap: _unknownDateTime ? null : _pickDate,
                      ),
                      AdminSelectRow(
                        icon: Icons.access_time_rounded,
                        label: 'Saat',
                        value:
                            '${_two(_selectedTime.hour)}:${_two(_selectedTime.minute)}',
                        placeholder: '',
                        onTap: _unknownDateTime ? null : _pickTime,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                AdminPrimaryButton(
                  label: 'KAYDET',
                  icon: Icons.check_rounded,
                  onPressed: _saveFixture,
                ),
              ],
            ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstYear: DateTime.now().year - 1,
      lastYear: DateTime.now().year + 1,
      title: 'Maç Tarihi',
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
    final week = int.tryParse(_weekController.text.trim());
    if (_selectedLeagueId == null ||
        _selectedSeasonId == null ||
        _selectedGroupId == null ||
        _homeTeamId == null ||
        _awayTeamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tüm alanları seçin.')),
      );
      return;
    }
    if (week == null || week < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen geçerli bir hafta girin.')),
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

      final match = MatchModel(
        id: '',
        leagueId: _selectedLeagueId!,
        seasonId: _selectedSeasonId!,
        groupId: _selectedGroupId!,
        homeTeamId: _homeTeamId!,
        awayTeamId: _awayTeamId!,
        homeScore: 0,
        awayScore: 0,
        week: week,
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

      final newId = await _matchService.addMatch(match);
      if (newId.trim().isEmpty) {
        throw Exception('Maç kaydedilemedi.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maç başarıyla planlandı.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

/// Hafta satırındaki küçük yuvarlak artı / eksi butonu.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }
}
