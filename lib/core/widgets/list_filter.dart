import 'package:flutter/material.dart';

import 'admin_form.dart';
import 'admin_page.dart';

/// Filtre penceresindeki bir bölüm: az seçenekte yan yana düğmeler, çok
/// seçenekte (ör. turnuva listesi) açılır liste.
class ListFilterSection {
  const ListFilterSection({
    required this.key,
    required this.label,
    required this.options,
    required this.defaultValue,
    this.hint,
    this.dropdown = false,
  });

  final String key;
  final String label;

  /// (değer, etiket)
  final List<(String, String)> options;
  final String defaultValue;
  final String? hint;
  final bool dropdown;

  String labelOf(String value) =>
      options.firstWhere((o) => o.$1 == value, orElse: () => options.first).$2;
}

/// Filtre penceresindeki sayılar: seçimle kalan toplam ve her bölümde
/// yalnız o bölüm değişirse kalacak sayı (bölüm → değer → sayı).
class ListFilterCounts {
  const ListFilterCounts({required this.total, required this.options});

  final int total;
  final Map<String, Map<String, int>> options;

  int? of(String key, String value) => options[key]?[value];

  /// Liste telefondaysa sayılar doğrudan hesaplanır.
  static ListFilterCounts compute(
    List<ListFilterSection> sections,
    Map<String, String> values,
    int Function(Map<String, String> values) count,
  ) => ListFilterCounts(
    total: count(values),
    options: {
      for (final s in sections)
        s.key: {
          for (final o in s.options) o.$1: count({...values, s.key: o.$1}),
        },
    },
  );
}

/// Seçenekleri arasında olmayan seçimleri varsayılana çeker.
Map<String, String> _normalize(
  List<ListFilterSection> Function(Map<String, String>) sections,
  Map<String, String> values,
) {
  final out = {...values};
  for (var i = 0; i < 3; i++) {
    var changed = false;
    for (final s in sections(out)) {
      if (!s.options.any((o) => o.$1 == out[s.key])) {
        out[s.key] = s.defaultValue;
        changed = true;
      }
    }
    if (!changed) break;
  }
  return out;
}

/// Listenin üstündeki "Filtre" düğmesi + varsayılandan farklı seçimlerin
/// çarpılı etiketleri. [count]: o seçimle kalan kayıt sayısı (pencerede
/// her seçeneğin altında yazar).
class ListFilterBar extends StatelessWidget {
  const ListFilterBar({
    super.key,
    required this.sections,
    required this.values,
    required this.onChanged,
    required this.total,
    required this.counts,
    this.title = 'Filtrele',
    this.unit = 'kayıt',
    this.trailing = const [],
  });

  /// Satırın sağına hizalanan düğmeler (ör. ara, ekle).
  final List<Widget> trailing;

  /// Bölümler seçime göre kurulur (ör. sezon listesi seçilen turnuvaya göre).
  final List<ListFilterSection> Function(Map<String, String> values) sections;
  final Map<String, String> values;
  final ValueChanged<Map<String, String>> onChanged;

  /// Uygulanan seçimle görünen kayıt sayısı.
  final int total;

  /// Penceredeki sayılar (sunucudan ya da telefonda hesaplanır).
  final Future<ListFilterCounts> Function(Map<String, String> values) counts;
  final String title;
  final String unit;

  String _value(ListFilterSection s) => values[s.key] ?? s.defaultValue;

  @override
  Widget build(BuildContext context) {
    final list = sections(values);
    final changed = [
      for (final s in list)
        if (_value(s) != s.defaultValue) s,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final r = await showModalBottomSheet<Map<String, String>>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: const Color(0xFF13203A),
                  showDragHandle: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                  ),
                  builder: (_) => _FilterSheet(
                    title: title,
                    unit: unit,
                    sections: sections,
                    initial: {for (final s in list) s.key: _value(s)},
                    counts: counts,
                  ),
                );
                if (r != null) onChanged(r);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Filtre',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (changed.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: kAdminAccent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '${changed.length}',
                        style: const TextStyle(
                          color: Color(0xFF052E1F),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$total $unit',
              style: const TextStyle(color: kAdminMuted, fontSize: 12.5),
            ),
            if (trailing.isNotEmpty) ...[const Spacer(), ...trailing],
          ],
        ),
        if (changed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in changed)
                InputChip(
                  label: Text(s.labelOf(_value(s))),
                  labelStyle: const TextStyle(
                    color: Color(0xFF6EE7B7),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: const Color(0xFF123B31),
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                  visualDensity: VisualDensity.compact,
                  deleteIconColor: const Color(0xFF6EE7B7),
                  onDeleted: () => onChanged(
                    _normalize(sections, {...values, s.key: s.defaultValue}),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.title,
    required this.unit,
    required this.sections,
    required this.initial,
    required this.counts,
  });

  final String title;
  final String unit;
  final List<ListFilterSection> Function(Map<String, String> values) sections;
  final Map<String, String> initial;
  final Future<ListFilterCounts> Function(Map<String, String> values) counts;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Map<String, String> _v = {...widget.initial};

  ListFilterCounts? _counts;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  /// Sayılar her seçim değişiminde yeniden istenir; geç gelen eski yanıt
  /// yok sayılır.
  Future<void> _loadCounts() async {
    final seq = ++_seq;
    try {
      final c = await widget.counts({..._v});
      if (mounted && seq == _seq) setState(() => _counts = c);
    } catch (_) {}
  }

  /// Seçim değişince bağlı bölümlerde geçersiz kalan seçim (ör. turnuva
  /// değişince sezon) varsayılana döner.
  void _set(String key, String value) {
    setState(() {
      _v[key] = value;
      final fixed = _normalize(widget.sections, _v);
      _v
        ..clear()
        ..addAll(fixed);
    });
    _loadCounts();
  }

  Widget _caption(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: kAdminMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    ),
  );

  Widget _segments(ListFilterSection s) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          for (final o in s.options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _set(s.key, o.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: _v[s.key] == o.$1
                        ? kAdminAccent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Column(
                    children: [
                      Text(
                        o.$2,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _v[s.key] == o.$1
                              ? const Color(0xFF052E1F)
                              : Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${_counts?.of(s.key, o.$1) ?? '–'}',
                        style: TextStyle(
                          color: _v[s.key] == o.$1
                              ? const Color(0xFF064E3B)
                              : kAdminMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dropdown(ListFilterSection s) {
    return Material(
      color: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final v = await showAdminOptionPicker<String>(
            context: context,
            title: s.label,
            items: [for (final o in s.options) o.$1],
            labelBuilder: s.labelOf,
            selected: _v[s.key],
          );
          if (v != null && mounted) _set(s.key, v);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.labelOf(_v[s.key] ?? s.defaultValue),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.expand_more_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${_counts?.total ?? '–'} ${widget.unit}',
                style: const TextStyle(color: kAdminMuted, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final s in widget.sections(_v)) ...[
            _caption(s.label),
            s.dropdown ? _dropdown(s) : _segments(s),
            if (s.hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  s.hint!,
                  style: const TextStyle(color: kAdminMuted, fontSize: 11.5),
                ),
              ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    for (final s in widget.sections(_v)) {
                      _v[s.key] = s.defaultValue;
                    }
                    final fixed = _normalize(widget.sections, _v);
                    _v
                      ..clear()
                      ..addAll(fixed);
                    _loadCounts();
                  }),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Text(
                    'Temizle',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, {..._v}),
                  style: FilledButton.styleFrom(
                    backgroundColor: kAdminAccent,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: const Text(
                    'Göster',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
