import 'package:flutter/material.dart';

import '../../models/auth_models.dart';
import '../../services/in_app_browser.dart';
import '../../services/service_locator.dart';

class AdminOtpMonitorScreen extends StatefulWidget {
  const AdminOtpMonitorScreen({super.key});

  @override
  State<AdminOtpMonitorScreen> createState() => _AdminOtpMonitorScreenState();
}

class _AdminOtpMonitorScreenState extends State<AdminOtpMonitorScreen> {
  var _includeVerified = true;

  @override
  Widget build(BuildContext context) {
    final stream = ServiceLocator.authService.watchOtpCodes(
      includeVerified: _includeVerified,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('OTP Takip'),
        actions: [
          Row(
            children: [
              const Text('Verified'),
              Switch(
                value: _includeVerified,
                onChanged: (v) => setState(() => _includeVerified = v),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<OtpCodeEntry>>(
        stream: stream,
        builder: (context, snap) {
          final items = snap.data ?? const <OtpCodeEntry>[];
          if (snap.connectionState == ConnectionState.waiting && items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return const Center(child: Text('Kayıt bulunamadı.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final e = items[i];
              final phone = e.phoneRaw10.trim();
              final code = e.code.trim();
              final status = e.status.trim();
              final waPhone = phone.length == 10 ? '90$phone' : phone;
              final waText = Uri.encodeComponent('Kodunuz: $code');
              final waUrl = 'https://wa.me/$waPhone?text=$waText';

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              phone.isEmpty ? '-' : phone,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(status.isEmpty ? '-' : status),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Kod: ${code.isEmpty ? '-' : code}'),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 42,
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: phone.isEmpty || code.isEmpty
                              ? null
                              : () => openInAppBrowser(context, waUrl),
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('WhatsApp ile Gönder'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
