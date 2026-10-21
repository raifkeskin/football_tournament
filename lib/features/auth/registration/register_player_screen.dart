import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../identity/id_card_reader.dart';
import '../../identity/identity_verify_screen.dart';
import '../../identity/verified_badge.dart';
import '../../player/services/player_profile_service.dart';
import '../screens/forgot_password_screen.dart';
import 'register_phone_screen.dart';
import 'registration_service.dart';

/// Futbolcu Profili kaydı: 1) kimlik çipi okunur (ad, soyad, doğum tarihi,
/// TC); 2) kişi mevki, boy, kilo, ayak bilgilerini girer; 3) telefon
/// doğrulama ekranında şifresini belirler. Profil onaylı (mavi tikli) açılır.
class RegisterPlayerScreen extends StatefulWidget {
  const RegisterPlayerScreen({super.key});

  @override
  State<RegisterPlayerScreen> createState() => _RegisterPlayerScreenState();
}

class _RegisterPlayerScreenState extends State<RegisterPlayerScreen> {
  static const _feet = <String>['Sağ', 'Sol', 'Her İkisi'];

  IdCardData? _card;
  String? _main;
  String? _sub;
  String? _foot;
  final _height = TextEditingController();
  final _weight = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  String get _first => trTitleCase(_card!.firstName);
  String get _last => trTitleCase(_card!.lastName);

  /// Kimlik okunur; bu kişinin hesabı olan bir profili zaten varsa uyarılır.
  Future<void> _readCard() async {
    final card = await IdentityVerifyScreen.readForRegistration(context);
    if (card == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await RegistrationService.precheckPlayer(
        firstName: trTitleCase(card.firstName),
        lastName: trTitleCase(card.lastName),
        birthDate: card.birthDate,
        tc: card.tc,
      );
      if (!mounted) return;
      if (r == 'ok') {
        setState(() => _card = card);
      } else if (r == 'profile_has_account') {
        await _alreadyRegistered();
      } else {
        setState(() => _error = RegistrationService.message(r));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Bağlantı hatası. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _alreadyRegistered() async {
    final forgot = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        icon: const VerifiedBadge(size: 40),
        title: const Text(
          'Zaten kayıtlı profiliniz var',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Bu kimlikle açılmış bir hesabınız bulunuyor. Şifrenizi '
          'unuttuysanız "Şifremi Unuttum" menüsünden şifre talebinde '
          'bulunabilirsiniz.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Kapat'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kAdminAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Şifremi Unuttum',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (forgot != true || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ForgotPasswordScreen'),
        builder: (_) => const ForgotPasswordScreen(),
      ),
    );
  }

  bool get _formOk {
    if (_main == null) return false;
    final subs = kSubPositionsByMain[_main] ?? const [];
    return subs.length <= 1 || _sub != null;
  }

  String? _numbersError() {
    final h = int.tryParse(_height.text.trim());
    final w = int.tryParse(_weight.text.trim());
    if (_height.text.trim().isNotEmpty && (h == null || h < 120 || h > 230)) {
      return 'Boy 120-230 cm arasında olmalı.';
    }
    if (_weight.text.trim().isNotEmpty && (w == null || w < 35 || w > 200)) {
      return 'Kilo 35-200 kg arasında olmalı.';
    }
    return null;
  }

  /// Bilgiler tamam: telefon doğrulama ekranına geçilir; profil orada
  /// oluşturulur.
  void _next() {
    final card = _card;
    if (card == null) return;
    if (!_formOk) {
      setState(() => _error = 'Mevki ve alt mevki seçin.');
      return;
    }
    final numErr = _numbersError();
    if (numErr != null) {
      setState(() => _error = numErr);
      return;
    }
    FocusScope.of(context).unfocus();
    final first = _first;
    final last = _last;
    final main = _main!;
    final sub = _sub;
    final foot = _foot;
    final height = int.tryParse(_height.text.trim());
    final weight = int.tryParse(_weight.text.trim());
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'RegisterPhoneScreen'),
        builder: (_) => RegisterPhoneScreen(
          kind: 'player',
          name: '$first $last',
          buttonLabel: 'PROFİLİMİ OLUŞTUR',
          successMessage: 'Futbolcu profilin oluşturuldu.',
          submit: (raw10, code, password) => RegistrationService.registerPlayer(
            raw10: raw10,
            code: code,
            password: password,
            firstName: first,
            lastName: last,
            birthDate: card.birthDate,
            tc: card.tc,
            mainPosition: main,
            subPosition: sub,
            foot: foot,
            height: height,
            weight: weight,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    return AdminPageScaffold(
      title: 'Futbolcu Profili',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _progress(card == null ? 1 : 2),
          const SizedBox(height: 18),
          if (card == null) ..._identityStep() else ..._formStep(card),
        ],
      ),
    );
  }

  Widget _progress(int step) => Row(
    children: [
      for (var i = 1; i <= 3; i++) ...[
        if (i > 1) const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 5,
            decoration: BoxDecoration(
              color: i <= step ? kVerifiedBlue : const Color(0xFF334155),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
      const SizedBox(width: 10),
      Text(
        '$step / 3',
        style: const TextStyle(
          color: kAdminMuted,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );

  List<Widget> _identityStep() => [
    const Text(
      'Kimliğini doğrula',
      style: TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w900,
      ),
    ),
    const SizedBox(height: 6),
    const Text(
      'Profilin kimlik çipindeki bilgilerle otomatik oluşur ve mavi tikli '
      'görünür.',
      style: TextStyle(color: kAdminMuted, fontSize: 14, height: 1.4),
    ),
    const SizedBox(height: 18),
    if (!IdCardReader.supported)
      _note(
        Icons.phone_android_rounded,
        'Futbolcu profili kimlik çipiyle açılır; bu yüzden yalnızca Lig '
        'Masası uygulamasından (Android / iPhone) kayıt olabilirsin.',
      )
    else ...[
      _note(
        Icons.lock_outline_rounded,
        'Adın, soyadın ve doğum tarihin kimlikten otomatik gelir. TC Kimlik '
        'No geri dönülemez şekilde şifrelenir, bunlar dışındaki hiçbir '
        'bilgi sisteme kaydedilmez.',
      ),
      if (_error != null) _errorText(),
      AdminPrimaryButton(
        label: 'KİMLİĞİMİ OKUT',
        icon: Icons.contactless_rounded,
        busy: _busy,
        onPressed: _readCard,
      ),
      const SizedBox(height: 12),
      const Text(
        'Telefonunda NFC yoksa bir yakınının telefonuyla da kayıt '
        'olabilirsin.',
        textAlign: TextAlign.center,
        style: TextStyle(color: kAdminMuted, fontSize: 12.5),
      ),
    ],
  ];

  Widget _note(IconData icon, String text) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kVerifiedBlue.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kVerifiedBlue.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: kVerifiedBlue, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _formStep(IdCardData card) {
    final subs = kSubPositionsByMain[_main] ?? const <String>[];
    return [
      _identityCard(card),
      const SizedBox(height: 18),
      AdminFormSection(
        title: 'Mevki',
        child: _chips(
          kMainPositions,
          _main,
          (v) => setState(() {
            _main = v;
            final s = kSubPositionsByMain[v] ?? const [];
            _sub = s.length == 1 ? s.first : null;
            _error = null;
          }),
          columns: 4,
        ),
      ),
      if (subs.length > 1)
        AdminFormSection(
          title: 'Alt Mevki · $_main',
          child: _chips(
            subs,
            _sub,
            (v) => setState(() {
              _sub = v;
              _error = null;
            }),
            columns: subs.length,
          ),
        ),
      AdminFormSection(
        title: 'Fiziksel',
        child: AdminFieldGroup(
          children: [
            AdminFieldRow(
              icon: Icons.height_rounded,
              label: 'Boy (cm)',
              child: _numberField(_height, 'ör. 178'),
            ),
            AdminFieldRow(
              icon: Icons.monitor_weight_outlined,
              label: 'Kilo (kg)',
              child: _numberField(_weight, 'ör. 76'),
            ),
          ],
        ),
      ),
      AdminFormSection(
        title: 'Kullandığı Ayak',
        child: _chips(
          _feet,
          _foot,
          (v) => setState(() => _foot = v),
          columns: _feet.length,
        ),
      ),
      if (_error != null) _errorText(),
      AdminPrimaryButton(
        label: 'İLERİ',
        icon: Icons.arrow_forward_rounded,
        onPressed: _formOk ? _next : null,
      ),
    ];
  }

  Widget _errorText() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      _error!,
      textAlign: TextAlign.center,
      style: const TextStyle(color: kAdminDanger, fontWeight: FontWeight.w700),
    ),
  );

  Widget _identityCard(IdCardData card) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: kVerifiedBlue.withValues(alpha: 0.45)),
    ),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: Color(0xFF334155),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_rounded, color: kAdminMuted, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '$_first $_last',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const VerifiedBadge(size: 18),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Doğum yılı ${card.birthDate.year} · kimlikten geldi, '
                'değiştirilemez',
                style: const TextStyle(color: kAdminMuted, fontSize: 12.5),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _readCard,
          child: const Text('Tekrar oku'),
        ),
      ],
    ),
  );

  Widget _numberField(TextEditingController c, String hint) => TextField(
    controller: c,
    enabled: !_busy,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(3),
    ],
    onChanged: (_) {
      if (_error != null) setState(() => _error = null);
    },
    style: const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
    decoration: adminInlineInputDecoration(hint: hint),
  );

  /// Seçim kutucukları; [columns] verilirse eşit genişlikte tek satır.
  Widget _chips(
    List<String> items,
    String? selected,
    ValueChanged<String> onPick, {
    int? columns,
  }) {
    Widget chip(String v) {
      final on = v == selected;
      return Material(
        color: on
            ? kAdminAccent.withValues(alpha: 0.22)
            : const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: on ? kAdminAccent : const Color(0xFF334155),
            width: on ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : () => onPick(v),
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: EdgeInsets.symmetric(horizontal: columns != null ? 4 : 14),
            alignment: Alignment.center,
            child: Text(
              v,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: on ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    if (columns != null) {
      return Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: chip(items[i])),
          ],
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final v in items) chip(v)],
    );
  }
}
