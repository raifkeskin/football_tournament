import 'package:flutter/material.dart';

import '../../core/widgets/admin_form.dart' show showAdminInfoDialog;
import 'identity_service.dart';

/// Onaylı profil rengi (mavi tik).
const kVerifiedBlue = Color(0xFF38BDF8);

/// Kimlik ibrazıyla onaylı profil rengi (turuncu tik).
const kIbrazOrange = Color(0xFFF97316);

/// Kimliği çipten doğrulanmış oyuncunun yanında görünen mavi tik.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 16, this.ibraz = false});

  final double size;

  /// Kimlik ibrazıyla onaylı: turuncu tik.
  final bool ibraz;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: ibraz
        ? 'Kimlik İbraz Onaylı'
        : 'Onaylı profil: kimliği çipten doğrulandı',
    child: Icon(
      Icons.verified_rounded,
      color: ibraz ? kIbrazOrange : kVerifiedBlue,
      size: size,
    ),
  );
}

/// Oyuncunun onay durumunu kendisi okur; onaylıysa [VerifiedBadge], değilse
/// boş. Önbellekteyse ilk karede görünür (titreme yok).
class VerifiedBadgeFor extends StatefulWidget {
  const VerifiedBadgeFor({
    super.key,
    required this.playerId,
    this.size = 16,
    this.leading = 5,
  });

  final String playerId;
  final double size;

  /// Tik görünürse soluna bırakılan boşluk.
  final double leading;

  @override
  State<VerifiedBadgeFor> createState() => _VerifiedBadgeForState();
}

class _VerifiedBadgeForState extends State<VerifiedBadgeFor> {
  late bool _ok = IdentityService.cached(widget.playerId) ?? false;

  @override
  void initState() {
    super.initState();
    IdentityService.changes.addListener(_refresh);
    _refresh();
  }

  @override
  void didUpdateWidget(VerifiedBadgeFor old) {
    super.didUpdateWidget(old);
    if (old.playerId != widget.playerId) {
      _ok = IdentityService.cached(widget.playerId) ?? false;
      _refresh();
    }
  }

  @override
  void dispose() {
    IdentityService.changes.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (widget.playerId.isEmpty) return;
    try {
      final ok = await IdentityService.isVerified(widget.playerId);
      if (mounted && ok != _ok) setState(() => _ok = ok);
    } catch (_) {}
  }

  Future<void> _showIbrazInfo(BuildContext context) async {
    Map<String, dynamic>? info;
    try {
      info = await IdentityService.badgeInfo(widget.playerId);
    } catch (_) {}
    if (!context.mounted) return;
    final by = (info?['by'] ?? '').toString();
    final at = DateTime.tryParse((info?['verified_at'] ?? '').toString());
    final date = at == null
        ? ''
        : '${at.toLocal().day.toString().padLeft(2, '0')}.'
              '${at.toLocal().month.toString().padLeft(2, '0')}.'
              '${at.toLocal().year}';
    await showAdminInfoDialog(
      context: context,
      title: 'Kimlik İbraz Onaylı',
      message: [
        'Kimlik taratılmadı ibraz yoluyla onay alındı',
        if (by.isNotEmpty) 'Onaylayan: $by',
        if (date.isNotEmpty) date,
      ].join(' · '),
      icon: Icons.verified_rounded,
      iconColor: kIbrazOrange,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Mavi tik kimlik doğrulama pasifken de görünür (bir kez doğrulanmış).
    if (!_ok) return const SizedBox.shrink();
    final ibraz = IdentityService.isIbraz(widget.playerId);
    final badge = VerifiedBadge(size: widget.size, ibraz: ibraz);
    return Padding(
      padding: EdgeInsets.only(left: widget.leading),
      child: ibraz
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showIbrazInfo(context),
              child: badge,
            )
          : badge,
    );
  }
}
