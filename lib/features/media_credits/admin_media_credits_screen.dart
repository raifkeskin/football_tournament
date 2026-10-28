import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/active_tournament.dart';
import '../../core/services/app_session.dart';
import '../../core/services/image_upload_service.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
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
      final rows = await _sb.from('media_credits').select().eq('league_id', id);
      if (!mounted || id != _leagueId) return;
      setState(() => _credits = [for (final r in rows) MediaCredit.fromMap(r)]);
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

  Future<void> _delete(MediaCredit c) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Künyeyi Sil',
      message: '"${c.name}" medya künyesinden kaldırılacak.',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _sb.from('media_credits').delete().eq('id', c.id);
      await deleteCreditAvatarIfUnused(c.avatarUrl);
      MediaCreditFeed.notifyChanged(c.leagueId);
      await _loadCredits();
    } catch (e) {
      _snack('Silinemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Künyeyi yönetilen başka bir turnuvaya kopyalar (oradaki aynı türdeki
  /// künyenin yerine geçer); her turnuvada yeniden girmek gerekmez.
  Future<void> _copyTo(MediaCredit c) async {
    final targets = [
      for (final l in _leagues ?? const <LeagueChoice>[])
        if (l.id != c.leagueId) l,
    ];
    if (targets.isEmpty) return;
    final target = await showAdminOptionPicker<LeagueChoice>(
      context: context,
      title: 'Hangi turnuvaya aktarılsın?',
      items: targets,
      labelBuilder: (l) => l.name,
    );
    if (target == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final existing = await _sb
          .from('media_credits')
          .select('id, name, avatar_url')
          .eq('league_id', target.id)
          .eq('kind', c.kind.name)
          .maybeSingle();
      if (existing != null && mounted) {
        final ok = await showAdminConfirmDialog(
          context: context,
          title: 'Künye Değişsin mi?',
          message:
              '${target.name} turnuvasında ${c.kind.label.toLowerCase()} '
              'olarak "${existing['name']}" kayıtlı. Yerine "${c.name}" '
              'yazılacak.',
        );
        if (!ok) return;
      }
      final row = c.toMap()
        ..remove('id')
        ..remove('created_at')
        ..remove('updated_at')
        ..['league_id'] = target.id;
      await _sb.from('media_credits').upsert(row, onConflict: 'league_id,kind');
      final oldAvatar = existing?['avatar_url'] as String?;
      if (oldAvatar != null && oldAvatar != c.avatarUrl) {
        await deleteCreditAvatarIfUnused(oldAvatar);
      }
      MediaCreditFeed.notifyChanged(target.id);
      _snack('"${c.name}" ${target.name} turnuvasına aktarıldı.');
    } catch (e) {
      _snack('Aktarılamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(MediaCreditKind kind, MediaCredit? credit) async {
    final leagueId = _leagueId;
    if (leagueId == null) return;
    final saved = await showAdminPopup<bool>(
      context: context,
      builder: (_) =>
          _MediaCreditForm(leagueId: leagueId, kind: kind, credit: credit),
    );
    if (saved == true) {
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
        final c = credits!.where((x) => x.kind == kind).firstOrNull;
        return AdminFormSection(
          title: kind.label,
          trailing: c != null
              ? null
              : TextButton.icon(
                  onPressed: _busy ? null : () => _edit(kind, null),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Ekle'),
                  style: TextButton.styleFrom(foregroundColor: kAdminAccent),
                ),
          child: c == null
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
                    _CreditRow(
                      credit: c,
                      busy: _busy,
                      onEdit: () => _edit(kind, c),
                      onPreview: () => showMediaCreditCard(context, c),
                      onDelete: () => _delete(c),
                      onCopy: leagues.length > 1 ? () => _copyTo(c) : null,
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
                'Maç detayının Bilgi sekmesinde (kâğıt ikonu) ve Medya '
                'sekmesinde görünür; dokununca kartvizit açılır. Başka '
                'turnuvaya aktarmak için satırdaki aktar düğmesini kullanın.',
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
    this.onCopy,
  });

  final MediaCredit credit;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onPreview;
  final VoidCallback onDelete;

  /// Başka turnuvaya aktar (birden çok turnuva yönetiliyorsa).
  final VoidCallback? onCopy;

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
              AdminSmallAction(
                icon: Icons.visibility_outlined,
                tooltip: 'Kartviziti gör',
                color: Colors.white70,
                onTap: busy ? null : onPreview,
              ),
              if (onCopy != null)
                AdminSmallAction(
                  icon: Icons.drive_file_move_outline,
                  tooltip: 'Başka turnuvaya aktar',
                  color: kAdminAccent,
                  onTap: busy ? null : onCopy,
                ),
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

/// Künye ekle / düzenle popup'ı: Genel (fotoğraf, ad, unvan, not) ve
/// İletişim (telefon, e-posta, Instagram, YouTube, onay) sekmeleri.
class _MediaCreditForm extends StatefulWidget {
  const _MediaCreditForm({
    required this.leagueId,
    required this.kind,
    required this.credit,
  });

  final String leagueId;
  final MediaCreditKind kind;
  final MediaCredit? credit;

  @override
  State<_MediaCreditForm> createState() => _MediaCreditFormState();
}

class _MediaCreditFormState extends State<_MediaCreditForm> {
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
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
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
      if (old == null) {
        await sb.from('media_credits').insert({
          ...payload,
          'league_id': widget.leagueId,
          'kind': widget.kind.name,
        });
      } else {
        await sb.from('media_credits').update(payload).eq('id', old.id);
        if (avatarUrl != null || _removeAvatar) {
          await deleteCreditAvatarIfUnused(old.avatarUrl);
        }
      }
      MediaCreditFeed.notifyChanged(widget.leagueId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
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
