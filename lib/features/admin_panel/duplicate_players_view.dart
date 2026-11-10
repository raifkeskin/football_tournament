import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/admin_page.dart';

/// Bekleyen Onaylar → "Çift kayıt": aynı ad-soyadlı oyuncu çiftleri. Admin
/// hangi kaydın kalacağını seçip birleştirir ya da "Farklı kişiler" der.
/// Veri `admin_dup_candidates()` ile gelir; birleştirme tek işlemde
/// `admin_player_merge` ile yapılır (silinen kaydın yedeği tutulur).
class DuplicatePlayersView extends StatefulWidget {
  const DuplicatePlayersView({super.key, this.onCount});

  /// Bekleyen çift sayısı değişince haber verir (sekme rozeti için).
  final ValueChanged<int>? onCount;

  @override
  State<DuplicatePlayersView> createState() => _DuplicatePlayersViewState();
}

/// Sekme rozeti için bekleyen çift sayısı; hata olursa 0.
Future<int> fetchDuplicatePairCount() async {
  try {
    final r = await Supabase.instance.client.rpc('admin_dup_candidates');
    return (r as List).length;
  } catch (_) {
    return 0;
  }
}

class _Rec {
  _Rec(Map<String, dynamic> m)
    : id = m['id'] as String,
      name = '${m['name']} ${m['surname']}',
      birth = DateTime.tryParse('${m['birth_date']}'),
      phone = (m['phone'] as String?) ?? '',
      hasAccount = m['has_acc'] == true,
      events = (m['ev'] as num?)?.toInt() ?? 0,
      rosters = [
        for (final r in (m['rosters'] as List? ?? const []))
          '${r['team']} (${r['league']})',
      ];

  final String id;
  final String name;
  final DateTime? birth;
  final String phone;
  final bool hasAccount;
  final int events;
  final List<String> rosters;

  bool get placeholder => birth != null && birth!.day == 1 && birth!.month == 1;

  String get birthText {
    final b = birth;
    if (b == null) return 'Tarih yok';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(b.day)}.${two(b.month)}.${b.year}';
  }
}

class _Pair {
  _Pair(Map<String, dynamic> m)
    : a = _Rec(Map<String, dynamic>.from(m['a'] as Map)),
      b = _Rec(Map<String, dynamic>.from(m['b'] as Map)),
      sameSeason = m['same_season'] == true,
      bothAccounts = m['both_accounts'] == true;

  final _Rec a;
  final _Rec b;
  final bool sameSeason;
  final bool bothAccounts;

  /// Aynı kişi olma ihtimali yüksekse büyük (sıralama için).
  int get score {
    var s = 0;
    final ya = a.birth?.year, yb = b.birth?.year;
    if (ya != null && yb != null && (ya - yb).abs() <= 1) s += 3;
    if (a.placeholder || b.placeholder) s += 2;
    if (!sameSeason) s += 1;
    return s;
  }
}

class _DuplicatePlayersViewState extends State<DuplicatePlayersView> {
  final _client = Supabase.instance.client;
  List<_Pair> _pairs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _client.rpc('admin_dup_candidates') as List;
      final pairs = [
        for (final m in r) _Pair(Map<String, dynamic>.from(m as Map)),
      ]..sort((x, y) => y.score.compareTo(x.score));
      if (!mounted) return;
      setState(() => _pairs = pairs);
      widget.onCount?.call(pairs.length);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _pairs.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: kAdminAccent),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Liste alınamadı: $_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    if (_pairs.isEmpty) {
      return const Center(
        child: Text(
          'Olası çift kayıt yok.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return RefreshIndicator(
      color: kAdminAccent,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, kAdminFabClearance),
        itemCount: _pairs.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == 0) {
            return const Text(
              'Aynı ad ve soyadı olan kayıtlar. Dokununca karşılaştırma açılır; '
              'aynı kişi olma ihtimali yüksek olanlar üstte.',
              style: TextStyle(color: Colors.white54, fontSize: 12.5),
            );
          }
          final p = _pairs[i - 1];
          return _PairCard(pair: p, onTap: () => _open(p));
        },
      ),
    );
  }

  Future<void> _open(_Pair p) async {
    final changed = await showAdminPopup<bool>(
      context: context,
      builder: (_) => _MergeSheet(pair: p),
    );
    if (changed == true) await _load();
  }
}

class _PairCard extends StatelessWidget {
  const _PairCard({required this.pair, required this.onTap});

  final _Pair pair;
  final VoidCallback onTap;

  Widget _badge(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      t,
      style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w800),
    ),
  );

  Widget _line(_Rec r) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(
            r.birthText,
            style: TextStyle(
              color: r.placeholder ? const Color(0xFFFCD34D) : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            r.rosters.isEmpty ? 'Takımı yok' : r.rosters.join(', '),
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ),
        Text(
          '${r.events} olay',
          style: const TextStyle(color: Colors.white38, fontSize: 11.5),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final a = pair.a;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF131D33),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    a.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (pair.sameSeason)
                  _badge('AYNI SEZON', const Color(0xFFF87171))
                else if (pair.a.placeholder || pair.b.placeholder)
                  _badge('01.01 VAR', const Color(0xFFFCD34D)),
              ],
            ),
            _line(pair.a),
            _line(pair.b),
          ],
        ),
      ),
    );
  }
}

class _MergeSheet extends StatefulWidget {
  const _MergeSheet({required this.pair});

  final _Pair pair;

  @override
  State<_MergeSheet> createState() => _MergeSheetState();
}

class _MergeSheetState extends State<_MergeSheet> {
  final _client = Supabase.instance.client;
  _Rec? _keep;
  bool _busy = false;

  _Rec get _drop => _keep == widget.pair.a ? widget.pair.b : widget.pair.a;

  Future<void> _merge() async {
    if (_keep == null) return;
    final pair = widget.pair;
    setState(() => _busy = true);
    try {
      await _client.rpc(
        'admin_player_merge',
        params: {
          'p_keep': _keep!.id,
          'p_drop': _drop.id,
          'p_force': pair.sameSeason,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kayıtlar birleştirildi.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _different() async {
    setState(() => _busy = true);
    try {
      await _client.rpc(
        'admin_dup_dismiss',
        params: {'p_a': widget.pair.a.id, 'p_b': widget.pair.b.id},
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  Widget _option(_Rec r) {
    final sel = _keep == r;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: (_busy || widget.pair.a.hasAccount || widget.pair.b.hasAccount)
          ? null
          : () => setState(() => _keep = r),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF0F2A26) : const Color(0xFF131D33),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? kAdminAccent : Colors.white.withValues(alpha: 0.14),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.birthText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(
                  sel
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: sel ? kAdminAccent : Colors.white38,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _kv('Takım', r.rosters.isEmpty ? 'yok' : r.rosters.join('\n')),
            _kv('Olay', '${r.events}'),
            _kv('Telefon', r.phone.isEmpty ? 'yok' : r.phone),
            _kv('Giriş hesabı', r.hasAccount ? 'var' : 'yok'),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            k,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pair = widget.pair;
    final blocked = pair.bothAccounts;
    // Giriş hesabı olan kayıt her zaman kalır.
    final mustKeep = pair.a.hasAccount
        ? pair.a
        : (pair.b.hasAccount ? pair.b : null);
    if (_keep == null && mustKeep != null) _keep = mustKeep;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${pair.a.name} · Birleştir',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Hangi kayıt kalsın? Seçtiğiniz kaydın doğum tarihi, adı ve '
            'telefonu korunur. Diğerinin takım, forma, gol ve istatistikleri '
            'buna taşınır.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          if (blocked)
            _note(
              'İki kaydın da giriş hesabı var. Bunlar otomatik '
              'birleştirilemez; "Farklı kişiler" diyebilirsiniz.',
              const Color(0xFFF87171),
            )
          else if (pair.sameSeason)
            _note(
              'Dikkat: bu iki kayıt aynı sezonda farklı takımlarda. Aynı kişi '
              'iki takımda aynı anda oynayamaz. Birleştirirseniz seçtiğiniz '
              'kaydın takımı kalır, diğerinin o sezondaki takımı kadrodan '
              'çıkar.',
              const Color(0xFFFCD34D),
            ),
          if (blocked || pair.sameSeason) const SizedBox(height: 10),
          _option(pair.a),
          const SizedBox(height: 10),
          _option(pair.b),
          if (mustKeep != null && !blocked) ...[
            const SizedBox(height: 8),
            const Text(
              'Giriş hesabı olan kayıt kalır.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          if (_keep != null && !blocked)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Kalan kayıt: ${_keep!.birthText}. '
                '${_drop.birthText} tarihli kayıt silinir, yedeği saklanır.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ),
          FilledButton(
            onPressed: (_keep == null || blocked || _busy) ? null : _merge,
            style: FilledButton.styleFrom(
              backgroundColor: pair.sameSeason
                  ? const Color(0xFFF59E0B)
                  : kAdminAccent,
              foregroundColor: const Color(0xFF04120D),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
            ),
            child: Text(
              pair.sameSeason ? 'YİNE DE BİRLEŞTİR' : 'BİRLEŞTİR',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _different,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'FARKLI KİŞİLER',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(String t, Color c) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.withValues(alpha: 0.5)),
    ),
    child: Text(t, style: TextStyle(color: c, fontSize: 12.5, height: 1.35)),
  );
}
