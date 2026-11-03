import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/admin_page.dart';

const _card = Color(0xFF1E293B);
const _muted = Color(0xFF94A3B8);
const _soft = Color(0xFFE2E8F0);
const _accent = Color(0xFF10B981);

/// Admin İstatistikler: kaynak kullanımı (trafik, depolama, Drive;
/// admin_usage_stats), kayıtlı kullanıcılar, futbolcular, etkin cihazlar ve
/// son 30 günde açılan cihazların sürüm dağılımı (admin_app_stats).
class AdminStatsScreen extends StatefulWidget {
  const AdminStatsScreen({super.key});

  @override
  State<AdminStatsScreen> createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends State<AdminStatsScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  late Future<Map<String, dynamic>> _usage = _loadUsage();

  Future<Map<String, dynamic>> _load() async {
    final r = await Supabase.instance.client.rpc('admin_app_stats');
    return Map<String, dynamic>.from(r as Map);
  }

  Future<Map<String, dynamic>> _loadUsage() async {
    final r = await Supabase.instance.client.rpc('admin_usage_stats');
    return Map<String, dynamic>.from(r as Map);
  }

  Future<void> _refresh() async {
    final f = _load();
    final u = _loadUsage();
    setState(() {
      _future = f;
      _usage = u;
    });
    await Future.wait([f, u]);
  }

  @override
  Widget build(BuildContext context) {
    // Diğer yönetim ekranları gibi: geri tuşu üst bantta, başlık altında.
    return AdminPageScaffold(
      title: 'İstatistikler',
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
                FutureBuilder<Map<String, dynamic>>(
                  future: _usage,
                  builder: (context, u) => u.hasData
                      ? _UsageSection(data: u.data!)
                      : const SizedBox.shrink(),
                ),
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

/// Kaynak kullanımı: bu ayın trafiği (önbelleksiz / önbellekli), depolama ve
/// Drive arşivi; kotaya göre çubuk (%70'te sarı, %90'da kırmızı), son 30 gün
/// günlük trafik ve en çok yer kaplayan turnuvalar.
class _UsageSection extends StatelessWidget {
  const _UsageSection({required this.data});

  final Map<String, dynamic> data;

  static String gb(num bytes) {
    final g = bytes / 1e9;
    if (g >= 10) return '${g.toStringAsFixed(0)} GB';
    if (g >= 1) return '${g.toStringAsFixed(1)} GB';
    return '${(bytes / 1e6).toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final q = data['quotas'] is Map ? data['quotas'] as Map : const {};
    final month = data['month'] is Map ? data['month'] as Map : const {};
    num m(String kind, String k) => ((month[kind] as Map?)?[k] as num?) ?? 0;
    num sum(String k) =>
        month.keys.fold<num>(0, (a, kind) => a + m(kind.toString(), k));
    final storage = data['storage'] is Map ? data['storage'] as Map : const {};
    num st(String b) => ((storage[b] as Map?)?['bytes'] as num?) ?? 0;
    final storageTotal = storage.keys.fold<num>(
      0,
      (a, b) => a + st(b.toString()),
    );
    final drive = data['drive'] is Map ? data['drive'] as Map : null;
    final driveBy = drive?['by_league'] is Map
        ? (drive!['by_league'] as Map).entries
              .where((e) => !e.key.toString().startsWith('.'))
              .toList()
        : <MapEntry>[];
    driveBy.sort((a, b) => (b.value as num).compareTo(a.value as num));
    final daily = [
      for (final d in (data['daily'] as List? ?? const []))
        if (d is Map) d,
    ];
    final leagues = [
      for (final l in (data['storage_leagues'] as List? ?? const []))
        if (l is Map) l,
    ];
    final since = DateTime.tryParse(
      (data['collected_since'] ?? '').toString(),
    )?.toLocal();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Text(
            'KAYNAK KULLANIMI · bu ay',
            style: TextStyle(
              color: _muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        _meter(
          'Trafik',
          sum('bytes'),
          (q['egress_gb'] as num?) ?? 250,
          'Video ${gb(m('video', 'bytes'))} · Fotoğraf ${gb(m('dosya', 'bytes'))}',
        ),
        _meter(
          'Önbellekli trafik',
          sum('cached'),
          (q['cached_egress_gb'] as num?) ?? 250,
          'Video ${gb(m('video', 'cached'))} · Fotoğraf ${gb(m('dosya', 'cached'))}',
        ),
        _meter(
          'Depolama',
          storageTotal,
          (q['storage_gb'] as num?) ?? 100,
          'Videolar ${gb(st('clips'))} · Fotoğraflar ${gb(st('media'))}',
        ),
        if (drive != null)
          _meter(
            'Drive arşivi',
            (drive['bytes'] as num?) ?? 0,
            null,
            [
              for (final e in driveBy.take(2)) '${e.key} ${gb(e.value as num)}',
            ].join(' · '),
          ),
        if (daily.isNotEmpty) _dailyChart(daily),
        if (leagues.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Depolamada en çok yer kaplayan turnuvalar',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                for (final l in leagues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (l['league'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _soft, fontSize: 13),
                          ),
                        ),
                        Text(
                          gb((l['bytes'] as num?) ?? 0),
                          style: const TextStyle(
                            color: _soft,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
          child: Text(
            since == null
                ? 'Trafik ölçümü ilk saatlik toplamadan sonra görünür.'
                : 'Trafik ${since.day}.${since.month}.${since.year} tarihinden '
                      'beri ölçülüyor. Uygulama verisinin (listeler, skorlar) '
                      'boyutu kayıtlarda yazmadığı için dahil değil; asıl yük '
                      'video ve fotoğraf. %70\'te Telegram uyarısı gelir.',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _meter(String label, num used, num? quotaGb, String sub) {
    final ratio = quotaGb == null || quotaGb <= 0
        ? null
        : (used / (quotaGb * 1e9)).clamp(0.0, 1.0).toDouble();
    final color = ratio == null || ratio < 0.7
        ? _accent
        : ratio < 0.9
        ? const Color(0xFFFBBF24)
        : const Color(0xFFF87171);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _soft,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                quotaGb == null ? gb(used) : '${gb(used)} / $quotaGb GB',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (ratio != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                color: color,
                backgroundColor: Colors.white12,
              ),
            ),
          ],
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(sub, style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  /// Son 30 gün: günlük trafik (önbelleksiz yeşil, önbellekli soluk).
  Widget _dailyChart(List<Map> daily) {
    num total(Map d) =>
        ((d['bytes'] as num?) ?? 0) + ((d['cached'] as num?) ?? 0);
    final peak = daily.fold<num>(0, (a, d) => total(d) > a ? total(d) : a);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Günlük trafik',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const Spacer(),
              Text(
                'en yüksek ${gb(peak)}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in daily)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: peak == 0
                                ? 0
                                : 56 * ((d['cached'] as num?) ?? 0) / peak,
                            color: _accent.withValues(alpha: 0.35),
                          ),
                          Container(
                            height: peak == 0
                                ? 0
                                : 56 * ((d['bytes'] as num?) ?? 0) / peak,
                            color: _accent,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
