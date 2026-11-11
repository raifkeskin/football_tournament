import 'package:flutter/material.dart';
import '../../core/utils/friendly_error.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/active_tournament.dart';
import '../../core/services/app_session.dart';
import '../../core/services/image_upload_service.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/photo_crop_screen.dart';
import '../../core/widgets/picked_image.dart';
import '../../core/widgets/web_safe_image.dart';
import '../auth/widgets/phone_input.dart';
import 'media_credit.dart';
import 'media_credit_card.dart';

/// Medya Künyesi: turnuvanın fotoğrafçısı ve yayıncısı. Maç detayı Medya
/// sekmesinde etiket olarak görünür, dokununca kartvizit açılır. Yalnızca
/// admin ve turnuvanın kurucu başkanları.
class AdminMediaCreditsScreen extends StatefulWidget {
  const AdminMediaCreditsScreen({super.key});

  @override
  State<AdminMediaCreditsScreen> createState() =>
      _AdminMediaCreditsScreenState();
}

class _AdminMediaCreditsScreenState extends State<AdminMediaCreditsScreen> {
  SupabaseClient get _sb => Supabase.instance.client;

  List<LeagueChoice>? _leagues;
  String? _leagueId;
  List<MediaCredit>? _credits;
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
      await _loadCredits();
    } catch (e) {
      if (mounted) _snack('Turnuvalar yüklenemedi: $e');
    }
  }

  Future<void> _loadCredits() async {
    final id = _leagueId;
    if (id == null) return;
    try {
      // Turnuvanın rehberden bağladığı kişiler (gizlenmişler dahil).
      final rows = await _sb
          .from('league_media_credits')
          .select('is_default, media_credits(*)')
          .eq('league_id', id);
      if (!mounted || id != _leagueId) return;
      setState(
        () => _credits = [
          for (final r in rows)
            if (r['media_credits'] is Map)
              MediaCredit.fromMap({
                ...Map<String, dynamic>.from(r['media_credits'] as Map),
                'league_id': id,
                'is_default': r['is_default'] == true,
              }),
        ],
      );
    } catch (e) {
      if (mounted) _snack('Künye yüklenemedi: $e');
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
      _credits = null;
    });
    await _loadCredits();
  }

  /// Kişiyi bu turnuvanın listesinden çıkarır; rehberde ve diğer
  /// turnuvalarda kalır.
  Future<void> _delete(MediaCredit c) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Turnuvadan Çıkar',
      message:
          '"${c.name}" bu turnuvanın medya listesinden çıkarılacak. Kişi '
          'medya rehberinde ve görev aldığı diğer turnuvalarda kalır.',
      confirmLabel: 'ÇIKAR',
    );
    if (!ok) return;
    final leagueId = _leagueId;
    if (leagueId == null) return;
    setState(() => _busy = true);
    try {
      await MediaDirectory.unlink(leagueId, c.id);
      await _loadCredits();
    } catch (e) {
      _snack('Çıkarılamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Türün varsayılanı: ekibi ayrıca seçilmemiş maçlarda bu kişi görünür.
  Future<void> _makeDefault(MediaCredit c) async {
    final leagueId = _leagueId;
    if (leagueId == null) return;
    setState(() => _busy = true);
    try {
      await MediaDirectory.makeDefault(leagueId, c);
      await _loadCredits();
    } catch (e) {
      _snack('Kaydedilemedi: ${friendlyErrorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ekle: önce rehberde aranır; yoksa yeni kişi açılır.
  Future<void> _add(MediaCreditKind kind) async {
    final leagueId = _leagueId;
    if (leagueId == null) return;
    final added = await showMediaCreditPicker(
      context,
      leagueId: leagueId,
      kind: kind,
      exclude: {for (final c in _credits ?? const <MediaCredit>[]) c.id},
    );
    if (added != null) {
      await _loadCredits();
      if (mounted) _snack('"${added.name}" turnuvaya eklendi.');
    }
  }

  Future<void> _edit(MediaCreditKind kind, MediaCredit? credit) async {
    final leagueId = _leagueId;
    if (leagueId == null) return;
    final saved = await showAdminPopup<MediaCredit>(
      context: context,
      builder: (_) =>
          MediaCreditForm(leagueId: leagueId, kind: kind, credit: credit),
    );
    if (saved != null) {
      await _loadCredits();
      if (mounted) {
        _snack(credit == null ? 'Künye eklendi.' : 'Künye güncellendi.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSession.of(context).value;
    if (!s.isAdmin && !s.isLeagueOwner) {
      return const AdminPageScaffold(
        title: 'Medya Künyesi',
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
    final credits = _credits;
    final Widget body;
    if (leagues == null || (_leagueId != null && credits == null)) {
      body = const Center(child: CircularProgressIndicator());
    } else if (leagues.isEmpty) {
      body = const Center(
        child: Text(
          'Yönetebildiğiniz turnuva yok.',
          style: TextStyle(color: kAdminMuted),
        ),
      );
    } else {
      Widget section(MediaCreditKind kind) {
        final list = [
          for (final x in credits!)
            if (x.kind == kind) x,
        ]..sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));
        return AdminFormSection(
          title: kind.label,
          trailing: TextButton.icon(
            onPressed: _busy ? null : () => _add(kind),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Ekle'),
            style: TextButton.styleFrom(foregroundColor: kAdminAccent),
          ),
          child: list.isEmpty
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
                    'Henüz ${kind.label.toLowerCase()} eklenmedi.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kAdminMuted),
                  ),
                )
              : AdminFieldGroup(
                  children: [
                    for (final c in list)
                      _CreditRow(
                        credit: c,
                        busy: _busy,
                        onEdit: () => _edit(kind, c),
                        onPreview: () => showMediaCreditCard(context, c),
                        onDelete: () => _delete(c),
                        onMakeDefault: c.isDefault || list.length < 2
                            ? null
                            : () => _makeDefault(c),
                      ),
                  ],
                ),
        );
      }

      body = RefreshIndicator(
        onRefresh: _loadCredits,
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
                'Kişiler medya rehberinde bir kez kayıtlıdır; Ekle ile '
                'rehberden turnuvaya bağlanır (yoksa yeni kişi açılır). '
                'Bilgileri düzenlemek görev aldığı tüm turnuvalarda geçerli '
                'olur. Ekibi ayrıca seçilmemiş maçlarda varsayılan (★) '
                'görünür; maçın ekibi maç detayındaki Düzenle ile seçilir.',
                style: TextStyle(
                  color: kAdminMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
            section(MediaCreditKind.photo),
            section(MediaCreditKind.broadcast),
          ],
        ),
      );
    }
    return AdminPageScaffold(title: 'Medya Künyesi', body: body);
  }
}

class _CreditRow extends StatelessWidget {
  const _CreditRow({
    required this.credit,
    required this.busy,
    required this.onEdit,
    required this.onPreview,
    required this.onDelete,
    this.onMakeDefault,
  });

  final MediaCredit credit;

  /// Türün varsayılanı yap (aynı türden birden çok kişi varsa).
  final VoidCallback? onMakeDefault;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onPreview;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = credit;
    return Opacity(
      opacity: c.isActive ? 1 : 0.55,
      child: InkWell(
        onTap: busy ? null : onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF064E3B),
                child: c.avatarUrl == null
                    ? Icon(
                        c.kind == MediaCreditKind.photo
                            ? Icons.photo_camera_outlined
                            : Icons.videocam_outlined,
                        color: kAdminAccent,
                      )
                    : ClipOval(
                        child: WebSafeImage(
                          url: c.avatarUrl!,
                          width: 44,
                          height: 44,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
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
                        if (c.isDefault) 'Varsayılan',
                        c.displayTitle,
                        if (!c.isActive) 'Gizli',
                        if (c.contactConsent && c.phone != null)
                          formatPhoneRaw10(normalizePhoneToRaw10(c.phone!)),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kAdminMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (onMakeDefault != null)
                AdminSmallAction(
                  icon: Icons.star_outline_rounded,
                  tooltip: 'Varsayılan yap',
                  color: const Color(0xFFFACC15),
                  onTap: busy ? null : onMakeDefault,
                ),
              AdminSmallAction(
                icon: Icons.visibility_outlined,
                tooltip: 'Kartviziti gör',
                color: Colors.white70,
                onTap: busy ? null : onPreview,
              ),
              AdminSmallAction(
                icon: Icons.link_off_rounded,
                tooltip: 'Turnuvadan çıkar',
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

/// Turnuvaya medya kişisi ekler: rehberde ada göre aranır (turnuvada
/// olmayanlar); bulunamazsa "Yeni kişi" formu açılır. Eklenen kişiyi döner.
Future<MediaCredit?> showMediaCreditPicker(
  BuildContext context, {
  required String leagueId,
  required MediaCreditKind kind,
  Set<String> exclude = const {},
}) async {
  final picked = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _DirectoryPicker(kind: kind, exclude: exclude),
  );
  if (!context.mounted) return null;
  if (picked is MediaCredit) {
    await MediaDirectory.link(leagueId, picked);
    return picked;
  }
  if (picked == 'new') {
    return showAdminPopup<MediaCredit>(
      context: context,
      builder: (_) =>
          MediaCreditForm(leagueId: leagueId, kind: kind, credit: null),
    );
  }
  return null;
}

class _DirectoryPicker extends StatefulWidget {
  const _DirectoryPicker({required this.kind, required this.exclude});

  final MediaCreditKind kind;
  final Set<String> exclude;

  @override
  State<_DirectoryPicker> createState() => _DirectoryPickerState();
}

class _DirectoryPickerState extends State<_DirectoryPicker> {
  List<MediaCredit>? _all;
  String _q = '';

  @override
  void initState() {
    super.initState();
    MediaDirectory.all(widget.kind).then((l) {
      if (mounted) setState(() => _all = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = [
      for (final c in _all ?? const <MediaCredit>[])
        if (!widget.exclude.contains(c.id) &&
            (q.isEmpty ||
                c.name.toLowerCase().contains(q) ||
                (c.title ?? '').toLowerCase().contains(q) ||
                (c.instagram ?? '').toLowerCase().contains(q)))
          c,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              Text(
                '${widget.kind.label} ekle',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Önce medya rehberinde ara; kişi kayıtlıysa seç, yoksa yeni '
                'kişi ekle. Aynı kişi birden çok turnuvada görev alabilir.',
                style: TextStyle(color: kAdminMuted, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _q = v),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Ad, unvan ya da Instagram',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              if (_all == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    q.isEmpty
                        ? 'Rehberde eklenebilecek ${widget.kind.label.toLowerCase()} yok.'
                        : 'Rehberde bulunamadı.',
                    style: const TextStyle(color: kAdminMuted),
                  ),
                )
              else
                for (final c in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => Navigator.of(context).pop(c),
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF064E3B),
                      child: c.avatarUrl == null
                          ? const Icon(
                              Icons.person_rounded,
                              color: kAdminAccent,
                            )
                          : ClipOval(
                              child: WebSafeImage(
                                url: c.avatarUrl!,
                                width: 40,
                                height: 40,
                              ),
                            ),
                    ),
                    title: Text(
                      c.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      c.displayTitle,
                      style: const TextStyle(color: kAdminMuted, fontSize: 12),
                    ),
                    trailing: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: kAdminAccent,
                    ),
                  ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop('new'),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Yeni kişi ekle'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAdminAccent,
                  side: const BorderSide(color: kAdminAccent),
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Künye ekle / düzenle popup'ı: Genel (fotoğraf, ad, unvan, not) ve
/// İletişim (telefon, e-posta, Instagram, YouTube, onay) sekmeleri.
class MediaCreditForm extends StatefulWidget {
  const MediaCreditForm({
    super.key,
    required this.leagueId,
    required this.kind,
    required this.credit,
  });

  final String leagueId;
  final MediaCreditKind kind;
  final MediaCredit? credit;

  @override
  State<MediaCreditForm> createState() => _MediaCreditFormState();
}

class _MediaCreditFormState extends State<MediaCreditForm> {
  late final _name = TextEditingController(text: widget.credit?.name ?? '');
  late final _title = TextEditingController(text: widget.credit?.title ?? '');
  late final _note = TextEditingController(text: widget.credit?.note ?? '');
  late final _phone = TextEditingController(
    text: (widget.credit?.phone ?? '').isEmpty
        ? ''
        : PhoneMaskFormatter.formatFromRaw(widget.credit!.phone!),
  );
  late final _email = TextEditingController(text: widget.credit?.email ?? '');
  late final _instagram = TextEditingController(
    text: widget.credit?.instagram ?? '',
  );
  late final _youtube = TextEditingController(
    text: widget.credit?.youtubeUrl ?? '',
  );
  late bool _consent = widget.credit?.contactConsent ?? false;
  late bool _active = widget.credit?.isActive ?? true;
  late bool _removeAvatar = false;
  XFile? _newAvatar;
  int _tab = 0;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _title,
      _note,
      _phone,
      _email,
      _instagram,
      _youtube,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await pickAndCropAvatarPhoto(context);
    if (picked == null || !mounted) return;
    setState(() {
      _newAvatar = picked;
      _removeAvatar = false;
    });
  }

  String? _clean(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    void fail(String text, int tab) {
      setState(() => _tab = tab);
      messenger.showSnackBar(SnackBar(content: Text(text)));
    }

    final name = _name.text.trim();
    if (name.isEmpty) return fail('Ad zorunludur.', 0);
    // Telefon her yerde olduğu gibi 10 hane (5XX…) saklanır.
    final rawPhone = normalizePhoneToRaw10(_phone.text);
    final phone = rawPhone.isEmpty ? null : rawPhone;
    final email = _clean(_email)?.toLowerCase();
    if (phone != null && (phone.length != 10 || !phone.startsWith('5'))) {
      return fail('Telefon numarası 5 ile başlayan 10 hane olmalı.', 1);
    }
    if (email != null && !isValidEmail(email)) {
      return fail('E-posta adresi geçersiz.', 1);
    }
    if ((phone != null || email != null) && !_consent) {
      return fail(
        'Telefon ve e-posta herkese açık görünür; kişinin onayını işaretleyin.',
        1,
      );
    }
    var youtube = _clean(_youtube);
    if (youtube != null && !youtube.startsWith('http')) {
      youtube = 'https://$youtube';
    }

    setState(() => _saving = true);
    final sb = Supabase.instance.client;
    final old = widget.credit;
    final upload = SupabaseImageUploadService();
    try {
      // Önce resim: yükleme başarısız olursa kayıt değişmez.
      String? avatarUrl;
      if (_newAvatar != null) {
        avatarUrl = (await upload.uploadImage(
          _newAvatar!,
          folder: MediaFolder.players,
          subfolder: 'kunye',
        ))?.trim();
        if ((avatarUrl ?? '').isEmpty) {
          throw Exception('Fotoğraf yüklenemedi, lütfen tekrar deneyin.');
        }
      }
      final payload = <String, dynamic>{
        'name': name,
        'title': _clean(_title),
        'note': _clean(_note),
        'phone': phone,
        'email': email,
        'instagram': _clean(_instagram)?.replaceFirst('@', ''),
        'youtube_url': youtube,
        'contact_consent': _consent,
        'is_active': _active,
        if (avatarUrl != null || _removeAvatar) 'avatar_url': avatarUrl,
      };
      MediaCredit? created;
      if (old == null) {
        // Rehbere yeni kişi; sonra bu turnuvaya bağlanır.
        final row = await sb
            .from('media_credits')
            .insert({
              ...payload,
              'league_id': widget.leagueId,
              'kind': widget.kind.name,
            })
            .select()
            .single();
        created = MediaCredit.fromMap(row);
        await MediaDirectory.link(widget.leagueId, created);
      } else {
        await sb.from('media_credits').update(payload).eq('id', old.id);
        if (avatarUrl != null || _removeAvatar) {
          await deleteCreditAvatarIfUnused(old.avatarUrl);
        }
      }
      MediaCreditFeed.notifyChanged(widget.leagueId);
      if (mounted) Navigator.of(context).pop(created ?? old);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: ${friendlyErrorText(e)}')));
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController c,
    IconData icon,
    String label, {
    String? hint,
    TextInputType? keyboard,
    TextCapitalization caps = TextCapitalization.none,
    int maxLines = 1,
    int? maxLength,
    List<TextInputFormatter>? formatters,
    String? prefixText,
  }) {
    return AdminFieldRow(
      icon: icon,
      label: label,
      child: TextField(
        controller: c,
        enabled: !_saving,
        keyboardType: keyboard,
        textCapitalization: caps,
        maxLines: maxLines,
        minLines: 1,
        maxLength: maxLength,
        inputFormatters: formatters,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        cursorColor: kAdminAccent,
        decoration: adminInlineInputDecoration(hint: hint).copyWith(
          counterText: '',
          prefixText: prefixText,
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
    final isEdit = widget.credit != null;
    final isPhoto = widget.kind == MediaCreditKind.photo;
    final existing = _removeAvatar ? null : widget.credit?.avatarUrl;
    final Widget avatar;
    if (_newAvatar != null) {
      avatar = Image(
        image: pickedImageProvider(_newAvatar!),
        fit: BoxFit.cover,
      );
    } else if (existing != null) {
      avatar = WebSafeImage(url: existing, width: 88, height: 88);
    } else {
      avatar = Icon(
        isPhoto
            ? Icons.add_a_photo_outlined
            : Icons.add_photo_alternate_outlined,
        color: kAdminAccent,
        size: 30,
      );
    }

    final general = <Widget>[
      Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: _saving ? null : _pickAvatar,
              child: Container(
                width: 88,
                height: 88,
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF064E3B),
                  border: Border.all(color: kAdminAccent, width: 2),
                ),
                child: avatar,
              ),
            ),
            if (_newAvatar != null || existing != null)
              Positioned(
                right: -4,
                top: -4,
                child: GestureDetector(
                  onTap: _saving
                      ? null
                      : () => setState(() {
                          _newAvatar = null;
                          _removeAvatar = true;
                        }),
                  child: const CircleAvatar(
                    radius: 13,
                    backgroundColor: kAdminDanger,
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 14),
        child: Text(
          isPhoto
              ? 'Fotoğrafçının fotoğrafı (isteğe bağlı)'
              : 'Logo (isteğe bağlı)',
          textAlign: TextAlign.center,
          style: const TextStyle(color: kAdminMuted, fontSize: 12),
        ),
      ),
      AdminFieldGroup(
        children: [
          _field(
            _name,
            isPhoto ? Icons.person_outline_rounded : Icons.live_tv_rounded,
            'Ad',
            hint: isPhoto ? 'Ekrem Ayyüz' : 'Özsoy tv',
            caps: TextCapitalization.words,
            maxLength: 80,
          ),
          _field(
            _title,
            Icons.badge_outlined,
            'Unvan',
            hint: widget.kind.defaultTitle,
            caps: TextCapitalization.sentences,
            maxLength: 60,
          ),
          _field(
            _note,
            Icons.notes_rounded,
            'Kartvizit notu (isteğe bağlı)',
            hint: isPhoto
                ? 'Baskı ve özel çekim için ulaşın.'
                : 'Maçınızın yayını için ulaşın.',
            caps: TextCapitalization.sentences,
            maxLines: 3,
            maxLength: 300,
          ),
        ],
      ),
      const SizedBox(height: 12),
      AdminFieldGroup(
        children: [
          SwitchListTile(
            value: _active,
            activeThumbColor: kAdminAccent,
            onChanged: _saving ? null : (v) => setState(() => _active = v),
            title: const Text(
              'Medya sekmesinde göster',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text(
              'Kapalıysa künye kayıtlı kalır ama görünmez.',
              style: TextStyle(color: kAdminMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    ];

    final contact = <Widget>[
      AdminFieldGroup(
        children: [
          _field(
            _phone,
            Icons.call_outlined,
            'Telefon',
            hint: '(5XX) XXX XX XX',
            keyboard: TextInputType.phone,
            formatters: [PhoneMaskFormatter()],
            prefixText: '0 ',
          ),
          _field(
            _email,
            Icons.mail_outline_rounded,
            'E-posta',
            hint: 'ornek@mail.com',
            keyboard: TextInputType.emailAddress,
          ),
          _field(
            _instagram,
            Icons.camera_alt_outlined,
            'Instagram',
            hint: 'kullanıcı adı',
          ),
          if (!isPhoto || _youtube.text.isNotEmpty)
            _field(
              _youtube,
              Icons.smart_display_outlined,
              'YouTube kanalı',
              hint: 'youtube.com/@kanal',
              keyboard: TextInputType.url,
            ),
        ],
      ),
      const SizedBox(height: 12),
      AdminFieldGroup(
        children: [
          CheckboxListTile(
            value: _consent,
            activeColor: kAdminAccent,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: _saving
                ? null
                : (v) => setState(() => _consent = v ?? false),
            title: const Text(
              'Kişinin onayı alındı',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text(
              'Telefon ve e-posta kartvizitte herkese açık görünür. Onay '
              'yoksa bu alanları boş bırakın.',
              style: TextStyle(color: kAdminMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    ];

    final viewInsets = MediaQuery.of(context).viewInsets;
    return AdminDialogCloseOverlay(
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminDialogHeader(
            icon: isPhoto
                ? Icons.photo_camera_outlined
                : Icons.videocam_outlined,
            title: isEdit
                ? '${widget.kind.label} Düzenle'
                : '${widget.kind.label} Ekle',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: AdminFormTabs(
              labels: const ['Genel', 'İletişim'],
              selected: _tab,
              onChanged: _saving ? null : (i) => setState(() => _tab = i),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 12 + viewInsets.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _tab == 0 ? general : contact,
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

/// Künye fotoğrafını depodan siler; başka turnuvaya aktarılmış bir künye
/// aynı dosyayı kullanıyorsa dokunmaz.
Future<void> deleteCreditAvatarIfUnused(String? url) async {
  if (url == null || url.isEmpty) return;
  try {
    final users = await Supabase.instance.client
        .from('media_credits')
        .select('id')
        .eq('avatar_url', url)
        .limit(1);
    if (users.isNotEmpty) return;
    await SupabaseImageUploadService().deleteImageByUrl(url);
  } catch (_) {
    // Dosya kalırsa yalnız depoda yer kaplar.
  }
}
