import 'package:flutter/material.dart';
import '../services/live_draw_service.dart';
import 'live_draw_screen.dart';
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
import 'fixture_draw_screen.dart';

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
  late final Stream<List<Pitch>> _pitchesStream = _leagueService.watchPitches();

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

  /// İki takımlı gruplarda aynı eşleşme haftalık tekrarlanabilir: toplam
  /// [_repeatCount] maç, 7 gün arayla, ev sahibi her hafta değişir.
  bool _repeat = false;
  int _repeatCount = 5;

  bool get _canRepeat => _teams.length == 2;

  List<League> _leagues = const [];
  List<AdminOption> _seasons = const [];
  final Map<String, bool> _seasonDoubleRound = {};
  List<AdminOption> _groups = const [];
  List<Team> _teams = const [];
  bool _loadingSeasons = false;
  bool _loadingGroups = false;
  bool _loadingTeams = false;
  bool _autoSelectingSingleLeague = false;

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
          .select('id, name, is_default, is_double_round')
          .eq('league_id', leagueId)
          .order('start_date', ascending: false);
      if (!mounted || _selectedLeagueId != leagueId) return;
      // Bölge sorumlusu yalnızca bölgesinin bulunduğu sezonları görür.
      final session = AppSession.of(context).value;
      final full = session.canManageLeague(leagueId);
      final mySeasons = {for (final r in session.ownedRegions) r.seasonId};
      final seasons = [
        for (final r in rows)
          if (full || mySeasons.contains((r['id'] ?? '').toString()))
            (
              id: (r['id'] ?? '').toString(),
              name: (r['name'] ?? '').toString().trim(),
              isDefault: r['is_default'] == true,
            ),
      ];
      setState(() {
        _seasons = seasons;
        _loadingSeasons = false;
        for (final r in rows) {
          _seasonDoubleRound[(r['id'] ?? '').toString()] =
              r['is_double_round'] == true;
        }
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
          .select('id, name, region_id')
          .eq('season_id', seasonId)
          .order('name', ascending: true);
      if (!mounted || _selectedSeasonId != seasonId) return;
      // Bölge sorumlusu yalnızca kendi bölgesinin gruplarını görür.
      final session = AppSession.of(context).value;
      final full = session.canManageLeague(_selectedLeagueId);
      final myRegions = {
        for (final r in session.regionsInSeason(seasonId)) r.id,
      };
      final groups = [
        for (final r in rows)
          if (full || myRegions.contains((r['region_id'] ?? '').toString()))
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
        // İki takım varsa eşleşme bellidir.
        if (teams.length == 2) {
          _homeTeamId = teams[0].id;
          _awayTeamId = teams[1].id;
        } else {
          _repeat = false;
        }
      });
    } catch (e) {
      if (!mounted || _selectedGroupId != groupId) return;
      setState(() => _loadingTeams = false);
      _showError('Takımlar yüklenemedi: $e');
    }
  }

  /// Fikstür kurası: grupta maç yoksa önizleme ekranını açar. Başlangıç
  /// haftası, sezonda başka grupların maçı varsa onların ilk haftası (gruplar
  /// aynı haftalarda oynar), yoksa 1.
  Future<void> _openDraw() async {
    final leagueId = _selectedLeagueId, seasonId = _selectedSeasonId;
    final groupId = _selectedGroupId;
    if (leagueId == null || seasonId == null || groupId == null) return;
    if (_teams.length < 2) {
      _showError('Kura için grupta en az 2 takım olmalı.');
      return;
    }
    try {
      // Planlanmış / süren canlı kura varsa yenisi çekilmez; kura açılır.
      final live = await LiveDrawService.instance.forGroup(groupId);
      if (!mounted) return;
      if (live != null && !live.done && !live.cancelled) {
        final open = await showAdminConfirmDialog(
          context: context,
          title: 'Canlı kura planlandı',
          message: live.notStarted
              ? 'Bu grubun canlı kurası planlandı. Kura sayfasından izleyebilir '
                    've başlamadan iptal edebilirsin.'
              : 'Bu grubun canlı kurası şu an sürüyor.',
          confirmLabel: 'KURAYI AÇ',
          destructive: false,
          icon: Icons.sensors_rounded,
        );
        if (open && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'LiveDrawScreen'),
              builder: (_) => LiveDrawScreen(drawId: live.id),
            ),
          );
        }
        return;
      }
      final inGroup = await _sb
          .from('matches')
          .select('id')
          .eq('group_id', groupId)
          .limit(1);
      if (inGroup.isNotEmpty) {
        _showError('Bu grupta maç girilmiş; kura çekilemez.');
        return;
      }
      final first = await _sb
          .from('matches')
          .select('week')
          .eq('season_id', seasonId)
          .not('week', 'is', null)
          .order('week', ascending: true)
          .limit(1);
      final w = first.isEmpty ? null : first.first['week'];
      final startWeek = w is num ? w.toInt() : 1;
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'FixtureDrawScreen'),
          builder: (_) => FixtureDrawScreen(
            leagueId: leagueId,
            seasonId: seasonId,
            groupId: groupId,
            groupName: _nameOf(_groups, groupId) ?? '',
            teams: _teams,
            doubleRound: _seasonDoubleRound[seasonId] ?? false,
            startWeek: startWeek < 1 ? 1 : startWeek,
          ),
        ),
      );
      if (saved == true && mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Kura açılamadı: $e');
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
    final session = AppSession.of(context).value;
    final panelLeagueIds = session.panelLeagueIds;
    if (!session.hasManagementPanel) {
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
                          if (panelLeagueIds == null ||
                              panelLeagueIds.contains(l.id))
                            (id: l.id, name: l.name, isDefault: false),
                      ];
                      if (session.hasManagementPanel &&
                          leagueOptions.length == 1 &&
                          _selectedLeagueId == null &&
                          !_autoSelectingSingleLeague) {
                        final onlyLeagueId = leagueOptions.single.id;
                        _autoSelectingSingleLeague = true;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _selectedLeagueId == null) {
                            _selectLeague(onlyLeagueId);
                          }
                        });
                      }
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
                if (groupChosen)
                  AdminFormSection(
                    title: 'Kura',
                    child: AdminFieldGroup(
                      children: [
                        AdminSelectRow(
                          icon: Icons.shuffle_rounded,
                          label: 'Fikstür kurası',
                          value: null,
                          placeholder: _teams.length < 2
                              ? 'Grupta en az 2 takım olmalı'
                              : 'Tüm lig maçlarını kurayla oluştur',
                          loading: _loadingTeams,
                          onTap: _teams.length < 2 ? null : _openDraw,
                        ),
                      ],
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
                                onChanged: (_) => setState(() {}),
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
                                  fontWeight: FontWeight.w800,
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
                if (_canRepeat)
                  AdminFormSection(
                    title: 'Tekrar',
                    child: AdminFieldGroup(
                      children: [
                        AdminFieldRow(
                          icon: Icons.repeat_rounded,
                          label: 'Haftalık tekrarla',
                          onTap: () => setState(() => _repeat = !_repeat),
                          trailing: Checkbox(
                            value: _repeat,
                            activeColor: kAdminAccent,
                            onChanged: (v) =>
                                setState(() => _repeat = v ?? false),
                          ),
                          child: const Text(
                            'Ev sahibi her hafta değişir',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_repeat)
                          AdminFieldRow(
                            icon: Icons.format_list_numbered_rounded,
                            label: 'Toplam maç sayısı',
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _StepButton(
                                  icon: Icons.remove_rounded,
                                  onTap: () => setState(
                                    () => _repeatCount = (_repeatCount - 1)
                                        .clamp(2, 52),
                                  ),
                                ),
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    '$_repeatCount',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                _StepButton(
                                  icon: Icons.add_rounded,
                                  onTap: () => setState(
                                    () => _repeatCount = (_repeatCount + 1)
                                        .clamp(2, 52),
                                  ),
                                ),
                              ],
                            ),
                            child: Text(
                              _repeatSummary(),
                              style: const TextStyle(
                                color: kAdminMuted,
                                fontSize: 13,
                              ),
                            ),
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

  /// Ör. "Hafta 3–7".
  String _repeatSummary() {
    final week = int.tryParse(_weekController.text.trim());
    if (week == null || week < 1) return '$_repeatCount hafta';
    return 'Hafta $week–${week + _repeatCount - 1}';
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
      final firstDateTime = _unknownDateTime
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

      final count = _canRepeat && _repeat ? _repeatCount : 1;
      var created = 0;
      try {
        for (var i = 0; i < count; i++) {
          // Takvim günü eklenir; yaz saati geçişinde saat kaymaz.
          final dt = firstDateTime == null
              ? null
              : DateTime(
                  firstDateTime.year,
                  firstDateTime.month,
                  firstDateTime.day + 7 * i,
                  firstDateTime.hour,
                  firstDateTime.minute,
                );
          final swap = i.isOdd;
          final match = MatchModel(
            id: '',
            leagueId: _selectedLeagueId!,
            seasonId: _selectedSeasonId!,
            groupId: _selectedGroupId!,
            homeTeamId: swap ? _awayTeamId! : _homeTeamId!,
            awayTeamId: swap ? _homeTeamId! : _awayTeamId!,
            homeScore: 0,
            awayScore: 0,
            week: week + i,
            matchDate: dt == null
                ? null
                : '${dt.year}-${_two(dt.month)}-${_two(dt.day)}',
            matchTime: dt == null
                ? null
                : '${_two(dt.hour)}:${_two(dt.minute)}',
            pitchId: _selectedPitchId,
            pitchName: _selectedPitchName,
            status: MatchStatus.notStarted,
          );

          final newId = await _matchService.addMatch(match);
          if (newId.trim().isEmpty) {
            throw Exception('Maç kaydedilemedi.');
          }
          created++;
        }
      } catch (e) {
        // Tekrarda yarıda kalırsa kaç maçın girildiği bilinmeli.
        if (created == 0) rethrow;
        throw Exception(
          '$created maç kaydedildi (hafta $week–${week + created - 1}), '
          'sonrakiler kaydedilemedi: $e',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Maç başarıyla planlandı.'
                : '$count maç planlandı (hafta $week–${week + count - 1}).',
          ),
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
