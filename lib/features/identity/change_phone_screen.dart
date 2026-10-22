import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../auth/registration/phone_verify_card.dart';
import '../auth/registration/registration_service.dart';
import '../auth/widgets/phone_input.dart';
import 'id_card_reader.dart';
import 'identity_verify_screen.dart';
import 'verified_badge.dart';

/// Onaylı profilin telefon numarasını değiştirir: kişi kimliğini yeniden
/// okutur (çipteki TC profilin onayıyla tutmalı), yeni numarayı kodla
/// doğrular; giriş numarası da yenisi olur.
class ChangePhoneScreen extends StatefulWidget {
  const ChangePhoneScreen({super.key});

  static Future<bool?> open(BuildContext context) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'ChangePhoneScreen'),
          builder: (_) => const ChangePhoneScreen(),
        ),
      );

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  static SupabaseClient get _sb => Supabase.instance.client;

  final _phone = PhoneVerifyController()..requirePassword = false;

  /// Okutulan kimliğin TC'si (profille tuttuysa).
  String? _tc;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String? _message(String code) => code == 'has_account'
      ? 'Bu numara başka bir hesapta kayıtlı.'
      : RegistrationService.message(code);

  Future<void> _readCard() async {
    final card = await IdentityVerifyScreen.readForRegistration(context);
    if (card == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _sb.rpc(
        'phone_change_identity',
        params: {'p_tc': card.tc},
      );
      if (!mounted) return;
      if (r == 'ok') {
        setState(() => _tc = card.tc);
      } else {
        setState(() => _error = _message((r ?? '').toString()));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Bağlantı hatası. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _send(String raw10) async {
    final r = await _sb.rpc(
      'phone_change_send',
      params: {'p_tc': _tc, 'p_new_phone': raw10},
    );
    final code = (r ?? '').toString();
    // Kart kendi metnini gösterir; "hesap var" metni burada değişir.
    return code == 'has_account' ? 'phone_taken' : code;
  }

  /// Kod doğruysa numara hemen değişir.
  Future<String> _confirm(String raw10, String code) async {
    final r = await _sb.rpc(
      'phone_change_confirm',
      params: {'p_tc': _tc, 'p_new_phone': raw10, 'p_code': code},
    );
    final res = (r ?? '').toString();
    if (res == 'ok') {
      try {
        await _sb.auth.refreshSession();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Telefon numaran değişti. Bundan sonra '
              '${formatPhoneRaw10(raw10)} ile giriş yap.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    }
    return res == 'has_account' ? 'phone_taken' : res;
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Telefon Değiştir',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (!IdCardReader.supported)
            _note(
              Icons.phone_android_rounded,
              'Telefon değişikliği kimlik çipiyle yapılır; Lig Masası '
              'uygulamasından (Android / iPhone) değiştirebilirsin.',
            )
          else if (_tc == null) ...[
            _note(
              Icons.verified_user_outlined,
              'Profilin kimlikle onaylı. Numaranı değiştirmek için önce '
              'kimliğini yeniden okut; okutulan kimlik profilinle '
              'eşleşmelidir.',
            ),
            if (_error != null) _errorText(),
            AdminPrimaryButton(
              label: 'KİMLİĞİMİ OKUT',
              icon: Icons.contactless_rounded,
              busy: _busy,
              onPressed: _readCard,
            ),
          ] else ...[
            _note(
              Icons.check_circle_outline_rounded,
              'Kimliğin doğrulandı. Yeni numaranı yaz; gelen kodu girince '
              'numaran değişir ve bundan sonra yeni numaranla giriş '
              'yaparsın.',
            ),
            PhoneVerifyCard(
              controller: _phone,
              kind: 'player',
              send: _send,
              check: _confirm,
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorText() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      _error!,
      textAlign: TextAlign.center,
      style: const TextStyle(color: kAdminDanger, fontWeight: FontWeight.w700),
    ),
  );

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
}
