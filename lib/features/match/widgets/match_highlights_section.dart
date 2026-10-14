import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/utils/team_name.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/youtube_player_page.dart';
import '../models/match.dart';
import '../services/match_highlight_service.dart';
import '../utils/season_match_settings.dart';
import '../../../core/services/app_session.dart';

String _clock(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String _teamLabel(
  MatchHighlight h,
  MatchModel match,
  String homeName,
  String awayName,
) {
  if (h.teamId == match.homeTeamId) return shortTeamName(homeName);
  if (h.teamId == match.awayTeamId) return shortTeamName(awayName);
  return '';
}

String _clipTitle(
  MatchHighlight h,
  MatchModel match,
  String homeName,
  String awayName,
) {
  final team = _teamLabel(h, match, homeName, awayName);
  final min = h.minute != null ? "${h.minute}' " : '';
  return '${min}Gol${team.isEmpty ? '' : ' · $team'}';
}

/// Medya sekmesinin üstü: onaylı gol videoları (herkes) ve yetkililer için
/// YZ gol kesitleri girişi.
class MatchHighlightsStrip extends StatefulWidget {
  const MatchHighlightsStrip({
    super.key,
    required this.match,
    required this.homeName,
    required this.awayName,
    required this.canReview,
    this.hasStream = false,
  });

  final MatchModel match;
  final String homeName;
  final String awayName;

  /// Admin, kurucu başkan, bölge sorumlusu (RLS ayrıca owns_match ile süzer).
  final bool canReview;

  /// Maçın yayın linki var mı; yoksa "Gol Kesitleri" (YZ) kartı gizlenir.
  final bool hasStream;

  @override
  State<MatchHighlightsStrip> createState() => _MatchHighlightsStripState();
}

class _MatchHighlightsStripState extends State<MatchHighlightsStrip> {
  late List<MatchHighlight> _items =
      MatchHighlightService.cached(widget.match.id) ?? const [];

  /// Sezonda gol dakikası tutulmuyorsa (halısaha) YZ tüm videoyu tarar
  /// (pahalı): analiz/inceleme yalnız admin'e görünür. Onaylı kesitler
  /// herkese görünmeye devam eder.
  late bool? _tracksMinutes = SeasonMatchSettings.cached(
    widget.match.seasonId,
  )?.tracksGoalMinutes;

  @override
  void initState() {
    super.initState();
    MatchHighlightService.changes.addListener(_onChanged);
    _load();
    if (_tracksMinutes == null) {
      SeasonMatchSettings.of(widget.match.seasonId).then((s) {
        if (mounted) setState(() => _tracksMinutes = s.tracksGoalMinutes);
      });
    }
  }

  @override
  void dispose() {
    MatchHighlightService.changes.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final c = MatchHighlightService.cached(widget.match.id);
    if (c != null && mounted) setState(() => _items = c);
  }

  Future<void> _load() async {
    try {
      final list = await MatchHighlightService.fetch(widget.match.id);
      if (mounted) setState(() => _items = list);
    } catch (_) {
      // Kesitler yüklenemezse Medya sekmesi yine çalışır.
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = [
      for (final h in _items)
        if (h.isApproved && h.kind == 'goal') h,
    ];
    final pending = _items.where((h) => h.isPending).length;
    final canRun = _tracksMinutes == false
        ? AppSession.of(context).value.isAdmin
        : widget.canReview;
    final showReview =
        canRun &&
        widget.hasStream &&
        widget.match.status == MatchStatus.finished;
    if (approved.isEmpty && !showReview) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (approved.isNotEmpty) ...[
            const Row(
              children: [
                Icon(Icons.movie_outlined, size: 16, color: Colors.white54),
                SizedBox(width: 6),
                Text(
                  'Gol Videoları',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: approved.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final h = approved[i];
                  final title = _clipTitle(
                    h,
                    widget.match,
                    widget.homeName,
                    widget.awayName,
                  );
                  return ActionChip(
                    avatar: const Icon(
                      Icons.play_circle_fill_rounded,
                      size: 18,
                      color: Color(0xFF10B981),
                    ),
                    label: Text(title),
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    backgroundColor: const Color(0xFF1E293B),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    onPressed: () => openYoutubeClip(
                      context,
                      videoId: h.videoId,
                      startSec: h.startSec,
                      endSec: h.endSec,
                      title: title,
                    ),
                  );
                },
              ),
            ),
          ],
          if (showReview) ...[
            if (approved.isNotEmpty) const SizedBox(height: 8),
            Material(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MatchHighlightReviewPage(
                      match: widget.match,
                      homeName: widget.homeName,
                      awayName: widget.awayName,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: kAdminAmber,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Gol Kesitleri',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        pending > 0
                            ? '$pending onay bekliyor'
                            : 'Videodan golleri bul',
                        style: TextStyle(
                          color: pending > 0 ? kAdminAmber : kAdminMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Yetkilinin YZ kesitlerini izleyip düzeltip onayladığı ekran. Üstte tek
/// oynatıcı; karttaki "İzle" kesiti orada oynatır.
class MatchHighlightReviewPage extends StatefulWidget {
  const MatchHighlightReviewPage({
    super.key,
    required this.match,
    required this.homeName,
    required this.awayName,
  });

  final MatchModel match;
  final String homeName;
  final String awayName;

  @override
  State<MatchHighlightReviewPage> createState() =>
      _MatchHighlightReviewPageState();
}

class _MatchHighlightReviewPageState extends State<MatchHighlightReviewPage> {
  /// İlk "İzle"de oluşturulur (hazır olmayan oynatıcıya video yüklenmez).
  YoutubePlayerController? _player;

  late List<MatchHighlight> _items =
      MatchHighlightService.cached(widget.match.id) ?? const [];
  MatchHighlightJob? _job;
  bool _loading = true;
  String? _playingId;
  final Set<String> _busy = {};

  /// Açılışta veri alınamadıysa yeniden deneme (bağlantı kopukluğu).
  Timer? _retry;

  /// Kendi [_refresh]'imizin artırdığı [changes] yeniden okuma tetiklemesin.
  bool _selfBump = false;

  String get _label =>
      '${shortTeamName(widget.homeName)} – ${shortTeamName(widget.awayName)}';

  @override
  void initState() {
    super.initState();
    MatchHighlightService.changes.addListener(_onServiceChanged);
    MatchHighlightService.offline.addListener(_onOffline);
    _refresh();
  }

  void _onServiceChanged() {
    if (!_selfBump) _refresh();
  }

  void _onOffline() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _retry?.cancel();
    MatchHighlightService.changes.removeListener(_onServiceChanged);
    MatchHighlightService.offline.removeListener(_onOffline);
    resetPlayerOrientation();
    _player?.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        MatchHighlightService.fetch(widget.match.id),
        MatchHighlightService.job(widget.match.id),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<MatchHighlight>;
        _job = results[1] as MatchHighlightJob?;
        _loading = false;
      });
      _retry?.cancel();
      MatchHighlightService.offline.value = false;
      _selfBump = true;
      MatchHighlightService.changes.value++;
      _selfBump = false;
      // İş sürüyorsa takip serviste (ekran kapansa da sürer, bitince
      // bildirir); bitince [changes] ile bu ekran da yenilenir.
      if (_job?.isRunning ?? false) {
        MatchHighlightService.watch(widget.match.id, label: _label);
      }
    } catch (_) {
      // Bağlantı koptu: ham hata yerine "yeniden deneniyor", sonra tekrar.
      if (!mounted) return;
      MatchHighlightService.offline.value = true;
      setState(() => _loading = false);
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 8), _refresh);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _play(MatchHighlight h) {
    final player = _player;
    if (player == null) {
      final created = YoutubePlayerController.fromVideoId(
        videoId: h.videoId,
        autoPlay: true,
        startSeconds: h.startSec.toDouble(),
        endSeconds: h.endSec.toDouble(),
        params: const YoutubePlayerParams(
          // Android'de YouTube'un kendi tam ekranı WebView'da boş ekran
          // bırakıyor; telefonda tam ekran YoutubePlayerFrame düğmesiyle.
          showFullscreenButton: kIsWeb,
          strictRelatedVideos: true,
          origin: youtubePlayerOrigin,
        ),
      );
      landscapeOnFullscreen(created);
      setState(() {
        _player = created;
        _playingId = h.id;
      });
      return;
    }
    setState(() => _playingId = h.id);
    player.loadVideoById(
      videoId: h.videoId,
      startSeconds: h.startSec.toDouble(),
      endSeconds: h.endSec.toDouble(),
    );
  }

  Future<void> _update(
    MatchHighlight h, {
    int? startSec,
    int? endSec,
    String? status,
  }) async {
    setState(() => _busy.add(h.id));
    try {
      await MatchHighlightService.update(
        h,
        startSec: startSec,
        endSec: endSec,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        _items = MatchHighlightService.cached(widget.match.id) ?? _items;
      });
      // Süre değiştiyse yeni aralık hemen izlensin.
      if ((startSec != null || endSec != null) && status == null) {
        final updated = _items.where((x) => x.id == h.id).firstOrNull;
        if (updated != null) _play(updated);
      }
    } catch (e) {
      _snack('Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(h.id));
    }
  }

  Future<void> _startAnalysis() async {
    // Gol kayıtları skorla eşit değilse tarama yapılmaz (boşa maliyet).
    final m = widget.match;
    final total = m.homeScore + m.awayScore;
    final int goals;
    try {
      goals = await MatchHighlightService.goalCount(m.id);
    } catch (_) {
      _snack('Bağlantı yok; biraz sonra tekrar deneyin.');
      return;
    }
    if (!mounted) return;
    if (total == 0 || goals != total) {
      await showAdminConfirmDialog(
        context: context,
        title: total == 0 ? 'Maçta gol yok' : 'Gol kayıtları eksik',
        message: total == 0
            ? 'Skor ${m.homeScore}-${m.awayScore}; taranacak gol yok.'
            : 'Skor ${m.homeScore}-${m.awayScore} ($total gol) ama maç '
                  'detayında $goals gol kaydı var. Maç detayındaki gol '
                  'girişlerini skorla eşitledikten sonra tekrar deneyin.',
        confirmLabel: 'TAMAM',
        destructive: false,
        icon: Icons.info_outline_rounded,
      );
      return;
    }
    if (!mounted) return;
    final offsets = await showAdminPopup<({int? kickoff, int? second})>(
      context: context,
      builder: (_) => const _AnalyzeDialog(),
    );
    if (offsets == null || !mounted) return;
    final err = await MatchHighlightService.analyze(
      widget.match.id,
      kickoffSec: offsets.kickoff,
      secondHalfSec: offsets.second,
    );
    if (!mounted) return;
    if (err != null) {
      _snack(err);
      return;
    }
    // İş sunucuda sürer; takip serviste. Ekrandan çıkılabilir.
    MatchHighlightService.watch(widget.match.id, label: _label);
    _snack(
      'Analiz arka planda başladı. Ekrandan çıkabilirsiniz; bitince '
      'bildirilecek.',
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _items.where((h) => h.isPending).toList();
    final approved = _items.where((h) => h.isApproved).toList();
    final running = _job?.isRunning ?? false;

    return AdminPageScaffold(
      title: 'Gol Kesitleri',
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _player == null
                    ? Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        child: const Text(
                          'Bir kesitte "İzle"ye dokunun.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : YoutubePlayer(controller: _player!),
              ),
            ),
            const SizedBox(height: 16),
            _statusCard(running),
            const SizedBox(height: 18),
            if (_loading && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (pending.isNotEmpty)
                AdminFormSection(
                  title: 'Onay bekleyen (${pending.length})',
                  child: Column(children: [for (final h in pending) _card(h)]),
                ),
              if (approved.isNotEmpty)
                AdminFormSection(
                  title: 'Yayında (${approved.length})',
                  child: Column(children: [for (final h in approved) _card(h)]),
                ),
              if (pending.isEmpty && approved.isEmpty && !running)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Henüz kesit yok. "Golleri Bul" ile videoyu taratın.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kAdminMuted),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusCard(bool running) {
    final job = _job;
    String text;
    Color color = kAdminMuted;
    if (running) {
      text = job?.mode == 'full'
          ? 'Tüm video taranıyor… (maç detayında gol yok)'
          : 'Gol dakikalarının çevresi taranıyor…';
      color = kAdminAmber;
    } else if (job?.status == 'error') {
      text = 'Son analiz başarısız: ${job?.error ?? ''}';
      color = kAdminDanger;
    } else if (job?.status == 'done') {
      text = 'Son analizde ${job?.found ?? 0} gol bulundu.';
    } else {
      text =
          'Maçın YouTube yayınında, maç detayına girilen gollerin '
          'dakikaları taranır ve gol anları bulunur. Gol kayıtları skorla '
          'eşit olmalıdır.';
    }
    return AdminFieldGroup(
      children: [
        AdminFieldRow(
          icon: Icons.auto_awesome_rounded,
          label: 'GOL ANALİZİ',
          trailing: running
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : FilledButton(
                  onPressed: _startAnalysis,
                  style: FilledButton.styleFrom(
                    backgroundColor: kAdminAccent,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    job == null ? 'Golleri Bul' : 'Yeniden Tara',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, style: TextStyle(color: color, fontSize: 13)),
              if (MatchHighlightService.offline.value) ...[
                const SizedBox(height: 4),
                const Text(
                  'Bağlantı koptu, yeniden deneniyor…',
                  style: TextStyle(color: kAdminDanger, fontSize: 11.5),
                ),
              ] else if (running) ...[
                const SizedBox(height: 4),
                const Text(
                  'Arka planda sürüyor; ekrandan çıkabilirsiniz.',
                  style: TextStyle(color: kAdminMuted, fontSize: 11.5),
                ),
              ],
              if (job != null && _jobDetails(job).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _jobDetails(job),
                  style: const TextStyle(color: kAdminMuted, fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Maliyet ve videoda bulunan/girilen başlangıç anları.
  String _jobDetails(MatchHighlightJob job) => [
    if (job.kickoffSec != null) 'Başlangıç ${_clock(job.kickoffSec!)}',
    if (job.secondHalfSec != null) '2. yarı ${_clock(job.secondHalfSec!)}',
    if (job.costUsd != null) 'Maliyet ${job.costUsd!.toStringAsFixed(3)} \$',
  ].join(' · ');

  Widget _card(MatchHighlight h) {
    final busy = _busy.contains(h.id);
    final team = _teamLabel(h, widget.match, widget.homeName, widget.awayName);
    final conf = switch (h.confidence) {
      'high' => ('Yüksek', kAdminAccent),
      'medium' => ('Orta', kAdminAmber),
      'low' => ('Düşük', kAdminDanger),
      _ => null,
    };
    final playing = _playingId == h.id;

    Widget nudge(String label, VoidCallback? onTap) => SizedBox(
      height: 30,
      child: OutlinedButton(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 30),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: playing ? kAdminAccent : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_soccer, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    if (h.minute != null) "${h.minute}'",
                    'Gol',
                    if (team.isNotEmpty) team,
                  ].join(' · '),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (conf != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: conf.$2.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    conf.$1,
                    style: TextStyle(
                      color: conf.$2,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          if (h.description != null) ...[
            const SizedBox(height: 6),
            Text(
              h.description!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
          if (h.matchEventId == null) ...[
            const SizedBox(height: 4),
            const Text(
              'Maç detayındaki bir golle eşleşmedi.',
              style: TextStyle(color: kAdminMuted, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _play(h),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('İzle'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_clock(h.startSec)} – ${_clock(h.endSec)}  '
                  '(${h.endSec - h.startSec} sn)',
                  style: const TextStyle(color: kAdminMuted, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Başlangıç',
                style: TextStyle(color: kAdminMuted, fontSize: 12),
              ),
              nudge(
                '−5 sn',
                h.startSec >= 5
                    ? () => _update(h, startSec: h.startSec - 5)
                    : null,
              ),
              nudge(
                '+5 sn',
                h.endSec - h.startSec > 6
                    ? () => _update(h, startSec: h.startSec + 5)
                    : null,
              ),
              const SizedBox(width: 6),
              const Text(
                'Bitiş',
                style: TextStyle(color: kAdminMuted, fontSize: 12),
              ),
              nudge(
                '−5 sn',
                h.endSec - h.startSec > 6
                    ? () => _update(h, endSec: h.endSec - 5)
                    : null,
              ),
              nudge('+5 sn', () => _update(h, endSec: h.endSec + 5)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _update(h, status: 'rejected'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kAdminDanger,
                    side: const BorderSide(color: kAdminDanger),
                  ),
                  child: Text(h.isApproved ? 'Yayından Kaldır' : 'Sil'),
                ),
              ),
              if (h.isPending) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: busy
                        ? null
                        : () => _update(h, status: 'approved'),
                    style: FilledButton.styleFrom(
                      backgroundColor: kAdminAccent,
                    ),
                    child: const Text(
                      'Onayla',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Analizden önce isteğe bağlı: maçın ve 2. yarının videoda başladığı an.
/// Verilirse taranan aralık daralır (daha ucuz, daha isabetli).
class _AnalyzeDialog extends StatefulWidget {
  const _AnalyzeDialog();

  @override
  State<_AnalyzeDialog> createState() => _AnalyzeDialogState();
}

class _AnalyzeDialogState extends State<_AnalyzeDialog> {
  int? _kickoff;
  int? _second;

  /// Videodaki an: saat / dk / sn çarkı (YouTube süresiyle aynı birimler).
  Future<int?> _pick(String title, int? current) {
    var picked = Duration(seconds: current ?? 0);
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "YouTube'daki süreyle aynı: saat · dakika · saniye",
              style: TextStyle(color: kAdminMuted, fontSize: 12),
            ),
            CupertinoTheme(
              data: const CupertinoThemeData(brightness: Brightness.dark),
              child: SizedBox(
                height: 200,
                child: CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.hms,
                  initialTimerDuration: picked,
                  onTimerDurationChanged: (d) => picked = d,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, picked.inSeconds),
                  style: FilledButton.styleFrom(backgroundColor: kAdminAccent),
                  child: const Text(
                    'TAMAM',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    Navigator.pop(context, (kickoff: _kickoff, second: _second));
  }

  Widget _timeRow(
    IconData icon,
    String label,
    int? value,
    ValueChanged<int?> onChanged,
  ) {
    return AdminFieldRow(
      icon: icon,
      label: label,
      onTap: () async {
        final v = await _pick(label, value);
        if (v != null && mounted) onChanged(v);
      },
      trailing: value == null
          ? const Icon(Icons.chevron_right_rounded, color: Colors.white54)
          : IconButton(
              tooltip: 'Temizle',
              visualDensity: VisualDensity.compact,
              onPressed: () => onChanged(null),
              icon: const Icon(Icons.close_rounded, color: Colors.white54),
            ),
      child: Text(
        value == null ? 'Seçin (boş olabilir)' : _clock(value),
        style: TextStyle(
          color: value == null ? Colors.white38 : Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminDialogCloseOverlay(
      onClose: () => Navigator.pop(context),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AdminDialogHeader(
              icon: Icons.auto_awesome_rounded,
              title: 'Golleri Bul',
              subtitle: 'Maçın YouTube yayınını tarar',
            ),
            const SizedBox(height: 16),
            AdminFormSection(
              title: 'Videoda başlangıç (isteğe bağlı)',
              child: AdminFieldGroup(
                children: [
                  _timeRow(
                    Icons.play_arrow_rounded,
                    'MAÇIN BAŞLADIĞI AN',
                    _kickoff,
                    (v) => setState(() => _kickoff = v),
                  ),
                  _timeRow(
                    Icons.timelapse_rounded,
                    '2. YARININ BAŞLADIĞI AN',
                    _second,
                    (v) => setState(() => _second = v),
                  ),
                ],
              ),
            ),
            const Text(
              'Girilirse her golün yalnızca ±2 dk çevresi taranır (en '
              'ucuzu). Boş bırakılırsa başlangıçlar yayından bulunur '
              '(birkaç sent ek maliyet).',
              style: TextStyle(color: kAdminMuted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: kAdminAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'ANALİZİ BAŞLAT',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
