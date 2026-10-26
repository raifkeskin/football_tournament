import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/web_safe_image.dart';
import '../auth/widgets/phone_input.dart';
import 'id_card_reader.dart';
import 'identity_service.dart';
import 'verified_badge.dart';

/// Kimlik doğrulama: kimlik kartının arka yüzü okutulur (çipin kilidi),
/// çip NFC ile okunur, çipteki ad, soyad, doğum tarihi ve TC no ile
/// eşleşen profil onaylanır (mavi tik). Maç günü sorumlu aynı ekrandan
/// sırayla bütün takımı okutabilir ("Sıradaki kimlik").
///
/// [expectedPlayerId]: esameden "Kimliği okut" ile gelindiyse o oyuncu;
/// onaylanınca ekran true ile kapanır.
class IdentityVerifyScreen extends StatefulWidget {
  const IdentityVerifyScreen({
    super.key,
    this.expectedPlayerId,
    this.expectedName,
    this.registration = false,
  });

  final String? expectedPlayerId;
  final String? expectedName;

  /// Kayıt Ol (giriş yapılmamış): çip okununca profil aranmaz, okunan
  /// bilgilerle ekran kapanır ([readForRegistration]).
  final bool registration;

  /// Kayıt Ol akışı: kimlik okunur, çipteki bilgiler döner. Vazgeçilirse null.
  static Future<IdCardData?> readForRegistration(BuildContext context) =>
      Navigator.of(context).push<IdCardData>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'IdentityRegisterScreen'),
          builder: (_) => const IdentityVerifyScreen(registration: true),
        ),
      );

  static Future<bool?> open(
    BuildContext context, {
    String? expectedPlayerId,
    String? expectedName,
  }) => Navigator.of(context).push<bool>(
    MaterialPageRoute(
      settings: const RouteSettings(name: 'IdentityVerifyScreen'),
      builder: (_) => IdentityVerifyScreen(
        expectedPlayerId: expectedPlayerId,
        expectedName: expectedName,
      ),
    ),
  );

  @override
  State<IdentityVerifyScreen> createState() => _IdentityVerifyScreenState();
}

class _IdentityVerifyScreenState extends State<IdentityVerifyScreen>
    with WidgetsBindingObserver {
  NfcState? _nfc;
  IdCardKey? _key;
  IdCardData? _card;
  List<IdentityCandidate>? _candidates;
  String? _verifiedId;
  String? _error;
  String? _status;
  bool _busy = false;
  int _count = 0;

  static const _blue = kVerifiedBlue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkNfc();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// NFC ayarından dönünce durum yeniden okunur.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _nfc != NfcState.available) {
      _checkNfc();
    }
  }

  Future<void> _checkNfc() async {
    final s = await IdCardReader.nfcState();
    if (mounted) setState(() => _nfc = s);
  }

  void _reset() => setState(() {
    _key = null;
    _card = null;
    _candidates = null;
    _verifiedId = null;
    _error = null;
    _status = null;
  });

  /// Canlı kamera: kart algılanınca kapanır; çip okuması butonla başlar.
  Future<void> _scanBack() async {
    setState(() => _error = null);
    final r = await IdCardReader.scanLive(context);
    if (!mounted || r == null) return;
    if (r.key != null) {
      // Çip okuması kullanıcı ÇİPİ OKU'ya basınca başlar.
      setState(() => _key = r.key);
    } else if (r.fallback == 'photo') {
      await _scanPhoto();
    } else if (r.fallback == 'manual') {
      await _manualKey();
    }
  }

  /// Yedek yol: arka yüzün fotoğrafı çekilir.
  Future<void> _scanPhoto() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final key = await IdCardReader.scanBackSide();
      if (!mounted || key == null) return;
      setState(() => _key = key);
    } on IdCardError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kamera açılamadı. Bilgileri elle girin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manualKey() async {
    final key = await showDialog<IdCardKey>(
      context: context,
      builder: (_) => _ManualKeyDialog(initial: _key),
    );
    if (key == null || !mounted) return;
    setState(() {
      _key = key;
      _error = null;
    });
  }

  Future<void> _readChip() async {
    final key = _key;
    if (key == null) return;
    if (_nfc != NfcState.available) {
      await _checkNfc();
      if (_nfc != NfcState.available) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _card = null;
      _candidates = null;
      _status = 'Kartı telefonun arkasına yaklaştırın';
    });
    try {
      final card = await IdCardReader.readChip(
        key,
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      if (!mounted) return;
      if (widget.registration) {
        Navigator.of(context).pop(card);
        return;
      }
      setState(() {
        _card = card;
        _status = 'Profil aranıyor…';
      });
      final list = await IdentityService.candidates(
        firstName: card.firstName,
        lastName: card.lastName,
        birthDate: card.birthDate,
        tc: card.tc,
      );
      if (!mounted) return;
      setState(() {
        _candidates = list;
        _status = null;
        final done = list.where((c) => c.matchKind == 'tc').firstOrNull;
        if (done != null) _verifiedId = done.playerId;
      });
    } on IdCardError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = IdentityService.errorText(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _verify(IdentityCandidate c) async {
    final card = _card;
    if (card == null) return;
    if (c.matchKind != 'exact') {
      final ok = await showAdminConfirmDialog(
        context: context,
        title: 'Bu profil mi?',
        message: c.matchKind == 'year' || c.matchKind == 'name'
            ? 'Kimlikteki ad: ${card.fullName}\nProfil: ${c.fullName}\n\n'
                  'Doğum tarihi${c.matchKind == 'name' ? ' ve ad soyad' : ''} '
                  'tutmuyor. Doğru kişiyse onaylayın; profil kimlikteki '
                  'bilgilerle düzeltilir.'
            : 'Kimlikteki ad: ${card.fullName}\nProfil: ${c.fullName}\n\n'
                  'Ad soyad tam tutmuyor. Doğru kişi olduğundan eminseniz '
                  'onaylayın.',
        confirmLabel: 'ONAYLA',
        destructive: false,
        icon: Icons.verified_outlined,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await IdentityService.verify(
        playerId: c.playerId,
        firstName: card.firstName,
        lastName: card.lastName,
        birthDate: card.birthDate,
        tc: card.tc,
      );
      if (!mounted) return;
      setState(() {
        _verifiedId = c.playerId;
        _count++;
      });
      await _askPhone(c);
      if (!mounted) return;
      if (widget.expectedPlayerId != null &&
          widget.expectedPlayerId == c.playerId) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = IdentityService.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Doğrulanan profilde numara yoksa yetkili numarayı hemen girer;
  /// futbolcu ilk girişinde bu numaraya gelen kodla şifresini belirler.
  Future<void> _askPhone(IdentityCandidate c) async {
    final String state;
    try {
      state = await IdentityService.phoneState(c.playerId);
    } catch (_) {
      return;
    }
    if (state != 'none' || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final value = await showAdminTextInputDialog(
      context: context,
      title: 'Telefon Numarası',
      subtitle:
          '${c.fullName} profilinde numara yok. Numarayı yazarsanız '
          'futbolcu ilk girişinde bu numaraya gelen kodla şifresini '
          'belirler. Kapatırsanız profil numarasız kalır.',
      icon: Icons.phone_iphone_rounded,
      label: 'Cep telefonu',
      fieldIcon: Icons.phone_rounded,
      hint: '(5XX) XXX XX XX',
      keyboardType: TextInputType.phone,
      inputFormatters: [PhoneMaskFormatter()],
      validator: (v) {
        final raw = normalizePhoneToRaw10(v);
        if (!RegExp(r'^5\d{9}$').hasMatch(raw)) {
          return 'Geçerli bir cep telefonu numarası girin.';
        }
        return null;
      },
    );
    if (value == null || !mounted) return;
    final raw = normalizePhoneToRaw10(value);
    try {
      final r = await IdentityService.setPhone(c.playerId, raw);
      if (!mounted) return;
      final text = switch (r) {
        'ok' =>
          'Numara kaydedildi. Futbolcu ${formatPhoneRaw10(raw)} ile '
              '"Şifremi Unuttum"dan kod alıp şifresini belirleyebilir.',
        'phone_taken' => 'Bu numara başka bir profilde ya da hesapta kayıtlı.',
        'confirmed' => 'Profilin numarası zaten onaylı.',
        'forbidden' => 'Bu profile numara ekleme yetkiniz yok.',
        _ => 'Numara kaydedilemedi. Lütfen tekrar deneyin.',
      };
      messenger.showSnackBar(SnackBar(content: Text(text)));
      if (r == 'phone_taken' && mounted) {
        await _askPhone(c);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(IdentityService.errorText(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: widget.registration ? 'Kimliğini Doğrula' : 'Kimlik Doğrulama',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (!IdCardReader.supported)
            _note(
              Icons.phone_android_rounded,
              'Kimlik kartının çipi yalnızca Lig Masası uygulamasından '
              '(Android / iPhone) okunabilir.',
            )
          else ...[
            if ((widget.expectedName ?? '').isNotEmpty)
              _note(
                Icons.person_search_rounded,
                'Okutulacak: ${widget.expectedName}',
              ),
            _nfcSection(),
            if (_nfc == NfcState.available) ...[
              _keySection(),
              if (_busy && _status != null) _reading(),
              if (_error != null) _errorBox(_error!),
              if (_card != null) _resultSection(),
            ],
            const SizedBox(height: 8),
            _privacyNote(),
          ],
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _blue.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _blue.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        Icon(icon, color: _blue, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _nfcSection() {
    final s = _nfc;
    if (s == NfcState.available) return const SizedBox.shrink();
    return AdminFormSection(
      title: 'NFC',
      child: AdminFieldGroup(
        children: [
          AdminFieldRow(
            icon: Icons.nfc_rounded,
            label: 'Durum',
            child: Text(
              s == null
                  ? 'Kontrol ediliyor…'
                  : s == NfcState.disabled
                  ? 'NFC kapalı'
                  : 'Bu telefonda NFC yok',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (s == NfcState.disabled)
            Padding(
              padding: const EdgeInsets.all(12),
              child: AdminPrimaryButton(
                label: "NFC'Yİ AÇ",
                icon: Icons.settings_rounded,
                onPressed: () async {
                  final opened = await IdCardReader.openNfcSettings();
                  if (!opened && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Ayarlar → Bağlantılar → NFC bölümünden açın.',
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          if (s == NfcState.unsupported)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Text(
                'Kimliği NFC özellikli başka bir telefonla okutun. '
                'Okutulan profil her yerde onaylı görünür.',
                style: TextStyle(color: kAdminMuted, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _keySection() {
    final k = _key;
    TextStyle v() => const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    );
    return AdminFormSection(
      title: _count > 0 ? 'Kimlik kartı · $_count onaylandı' : 'Kimlik kartı',
      trailing: k == null
          ? null
          : TextButton(
              onPressed: _busy ? null : _manualKey,
              child: const Text('Düzelt'),
            ),
      child: k == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Steps(),
                const SizedBox(height: 14),
                AdminPrimaryButton(
                  label: 'ARKA YÜZÜ OKUT',
                  icon: Icons.photo_camera_rounded,
                  busy: _busy,
                  onPressed: _scanBack,
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _busy ? null : _manualKey,
                  child: const Text(
                    'Okunmuyorsa bilgileri elle girin',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminFieldGroup(
                  children: [
                    AdminFieldRow(
                      icon: Icons.badge_outlined,
                      label: 'Seri No',
                      child: Text(_maskDoc(k.documentNumber), style: v()),
                    ),
                    AdminFieldRow(
                      icon: Icons.cake_outlined,
                      label: 'Doğum Tarihi',
                      child: Text(_maskDate(k.birthDate), style: v()),
                    ),
                    AdminFieldRow(
                      icon: Icons.event_available_outlined,
                      label: 'Son Geçerlilik',
                      child: Text(_maskDate(k.expiryDate), style: v()),
                    ),
                  ],
                ),
                if (_card == null && !_busy) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '2. adım: ÇİPİ OKU\'ya basın, ardından kartı telefonun '
                    'arkasına düz yaslayın.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kAdminMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  AdminPrimaryButton(
                    label: 'ÇİPİ OKU',
                    icon: Icons.nfc_rounded,
                    onPressed: _readChip,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _reading() => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _blue.withValues(alpha: 0.4)),
    ),
    child: Column(
      children: [
        const Icon(Icons.contactless_rounded, color: _blue, size: 56),
        const SizedBox(height: 12),
        Text(
          _status ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Kartı telefonun arka ortasına düz yaslayın; okuma bitene kadar '
          'oynatmayın (birkaç saniye).',
          textAlign: TextAlign.center,
          style: TextStyle(color: kAdminMuted, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: _blue),
        ),
      ],
    ),
  );

  Widget _errorBox(String msg) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kAdminDanger.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kAdminDanger.withValues(alpha: 0.4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: kAdminDanger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
              ),
            ),
          ],
        ),
        if (_key != null && _card == null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy ? null : _readChip,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar dene'),
            ),
          ),
        ],
      ],
    ),
  );

  /// Ekranda kimlik bilgileri maskeli: seri noyu ve tarihlerin gün/ayını
  /// yanınızdaki göremez.
  String _maskDoc(String d) =>
      d.length <= 3 ? d : '${d.substring(0, 3)}${'•' * (d.length - 3)}';

  String _maskDate(DateTime d) => '••.••.${d.year}';

  Widget _resultSection() {
    final card = _card!;
    final list = _candidates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminFormSection(
          title: 'Kimlikten okunan',
          child: AdminFieldGroup(
            children: [
              AdminFieldRow(
                icon: Icons.person_rounded,
                label: 'Ad Soyad',
                child: Text(
                  card.fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              AdminFieldRow(
                icon: Icons.cake_outlined,
                label: 'Doğum Tarihi',
                child: Text(
                  _maskDate(card.birthDate),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
              AdminFieldRow(
                icon: Icons.pin_outlined,
                label: 'Kimlik No',
                child: _EncryptingTc(key: ValueKey(card.tc), tc: card.tc),
              ),
            ],
          ),
        ),
        if (list != null)
          AdminFormSection(
            title: 'Eşleşen profil',
            child: list.isEmpty
                ? const _EmptyMatch()
                : Column(children: [for (final c in list) _candidateTile(c)]),
          ),
        if (_verifiedId != null || (list != null && list.isEmpty)) ...[
          const SizedBox(height: 4),
          AdminPrimaryButton(
            label: 'SIRADAKİ KİMLİK',
            icon: Icons.skip_next_rounded,
            onPressed: _busy ? null : _reset,
          ),
        ],
      ],
    );
  }

  Widget _candidateTile(IdentityCandidate c) {
    final done = c.playerId == _verifiedId;
    final photo = c.photoUrl.trim();
    final String tag;
    final Color tagColor;
    if (done) {
      tag = 'Onaylı';
      tagColor = _blue;
    } else if (c.verifiedOther) {
      tag = 'Başka kimlikle onaylı';
      tagColor = kAdminDanger;
    } else if (c.matchKind == 'exact') {
      tag = 'Eşleşti';
      tagColor = kAdminAccent;
    } else if (c.matchKind == 'year') {
      tag = 'Doğum tarihi farklı';
      tagColor = kAdminAmber;
    } else if (c.matchKind == 'name') {
      tag = 'Benzer kayıt';
      tagColor = kAdminAmber;
    } else {
      tag = 'Ad soyad farklı';
      tagColor = kAdminAmber;
    }
    final canPick = !done && !c.verifiedOther && _verifiedId == null && !_busy;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done ? _blue : Colors.white.withValues(alpha: 0.08),
          width: done ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: photo.isEmpty
                        ? Container(
                            color: const Color(0xFF334155),
                            child: const Icon(
                              Icons.person_rounded,
                              color: Colors.white54,
                            ),
                          )
                        : WebSafeImage(url: photo, width: 46, height: 46),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              c.fullName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (done) ...[
                            const SizedBox(width: 5),
                            const VerifiedBadge(size: 17),
                          ],
                        ],
                      ),
                      if (c.teams.isNotEmpty)
                        Text(
                          c.teams,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: kAdminMuted,
                            fontSize: 12.5,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tagColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: tagColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (canPick) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () => _verify(c),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.verified_rounded, size: 20),
                  label: const Text(
                    'PROFİLİ ONAYLA',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _privacyNote() => const _StorageCard();
}

/// "Neler kaydedilir?" kartı: kullanıcıya kimliğinin sisteme eklenmediğini
/// açıkça gösterir.
class _StorageCard extends StatelessWidget {
  const _StorageCard();

  @override
  Widget build(BuildContext context) {
    Widget line(bool saved, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            saved ? Icons.check_circle_rounded : Icons.block_rounded,
            size: 17,
            color: saved ? kAdminAccent : kAdminDanger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
    Widget head(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(
        t,
        style: const TextStyle(
          color: kAdminMuted,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_rounded, color: kVerifiedBlue, size: 18),
              SizedBox(width: 8),
              Text(
                'Kimlik bilgileriniz sisteme eklenmez',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          head('KAYDEDİLEN'),
          line(true, 'Profilinizdeki "onaylı" işareti ve onay tarihi'),
          line(
            true,
            'Kimlik numaranızın geri çevrilemez şifreli özeti (aynı kimlik '
            'iki profile bağlanamasın diye; kimse, yönetici de dahil, '
            'numaranızı buradan göremez)',
          ),
          const SizedBox(height: 4),
          head('KAYDEDİLMEYEN'),
          line(false, 'Kimlik kartının görüntüsü (telefonda okunur, silinir)'),
          line(false, 'Kimlik numaranızın kendisi'),
          line(false, 'Seri no, son geçerlilik tarihi, çipteki fotoğraf'),
          line(
            false,
            'Çipteki ad, soyad ve doğum tarihi (yalnızca profilinizle '
            'karşılaştırılır)',
          ),
          const SizedBox(height: 4),
          const Text(
            'Kimliği yalnızca sahibinin izniyle okutun.',
            style: TextStyle(color: kAdminMuted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

/// Kimlik numarası önce okunduğu gibi görünür, sonra rakamlar tek tek
/// gizlenir ve kilit simgesiyle "şifrelendi" yazar.
class _EncryptingTc extends StatefulWidget {
  const _EncryptingTc({super.key, required this.tc});

  final String tc;

  @override
  State<_EncryptingTc> createState() => _EncryptingTcState();
}

class _EncryptingTcState extends State<_EncryptingTc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    // Yarım saniye okunur halde kalır, sonra gizlenir.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = widget.tc;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Baştaki 1 ve sondaki 2 hane kalır; aradaki 8 hane soldan gizlenir.
        final hidden = (_c.value * 8).ceil();
        final b = StringBuffer(tc.substring(0, 1));
        for (var i = 1; i < 9; i++) {
          b.write(i <= hidden ? '•' : tc[i]);
        }
        b.write(tc.substring(9));
        final done = _c.isCompleted;
        return Row(
          children: [
            Text(
              b.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedOpacity(
              opacity: done ? 1 : 0.6,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: kVerifiedBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      done ? Icons.lock_rounded : Icons.lock_open_rounded,
                      size: 13,
                      color: kVerifiedBlue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      done ? 'Şifrelendi' : 'Şifreleniyor…',
                      style: const TextStyle(
                        color: kVerifiedBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    Widget step(String n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: kVerifiedBlue,
              shape: BoxShape.circle,
            ),
            child: Text(
              n,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          step(
            '1',
            'Kimlik kartının arka yüzünü kameraya gösterin; kart '
                'kendiliğinden okunur.',
          ),
          step('2', 'Kartı telefonun arkasına yaslayın; çip okunur.'),
          step(
            '3',
            'Eşleşen profili onaylayın; profil mavi tikle '
                'işaretlenir.',
          ),
        ],
      ),
    );
  }
}

class _EmptyMatch extends StatelessWidget {
  const _EmptyMatch();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kAdminAmber.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kAdminAmber.withValues(alpha: 0.35)),
    ),
    child: const Text(
      'Bu kimlikle eşleşen futbolcu profili bulunamadı. Profildeki ad, '
      'soyad ve doğum tarihinin kimlikle aynı olduğunu kontrol edin; '
      'düzeltilince tekrar okutun.',
      style: TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35),
    ),
  );
}

/// Arka yüz okunmazsa: kartın ön yüzündeki seri no, doğum tarihi ve son
/// geçerlilik tarihi elle girilir.
class _ManualKeyDialog extends StatefulWidget {
  const _ManualKeyDialog({this.initial});

  final IdCardKey? initial;

  @override
  State<_ManualKeyDialog> createState() => _ManualKeyDialogState();
}

class _ManualKeyDialogState extends State<_ManualKeyDialog> {
  late final _doc = TextEditingController(
    text: widget.initial?.documentNumber ?? '',
  );
  late final _birth = TextEditingController(
    text: widget.initial == null ? '' : _fmt(widget.initial!.birthDate),
  );
  late final _expiry = TextEditingController(
    text: widget.initial == null ? '' : _fmt(widget.initial!.expiryDate),
  );
  String? _error;

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  static DateTime? _parse(String s) {
    final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(s.trim());
    if (m == null) return null;
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    if (d < 1 || d > 31 || mo < 1 || mo > 12 || y < 1900) return null;
    return DateTime(y, mo, d);
  }

  @override
  void dispose() {
    _doc.dispose();
    _birth.dispose();
    _expiry.dispose();
    super.dispose();
  }

  void _save() {
    final doc = _doc.text.trim().toUpperCase();
    final b = _parse(_birth.text);
    final e = _parse(_expiry.text);
    if (!RegExp(r'^[A-Z0-9]{9}$').hasMatch(doc)) {
      setState(() => _error = 'Seri no 9 karakter olmalı (ör. A12B34567).');
      return;
    }
    if (b == null || e == null) {
      setState(() => _error = 'Tarihleri GG.AA.YYYY biçiminde girin.');
      return;
    }
    Navigator.pop(
      context,
      IdCardKey(documentNumber: doc, birthDate: b, expiryDate: e),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    bool date = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: c,
      keyboardType: date ? TextInputType.number : TextInputType.text,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: date
          ? [_DateFormatter()]
          : [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(9),
            ],
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        hintText: date ? 'GG.AA.YYYY' : 'A12B34567',
        prefixIcon: Icon(icon, color: kAdminAccent),
        labelStyle: const TextStyle(color: kAdminMuted),
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: adminDialogDecoration(),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Kimlik bilgileri',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Kartın ön yüzündeki bilgileri girin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kAdminMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _field(_doc, 'Seri No', Icons.badge_outlined),
              _field(_birth, 'Doğum Tarihi', Icons.cake_outlined, date: true),
              _field(
                _expiry,
                'Son Geçerlilik',
                Icons.event_available_outlined,
                date: true,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kAdminDanger, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 6),
              AdminPrimaryButton(label: 'ÇİPİ OKU', onPressed: _save),
              const SizedBox(height: 8),
              AdminSecondaryButton(onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// GG.AA.YYYY: rakamlar yazıldıkça noktalar kendiliğinden eklenir.
class _DateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 8 ? digits.substring(0, 8) : digits;
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 2 || i == 4) b.write('.');
      b.write(d[i]);
    }
    final t = b.toString();
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}
