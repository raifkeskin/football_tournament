import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/active_tournament.dart';
import '../../core/services/app_session.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../auth/widgets/phone_input.dart';
import 'referee_service.dart';

/// Hakemler: turnuvada görev alacak hakemlerin listesi. Hakem bir kez
/// kaydedilir, başka turnuvaya bağlanabilir; maça yalnız turnuvanın
/// hakemleri atanır. Telefon girilirse hakem o numarayla giriş yapıp kendi
/// maçlarını görür. Yalnızca admin ve turnuvanın kurucu başkanları.
class AdminRefereesScreen extends StatefulWidget {
  const AdminRefereesScreen({super.key});

  @override
  State<AdminRefereesScreen> createState() => _AdminRefereesScreenState();
}

class _AdminRefereesScreenState extends State<AdminRefereesScreen> {
  List<LeagueChoice>? _leagues;
  String? _leagueId;
  List<Referee>? _referees;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_leagues == null) _loadLeagues();
  }

  Future<void> _loadLeagues() async {
    final s = AppSession.of(context).value;
    _leagues = const [];
    try {
      final rows = await Supabase.instance.client
          .from('leagues')
          .select('id, name, logo_url, status')
          .order('name');
      final list = [
        for (final r in rows)
          if (r['status'] == 'active' &&
              (s.isAdmin || s.ownedLeagueIds.contains(r['id'].toString())))
            LeagueChoice(
              id: r['id'].toString(),
              name: (r['name'] ?? '').toString(),
              logoUrl: (r['logo_url'] ?? '').toString(),
            ),
      ];
      if (!mounted) return;
      final current = ActiveTournament.currentLeagueId.value;
      setState(() {
        _leagues = list;
        _leagueId = list.any((l) => l.id == current)
            ? current
            : (list.isEmpty ? null : list.first.id);
      });
      await _load();
    } catch (e) {
      if (mounted) _snack('Turnuvalar yüklenemedi: $e');
    }
  }

  Future<void> _load() async {
    final id = _leagueId;
    if (id == null) return;
    try {
      final list = await RefereeService.leagueList(id);
      if (!mounted || id != _leagueId) return;
      setState(() => _referees = list);
    } catch (e) {
      if (mounted) _snack('Hakemler yüklenemedi: ${RefereeService.message(e)}');
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickLeague() async {
    final leagues = _leagues ?? const <LeagueChoice>[];
    final picked = await showAdminOptionPicker<LeagueChoice>(
      context: context,
      title: 'Turnuva',
      items: leagues,
      labelBuilder: (l) => l.name,
      selected: leagues.where((l) => l.id == _leagueId).firstOrNull,
    );
    if (picked == null || picked.id == _leagueId) return;
    setState(() {
      _leagueId = picked.id;
      _referees = null;
    });
    await _load();
  }

  Future<void> _edit(Referee? referee) async {
    final leagueId = _leagueId;
    if (leagueId == null) return;
    final saved = await showAdminPopup<String>(
      context: context,
      builder: (_) => _RefereeForm(leagueId: leagueId, referee: referee),
    );
    if (saved != null) {
      await _load();
      if (mounted) _snack(saved);
    }
  }

  Future<void> _remove(Referee r) async {
    final leagueId = _leagueId;
    if (leagueId == null) return;
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Turnuvadan Çıkar',
      message:
          '"${r.name}" bu turnuvanın hakem listesinden çıkarılacak. '
          'Atandığı maçlar değişmez.',
      confirmLabel: 'ÇIKAR',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await RefereeService.unlink(leagueId, r.id);
      await _load();
    } catch (e) {
      _snack('Çıkarılamadı: ${RefereeService.message(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSession.of(context).value;
    if (!s.isAdmin && !s.isLeagueOwner) {
      return const AdminPageScaffold(
        title: 'Hakemler',
        body: Center(
          child: Text(
            'Bu ekrana yalnızca admin ve kurucu başkan erişebilir.',
            style: TextStyle(color: kAdminMuted),
          ),
        ),
      );
    }
    final leagues = _leagues;
    final league = leagues?.where((l) => l.id == _leagueId).firstOrNull;
    final referees = _referees;
    final Widget body;
    if (leagues == null || (_leagueId != null && referees == null)) {
      body = const Center(child: CircularProgressIndicator());
    } else if (leagues.isEmpty) {
      body = const Center(
        child: Text(
          'Yönetebildiğiniz turnuva yok.',
          style: TextStyle(color: kAdminMuted),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            AdminFieldGroup(
              children: [
                AdminSelectRow(
                  icon: Icons.emoji_events_rounded,
                  label: 'Turnuva',
                  value: league?.name,
                  placeholder: 'Turnuva seçin',
                  onTap: leagues.length > 1 && !_busy ? _pickLeague : null,
                  locked: leagues.length <= 1,
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 6, 4, 18),
              child: Text(
                'Maça hakem atarken yalnız bu listedeki hakemler seçilir. '
                'Telefon girilirse hakem o numarayla giriş yapıp yöneteceği '
                'maçları görür.',
                style: TextStyle(
                  color: kAdminMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
            AdminFormSection(
              title: 'Turnuvanın Hakemleri (${referees!.length})',
              trailing: TextButton.icon(
                onPressed: _busy ? null : () => _edit(null),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Hakem Ekle'),
                style: TextButton.styleFrom(foregroundColor: kAdminAccent),
              ),
              child: referees.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: const Text(
                        'Henüz hakem eklenmedi.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kAdminMuted),
                      ),
                    )
                  : AdminFieldGroup(
                      children: [
                        for (final r in referees)
                          _RefereeRow(
                            referee: r,
                            busy: _busy,
                            onEdit: () => _edit(r),
                            onRemove: () => _remove(r),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      );
    }
    return AdminPageScaffold(title: 'Hakemler', body: body);
  }
}

class _RefereeRow extends StatelessWidget {
  const _RefereeRow({
    required this.referee,
    required this.busy,
    required this.onEdit,
    required this.onRemove,
  });

  final Referee referee;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final r = referee;
    final phone = r.phone;
    final (status, color) = phone == null
        ? ('Telefonsuz', kAdminMuted)
        : r.hasAccount
        ? ('Giriş yapabilir', kAdminAccent)
        : ('Hesap açmadı', const Color(0xFFF59E0B));
    return InkWell(
      onTap: busy ? null : onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: const Color(0xFF334155),
              child: Text(
                r.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    [
                      if (phone != null) formatPhoneRaw10(phone),
                      '${r.matchCount} maç',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kAdminMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    style: TextStyle(
                      color: color,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            AdminSmallAction(
              icon: Icons.person_remove_outlined,
              tooltip: 'Turnuvadan çıkar',
              color: kAdminDanger,
              onTap: busy ? null : onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hakem ekle / düzenle. Eklerken havuzda aynı telefon ya da aynı ad varsa
/// yeni kayıt yerine mevcudu bağlamak önerilir.
class _RefereeForm extends StatefulWidget {
  const _RefereeForm({required this.leagueId, this.referee});

  final String leagueId;
  final Referee? referee;

  @override
  State<_RefereeForm> createState() => _RefereeFormState();
}

class _RefereeFormState extends State<_RefereeForm> {
  late final _name = TextEditingController(text: widget.referee?.name ?? '');
  late final _phone = TextEditingController(
    text: (widget.referee?.phone ?? '').isEmpty
        ? ''
        : PhoneMaskFormatter.formatFromRaw(widget.referee!.phone!),
  );
  bool _saving = false;
  List<RefereeCandidate> _candidates = const [];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save({bool force = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final name = _name.text.trim();
    final raw = normalizePhoneToRaw10(_phone.text);
    if (name.length < 2) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Hakemin adını girin.')),
      );
      return;
    }
    if (raw.isNotEmpty && (raw.length != 10 || !raw.startsWith('5'))) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Telefon numarası 5 ile başlayan 10 hane olmalı.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final isNew = widget.referee == null;
      if (isNew && !force) {
        final c = await RefereeService.candidates(
          widget.leagueId,
          name,
          raw.isEmpty ? null : raw,
        );
        if (c.isNotEmpty) {
          if (mounted) {
            setState(() {
              _candidates = c;
              _saving = false;
            });
          }
          return;
        }
      }
      await RefereeService.save(
        leagueId: widget.leagueId,
        refereeId: widget.referee?.id,
        name: name,
        phone: raw.isEmpty ? null : raw,
      );
      nav.pop(isNew ? 'Hakem eklendi.' : 'Hakem güncellendi.');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(RefereeService.message(e))),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _link(RefereeCandidate c) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await RefereeService.link(widget.leagueId, c.id);
      nav.pop('${c.name} turnuvaya bağlandı.');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(RefereeService.message(e))),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController c,
    IconData icon,
    String label, {
    String? hint,
    bool phone = false,
  }) {
    return AdminFieldRow(
      icon: icon,
      label: label,
      child: TextField(
        controller: c,
        enabled: !_saving,
        keyboardType: phone ? TextInputType.phone : TextInputType.name,
        textCapitalization: phone
            ? TextCapitalization.none
            : TextCapitalization.words,
        inputFormatters: phone ? [PhoneMaskFormatter()] : null,
        onChanged: (_) {
          if (_candidates.isNotEmpty) setState(() => _candidates = const []);
        },
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        cursorColor: kAdminAccent,
        decoration: adminInlineInputDecoration(hint: hint).copyWith(
          prefixText: phone ? '0 ' : null,
          prefixStyle: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.referee != null;
    final samePhone = _candidates.any((c) => c.samePhone);
    return AdminDialogCloseOverlay(
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminDialogHeader(
            icon: Icons.sports_rounded,
            title: isEdit ? 'Hakemi Düzenle' : 'Hakem Ekle',
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminFieldGroup(
                    children: [
                      _field(
                        _name,
                        Icons.person_outline_rounded,
                        'Ad Soyad',
                        hint: 'Murat Özkan',
                      ),
                      _field(
                        _phone,
                        Icons.call_outlined,
                        'Telefon (isteğe bağlı)',
                        hint: '(5XX) XXX XX XX',
                        phone: true,
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Text(
                      'Hakem bu numarayla giriş yapınca yöneteceği maçları ve '
                      'kendi sayılarını görür. Numara herkese açık görünmez.',
                      style: TextStyle(color: kAdminMuted, fontSize: 12),
                    ),
                  ),
                  if (_candidates.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            samePhone
                                ? 'Bu telefon kayıtlı bir hakemde. Yeni kayıt '
                                      'açılamaz; turnuvaya bağlayın.'
                                : 'Bu isimde kayıtlı hakem var. Aynı kişiyse '
                                      'bağlayın, yeni kayıt açılmaz.',
                            style: const TextStyle(
                              color: Color(0xFFBAE6FD),
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                          for (final c in _candidates)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                c.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: c.leagues == null
                                  ? null
                                  : Text(
                                      c.leagues!,
                                      style: const TextStyle(
                                        color: kAdminMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                              trailing: TextButton(
                                onPressed: _saving ? null : () => _link(c),
                                child: const Text('Bağla'),
                              ),
                            ),
                          if (!samePhone)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => _save(force: true),
                                child: const Text('Farklı kişi, yeni kaydet'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: AdminPrimaryButton(
              label: isEdit ? 'GÜNCELLE' : 'KAYDET',
              busy: _saving,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
