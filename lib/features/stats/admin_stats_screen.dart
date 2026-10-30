import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _bg = Color(0xFF0F172A);
const _card = Color(0xFF1E293B);
const _muted = Color(0xFF94A3B8);
const _soft = Color(0xFFE2E8F0);
const _accent = Color(0xFF10B981);

/// Admin İstatistikler: kayıtlı kullanıcılar, futbolcular, etkin cihazlar
/// ve son 30 günde açılan cihazların sürüm dağılımı (admin_app_stats).
class AdminStatsScreen extends StatefulWidget {
  const AdminStatsScreen({super.key});

  @override
  State<AdminStatsScreen> createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends State<AdminStatsScreen> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() async {
    final r = await Supabase.instance.client.rpc('admin_app_stats');
    return Map<String, dynamic>.from(r as Map);
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1729),
        foregroundColor: Colors.white,
        title: const Text('İstatistikler'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Okunamadı: ${snap.error}',
                style: const TextStyle(color: _muted),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _accent),
            );
          }
          final d = snap.data!;
          int n(String k) => (d[k] as num?)?.toInt() ?? 0;
          final versions = [
            for (final v in (d['versions'] as List? ?? const []))
              if (v is Map) v,
          ];
          final since = DateTime.tryParse(
            (d['tracking_since'] ?? '').toString(),
          )?.toLocal();
          return RefreshIndicator(
            color: _accent,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
              children: [
                _section('KULLANICILAR'),
                _grid([
                  ('Hesabı olan', n('users')),
                  ('Son 24 saatte giriş', n('users_24h')),
                  ('Son 7 günde giriş', n('users_7d')),
                  ('Son 7 günde yeni', n('users_new_7d')),
                ]),
                _section('FUTBOLCULAR'),
                _grid([
                  ('Toplam kayıt', n('players')),
                  ('Hesabına bağlı', n('players_linked')),
                  ('Bildirim izni veren', n('push_devices')),
                ]),
                _section('CİHAZLAR (uygulamayı açan)'),
                _grid([
                  ('Son 24 saat', n('clients_1d')),
                  ('Son 7 gün', n('clients_7d')),
                  ('Son 30 gün', n('clients_30d')),
                ]),
                _section('SÜRÜM DAĞILIMI · son 30 gün'),
                if (versions.isEmpty)
                  const Text(
                    'Henüz kayıt yok.',
                    style: TextStyle(color: _muted),
                  )
                else
                  ..._versionRows(versions),
                const SizedBox(height: 14),
                Text(
                  'Sürüm kaydı bu sürümle başladı'
                  '${since == null ? '' : ' (${since.day}.${since.month}.${since.year})'}; '
                  'daha eski sürümler kendini bildirmez. Eski sürüm sayısı için '
                  'Play Console ve App Store Connect istatistiklerine bakın.',
                  style: const TextStyle(color: _muted, fontSize: 12.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
    child: Text(
      t,
      style: const TextStyle(
        color: _muted,
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    ),
  );

  Widget _grid(List<(String, int)> items) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (label, value) in items)
        Container(
          width: 160,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(color: _muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
    ],
  );

  List<Widget> _versionRows(List<Map> versions) {
    final total = versions.fold<int>(
      0,
      (s, v) => s + ((v['devices'] as num?)?.toInt() ?? 0),
    );
    const names = {'android': 'Android', 'ios': 'iOS', 'web': 'Web'};
    return [
      for (final v in versions)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${names[v['platform']] ?? v['platform']} · ${v['version']}',
                      style: const TextStyle(
                        color: _soft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${v['devices']} cihaz · ${v['users']} hesap',
                      style: const TextStyle(color: _muted, fontSize: 12.5),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: total == 0
                        ? 0
                        : ((v['devices'] as num?) ?? 0) / total,
                    minHeight: 6,
                    color: _accent,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}
