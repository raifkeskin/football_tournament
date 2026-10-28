import 'package:flutter/material.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../match/models/match.dart';
import '../match/utils/season_match_settings.dart';
import 'referee_service.dart';

/// Maç detayı › "Hakem Ata": orta hakem ve (sezonda açıksa) iki yardımcı,
/// yalnız turnuvanın hakem listesinden. Kaydedilince true döner.
Future<bool> showMatchRefereePicker(BuildContext context, MatchModel match) {
  return showAdminPopup<bool>(
    context: context,
    builder: (_) => _MatchRefereePicker(match: match),
  ).then((v) => v == true);
}

class _MatchRefereePicker extends StatefulWidget {
  const _MatchRefereePicker({required this.match});

  final MatchModel match;

  @override
  State<_MatchRefereePicker> createState() => _MatchRefereePickerState();
}

class _MatchRefereePickerState extends State<_MatchRefereePicker> {
  static const _none = Referee(id: '', name: 'Seçilmedi');

  List<Referee>? _list;
  bool _assistants = true;
  String? _error;
  bool _saving = false;
  late String? _center = widget.match.refereeId;
  late String? _a1 = widget.match.assistantReferee1Id;
  late String? _a2 = widget.match.assistantReferee2Id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        RefereeService.leagueList(widget.match.leagueId),
        SeasonMatchSettings.of(widget.match.seasonId),
      ]);
      if (!mounted) return;
      setState(() {
        _list = results[0] as List<Referee>;
        _assistants = (results[1] as SeasonMatchSettings).assistantReferees;
      });
    } catch (e) {
      if (mounted) setState(() => _error = RefereeService.message(e));
    }
  }

  String? _name(String? id) =>
      _list?.where((r) => r.id == id).firstOrNull?.name;

  Future<void> _pick(
    String title,
    String? current,
    void Function(String?) set,
  ) async {
    final others = {_center, _a1, _a2}..remove(current);
    final items = [
      _none,
      for (final r in _list ?? const <Referee>[])
        if (!others.contains(r.id)) r,
    ];
    final picked = await showAdminOptionPicker<Referee>(
      context: context,
      title: title,
      items: items,
      labelBuilder: (r) => r.name,
      selected: items.where((r) => r.id == (current ?? '')).firstOrNull,
    );
    if (picked == null || !mounted) return;
    setState(() => set(picked.id.isEmpty ? null : picked.id));
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (_center == null && (_a1 != null || _a2 != null)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Önce orta hakemi seçin.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await RefereeService.setMatchReferees(
        widget.match.id,
        referee: _center,
        assistant1: _assistants ? _a1 : null,
        assistant2: _assistants ? _a2 : null,
      );
      nav.pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Maçın hakemleri kaydedildi.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(RefereeService.message(e))),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final Widget content;
    if (_error != null) {
      content = Padding(
        padding: const EdgeInsets.all(20),
        child: Text(_error!, style: const TextStyle(color: kAdminMuted)),
      );
    } else if (list == null) {
      content = const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (list.isEmpty) {
      content = const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Text(
          'Turnuvanın hakem listesi boş. Kurucu başkan Yönetim Paneli › '
          'Hakemler ekranından hakem ekleyince burada seçilebilir.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kAdminMuted, height: 1.4),
        ),
      );
    } else {
      content = Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminFieldGroup(
                children: [
                  AdminSelectRow(
                    icon: Icons.sports_rounded,
                    label: 'Orta Hakem',
                    value: _name(_center),
                    placeholder: 'Seçin',
                    onTap: _saving
                        ? null
                        : () =>
                              _pick('Orta Hakem', _center, (v) => _center = v),
                  ),
                  if (_assistants) ...[
                    AdminSelectRow(
                      icon: Icons.flag_outlined,
                      label: '1. Yardımcı Hakem',
                      value: _name(_a1),
                      placeholder: 'Seçilmedi',
                      onTap: _saving
                          ? null
                          : () =>
                                _pick('1. Yardımcı Hakem', _a1, (v) => _a1 = v),
                    ),
                    AdminSelectRow(
                      icon: Icons.flag_outlined,
                      label: '2. Yardımcı Hakem',
                      value: _name(_a2),
                      placeholder: 'Seçilmedi',
                      onTap: _saving
                          ? null
                          : () =>
                                _pick('2. Yardımcı Hakem', _a2, (v) => _a2 = v),
                    ),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(
                  _assistants
                      ? 'Yalnız bu turnuvanın hakem listesindekiler seçilir. '
                            'Yardımcı hakemler isteğe bağlıdır.'
                      : 'Bu sezonda tek hakem: yalnız orta hakem seçilir.',
                  style: const TextStyle(color: kAdminMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return AdminDialogCloseOverlay(
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminDialogHeader(
            icon: Icons.sports_rounded,
            title: 'Hakem Ata',
          ),
          content,
          if (list != null && list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: AdminPrimaryButton(
                label: 'KAYDET',
                busy: _saving,
                onPressed: _save,
              ),
            ),
        ],
      ),
    );
  }
}
