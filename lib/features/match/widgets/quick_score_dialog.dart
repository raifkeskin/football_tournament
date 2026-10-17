import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_form.dart';
import '../models/match.dart';

/// Hızlı skor girişi: skoru yazıp maçı "Bitti" yapar (fikstür kartı ve maç
/// detayı ortak kullanır).
///
/// Skor girilmemiş maçta kutular boş açılır (silinecek 0-0 yok); ev sahibi
/// kutusu odaklı gelir, klavye doğrudan rakam klavyesidir. Skor varsa
/// kutuya dokununca tamamı seçilir, yazılan rakam üstüne yazılır. Boş
/// bırakılan kutu 0 sayılır.
Future<void> showQuickScoreDialog(
  BuildContext context, {
  required MatchModel match,
  required String homeName,
  required String awayName,
  VoidCallback? onSaved,
}) async {
  const accent = Color(0xFF10B981);
  final matchService = ServiceLocator.matchService;
  final hasScore =
      match.status == MatchStatus.finished ||
      match.homeScore != 0 ||
      match.awayScore != 0;
  final homeScoreCtrl = TextEditingController(
    text: hasScore ? match.homeScore.toString() : '',
  );
  final awayScoreCtrl = TextEditingController(
    text: hasScore ? match.awayScore.toString() : '',
  );
  final homeFocus = FocusNode();
  final awayFocus = FocusNode();
  // Eleme maçı berabere girilirse penaltı skoru da istenir.
  final homePensCtrl = TextEditingController(
    text: match.homePens?.toString() ?? '',
  );
  final awayPensCtrl = TextEditingController(
    text: match.awayPens?.toString() ?? '',
  );
  var saving = false;

  void selectAllOnFocus(FocusNode node, TextEditingController ctrl) {
    node.addListener(() {
      if (node.hasFocus) {
        ctrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: ctrl.text.length,
        );
      }
    });
  }

  selectAllOnFocus(homeFocus, homeScoreCtrl);
  selectAllOnFocus(awayFocus, awayScoreCtrl);

  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setDialogState) {
        final homeScore = int.tryParse(homeScoreCtrl.text) ?? 0;
        final awayScore = int.tryParse(awayScoreCtrl.text) ?? 0;
        final needsPens = match.isKnockout && homeScore == awayScore;

        Future<void> save() async {
          if (saving) return;
          final hp = int.tryParse(homePensCtrl.text);
          final ap = int.tryParse(awayPensCtrl.text);
          if (needsPens && (hp == null || ap == null || hp == ap)) {
            ScaffoldMessenger.of(c).showSnackBar(
              const SnackBar(
                content: Text(
                  'Eleme maçı berabere bitemez: penaltı skorunu girin.',
                ),
                backgroundColor: Colors.redAccent,
              ),
            );
            return;
          }
          setDialogState(() => saving = true);
          try {
            await matchService.completeMatchWithScoreAndDefaultEvents(
              matchId: match.id,
              homeScore: homeScore,
              awayScore: awayScore,
            );
            if (match.isKnockout) {
              await matchService.setPenaltyScore(
                matchId: match.id,
                home: needsPens ? hp : null,
                away: needsPens ? ap : null,
              );
            }
            if (!c.mounted) return;
            Navigator.pop(c);
            onSaved?.call();
          } catch (e) {
            if (!c.mounted) return;
            setDialogState(() => saving = false);
            ScaffoldMessenger.of(c).showSnackBar(
              SnackBar(
                content: Text('Hata: $e'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }

        Widget scoreBox(
          String teamName,
          TextEditingController ctrl,
          FocusNode focus, {
          required bool first,
        }) {
          return Expanded(
            child: Column(
              children: [
                Text(
                  teamName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  focusNode: focus,
                  autofocus: first,
                  keyboardType: TextInputType.number,
                  textInputAction: first
                      ? TextInputAction.next
                      : TextInputAction.done,
                  onSubmitted: (_) => first ? awayFocus.requestFocus() : save(),
                  // Eleme maçında beraberlik penaltı alanlarını açar.
                  onChanged: match.isKnockout
                      ? (_) => setDialogState(() {})
                      : null,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.4),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: accent, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: AdminDialogCloseOverlay(
            onClose: saving ? null : () => Navigator.pop(c),
            child: Container(
              padding: const EdgeInsets.all(24),
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.scoreboard_outlined,
                          color: accent,
                          size: 22,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Hızlı Skor Girişi',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white24, height: 1),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        scoreBox(
                          homeName.isEmpty ? 'Ev Sahibi' : homeName,
                          homeScoreCtrl,
                          homeFocus,
                          first: true,
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(12, 0, 12, 18),
                          child: Text(
                            '-',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        scoreBox(
                          awayName.isEmpty ? 'Deplasman' : awayName,
                          awayScoreCtrl,
                          awayFocus,
                          first: false,
                        ),
                      ],
                    ),
                    if (needsPens) ...[
                      const SizedBox(height: 16),
                      _PensRow(home: homePensCtrl, away: awayPensCtrl),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Kaydedildiğinde maç "Bitti" olarak işaretlenir.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          disabledBackgroundColor: accent.withValues(
                            alpha: 0.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: saving ? null : save,
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'KAYDET',
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
        );
      },
    ),
  );

  // Dialog kapanış animasyonu bitene kadar TextField'lar controller'ı
  // kullanmaya devam eder; hemen dispose etmek hata verir.
  Future<void>.delayed(const Duration(milliseconds: 600), () {
    homeScoreCtrl.dispose();
    awayScoreCtrl.dispose();
    homeFocus.dispose();
    awayFocus.dispose();
    homePensCtrl.dispose();
    awayPensCtrl.dispose();
  });
}

/// Eleme maçında berabere skorun altında: "Penaltılar" ve iki küçük kutu.
class _PensRow extends StatelessWidget {
  const _PensRow({required this.home, required this.away});

  final TextEditingController home;
  final TextEditingController away;

  static const _gold = Color(0xFFFBBF24);

  Widget _box(TextEditingController ctrl) => SizedBox(
    width: 64,
    child: TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(2),
      ],
      style: const TextStyle(
        color: _gold,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: '0',
        hintStyle: TextStyle(color: _gold.withValues(alpha: 0.3)),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _gold.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _gold, width: 2),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'PENALTILAR',
          style: TextStyle(
            color: _gold,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _box(home),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '-',
                style: TextStyle(color: Colors.white70, fontSize: 20),
              ),
            ),
            _box(away),
          ],
        ),
      ],
    );
  }
}
