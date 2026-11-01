import 'package:flutter/material.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../match/models/match.dart';
import 'admin_media_credits_screen.dart';
import 'media_credit.dart';

/// Maçın medya ekibini düzenler: turnuvanın künye havuzundan yayıncı ve
/// fotoğrafçılar işaretlenir (birden çok), havuzda olmayan kişi buradan
/// eklenir. "Varsayılana dön" maçı turnuvanın varsayılanına bağlar.
Future<void> showMatchCrewSheet(BuildContext context, MatchModel match) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _MatchCrewSheet(match: match),
  );
}

class _MatchCrewSheet extends StatefulWidget {
  const _MatchCrewSheet({required this.match});

  final MatchModel match;

  @override
  State<_MatchCrewSheet> createState() => _MatchCrewSheetState();
}

class _MatchCrewSheetState extends State<_MatchCrewSheet> {
  List<MediaCredit>? _credits;
  final Set<String> _picked = {};
  bool _saving = false;

  String get _leagueId => widget.match.leagueId;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final before = {for (final c in _credits ?? const []) c.id};
      final res = await Future.wait<Object>([
        MediaCreditFeed.fetch(_leagueId),
        MatchMediaCrew.fetch(widget.match.id),
      ]);
      final credits = res[0] as List<MediaCredit>;
      final crew = res[1] as MatchCrew;
      if (!mounted) return;
      setState(() {
        if (initial) {
          for (final k in MediaCreditKind.values) {
            _picked.addAll(
              MatchMediaCrew.resolve(credits, crew, k).map((c) => c.id),
            );
          }
        } else {
          // Az önce eklenen kişi bu maça da seçilir.
          _picked.addAll(
            credits.map((c) => c.id).where((id) => !before.contains(id)),
          );
        }
        _credits = credits;
      });
    } catch (e) {
      if (mounted) _snack('Künye yüklenemedi: $e');
    }
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _add(MediaCreditKind kind) async {
    final saved = await showAdminPopup<bool>(
      context: context,
      builder: (_) =>
          MediaCreditForm(leagueId: _leagueId, kind: kind, credit: null),
    );
    if (saved == true) await _load();
  }

  Future<void> _save(Set<String>? ids) async {
    setState(() => _saving = true);
    try {
      await MatchMediaCrew.save(widget.match.id, ids);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Kaydedilemedi: $e');
      }
    }
  }

  Widget _section(MediaCreditKind kind, List<MediaCredit> credits) {
    final list = [
      for (final c in credits)
        if (c.kind == kind) c,
    ];
    return AdminFormSection(
      title: kind == MediaCreditKind.broadcast ? 'Yayıncı' : 'Fotoğrafçı',
      trailing: TextButton.icon(
        onPressed: _saving ? null : () => _add(kind),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Yeni ekle'),
        style: TextButton.styleFrom(foregroundColor: kAdminAccent),
      ),
      child: list.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Turnuvada kayıtlı ${kind.label.toLowerCase()} yok.',
                style: const TextStyle(color: kAdminMuted),
              ),
            )
          : AdminFieldGroup(
              children: [
                for (final c in list)
                  CheckboxListTile(
                    value: _picked.contains(c.id),
                    onChanged: _saving
                        ? null
                        : (v) => setState(
                            () => v == true
                                ? _picked.add(c.id)
                                : _picked.remove(c.id),
                          ),
                    activeColor: kAdminAccent,
                    title: Text(
                      c.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      c.isDefault
                          ? 'Varsayılan · ${c.displayTitle}'
                          : c.displayTitle,
                      style: const TextStyle(color: kAdminMuted, fontSize: 12),
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final credits = _credits;
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scroll) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Maçın Medya Ekibi',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Bu maçı yayınlayan ve fotoğraflayanları işaretle. Hiçbiri '
                    'işaretli değilse bu maçta medya ekibi görünmez.',
                    style: TextStyle(color: kAdminMuted, fontSize: 12.5),
                  ),
                  if (credits == null)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    _section(MediaCreditKind.broadcast, credits),
                    _section(MediaCreditKind.photo, credits),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: AdminSecondaryButton(
                      label: 'VARSAYILAN',
                      onPressed: _saving ? null : () => _save(null),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: AdminPrimaryButton(
                      label: 'KAYDET',
                      icon: Icons.check_rounded,
                      busy: _saving,
                      onPressed: credits == null || _saving
                          ? null
                          : () => _save({..._picked}),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
