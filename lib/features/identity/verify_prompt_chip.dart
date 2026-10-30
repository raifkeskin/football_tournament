import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/services/app_session.dart';
import '../../core/services/app_settings.dart';
import 'identity_access.dart';
import 'identity_service.dart';
import 'identity_verify_screen.dart';

/// Ana sayfada selamın yanında "Profilini onayla" rozeti (yanıp sönen mavi
/// tik) ve altında ince "Kimliğini okut" yazısı. Yalnız telefonda, oyuncu
/// profili onaysızken görünür; onaylanınca kendiliğinden kaybolur.
/// Yeni özellik: admin her zaman, diğerleri `verify_prompt_home_enabled`
/// açılınca görür.
class VerifyPromptChip extends StatefulWidget {
  const VerifyPromptChip({super.key, required this.session});

  final AppSessionState session;

  static bool _platform() =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<VerifyPromptChip> createState() => _VerifyPromptChipState();
}

class _VerifyPromptChipState extends State<VerifyPromptChip>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool _allowed() {
    final s = widget.session;
    if (!VerifyPromptChip._platform()) return false;
    if ((s.playerId ?? '').trim().isEmpty) return false;
    if (!IdentityAccess.visible(s)) return false;
    return s.isAdmin || AppSettings.verifyPromptHomeEnabled.value;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppSettings.verifyPromptHomeEnabled,
        IdentityAccess.changes,
        IdentityService.changes,
      ]),
      builder: (context, _) {
        if (!_allowed()) return const SizedBox.shrink();
        final playerId = widget.session.playerId!.trim();
        return FutureBuilder<bool>(
          future: IdentityService.isVerified(playerId),
          initialData: IdentityService.cached(playerId),
          // Durum bilinmeden gösterilmez (onaylıya bir an görünmesin).
          builder: (context, snap) =>
              snap.data == false ? _chip(context) : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _chip(BuildContext context) {
    const blue = Color(0xFF3B82F6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: blue.withValues(alpha: 0.14),
          shape: StadiumBorder(
            side: BorderSide(
              color: const Color(0xFF60A5FA).withValues(alpha: 0.6),
            ),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => IdentityVerifyScreen.open(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) {
                      final t = _pulse.value;
                      // 0 → 0.7: halka büyüyüp söner; sonra kısa bekleme.
                      final p = (t / 0.7).clamp(0.0, 1.0);
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: blue.withValues(alpha: 0.65 * (1 - p)),
                              spreadRadius: 8 * p,
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        color: blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'Profilini onayla',
                    style: TextStyle(
                      fontFamily: 'Barlow',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFDBEAFE),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Kimliğini telefona okut',
          style: TextStyle(
            fontFamily: 'Barlow',
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: Color(0xFF93C5FD),
          ),
        ),
      ],
    );
  }
}
