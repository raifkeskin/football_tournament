import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.phoneRaw10,
    required this.otp,
  });

  final String phoneRaw10;
  final String otp;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _pass1Controller = TextEditingController();
  final _pass2Controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pass1Controller.dispose();
    _pass2Controller.dispose();
    super.dispose();
  }

  bool _validPassword(String s) {
    final v = s.trim();
    if (v.length < 6 || v.length > 10) return false;
    final hasDigit = RegExp(r'\d').hasMatch(v);
    final hasSpecial = RegExp(r'[^A-Za-z0-9]').hasMatch(v);
    return hasDigit || hasSpecial;
  }

  Future<void> _save() async {
    final p1 = _pass1Controller.text;
    final p2 = _pass2Controller.text;
    if (p1 != p2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifreler eşleşmiyor.')),
      );
      return;
    }
    if (!_validPassword(p1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Şifreniz biraz daha 'takım kaptanı' sertliğinde olmalı! Lütfen en az bir rakam veya özel karakter ekleyerek 6-10 karakter arası bir şifre belirleyin.",
          ),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final fn = FirebaseFunctions.instance.httpsCallable(
        'resetPasswordWithOtp',
      );
      await fn.call({
        'phone': widget.phoneRaw10,
        'otp': widget.otp,
        'newPassword': p1,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifre başarıyla güncellendi.')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unimplemented' || e.code == 'UNIMPLEMENTED') {
        final u = FirebaseAuth.instance.currentUser;
        if (u == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Şifre sıfırlama servisi aktif değil. Lütfen yönetici ile iletişime geçin.',
              ),
            ),
          );
          return;
        }
        try {
          await u.updatePassword(p1);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Şifre başarıyla güncellendi.')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        } catch (ex) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $ex')),
          );
          return;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Şifre Sıfırla'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _pass1Controller,
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Yeni Şifre',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass2Controller,
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Yeni Şifre (Tekrar)',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.primary),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Kaydet',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
