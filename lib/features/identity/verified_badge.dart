import 'package:flutter/material.dart';

import 'identity_service.dart';

/// Onaylı profil rengi (mavi tik).
const kVerifiedBlue = Color(0xFF38BDF8);

/// Kimliği çipten doğrulanmış oyuncunun yanında görünen mavi tik.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Onaylı profil: kimliği çipten doğrulandı',
    child: Icon(Icons.verified_rounded, color: kVerifiedBlue, size: size),
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

  @override
  Widget build(BuildContext context) {
    if (!_ok) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(left: widget.leading),
      child: VerifiedBadge(size: widget.size),
    );
  }
}
