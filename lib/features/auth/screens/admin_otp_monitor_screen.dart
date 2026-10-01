import 'package:flutter/material.dart';

import '../models/auth_models.dart';
import '../../../core/services/in_app_browser.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/custom_popup_selector.dart';

class AdminOtpMonitorScreen extends StatefulWidget {
  const AdminOtpMonitorScreen({super.key});

  @override
  State<AdminOtpMonitorScreen> createState() => _AdminOtpMonitorScreenState();
}

class _AdminOtpMonitorScreenState extends State<AdminOtpMonitorScreen> {
  var _includeVerified = true;

  // Akış sadece filtre değişince yeniden kurulur (build'de değil). Servis,
  // dinleyici ayrılınca akışı kapattığı için eski akış saklanmaz.
  late Stream<List<OtpCodeEntry>> _stream = _createStream();

  Stream<List<OtpCodeEntry>> _createStream() =>
      ServiceLocator.authService.watchOtpCodes(
        includeVerified: _includeVerified,
      );

  static (String, Color) _statusStyle(String status) => switch (status) {
    'pending' => ('Bekliyor', const Color(0xFFFBBF24)),
    'verified' => ('Doğrulandı', kAdminAccent),
    'expired' => ('Süresi doldu', const Color(0xFF94A3B8)),
    'locked' => ('Kilitlendi', kAdminDanger),
    _ => (status.isEmpty ? '-' : status, const Color(0xFF94A3B8)),
  };

  static String _formatPhone(String raw10) {
    final p = raw10.trim();
    if (p.length != 10) return p.isEmpty ? '-' : p;
    return '0 (${p.substring(0, 3)}) ${p.substring(3, 6)} '
        '${p.substring(6, 8)} ${p.substring(8)}';
  }

  static String _time(DateTime? at) {
    if (at == null) return '';
    final l = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
  }

  Widget _otpCard(OtpCodeEntry e) {
    final phone = e.phoneRaw10.trim();
    final code = e.code.trim();
    final (statusLabel, statusColor) = _statusStyle(e.status.trim());
    final waPhone = phone.length == 10 ? '90$phone' : phone;
    final waUrl =
        'https://wa.me/$waPhone?text=${Uri.encodeComponent('Kodunuz: $code')}';
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
                  _formatPhone(phone),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                code.isEmpty ? '-' : code,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const Spacer(),
              if (created.isNotEmpty)
                Text(
                  created,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: kAdminAccent,
                side: BorderSide(color: kAdminAccent.withValues(alpha: 0.6)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: phone.isEmpty || code.isEmpty
                  ? null
                  : () => openInAppBrowser(context, waUrl),
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text(
                'WhatsApp ile Gönder',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'OTP Takip',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: CustomPopupSelector<bool>(
              label: 'Durum',
              selectedValue: _includeVerified,
              items: const [false, true],
              labelBuilder: (v) => v == true ? 'Tümü' : 'Bekleyen kodlar',
              onChanged: (v) {
                if (v == null || v == _includeVerified) return;
                setState(() {
                  _includeVerified = v;
                  _stream = _createStream();
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<List<OtpCodeEntry>>(
              stream: _stream,
              builder: (context, snap) {
                final items = snap.data ?? const <OtpCodeEntry>[];
                if (snap.connectionState == ConnectionState.waiting &&
                    items.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(color: kAdminAccent),
                  );
                }
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'Kayıt bulunamadı.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _otpCard(items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
