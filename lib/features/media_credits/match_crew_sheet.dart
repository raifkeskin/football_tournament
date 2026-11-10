import 'package:flutter/material.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../match/models/match.dart';
import 'admin_media_credits_screen.dart';
import 'media_credit.dart';

/// Maçın medya ekibini düzenler: turnuvanın künye havuzundan yayıncı ve
/// fotoğrafçılar işaretlenir (birden çok), havuzda olmayan kişi buradan
/// eklenir. "Varsayılana dön" maçı turnuvanın varsayılanına bağlar.
/// [kind] verilirse yalnız o tür (Yayıncı ya da Fotoğrafçı) düzenlenir; tür
/// bilgi olarak gösterilir, değiştirilemez.
Future<void> showMatchCrewSheet(
  BuildContext context,
  MatchModel match, {
  MediaCreditKind? kind,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _MatchCrewSheet(match: match, kind: kind),
  );
}

class _MatchCrewSheet extends StatefulWidget {
  const _MatchCrewSheet({required this.match, this.kind});

  final MatchModel match;
  final MediaCreditKind? kind;

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
    final added = await showMediaCreditPicker(
      context,
      leagueId: _leagueId,
      kind: kind,
      exclude: {for (final c in _credits ?? const <MediaCredit>[]) c.id},
    );
    if (added != null) await _load();
  }

  /// Tek tür düzenlenirken "Varsayılan": o türün seçimi turnuva varsayılanına
  /// döner, diğer türün seçimi korunur.
  Future<void> _resetKind(MediaCreditKind k) async {
    final credits = _credits ?? const <MediaCredit>[];
    final of = credits.where((c) => c.kind == k).toList();
    final def = of.where((c) => c.isDefault).firstOrNull ?? of.firstOrNull;
    setState(() {
      _picked.removeAll(of.map((c) => c.id));
      if (def != null) _picked.add(def.id);
    });
    await _save({..._picked});
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
        label: const Text('Ekle'),
        style: TextButton.styleFrom(foregroundColor: kAdminAccent),
      ),
      child: list.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Turnuvanın listesinde ${kind.label.toLowerCase()} yok; '
                'Ekle ile rehberden seç.',
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
                  Text(
                    widget.kind == null
                        ? 'Maçın Medya Ekibi'
                        : (widget.kind == MediaCreditKind.broadcast
                              ? 'Maç Yayıncısı'
                              : 'Maç Fotoğrafçısı'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.kind == null
                        ? 'Bu maçı yayınlayan ve fotoğraflayanları işaretle. '
                              'Hiçbiri işaretli değilse bu maçta medya ekibi '
                              'görünmez.'
                        : 'Bu maçta görev alanları işaretle (birden fazla '
                              'kişi seçilebilir). Listede yoksa Ekle ile '
                              'rehberden seç ya da yeni kişi kaydet.',
                    style: const TextStyle(color: kAdminMuted, fontSize: 12.5),
                  ),
                  if (widget.kind != null) ...[
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: 0.6,
                      child: AdminFieldGroup(
                        children: [
                          ListTile(
                            enabled: false,
                            dense: true,
                            title: const Text(
                              'Tür',
                              style: TextStyle(color: kAdminMuted),
                            ),
                            trailing: Text(
                              widget.kind!.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (credits == null)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    if (widget.kind == null ||
                        widget.kind == MediaCreditKind.broadcast)
                      _section(MediaCreditKind.broadcast, credits),
                    if (widget.kind == null ||
                        widget.kind == MediaCreditKind.photo)
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
                      onPressed: _saving
                          ? null
                          : () => widget.kind == null
                                ? _save(null)
                                : _resetKind(widget.kind!),
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
