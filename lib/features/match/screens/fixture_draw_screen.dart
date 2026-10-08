import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../team/models/team.dart';
import '../services/live_draw_service.dart';
import '../utils/fixture_draw.dart';
import 'live_draw_screen.dart';

/// Fikstür kurası önizlemesi: kura çekilir, haftalara dağıtılmış eşleşmeler
/// gösterilir; "Yeniden Çek" ile tekrarlanır, "Kaydet" ile maçlar tarih/saat
/// belirsiz olarak tek seferde eklenir. Kaydedilirse `true` döner.
class FixtureDrawScreen extends StatefulWidget {
  const FixtureDrawScreen({
    super.key,
    required this.leagueId,
    required this.seasonId,
    required this.groupId,
    required this.groupName,
    required this.teams,
    required this.doubleRound,
    required this.startWeek,
  });

  final String leagueId;
  final String seasonId;
  final String groupId;
  final String groupName;
  final List<Team> teams;
  final bool doubleRound;
  final int startWeek;

  @override
  State<FixtureDrawScreen> createState() => _FixtureDrawScreenState();
}

class _FixtureDrawScreenState extends State<FixtureDrawScreen> {
  late final Map<String, Team> _teamById = {
    for (final t in widget.teams) t.id: t,
  };

  /// Açılış maçı (isteğe bağlı): kurada 1. haftanın ilk maçı olur.
  String? _openingHome;
  String? _openingAway;
  late List<DrawWeek> _weeks = _draw();
  late int _startWeek = widget.startWeek;
  bool _saving = false;

  /// Canlı yayın: kura önceden gösterilmez, planlanan anda herkes izler.
  bool _live = false;

  /// Canlı kuranın başlangıcı; null: hemen.
  DateTime? _liveAt;

  DrawPair? get _opening {
    final h = _openingHome, a = _openingAway;
    return h == null || a == null || h == a ? null : (home: h, away: a);
  }

  List<DrawWeek> _draw() => drawLeagueFixture(
    [for (final t in widget.teams) t.id],
    doubleRound: widget.doubleRound,
    opening: _opening,
  );

  /// Açılış maçının bir tarafını seçer; diğer tarafta seçili takım listede
  /// yer almaz. "Seçme" ile kaldırılır. Seçim değişince kura yenilenir.
  Future<void> _pickOpening({required bool home}) async {
    const none = '';
    final other = home ? _openingAway : _openingHome;
    final current = home ? _openingHome : _openingAway;
    final choice = await showAdminOptionPicker<String>(
      context: context,
      title: home ? 'Açılış maçı · Ev sahibi' : 'Açılış maçı · Deplasman',
      items: [
        none,
        for (final t in widget.teams)
          if (t.id != other) t.id,
      ],
      labelBuilder: (id) =>
          id == none ? 'Seçme (rastgele)' : (_teamById[id]?.name ?? ''),
      selected: current ?? none,
    );
    if (choice == null || !mounted) return;
    setState(() {
      final v = choice == none ? null : choice;
      if (home) {
        _openingHome = v;
      } else {
        _openingAway = v;
      }
      _weeks = _draw();
    });
  }

  int get _matchCount => _weeks.fold(0, (sum, w) => sum + w.pairs.length);

  Future<void> _save() async {
    setState(() => _saving = true);
    final now = DateTime.now().toIso8601String();
    final rows = [
      for (var i = 0; i < _weeks.length; i++)
        for (final p in _weeks[i].pairs)
          {
            'league_id': widget.leagueId,
            'season_id': widget.seasonId,
            'group_id': widget.groupId,
            'home_team_id': p.home,
            'away_team_id': p.away,
            'home_score': 0,
            'away_score': 0,
            'week': _startWeek + i,
            'status': 'notStarted',
            'created_at': now,
          },
    ];
    try {
      final sb = Supabase.instance.client;
      // Bu arada başka biri maç girdiyse kura üstüne eklenmez.
      final existing = await sb
          .from('matches')
          .select('id')
          .eq('group_id', widget.groupId)
          .limit(1);
      if ((existing as List).isNotEmpty) {
        throw Exception('Bu gruba maç girilmiş; kura kaydedilemez.');
      }
      // Tek istekte eklenir: ya hepsi kaydedilir ya hiçbiri.
      await sb.from('matches').insert(rows);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${rows.length} maç kaydedildi '
            '(hafta $_startWeek–${_startWeek + _weeks.length - 1}).',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Canlı kura: sonuç şimdi çekilir ve sunucuda kilitlenir; yöneticiye de
  /// gösterilmez. Kayıttan sonra canlı kura ekranı açılır.
  Future<void> _saveLive() async {
    setState(() => _saving = true);
    try {
      final at = _liveAt;
      final id = await LiveDrawService.instance.create(
        leagueId: widget.leagueId,
        seasonId: widget.seasonId,
        groupId: widget.groupId,
        groupName: widget.groupName,
        startWeek: _startWeek,
        startAt: at == null || at.isBefore(DateTime.now())
            ? DateTime.now()
            : at,
        teamIds: [for (final t in widget.teams) t.id],
        weeks: _draw(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => LiveDrawScreen(drawId: id)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickLiveStart() async {
    const now = 'Hemen';
    const later = 'Tarih ve saat seç';
    final choice = await showAdminOptionPicker<String>(
      context: context,
      title: 'Başlangıç',
      items: const [now, later],
      labelBuilder: (v) => v,
      selected: _liveAt == null ? now : later,
    );
    if (choice == null || !mounted) return;
    if (choice == now) {
      setState(() => _liveAt = null);
      return;
    }
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _liveAt ?? today,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _liveAt ?? today.add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;
    setState(
      () => _liveAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  String get _liveAtLabel {
    final at = _liveAt;
    if (at == null) return 'Hemen';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.day)}.${two(at.month)}.${at.year} · '
        '${two(at.hour)}:${two(at.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final duration = LiveDrawService.estimate(_weeks);
    return AdminPageScaffold(
      title: 'Fikstür Kurası',
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                AdminFormSection(
                  title: widget.groupName.isEmpty ? 'Kura' : widget.groupName,
                  child: AdminFieldGroup(
                    children: [
                      AdminFieldRow(
                        icon: Icons.info_outline_rounded,
                        label: widget.doubleRound ? 'Rövanşlı' : 'Tek maç',
                        child: Text(
                          '${widget.teams.length} takım · ${_weeks.length} '
                          'hafta · $_matchCount maç',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      AdminFieldRow(
                        icon: Icons.format_list_numbered_rounded,
                        label: 'Başlangıç haftası',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _RoundIconButton(
                              icon: Icons.remove_rounded,
                              onTap: _saving || _startWeek <= 1
                                  ? null
                                  : () => setState(() => _startWeek--),
                            ),
                            SizedBox(
                              width: 44,
                              child: Text(
                                '$_startWeek',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            _RoundIconButton(
                              icon: Icons.add_rounded,
                              onTap: _saving
                                  ? null
                                  : () => setState(() => _startWeek++),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Tarih ve saat sonra girilir',
                          style: TextStyle(color: kAdminMuted, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                AdminFormSection(
                  title: 'Açılış maçı',
                  child: AdminFieldGroup(
                    children: [
                      AdminSelectRow(
                        icon: Icons.home_rounded,
                        label: 'Ev sahibi',
                        value: _teamById[_openingHome]?.name,
                        placeholder: 'Rastgele',
                        onTap: _saving ? null : () => _pickOpening(home: true),
                        onClear: _saving || _openingHome == null
                            ? null
                            : () => setState(() {
                                _openingHome = null;
                                _weeks = _draw();
                              }),
                      ),
                      AdminSelectRow(
                        icon: Icons.flight_takeoff_rounded,
                        label: 'Deplasman',
                        value: _teamById[_openingAway]?.name,
                        placeholder: 'Rastgele',
                        onTap: _saving ? null : () => _pickOpening(home: false),
                        onClear: _saving || _openingAway == null
                            ? null
                            : () => setState(() {
                                _openingAway = null;
                                _weeks = _draw();
                              }),
                      ),
                    ],
                  ),
                ),
                if ((_openingHome == null) != (_openingAway == null))
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'Açılış maçı için iki takımı da seç; seçilmezse kura '
                      'tamamen rastgele çekilir.',
                      style: TextStyle(color: kAdminAmber, fontSize: 12.5),
                    ),
                  ),
                AdminFormSection(
                  title: 'Canlı yayın',
                  child: AdminFieldGroup(
                    children: [
                      AdminFieldRow(
                        icon: Icons.sensors_rounded,
                        label: 'Canlı yayınla',
                        trailing: Switch(
                          value: _live,
                          activeThumbColor: Colors.white,
                          activeTrackColor: kAdminAccent,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _live = v),
                        ),
                        child: const Text(
                          'Herkes çekimi Haberler\'den canlı izler',
                          style: TextStyle(color: kAdminMuted, fontSize: 13),
                        ),
                      ),
                      if (_live) ...[
                        AdminSelectRow(
                          icon: Icons.schedule_rounded,
                          label: 'Başlangıç',
                          value: _liveAtLabel,
                          placeholder: 'Hemen',
                          onTap: _saving ? null : _pickLiveStart,
                        ),
                        AdminFieldRow(
                          icon: Icons.timer_outlined,
                          label: 'Süre',
                          child: Text(
                            '~${(duration.inSeconds / 60).ceil()} dk · ilk 2 '
                            'hafta takım takım, sonrası maç maç',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_live)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: Text(
                      'Kura, planladığın anda çekilir ve sunucuda kilitlenir; '
                      'sonucu sen dahil kimse önceden göremez. Başladıktan '
                      'sonra tekrar çekilemez. Bitince maçlar fikstüre '
                      'otomatik eklenir.',
                      style: TextStyle(
                        color: kAdminMuted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                if (!_live)
                  for (var i = 0; i < _weeks.length; i++)
                    AdminFormSection(
                      title: '${_startWeek + i}. Hafta',
                      child: AdminFieldGroup(
                        children: [
                          for (final p in _weeks[i].pairs) _pairRow(p),
                          if (_weeks[i].bye != null)
                            _byeRow(_teamById[_weeks[i].bye]?.name ?? ''),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminPrimaryButton(
                    label: _live ? 'CANLI KURAYI PLANLA' : 'KAYDET',
                    icon: _live ? Icons.sensors_rounded : Icons.check_rounded,
                    busy: _saving,
                    onPressed: _live ? _saveLive : _save,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (!_live) ...[
                        Expanded(
                          child: AdminSecondaryButton(
                            label: 'YENİDEN ÇEK',
                            onPressed: _saving
                                ? null
                                : () => setState(() => _weeks = _draw()),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: AdminSecondaryButton(
                          label: 'İPTAL',
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pairRow(DrawPair p) {
    final home = _teamById[p.home], away = _teamById[p.away];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(child: _TeamCell(team: home, alignEnd: true)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '-',
              style: TextStyle(
                color: kAdminMuted,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(child: _TeamCell(team: away, alignEnd: false)),
        ],
      ),
    );
  }

  Widget _byeRow(String name) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        'Bay: $name',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: kAdminAmber,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Eşleşme satırında takım: logo + ad (ev sahibi sağa, deplasman sola yaslı).
class _TeamCell extends StatelessWidget {
  const _TeamCell({required this.team, required this.alignEnd});

  final Team? team;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final logo = (team?.logoUrl ?? '').trim();
    final name = Flexible(
      child: Text(
        team?.name ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final image = logo.isEmpty
        ? const Icon(Icons.shield_outlined, color: kAdminMuted, size: 22)
        : WebSafeImage(url: logo, width: 26, height: 26, fit: BoxFit.contain);
    return Row(
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: alignEnd
          ? [name, const SizedBox(width: 8), image]
          : [image, const SizedBox(width: 8), name],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

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
        child: Icon(
          icon,
          color: onTap == null ? Colors.white24 : Colors.white70,
          size: 18,
        ),
      ),
    );
  }
}
