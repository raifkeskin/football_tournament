import 'package:flutter/material.dart';

import '../../../core/widgets/admin_page.dart';
import 'online_registration_screen.dart';

/// Şifremi Unuttum: SMS doğrulama açıksa kodla yeni şifre, kapalıysa yeni
/// geçici şifre talebi (admin onaylayınca şifre WhatsApp'tan iletilir).
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminPageScaffold(
      title: 'Şifremi Unuttum',
      body: AccountRequestForm(isReset: true),
    );
  }
}
