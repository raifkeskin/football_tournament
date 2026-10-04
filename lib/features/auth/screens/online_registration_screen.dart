import 'package:flutter/material.dart';

import '../../../core/services/app_settings.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../models/auth_models.dart';
import '../widgets/phone_input.dart';
import 'forgot_password_screen.dart';

/// Kayıt: telefon numarasıyla geçici şifre talebi. Admin onaylayınca
/// geçici şifre WhatsApp'tan iletilir (SMS kullanılmıyor).
class OnlineRegistrationScreen extends StatelessWidget {
  const OnlineRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminPageScaffold(
      title: 'Kayıt Ol',
      body: AccountRequestForm(isReset: false),
    );
  }
}

/// Kayıt ve "Şifremi Unuttum" ekranlarının ortak formu.
class AccountRequestForm extends StatefulWidget {
  const AccountRequestForm({super.key, required this.isReset});

  final bool isReset;

  @override
  State<AccountRequestForm> createState() => _AccountRequestFormState();
}

class _AccountRequestFormState extends State<AccountRequestForm> {
  final _phoneController = TextEditingController();

  bool _busy = false;
  String? _error;

  /// Talep alındıysa gösterilecek sonuç metni.
  String? _doneMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw10 = normalizePhoneToRaw10(_phoneController.text);
    if (raw10.length != 10 || !raw10.startsWith('5')) {
      setState(() => _error = 'Geçerli bir cep telefonu numarası girin.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await ServiceLocator.authService.requestAccountPassword(
        phoneRaw10: raw10,
        isReset: widget.isReset,
      );
      if (!mounted) return;
      const whatsapp =
          'Yönetici onayladığında geçici şifreniz bu numaranın WhatsApp '
          'hesabına iletilecektir.';
      setState(() {
        switch (outcome) {
          case AccountRequestOutcome.requested:
            _doneMessage = 'Kayıt talebiniz alındı.\n$whatsapp';
          case AccountRequestOutcome.resetRequested:
            _doneMessage = widget.isReset
                ? 'Yeni şifre talebiniz alındı.\n$whatsapp'
                : 'Bu numarayla kayıtlı bir hesap zaten var; yeni şifre '
                      'talebiniz alındı.\n$whatsapp';
          case AccountRequestOutcome.alreadyPending:
            _doneMessage =
                'Bu numara için bekleyen bir talebiniz zaten var.\n$whatsapp';
          case AccountRequestOutcome.notRegistered:
            _error =
                'Bu numarayla kayıtlı hesap bulunamadı. Önce kayıt olmanız '
                'gerekiyor.';
          case AccountRequestOutcome.unknownPhone:
            _error = AppSettings.privateLeaguesEnabled.value
                ? 'Bu numara sistemde kayıtlı değil. Bir turnuvayı takip etmek '
                      'için hesap gerekmez; turnuva sorumlusundan kodu alıp '
                      'menüdeki "Turnuva Kodu Gir"e yazabilirsiniz. '
                      'Futbolcuysanız takım sorumlunuza, turnuva '
                      'yöneticisiyseniz bize ulaşın.'
                : 'Bu numara sistemde kayıtlı değil. Turnuvaları takip etmek '
                      'için hesap gerekmez. Futbolcuysanız takım sorumlunuza, '
                      'turnuva yöneticisiyseniz bize ulaşın.';
          case AccountRequestOutcome.invalidPhone:
            _error = 'Geçerli bir cep telefonu numarası girin.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Talep gönderilemedi. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    String? prefixText,
    bool phone = false,
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: keyboardType,
      textCapitalization: phone
          ? TextCapitalization.none
          : TextCapitalization.words,
      inputFormatters: phone ? [PhoneMaskFormatter()] : null,
      onSubmitted: (_) => _submit(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: adminInlineInputDecoration(
        hint: hint,
        prefixText: prefixText,
      ),
    );
  }

  Widget _doneView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: adminCardDecoration(),
          child: Column(
            children: [
              const Icon(
                Icons.mark_chat_read_outlined,
                color: kAdminAccent,
                size: 48,
              ),
              const SizedBox(height: 14),
              Text(
                _doneMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'İlk girişte kendi şifrenizi belirlemeniz istenecek.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kAdminMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        AdminPrimaryButton(
          label: 'GİRİŞ EKRANINA DÖN',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (_doneMessage != null)
          _doneView()
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
            child: Text(
              widget.isReset
                  ? 'Kayıtlı telefon numaranızı yazın. Yeni geçici şifreniz, '
                        'yönetici onayından sonra WhatsApp üzerinden '
                        'iletilecektir.'
                  : 'Telefon numaranızı yazın. Geçici şifreniz, '
                        'yönetici onayından sonra WhatsApp üzerinden '
                        'iletilecektir.',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
          AdminFormSection(
            title: widget.isReset ? 'Hesap' : 'Bilgileriniz',
            child: AdminFieldGroup(
              children: [
                AdminFieldRow(
                  icon: Icons.phone_iphone_rounded,
                  label: 'Cep Telefonu (WhatsApp)',
                  child: _input(
                    controller: _phoneController,
                    hint: '(5XX) XXX XX XX',
                    keyboardType: TextInputType.phone,
                    prefixText: '0 ',
                    phone: true,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kAdminDanger,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.isReset &&
                _error!.startsWith('Bu numarayla kayıtlı hesap')) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => const OnlineRegistrationScreen(),
                    ),
                  ),
                  child: const Text(
                    'Kayıt Ol',
                    style: TextStyle(
                      color: kAdminAmber,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
          ],
          AdminPrimaryButton(
            label: widget.isReset ? 'YENİ ŞİFRE İSTE' : 'KAYIT TALEBİ GÖNDER',
            icon: Icons.send_rounded,
            busy: _busy,
            onPressed: _submit,
          ),
          if (!widget.isReset) ...[
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => const ForgotPasswordScreen(),
                        ),
                      ),
                child: const Text(
                  'Hesabım var, şifremi unuttum',
                  style: TextStyle(
                    color: kAdminAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
