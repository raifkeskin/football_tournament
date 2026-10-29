import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/team_colors.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/web_safe_image.dart';

/// Takımın oynadığı bir sezon (turnuvanın o yılki sezonu).
class TeamSeasonOption {
  const TeamSeasonOption({
    required this.id,
    required this.leagueName,
    required this.year,
    this.isDefault = false,
  });

  /// seasons.id (kadro ekranının "turnuva" kimliği).
  final String id;
  final String leagueName;

  /// seasons.season_year (yoksa başlangıç yılı); 0 = bilinmiyor.
  final int year;
  final bool isDefault;
}

String seasonYearLabel(int year) => year > 0 ? '$year Sezonu' : 'Sezon';

/// Forma numarası yuvarlağı: takımın ana rengi zemin, ikinci rengi yazı.
class SquadJerseyCircle extends StatelessWidget {
  const SquadJerseyCircle({
    super.key,
    required this.number,
    required this.palette,
    this.size = 32,
  });

  final String number;
  final TeamPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final has = number.isNotEmpty;
    final bg = palette.primary;
    // İkinci renk zeminde okunmuyorsa siyah/beyaz.
    final fg = colorsClash(bg, palette.secondary)
        ? onColorOf(bg)
        : palette.secondary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: has ? bg : null,
        border: Border.all(
          color: has ? fg : kAdminMuted.withValues(alpha: 0.5),
          width: has ? 2 : 1,
        ),
      ),
      child: Text(
        has ? number : '—',
        style: TextStyle(
          color: has ? fg : kAdminMuted,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

/// Oyuncu fotoğrafı (izinliyse); yoksa adın baş harfleri.
class SquadPlayerAvatar extends StatelessWidget {
  const SquadPlayerAvatar({
    super.key,
    required this.name,
    required this.photoUrl,
    this.size = 40,
  });

  final String name;
  final String photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first)
        .join()
        .toUpperCase();
    final url = photoUrl.trim();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0F172A),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: url.isEmpty
          ? Text(
              initials,
              style: TextStyle(
                color: const Color(0xFFE2E8F0),
                fontSize: size * 0.34,
                fontWeight: FontWeight.w800,
              ),
            )
          : WebSafeImage(
              url: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
    );
  }
}

Widget _popupFrame(BuildContext ctx, List<Widget> children) {
  return Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    child: AdminDialogCloseOverlay(
      onClose: () => Navigator.pop(ctx),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.8,
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        decoration: adminDialogDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: selected
            ? kAdminAccent.withValues(alpha: 0.12)
            : const Color(0xFF0F172A).withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected
                ? kAdminAccent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              color: kAdminMuted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_rounded, color: kAdminAccent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Takımın oynadığı sezonlar; seçilen yıl döner.
Future<int?> showSquadSeasonPicker({
  required BuildContext context,
  required List<TeamSeasonOption> options,
  required int selectedYear,
}) {
  final years = options.map((o) => o.year).toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  final nowYear = DateTime.now().year;
  return showDialog<int>(
    context: context,
    builder: (ctx) => _popupFrame(ctx, [
      const AdminDialogHeader(
        icon: Icons.calendar_month_rounded,
        title: 'Sezon',
        subtitle: 'Takımın oynadığı sezonlar',
      ),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final y in years)
              _ChoiceRow(
                title: seasonYearLabel(y),
                subtitle: [
                  if (y == nowYear) 'Aktif sezon',
                  '${options.where((o) => o.year == y).length} turnuva',
                ].join(' · '),
                selected: y == selectedYear,
                onTap: () => Navigator.pop(ctx, y),
              ),
          ],
        ),
      ),
    ]),
  );
}

/// Seçili sezondaki turnuvalar; seçilen sezon kimliği döner.
Future<String?> showSquadTournamentPicker({
  required BuildContext context,
  required List<TeamSeasonOption> options,
  required String? selectedId,
  required int year,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _popupFrame(ctx, [
      AdminDialogHeader(
        icon: Icons.emoji_events_outlined,
        title: 'Turnuva',
        subtitle: '${seasonYearLabel(year)} · takımın oynadığı turnuvalar',
      ),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final o in options)
              _ChoiceRow(
                title: o.leagueName,
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: kAdminAmber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.emoji_events_outlined,
                    color: kAdminAmber,
                    size: 20,
                  ),
                ),
                selected: o.id == selectedId,
                onTap: () => Navigator.pop(ctx, o.id),
              ),
          ],
        ),
      ),
    ]),
  );
}

/// Kadro satırındaki ≡ düğmesinin işlem popup'ı; seçilen işlem döner
/// ('jersey', 'card', 'edit', 'remove').
Future<String?> showSquadPlayerActions({
  required BuildContext context,
  required String name,
  required String subtitle,
  required String photoUrl,
  required String number,
  required TeamPalette palette,
  required bool canEditInfo,
  required bool removeNeedsApproval,
}) {
  Widget action(
    BuildContext ctx,
    String key,
    IconData icon,
    String title, {
    String? sub,
    Color color = Colors.white,
    Color tint = kAdminAccent,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.pop(ctx, key),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: tint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        style: const TextStyle(
                          color: kAdminMuted,
                          fontSize: 11.5,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  return showDialog<String>(
    context: context,
    builder: (ctx) => _popupFrame(ctx, [
      Padding(
        padding: const EdgeInsets.only(right: 28, bottom: 12),
        child: Row(
          children: [
            SquadPlayerAvatar(name: name, photoUrl: photoUrl, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(color: kAdminMuted, fontSize: 12),
                    ),
                ],
              ),
            ),
            SquadJerseyCircle(number: number, palette: palette, size: 38),
          ],
        ),
      ),
      const Divider(color: Colors.white24, height: 1),
      const SizedBox(height: 6),
      action(
        ctx,
        'jersey',
        Icons.checkroom_rounded,
        'Forma no değiştir',
        sub: number.isEmpty ? 'Numarası yok' : 'Şu an $number numara',
      ),
      action(
        ctx,
        'card',
        Icons.badge_outlined,
        'Futbolcu kartını aç',
        tint: const Color(0xFF60A5FA),
      ),
      if (canEditInfo)
        action(
          ctx,
          'edit',
          Icons.edit_outlined,
          'Bilgileri düzenle',
          tint: const Color(0xFFCBD5E1),
        ),
      action(
        ctx,
        'remove',
        Icons.person_remove_outlined,
        'Kadrodan çıkar',
        sub: removeNeedsApproval ? 'Turnuva sorumlusunun onayına gider' : null,
        color: kAdminDanger,
        tint: kAdminDanger,
      ),
    ]),
  );
}

/// Forma numarası popup'ı: yazarak ya da 1-99 arasından seçerek. Dolu
/// numaralar seçilemez. Boş metin = numarayı kaldır; null = vazgeçildi.
Future<String?> showSquadJerseyPicker({
  required BuildContext context,
  required String playerName,
  required String current,
  required Set<int> taken,
  required TeamPalette palette,
}) {
  final controller = TextEditingController(text: current);
  String? error;
  final result = showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final picked = controller.text.trim();
        void submit() {
          final n = int.tryParse(picked);
          if (picked.isNotEmpty && (n == null || n < 1 || n > 999)) {
            setState(() => error = 'Forma numarası geçersiz.');
            return;
          }
          if (n != null && taken.contains(n)) {
            setState(() => error = '$n numara takımda başka oyuncuda.');
            return;
          }
          Navigator.pop(ctx, picked);
        }

        return _popupFrame(ctx, [
          Padding(
            padding: const EdgeInsets.only(right: 28),
            child: Row(
              children: [
                SquadJerseyCircle(number: picked, palette: palette, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Forma Numarası',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        current.isEmpty
                            ? playerName
                            : '$playerName · şu an $current',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kAdminMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            onChanged: (_) => setState(() => error = null),
            onSubmitted: (_) => submit(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Numara yaz',
              hintStyle: const TextStyle(color: kAdminMuted, fontSize: 15),
              filled: true,
              fillColor: const Color(0xFF0F172A).withValues(alpha: 0.7),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kAdminAccent),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kAdminDanger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(
                child: Text(
                  'veya seç',
                  style: TextStyle(color: kAdminMuted, fontSize: 12),
                ),
              ),
              Text(
                'Soluk olanlar dolu',
                style: TextStyle(color: kAdminMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 6,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (var v = 1; v <= 99; v++)
                  _NumberCell(
                    value: v,
                    taken: taken.contains(v),
                    selected: picked == '$v',
                    palette: palette,
                    onTap: () => setState(() {
                      controller.text = '$v';
                      error = null;
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (current.isNotEmpty) ...[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: kAdminDanger,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, ''),
                    child: const Text(
                      'Numarayı kaldır',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: AdminPrimaryButton(label: 'KAYDET', onPressed: submit),
              ),
            ],
          ),
        ]);
      },
    ),
  );
  // Kapanış animasyonu bitene kadar alan controller'ı kullanır.
  result.whenComplete(
    () => Future<void>.delayed(
      const Duration(milliseconds: 600),
      controller.dispose,
    ),
  );
  return result;
}

class _NumberCell extends StatelessWidget {
  const _NumberCell({
    required this.value,
    required this.taken,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final int value;
  final bool taken;
  final bool selected;
  final TeamPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return Center(
        child: SquadJerseyCircle(number: '$value', palette: palette, size: 42),
      );
    }
    return Center(
      child: Material(
        type: MaterialType.circle,
        color: taken
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFF0F172A).withValues(alpha: 0.7),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: taken ? null : onTap,
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: taken ? 0.05 : 0.14),
              ),
            ),
            child: Text(
              '$value',
              style: TextStyle(
                color: taken ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
