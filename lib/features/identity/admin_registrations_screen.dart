import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import 'verified_badge.dart';

/// Kayıtlar (yalnız admin): uygulamadan açılan hesaplar, en yeni üstte.
class AdminRegistrationsScreen extends StatefulWidget {
  const AdminRegistrationsScreen({super.key});

  @override
  State<AdminRegistrationsScreen> createState() =>
      _AdminRegistrationsScreenState();
}

class _AdminRegistrationsScreenState extends State<AdminRegistrationsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client.rpc(
        'admin_registrations',
        params: {'p_limit': 300},
      );
      if (!mounted) return;
      setState(() {
        _items = [
          for (final e in (r as List? ?? const []))
            Map<String, dynamic>.from(e as Map),
        ];
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Kayıtlar yüklenemedi. Aşağı çekerek yenileyin.';
        });
      }
    }
  }

  static String _kindLabel(String k) => switch (k) {
    'player' => 'Futbolcu',
    'fan' => 'Taraftar',
    'organizer' => 'Sorumlu',
    _ => 'Diğer',
  };

  static Color _kindColor(String k) => switch (k) {
    'player' => const Color(0xFF34D399),
    'fan' => const Color(0xFFA78BFA),
    'organizer' => const Color(0xFFFBBF24),
    _ => kAdminMuted,
  };

  static String _phone(String raw) => raw.length == 10
      ? '0 ${raw.substring(0, 3)} ${raw.substring(3, 6)} '
            '${raw.substring(6, 8)} ${raw.substring(8)}'
      : raw;

  static String _when(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    final date =
        '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
    final diff = DateTime.now().difference(d);
    final ago = diff.inDays >= 1
        ? '${diff.inDays} gün önce'
        : diff.inHours >= 1
        ? '${diff.inHours} sa önce'
        : 'az önce';
    return '$date · $ago';
  }

  Widget _tick(Map<String, dynamic> r) {
    final v = r['verified'];
    if (v == null) return const SizedBox.shrink();
    if (v == 'pending') {
      return const Padding(
        padding: EdgeInsets.only(left: 6),
        child: Icon(Icons.hourglass_top_rounded, size: 16, color: kIbrazOrange),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: VerifiedBadge(size: 16, ibraz: v == 'ibraz'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filter == 'all'
        ? _items
        : [
            for (final r in _items)
              if (r['kind'] == _filter) r,
          ];
    return AdminPageScaffold(
      title: 'Kayıtlar',
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in const [
                          ('all', 'Tümü'),
                          ('player', 'Futbolcu'),
                          ('fan', 'Taraftar'),
                          ('organizer', 'Sorumlu'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(f.$2),
                              selected: _filter == f.$1,
                              onSelected: (_) => setState(() => _filter = f.$1),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kAdminMuted),
                      ),
                    )
                  else if (shown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Text(
                        'Kayıt yok.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kAdminMuted),
                      ),
                    )
                  else
                    for (final r in shown) _row(r),
                ],
              ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final kind = (r['kind'] ?? '').toString();
    final name = (r['name'] ?? '').toString().trim();
    final phone = (r['phone'] ?? '').toString();
    final c = _kindColor(kind);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16213A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(color: c, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isEmpty ? '(adsız)' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _tick(r),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (phone.isNotEmpty) _phone(phone),
                    _when((r['created_at'] ?? '').toString()),
                  ].where((e) => e.isNotEmpty).join('  ·  '),
                  style: const TextStyle(color: kAdminMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _kindLabel(kind),
              style: TextStyle(
                color: c,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
