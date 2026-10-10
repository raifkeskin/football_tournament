import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/active_tournament.dart';
import '../../core/services/app_session.dart';
import '../../core/services/image_upload_service.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/picked_image.dart';
import '../../core/widgets/web_safe_image.dart';
import 'sponsor.dart';

/// Sponsor Yönetimi: turnuvanın ana ve alt sponsorları (logo, ad, link,
/// sıra). Yalnızca admin ve turnuvanın kurucu başkanları.
class AdminSponsorsScreen extends StatefulWidget {
  const AdminSponsorsScreen({super.key});

  @override
  State<AdminSponsorsScreen> createState() => _AdminSponsorsScreenState();
}

class _AdminSponsorsScreenState extends State<AdminSponsorsScreen> {
  SupabaseClient get _sb => Supabase.instance.client;

  List<LeagueChoice>? _leagues;
  String? _leagueId;
  List<Sponsor>? _sponsors;
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
      final rows = await _sb
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
      await _loadSponsors();
    } catch (e) {
      if (mounted) _snack('Turnuvalar yüklenemedi: $e');
    }
  }

  Future<void> _loadSponsors() async {
    final id = _leagueId;
    if (id == null) return;
    try {
      final rows = await _sb.from('sponsors').select().eq('league_id', id);
      if (!mounted || id != _leagueId) return;
      setState(() {
        _sponsors = [for (final r in rows) Sponsor.fromMap(r)]
          ..sort(Sponsor.compare);
      });
    } catch (e) {
      if (mounted) _snack('Sponsorlar yüklenemedi: $e');
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
      _sponsors = null;
    });
    await _loadSponsors();
  }

  /// Sırayı bir basamak kaydırır; türün sıraları 10'ar aralıkla yeniden yazılır.
  Future<void> _move(Sponsor s, int delta) async {
    final same = (_sponsors ?? const <Sponsor>[])
        .where((x) => x.tier == s.tier)
        .toList();
    final i = same.indexWhere((x) => x.id == s.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= same.length) return;
    same.insert(j, same.removeAt(i));
    setState(() => _busy = true);
    try {
      for (var k = 0; k < same.length; k++) {
        if (same[k].sortOrder != (k + 1) * 10) {
          await _sb
              .from('sponsors')
              .update({'sort_order': (k + 1) * 10})
              .eq('id', same[k].id);
        }
      }
      await _loadSponsors();
    } catch (e) {
      _snack('Sıra değiştirilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Sponsor s) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Sponsoru Sil',
      message: '"${s.name}" sponsorlardan kaldırılacak.',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _sb.from('sponsors').delete().eq('id', s.id);
      if (s.logoUrl.isNotEmpty) {
        await SupabaseImageUploadService().deleteImageByUrl(s.logoUrl);
      }
      await _loadSponsors();
    } catch (e) {
      _snack('Silinemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Sponsor? sponsor, {String tier = 'main'}) async {
    final leagueId = _leagueId;
    if (leagueId == null) return;
    final saved = await showAdminPopup<bool>(
      context: context,
      builder: (_) => _SponsorForm(
        leagueId: leagueId,
        sponsor: sponsor,
        initialTier: sponsor?.tier ?? tier,
        nextOrder: (String t) {
          final same = (_sponsors ?? const <Sponsor>[]).where(
            (x) => x.tier == t,
          );
          return same.isEmpty
              ? 10
              : same.map((x) => x.sortOrder).reduce((a, b) => a > b ? a : b) +
                    10;
        },
      ),
    );
    if (saved == true) {
      await _loadSponsors();
      if (mounted) {
        _snack(sponsor == null ? 'Sponsor eklendi.' : 'Sponsor güncellendi.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSession.of(context).value;
    if (!s.isAdmin && !s.isLeagueOwner) {
      return const AdminPageScaffold(
        title: 'Sponsor Yönetimi',
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
    final sponsors = _sponsors;
    final Widget body;
    if (leagues == null || (_leagueId != null && sponsors == null)) {
      body = const Center(child: CircularProgressIndicator());
    } else if (leagues.isEmpty) {
      body = const Center(
        child: Text(
          'Yönetebildiğiniz turnuva yok.',
          style: TextStyle(color: kAdminMuted),
        ),
      );
    } else {
      Widget section(String title, String tier) {
        final items = sponsors!.where((x) => x.tier == tier).toList();
        return AdminFormSection(
          title: title,
          trailing: TextButton.icon(
            onPressed: _busy ? null : () => _edit(null, tier: tier),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Ekle'),
            style: TextButton.styleFrom(foregroundColor: kAdminAccent),
          ),
          child: items.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    tier == 'main'
                        ? 'Henüz ana sponsor yok.'
                        : 'Henüz alt sponsor yok.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kAdminMuted),
                  ),
                )
              : AdminFieldGroup(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _SponsorRow(
                        sponsor: items[i],
                        busy: _busy,
                        canUp: i > 0,
                        canDown: i < items.length - 1,
                        onUp: () => _move(items[i], -1),
                        onDown: () => _move(items[i], 1),
                        onEdit: () => _edit(items[i]),
                        onDelete: () => _delete(items[i]),
                      ),
                  ],
                ),
        );
      }

      body = RefreshIndicator(
        onRefresh: _loadSponsors,
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
                'Ana sayfadaki sponsor şeridinde önce ana sponsorlar, sonra alt '
                'sponsorlar sırayla gösterilir. Ekranda kalma süreleri Turnuva '
                'Yönetimi › turnuva düzenle ekranından ayarlanır.',
                style: TextStyle(
                  color: kAdminMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
            section('Ana Sponsorlar', 'main'),
            section('Alt Sponsorlar', 'sub'),
          ],
        ),
      );
    }
    return AdminPageScaffold(title: 'Sponsor Yönetimi', body: body);
  }
}

class _SponsorRow extends StatelessWidget {
  const _SponsorRow({
    required this.sponsor,
    required this.busy,
    required this.canUp,
    required this.canDown,
    required this.onUp,
    required this.onDown,
    required this.onEdit,
    required this.onDelete,
  });

  final Sponsor sponsor;
  final bool busy;
  final bool canUp;
  final bool canDown;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, bool on, VoidCallback f) => IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: busy || !on ? null : f,
      icon: Icon(icon, color: on ? Colors.white70 : Colors.white12),
    );
    return Opacity(
      opacity: sponsor.isActive ? 1 : 0.55,
      child: InkWell(
        onTap: busy ? null : onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: sponsor.logoUrl.isEmpty
                    ? const Icon(Icons.image_outlined, color: Colors.black26)
                    : WebSafeImage(url: sponsor.logoUrl, fit: BoxFit.contain),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sponsor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (!sponsor.isActive || sponsor.linkUrl != null)
                      Text(
                        sponsor.isActive ? sponsor.linkUrl! : 'Pasif',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kAdminMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              arrow(Icons.keyboard_arrow_up_rounded, canUp, onUp),
              arrow(Icons.keyboard_arrow_down_rounded, canDown, onDown),
              AdminSmallAction(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Sil',
                color: kAdminDanger,
                onTap: busy ? null : onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sponsor ekle / düzenle popup'ı.
class _SponsorForm extends StatefulWidget {
  const _SponsorForm({
    required this.leagueId,
    required this.sponsor,
    required this.initialTier,
    required this.nextOrder,
  });

  final String leagueId;
  final Sponsor? sponsor;
  final String initialTier;
  final int Function(String tier) nextOrder;

  @override
  State<_SponsorForm> createState() => _SponsorFormState();
}

class _SponsorFormState extends State<_SponsorForm> {
  late final _name = TextEditingController(text: widget.sponsor?.name ?? '');
  late final _link = TextEditingController(text: widget.sponsor?.linkUrl ?? '');
  late String _tier = widget.initialTier;
  late bool _active = widget.sponsor?.isActive ?? true;
  XFile? _newLogo;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final logo = await preparePickedLogo(picked);
    if (mounted) setState(() => _newLogo = logo);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sponsor adı zorunludur.')),
      );
      return;
    }
    var link = _link.text.trim();
    if (link.isNotEmpty && !link.startsWith('http')) link = 'https://$link';
    setState(() => _saving = true);
    final sb = Supabase.instance.client;
    final old = widget.sponsor;
    try {
      // Önce resim: yükleme başarısız olursa kayıt değişmez.
      String? logoUrl;
      if (_newLogo != null) {
        logoUrl = (await SupabaseImageUploadService().uploadImage(
          _newLogo!,
          folder: MediaFolder.sponsors,
        ))?.trim();
        if ((logoUrl ?? '').isEmpty) {
          throw Exception('Logo yüklenemedi, lütfen tekrar deneyin.');
        }
      }
      final payload = <String, dynamic>{
        'name': name,
        'tier': _tier,
        'link_url': link.isEmpty ? null : link,
        'is_active': _active,
        'logo_url': ?logoUrl,
        // Tür değişince yeni türün sonuna eklenir.
        if (old == null || old.tier != _tier)
          'sort_order': widget.nextOrder(_tier),
      };
      if (old == null) {
        await sb.from('sponsors').insert({
          ...payload,
          'league_id': widget.leagueId,
        });
      } else {
        await sb.from('sponsors').update(payload).eq('id', old.id);
        if (logoUrl != null && old.logoUrl.isNotEmpty) {
          await SupabaseImageUploadService().deleteImageByUrl(old.logoUrl);
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.sponsor != null;
    final existing = widget.sponsor?.logoUrl ?? '';
    final Widget logo;
    if (_newLogo != null) {
      logo = Image(image: pickedImageProvider(_newLogo!), fit: BoxFit.contain);
    } else if (existing.isNotEmpty) {
      logo = WebSafeImage(url: existing, fit: BoxFit.contain);
    } else {
      logo = const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined, color: Colors.black38),
          SizedBox(height: 4),
          Text(
            'Logo seç',
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ],
      );
    }
    Widget tierChip(String value, String label) {
      final sel = _tier == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _saving ? null : () => setState(() => _tier = value),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? kAdminAccent.withValues(alpha: 0.18) : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: sel
                    ? kAdminAccent
                    : Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: sel ? Colors.white : Colors.white70,
                fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    final viewInsets = MediaQuery.of(context).viewInsets;
    return AdminDialogCloseOverlay(
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminDialogHeader(
            icon: Icons.handshake_rounded,
            title: isEdit ? 'Sponsoru Düzenle' : 'Sponsor Ekle',
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12 + viewInsets.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _saving ? null : _pickLogo,
                      child: Container(
                        width: 200,
                        height: 100,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: logo,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 16),
                    child: Text(
                      'Logoya dokunarak değiştirin. Şeritte beyaz zeminde '
                      'görünür.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kAdminMuted, fontSize: 12),
                    ),
                  ),
                  Row(
                    children: [
                      tierChip('main', 'Ana Sponsor'),
                      const SizedBox(width: 10),
                      tierChip('sub', 'Alt Sponsor'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _name,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    cursorColor: kAdminAccent,
                    decoration: adminInputDecoration(
                      label: 'Sponsor Adı',
                      icon: Icons.storefront_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _link,
                    enabled: !_saving,
                    keyboardType: TextInputType.url,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: kAdminAccent,
                    decoration: adminInputDecoration(
                      label: 'Link (isteğe bağlı)',
                      hint: 'web sitesi ya da Instagram adresi',
                      icon: Icons.link_rounded,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    value: _active,
                    activeThumbColor: kAdminAccent,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _active = v),
                    title: const Text(
                      'Şeritte göster',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Kapalıysa sponsor kayıtlı kalır ama gösterilmez.',
                      style: TextStyle(color: kAdminMuted, fontSize: 12),
                    ),
                  ),
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
