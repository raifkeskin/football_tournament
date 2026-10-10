import 'package:flutter/material.dart';

const _months = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];
const _weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const _accent = Color(0xFF10B981);
const _dot = Color(0xFF38BDF8);

/// Uygulamanın standart tarih seçicisi (ortada açılan gradientli popup).
///
/// - Bir güne dokunmak tarihi seçer ve popup'ı kapatır.
/// - Popup dışına dokunmak hiçbir şey seçmeden kapatır (sonuç `null`).
/// - [markedDays] verilirse, döndürdüğü günlerin altına nokta konur
///   (ör. maç olan günler). Ay/yıl değiştikçe yeniden çağrılır.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  DateTime? initialDate,
  int? firstYear,
  int? lastYear,
  String title = 'Tarih Seçin',
  Future<Set<int>> Function(int year, int month)? markedDays,
}) {
  final now = DateTime.now();
  final init = initialDate ?? now;
  final fromYear = firstYear ?? now.year - 5;
  final toYear = lastYear ?? now.year + 5;
  var year = init.year.clamp(fromYear, toYear);
  var month = init.month;
  final selected = DateTime(init.year, init.month, init.day);

  var loadedKey = '';
  Future<Set<int>> marks = Future.value(const <int>{});

  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final key = '$year-$month';
        if (markedDays != null && key != loadedKey) {
          loadedKey = key;
          marks = markedDays(year, month);
        }
        final first = DateTime(year, month, 1);
        final daysInMonth = DateTime(year, month + 1, 0).day;
        final lead = first.weekday - 1; // Pazartesi başlangıçlı

        // Ay gezinmesi: < Ekim 2026 >; yıl sınırlarında ok pasifleşir.
        final canPrev = year > fromYear || month > 1;
        final canNext = year < toYear || month < 12;
        void shift(int delta) => setLocal(() {
          final d = DateTime(year, month + delta);
          year = d.year;
          month = d.month;
        });
        Widget arrow(IconData icon, String tip, bool enabled, int delta) =>
            IconButton(
              tooltip: tip,
              onPressed: enabled ? () => shift(delta) : null,
              icon: Icon(icon),
              color: Colors.white,
              disabledColor: Colors.white24,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.3),
                side: const BorderSide(color: Colors.white24),
              ),
            );

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E293B), Color(0xFF064E3B)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 15,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      arrow(
                        Icons.chevron_left_rounded,
                        'Önceki ay',
                        canPrev,
                        -1,
                      ),
                      Expanded(
                        child: Text(
                          '${_months[month - 1]} $year',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      arrow(
                        Icons.chevron_right_rounded,
                        'Sonraki ay',
                        canNext,
                        1,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      for (final w in _weekdays)
                        Expanded(
                          child: Text(
                            w,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<Set<int>>(
                    future: marks,
                    builder: (context, snap) {
                      final marked = snap.data ?? const <int>{};
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                            ),
                        itemCount: lead + daysInMonth,
                        itemBuilder: (context, index) {
                          if (index < lead) return const SizedBox.shrink();
                          final day = index - lead + 1;
                          final date = DateTime(year, month, day);
                          final isSelected = date == selected;
                          final isToday =
                              date == DateTime(now.year, now.month, now.day);
                          return InkWell(
                            // Güne dokunmak seçer ve kapatır.
                            onTap: () => Navigator.pop(ctx, date),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _accent
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: isSelected
                                    ? Border.all(color: Colors.white)
                                    : (isToday
                                          ? Border.all(
                                              color: _accent.withValues(
                                                alpha: 0.7,
                                              ),
                                            )
                                          : null),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$day',
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white70,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: marked.contains(day)
                                          ? (isSelected ? Colors.white : _dot)
                                          : Colors.transparent,
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
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
