import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/auth_models.dart';
import '../widgets/phone_input.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/custom_popup_selector.dart';

/// Şifre Talepleri (eski adıyla OTP Takip): kayıt / şifre sıfırlama
/// talepleri. Admin onaylayınca geçici şifre üretilir ve kendi WhatsApp'ından
/// kullanıcıya gönderir.
class AdminOtpMonitorScreen extends StatefulWidget {
  const AdminOtpMonitorScreen({super.key});

  @override
  State<AdminOtpMonitorScreen> createState() => _AdminOtpMonitorScreenState();
}

class _AdminOtpMonitorScreenState extends State<AdminOtpMonitorScreen> {
  static const _loginUrl = 'https://masterfutbol.web.app';

  var _includeClosed = false;
  final _busyIds = <String>{};

  // Akış sadece filtre değişince / işlemden sonra yeniden kurulur. Servis,
  // dinleyici ayrılınca akışı kapattığı için eski akış saklanmaz.
  late Stream<List<AccountRequestEntry>> _stream = _createStream();

  Stream<List<AccountRequestEntry>> _createStream() => ServiceLocator
      .authService
      .watchAccountRequests(includeClosed: _includeClosed);

  void _refresh() => setState(() => _stream = _createStream());

  static (String, Color) _statusStyle(String status) => switch (status) {
    'pending' => ('Bekliyor', kAdminAmber),
    'approved' => ('Gönderildi', kAdminAccent),
    'rejected' => ('Reddedildi', kAdminMuted),
    _ => (status.isEmpty ? '-' : status, kAdminMuted),
  };

  static String _time(DateTime? at) {
    if (at == null) return '';
    final l = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
  }

  static String _message(TempPasswordGrant g) =>
      'Master Lig Platformuna giriş için geçici şifreniz: ${g.password}\n\n'
      'Giriş: $_loginUrl\n'
      'İlk girişte kendi şifrenizi belirlemeniz istenecek.';

  Future<void> _openWhatsApp(TempPasswordGrant g) async {
    final uri = Uri.parse(
      'https://wa.me/90${g.phoneRaw10}'
      '?text=${Uri.encodeComponent(_message(g))}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('WhatsApp açılamadı.')));
    }
  }

  Future<void> _approve(AccountRequestEntry e) async {
    if (e.status == 'approved') {
      final ok = await showAdminConfirmDialog(
        context: context,
        title: 'Yeni Şifre Gönder',
        message:
            'Yeni bir geçici şifre üretilecek; daha önce gönderilen şifre '
            'geçersiz olacak.',
        confirmLabel: 'YENİ ŞİFRE ÜRET',
        destructive: false,
        icon: Icons.key_rounded,
      );
      if (!ok) return;
    }

    setState(() => _busyIds.add(e.id));
    try {
      final grant = await ServiceLocator.authService.approveAccountRequest(
        e.id,
      );
      if (!mounted) return;
      _refresh();
      await _showGrantDialog(grant);
    } catch (err) {
      if (!mounted) return;
      await showAdminInfoDialog(
        context: context,
        title: 'Onaylanamadı',
        message: '$err',
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(e.id));
    }
  }

  Future<void> _reject(AccountRequestEntry e) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Talebi Reddet',
      message: '${formatPhoneRaw10(e.phoneRaw10)} numaralı talep reddedilecek.',
      confirmLabel: 'REDDET',
      icon: Icons.block_rounded,
    );
    if (!ok) return;
    setState(() => _busyIds.add(e.id));
    try {
      await ServiceLocator.authService.rejectAccountRequest(e.id);
      if (mounted) _refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reddedilemedi: $err')));
    } finally {
      if (mounted) setState(() => _busyIds.remove(e.id));
    }
  }

  /// Şifre üretildikten sonra açılır. WhatsApp bu popup'taki butonla açılır:
  /// tarayıcılar yalnızca doğrudan dokunuşla yeni sekme açmaya izin veriyor.
  Future<void> _showGrantDialog(TempPasswordGrant g) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: adminDialogDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminDialogHeader(
                icon: Icons.key_rounded,
                title: g.isReset ? 'Şifre Sıfırlandı' : 'Hesap Açıldı',
                subtitle: [
                  ?g.fullName,
                  formatPhoneRaw10(g.phoneRaw10),
                ].join(' · '),
              ),
              const SizedBox(height: 18),
              const Text(
                'GEÇİCİ ŞİFRE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kAdminMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                g.password,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _message(g),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              AdminPrimaryButton(
                label: 'WHATSAPP İLE GÖNDER',
                icon: Icons.send_rounded,
                onPressed: () => _openWhatsApp(g),
              ),
              const SizedBox(height: 10),
              AdminSecondaryButton(
                label: 'KAPAT',
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _requestCard(AccountRequestEntry e) {
    final (statusLabel, statusColor) = _statusStyle(e.status);
    final busy = _busyIds.contains(e.id);
    final name = e.displayName;
    final created = _time(e.createdAt);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatPhoneRaw10(e.phoneRaw10),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _chip(statusLabel, statusColor),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            name ?? 'İsim yazılmamış',
            style: TextStyle(
              color: name == null ? kAdminMuted : Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (e.playerName != null &&
              e.fullName != null &&
              e.playerName != e.fullName)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Formda yazılan: ${e.fullName}',
                style: const TextStyle(color: kAdminMuted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip(
                e.isReset ? 'Şifre sıfırlama' : 'Yeni kayıt',
                e.isReset ? const Color(0xFF60A5FA) : kAdminAccent,
              ),
              const SizedBox(width: 6),
              _chip(
                e.playerName != null ? 'Oyuncu kaydı var' : 'Oyuncu kaydı yok',
                e.playerName != null ? kAdminAccent : kAdminMuted,
              ),
              const Spacer(),
              if (created.isNotEmpty)
                Text(
                  created,
                  style: const TextStyle(color: kAdminMuted, fontSize: 12),
                ),
            ],
          ),
          if (e.status != 'rejected') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (e.status == 'pending') ...[
                  SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kAdminDanger,
                        side: BorderSide(
                          color: kAdminDanger.withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: busy ? null : () => _reject(e),
                      child: const Text(
                        'Reddet',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kAdminAccent,
                        side: BorderSide(
                          color: kAdminAccent.withValues(alpha: 0.6),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: busy ? null : () => _approve(e),
                      icon: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kAdminAccent,
                              ),
                            )
                          : const Icon(Icons.key_rounded, size: 18),
                      label: Text(
                        e.status == 'pending'
                            ? 'Onayla ve Şifre Üret'
                            : 'Yeni Şifre Gönder',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Şifre Talepleri',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: CustomPopupSelector<bool>(
              label: 'Durum',
              selectedValue: _includeClosed,
              items: const [false, true],
              labelBuilder: (v) => v == true ? 'Tümü' : 'Bekleyen talepler',
              onChanged: (v) {
                if (v == null || v == _includeClosed) return;
                _includeClosed = v;
                _refresh();
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AccountRequestEntry>>(
              stream: _stream,
              builder: (context, snap) {
                final items = snap.data ?? const <AccountRequestEntry>[];
                if (snap.hasError && items.isEmpty) {
                  return Center(
                    child: Text(
                      'Talepler yüklenemedi: ${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kAdminDanger),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting &&
                    items.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(color: kAdminAccent),
                  );
                }
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      _includeClosed
                          ? 'Talep bulunamadı.'
                          : 'Bekleyen talep yok.',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _requestCard(items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
