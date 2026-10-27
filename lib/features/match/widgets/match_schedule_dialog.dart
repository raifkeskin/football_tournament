import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../models/match.dart';

/// Maçı Düzenle penceresi: tarih, saat ve stad (Fikstür ve maç detayı).
Future<void> showMatchScheduleDialog(
  BuildContext context, {
  required MatchModel match,
  required VoidCallback onDataChanged,
}) async {
  const accent = Color(0xFF10B981);
  String initialDate = '';
  if (match.matchDate != null && match.matchDate!.contains('-')) {
    final p = match.matchDate!.split('-');
    if (p.length == 3) initialDate = '${p[2]}/${p[1]}/${p[0]}';
  } else {
    initialDate = match.matchDate ?? '';
  }

  final dCtrl = TextEditingController(text: initialDate);
  final rawInitialTime = (match.matchTime ?? '').trim();
  final initialTimeText = rawInitialTime.length >= 5
      ? rawInitialTime.substring(0, 5)
      : rawInitialTime;
  final tCtrl = TextEditingController(text: initialTimeText);
  final refCtrl = TextEditingController(text: match.refereeName ?? '');
  final dateFocus = FocusNode();
  final timeFocus = FocusNode();

  String? selectedPitchId = (match.pitchId ?? '').trim().isEmpty
      ? null
      : match.pitchId!.trim();
  String? selectedPitchName = (match.pitchName ?? '').trim().isEmpty
      ? null
      : match.pitchName!.trim();

  final pitches = [...await ServiceLocator.leagueService.watchPitches().first]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  if (pitches.length == 1) {
    selectedPitchId = pitches.first.id;
    selectedPitchName = pitches.first.name.trim().isEmpty
        ? null
        : pitches.first.name.trim();
  }
  if (selectedPitchId != null) {
    final m = pitches.where((p) => p.id == selectedPitchId);
    if (m.isNotEmpty) selectedPitchName = m.first.name.trim();
  }

  dCtrl.addListener(() {
    if (dCtrl.text.length == 10) {
      timeFocus.requestFocus();
    }
  });

  if (!context.mounted) return;

  InputDecoration deco(String label, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.4),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      );

  BoxDecoration dialogBox() => BoxDecoration(
    borderRadius: BorderRadius.circular(24),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1E293B), Color(0xFF064E3B)],
    ),
    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    boxShadow: const [
      BoxShadow(color: Colors.black54, blurRadius: 15, offset: Offset(0, 8)),
    ],
  );

  Future<void> pickDateFromCalendar(StateSetter setDialogState) async {
    final m = RegExp(
      r'^(\d{2})[\/\-](\d{2})[\/\-](\d{4})$',
    ).firstMatch(dCtrl.text.trim());
    final current = m == null
        ? null
        : DateTime.tryParse('${m.group(3)}-${m.group(2)}-${m.group(1)}');
    final picked = await showAppDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstYear: DateTime.now().year - 1,
      lastYear: DateTime.now().year + 2,
      title: 'Maç Tarihi',
    );
    if (picked == null) return;
    setDialogState(() {
      dCtrl.text =
          '${picked.day.toString().padLeft(2, '0')}/'
          '${picked.month.toString().padLeft(2, '0')}/'
          '${picked.year}';
    });
    timeFocus.requestFocus();
  }

  /// Stad seçimi: üstte isim filtresi olan ortada açılan popup.
  /// Sonuç: null → vazgeçildi, '' → "Stad Seçilmedi", aksi halde stad id.
  Future<String?> pickPitch() {
    var query = '';
    String norm(String v) =>
        v.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().trim();
    return showDialog<String>(
      context: context,
      builder: (pc) => StatefulBuilder(
        builder: (pc, setLocal) {
          final q = norm(query);
          final list = pitches
              .where((p) => q.isEmpty || norm(p.name).contains(q))
              .toList();
          final h = MediaQuery.of(pc).size.height * 0.7;
          Widget tile(String id, String title, String sub) {
            final on = (selectedPitchId ?? '') == id;
            return ListTile(
              dense: true,
              title: Text(
                title,
                style: TextStyle(
                  color: on ? accent : Colors.white,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              subtitle: sub.isEmpty
                  ? null
                  : Text(
                      sub,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
              trailing: on
                  ? const Icon(Icons.check_rounded, color: accent)
                  : null,
              onTap: () => Navigator.pop(pc, id),
            );
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: h,
              padding: const EdgeInsets.all(20),
              decoration: dialogBox(),
              child: Column(
                children: [
                  const Text(
                    'Stad Seç',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    onChanged: (v) => setLocal(() => query = v),
                    decoration: deco('Stad ara', Icons.search_rounded),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        if (q.isEmpty) tile('', 'Stad Seçilmedi', ''),
                        for (final p in list)
                          tile(
                            p.id,
                            p.name,
                            [
                              if (p.city.trim().isNotEmpty) p.city.trim(),
                              if (p.country.trim().isNotEmpty) p.country.trim(),
                            ].join(' / '),
                          ),
                        if (list.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'Stad bulunamadı.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setDialogState) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: AdminDialogCloseOverlay(
          onClose: () => Navigator.pop(c),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: dialogBox(),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit_calendar_rounded, color: accent),
                      SizedBox(width: 8),
                      Text(
                        'Maçı Düzenle',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 18),
                  // Elle yazılabilir; buton standart takvimi açar.
                  TextField(
                    controller: dCtrl,
                    focusNode: dateFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_DateInputFormatter()],
                    style: const TextStyle(color: Colors.white),
                    decoration: deco(
                      'Tarih (GG/AA/YYYY)',
                      Icons.event_rounded,
                      suffix: IconButton(
                        tooltip: 'Takvimden seç',
                        icon: const Icon(
                          Icons.calendar_month_outlined,
                          color: accent,
                        ),
                        onPressed: () => pickDateFromCalendar(setDialogState),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tCtrl,
                    focusNode: timeFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_TimeInputFormatter()],
                    style: const TextStyle(color: Colors.white),
                    decoration: deco('Saat (SS:DD)', Icons.schedule_rounded),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final picked = await pickPitch();
                      if (picked == null) return;
                      setDialogState(() {
                        if (picked.isEmpty) {
                          selectedPitchId = null;
                          selectedPitchName = null;
                        } else {
                          selectedPitchId = picked;
                          final name = pitches
                              .firstWhere((p) => p.id == picked)
                              .name
                              .trim();
                          selectedPitchName = name.isEmpty ? null : name;
                        }
                      });
                    },
                    child: InputDecorator(
                      decoration: deco('Stad', Icons.stadium_outlined),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedPitchName ?? 'Stad Seçilmedi',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selectedPitchName == null
                                    ? Colors.white54
                                    : Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: Colors.white),
                    decoration: deco('Hakem', Icons.sports_rounded),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        final dateText = dCtrl.text;
                        final timeText = tCtrl.text;

                        final dateMatch = RegExp(
                          r'^(\d{2})[\/\-](\d{2})[\/\-](\d{4})$',
                        ).firstMatch(dateText);
                        if (dateMatch == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Tarih formatı hatalı! (GG/AA/YYYY)',
                              ),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }
                        final timeMatch = RegExp(
                          r'^(\d{2}):(\d{2})$',
                        ).firstMatch(timeText);
                        if (timeMatch == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Saat formatı hatalı! (SS:DD)'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }

                        final dd = dateMatch.group(1)!;
                        final mm = dateMatch.group(2)!;
                        final yyyy = dateMatch.group(3)!;
                        final dbDate = '$yyyy-$mm-$dd';

                        try {
                          await ServiceLocator.matchService.updateMatchSchedule(
                            matchId: match.id,
                            matchDateDb: dbDate,
                            matchTime: timeText,
                            pitchId: selectedPitchId,
                            pitchName: selectedPitchName,
                            refereeName: refCtrl.text,
                          );
                          if (c.mounted) Navigator.pop(c);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Maç güncellendi.'),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                          onDataChanged();
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Güncelleme başarısız: $e'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'GÜNCELLE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // Dialog kapanış animasyonu bitene kadar alanlar bunları kullanır.
  Future<void>.delayed(const Duration(milliseconds: 600), () {
    dateFocus.dispose();
    timeFocus.dispose();
    dCtrl.dispose();
    tCtrl.dispose();
    refCtrl.dispose();
  });
}

class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    if (newValue.text.length < oldValue.text.length) return newValue;
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length > 8) digitsOnly = digitsOnly.substring(0, 8);
    String formatted = '';
    for (int i = 0; i < digitsOnly.length; i++) {
      formatted += digitsOnly[i];
      if (i == 1 || i == 3) formatted += '/';
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _TimeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length < oldValue.text.length) return newValue;
    String cleanText = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanText.length > 4) cleanText = cleanText.substring(0, 4);
    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < cleanText.length; i++) {
      buffer.write(cleanText[i]);
      if (i == 1) buffer.write(':');
    }
    String finalString = buffer.toString();
    return TextEditingValue(
      text: finalString,
      selection: TextSelection.collapsed(offset: finalString.length),
    );
  }
}
