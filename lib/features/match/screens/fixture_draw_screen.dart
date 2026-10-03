import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../team/models/team.dart';
import '../utils/fixture_draw.dart';

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
  late List<DrawWeek> _weeks = _draw();
  late int _startWeek = widget.startWeek;
  bool _saving = false;

  List<DrawWeek> _draw() => drawLeagueFixture([
    for (final t in widget.teams) t.id,
  ], doubleRound: widget.doubleRound);

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

  @override
  Widget build(BuildContext context) {
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
                                  fontWeight: FontWeight.w900,
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
                    label: 'KAYDET',
                    icon: Icons.check_rounded,
                    busy: _saving,
                    onPressed: _save,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AdminSecondaryButton(
                          label: 'YENİDEN ÇEK',
                          onPressed: _saving
                              ? null
                              : () => setState(() => _weeks = _draw()),
                        ),
                      ),
                      const SizedBox(width: 10),
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
                fontWeight: FontWeight.w900,
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
