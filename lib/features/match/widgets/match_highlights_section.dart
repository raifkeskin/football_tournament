import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../utils/minute_label.dart';

import '../../../core/widgets/match_event_icons.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/utils/team_name.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/youtube_player_page.dart';
import '../models/match.dart';
import '../services/match_highlight_service.dart';
import '../utils/season_match_settings.dart';
import '../../../core/services/app_session.dart';
import '../../../core/utils/realtime_signal.dart';
import '../../../core/utils/resilient_stream.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final min = h.minute != null
      ? '${minuteLabel(h.minute, h.addedMinute)} '
      : '';
  return '${min}Gol${team.isEmpty ? '' : ' · $team'}';
}

/// Medya > Gol Videoları: yetkililer için YZ gol kesitleri girişi, onaylı
/// gol kesitleri (herkes) ve altta [trailing] (ör. video linkleri).
class MatchHighlightsStrip extends StatefulWidget {
  const MatchHighlightsStrip({
    super.key,
    required this.match,
    required this.homeName,
    required this.awayName,
    required this.canReview,
    this.hasStream = false,
    this.trailing = const [],
  });

  /// Kesitlerin altında gösterilecek diğer videolar.
  final List<Widget> trailing;

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
  late Map<String, HighlightScorer> _scorers =
      MatchHighlightService.cachedScorers(widget.match.id) ?? const {};

  /// Sezonda gol dakikası tutulmuyorsa (halısaha) YZ tüm videoyu tarar
  /// (pahalı): analiz/inceleme yalnız admin'e görünür. Onaylı kesitler
  /// herkese görünmeye devam eder.
  late bool? _tracksMinutes = SeasonMatchSettings.cached(
    widget.match.seasonId,
  )?.tracksGoalMinutes;

  /// Yeni biten maçta kesitler (otomatik analiz) maç detayı açıkken gelir:
  /// `match:<id>` Broadcast konusundan dinlenir. Eski maçlarda kanal açılmaz.
  StreamSubscription<RowChange>? _live;
  Timer? _liveDebounce;

  bool get _awaitsClips {
    final m = widget.match;
    if (m.status != MatchStatus.finished &&
        m.status != MatchStatus.live &&
        m.status != MatchStatus.halftime) {
      return false;
    }
    final at = m.updatedAt ?? DateTime.tryParse((m.matchDate ?? '').trim());
    return at == null ||
        DateTime.now().difference(at.toLocal()) < const Duration(hours: 14);
  }

  void _listenLive() {
    if (!_awaitsClips) return;
    _live =
        resilientStream(
          () => realtimeRowChanges(
            Supabase.instance.client,
            table: 'match_highlights',
            column: 'match_id',
            value: widget.match.id,
          ),
        ).listen((_) {
          // Kesitler toplu eklenir: tek okuma, izleyicilere yayılarak.
          _liveDebounce?.cancel();
          _liveDebounce = Timer(
            Duration(milliseconds: 800 + DateTime.now().microsecond % 2500),
            _load,
          );
        }, onError: (_) {});
  }

  @override
  void initState() {
    super.initState();
    MatchHighlightService.changes.addListener(_onChanged);
    _load();
    _listenLive();
    if (_tracksMinutes == null) {
      SeasonMatchSettings.of(widget.match.seasonId).then((s) {
        if (mounted) setState(() => _tracksMinutes = s.tracksGoalMinutes);
      });
    }
  }

  @override
  void dispose() {
    MatchHighlightService.changes.removeListener(_onChanged);
    _liveDebounce?.cancel();
    _live?.cancel();
    super.dispose();
  }

  void _onChanged() {
    final c = MatchHighlightService.cached(widget.match.id);
    if (c != null && mounted) {
      setState(() => _items = c);
      _loadScorers();
    }
  }

  Future<void> _load() async {
    try {
      final list = await MatchHighlightService.fetch(widget.match.id);
      if (mounted) setState(() => _items = list);
      await _loadScorers();
    } catch (_) {
      // Kesitler yüklenemezse Medya sekmesi yine çalışır.
    }
  }

  Future<void> _loadScorers() async {
    final m = widget.match;
    try {
      final map = await MatchHighlightService.scorers(
        matchId: m.id,
        seasonId: m.seasonId,
        homeTeamId: m.homeTeamId,
        awayTeamId: m.awayTeamId,
        items: [
          for (final h in _items)
            if (h.isApproved) h,
        ],
      );
      if (mounted) setState(() => _scorers = map);
    } catch (_) {
      // Golü atan okunamazsa kart dakika + takımla görünür.
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
    final aiClips =
        SeasonMatchSettings.cached(widget.match.seasonId)?.aiClips ?? true;
    final showReview =
        canRun &&
        aiClips &&
        widget.hasStream &&
        widget.match.status == MatchStatus.finished;
    if (approved.isEmpty && !showReview && widget.trailing.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            'Henüz gol videosu yok.',
            style: TextStyle(color: Colors.white60),
          ),
        ),
      );
    }

    final main = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showReview) ...[
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
            const SizedBox(height: 10),
          ],
          for (final h in approved)
            GoalClipCard(
              title: _clipTitle(
                h,
                widget.match,
                widget.homeName,
                widget.awayName,
              ),
              scorer: _scorers[h.id],
              description: h.description,
              onPlay: () => openYoutubeClip(
                context,
                videoId: h.videoId,
                startSec: h.startSec,
                endSec: h.endSec,
                title: _clipTitle(
                  h,
                  widget.match,
                  widget.homeName,
                  widget.awayName,
                ),
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [main, ...widget.trailing],
    );
  }
}

/// Herkesin gördüğü gol kesiti kartı: dakika · Gol · takım, altında golü
/// atan (forma no + ad) ve açıklama; "İzle" kesiti oynatır.
class GoalClipCard extends StatelessWidget {
  const GoalClipCard({
    super.key,
    required this.title,
    required this.scorer,
    required this.description,
    required this.onPlay,
    this.highlighted = false,
    this.footer,
  });

  final String title;
  final HighlightScorer? scorer;
  final String? description;
  final VoidCallback onPlay;
  final bool highlighted;

  /// Yetkili ekranındaki ek düğmeler (düzenle, onayla…).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final desc = (description ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? kAdminAccent
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const BallIcon(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onPlay,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('İzle'),
              ),
            ],
          ),
          if (scorer != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (scorer!.jersey != null) ...[
                  Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${scorer!.jersey}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    scorer!.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              desc,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
          ?footer,
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
  Map<String, HighlightScorer> _scorers = const {};
  List<HighlightRosterPlayer>? _roster;
  bool _loading = true;
  String? _playingId;
  final Set<String> _busy = {};

  /// Kaydedilmemiş ±5 sn düzeltmeleri (kesit id → başlangıç, bitiş).
  /// "Kaydet" ile yayındaki kesite yazılır; önizleme taslak aralıkla oynar.
  final Map<String, (int, int)> _draft = {};

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
      _loadScorers();
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

  Future<void> _loadScorers() async {
    final m = widget.match;
    try {
      final map = await MatchHighlightService.scorers(
        matchId: m.id,
        seasonId: m.seasonId,
        homeTeamId: m.homeTeamId,
        awayTeamId: m.awayTeamId,
        items: _items,
      );
      if (mounted) setState(() => _scorers = map);
    } catch (_) {}
  }

  /// Golü atanı esameden (yoksa kadrodan) seçer; kesitin takımı biliniyorsa
  /// yalnız o takımın oyuncuları.
  Future<void> _pickScorer(MatchHighlight h) async {
    final m = widget.match;
    try {
      _roster ??= await MatchHighlightService.roster(
        matchId: m.id,
        seasonId: m.seasonId,
        teamIds: [m.homeTeamId, m.awayTeamId],
      );
    } catch (_) {
      _snack('Esame okunamadı; bağlantıyı kontrol edin.');
      return;
    }
    if (!mounted) return;
    final pool = [
      for (final p in _roster!)
        if (h.teamId == null || p.teamId == h.teamId) p,
    ];
    final picked = await showAdminOptionPicker<HighlightRosterPlayer>(
      context: context,
      title: 'Golü Atan',
      items: pool,
      selected: pool
          .where((p) => p.playerId == _scorers[h.id]?.playerId)
          .firstOrNull,
      labelBuilder: (p) => p.jersey == null ? p.name : '${p.jersey}  ${p.name}',
      emptyText: 'Esamede oyuncu yok.',
    );
    if (picked == null) return;
    await _update(h, playerId: picked.playerId);
  }

  Future<void> _editDescription(MatchHighlight h) async {
    final text = await showAdminTextInputDialog(
      context: context,
      title: 'Gol Açıklaması',
      icon: Icons.edit_note_rounded,
      label: 'AÇIKLAMA',
      fieldIcon: Icons.notes_rounded,
      initialValue: h.description ?? '',
      hint: 'Örn. Sağdan gelen ortaya kafa vuruşu',
    );
    if (text == null) return;
    await _update(h, description: text);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _play(MatchHighlight h) {
    final (startSec, endSec) = _draft[h.id] ?? (h.startSec, h.endSec);
    final player = _player;
    if (player == null) {
      final created = YoutubePlayerController.fromVideoId(
        videoId: h.videoId,
        autoPlay: true,
        startSeconds: startSec.toDouble(),
        endSeconds: endSec.toDouble(),
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
      startSeconds: startSec.toDouble(),
      endSeconds: endSec.toDouble(),
    );
  }

  /// Taslak aralığı değiştirir ve yeni aralığı hemen oynatır.
  void _nudge(MatchHighlight h, {int startBy = 0, int endBy = 0}) {
    final (a, b) = _draft[h.id] ?? (h.startSec, h.endSec);
    final next = (a + startBy, b + endBy);
    setState(() {
      if (next == (h.startSec, h.endSec)) {
        _draft.remove(h.id);
      } else {
        _draft[h.id] = next;
      }
    });
    _play(h);
  }

  Future<void> _saveDraft(MatchHighlight h) async {
    final d = _draft[h.id];
    if (d == null) return;
    await _update(h, startSec: d.$1, endSec: d.$2);
    if (mounted) setState(() => _draft.remove(h.id));
  }

  Future<void> _update(
    MatchHighlight h, {
    int? startSec,
    int? endSec,
    String? status,
    String? description,
    String? playerId,
  }) async {
    setState(() => _busy.add(h.id));
    try {
      await MatchHighlightService.update(
        h,
        startSec: startSec,
        endSec: endSec,
        status: status,
        description: description,
        playerId: playerId,
      );
      if (!mounted) return;
      setState(() {
        _items = MatchHighlightService.cached(widget.match.id) ?? _items;
      });
      if (playerId != null) _loadScorers();
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
    // Maç detayında hiç gol yoksa tüm video taranır (yalnız admin; dakika
    // ve takım YZ'den, golü atan spikerden/formadan eşleştirilir).
    final full = goals == 0 && total > 0;
    if (full) {
      if (!AppSession.of(context).value.isAdmin) {
        _snack(
          'Maç detayında gol yok; tüm video taramasını admin başlatabilir.',
        );
        return;
      }
      final ok = await showAdminConfirmDialog(
        context: context,
        title: 'Tüm video taranacak',
        message:
            'Maç detayında gol kaydı yok. YZ videonun tamamını tarar; '
            'dakika, takım ve (spiker söylüyorsa) golü atanı bulur. '
            'Tahmini maliyet 1,5 saatlik videoda ~0,18 \$.',
        confirmLabel: 'TARAMAYI BAŞLAT',
        destructive: false,
        icon: Icons.auto_awesome_rounded,
      );
      if (!ok || !mounted) return;
      final err = await MatchHighlightService.analyze(widget.match.id);
      if (!mounted) return;
      if (err != null) {
        _snack(err);
        return;
      }
      MatchHighlightService.watch(widget.match.id, label: _label);
      _snack(
        'Analiz arka planda başladı. Ekrandan çıkabilirsiniz; bitince '
        'bildirilecek.',
      );
      _refresh();
      return;
    }
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
            // Oynatıcı ilk "İzle"de açılır; öncesinde boş siyah alan yok.
            if (_player != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: YoutubePlayer(controller: _player!),
                ),
              ),
              const SizedBox(height: 16),
            ],
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
          'dakikaları taranır ve gol anları bulunur. Maç detayında gol '
          'yoksa tüm video taranır (yalnız admin).';
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
    if (job.needsReview) 'Kontrol önerilir',
    if ((job.missing ?? 0) > 0) '${job.missing} gol yayında bulunamadı',
    if (job.kickoffSec != null) 'Başlangıç ${_clock(job.kickoffSec!)}',
    if (job.secondHalfSec != null) '2. yarı ${_clock(job.secondHalfSec!)}',
    if (job.costUsd != null) 'Maliyet ${job.costUsd!.toStringAsFixed(3)} \$',
  ].join(' · ');

  /// Kartta düzenlenebilir satır: ikon + metin + sağda düğme.
  Widget _editRow({
    required IconData icon,
    required String text,
    required bool muted,
    required String action,
    required VoidCallback? onTap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: kAdminMuted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: muted ? kAdminMuted : Colors.white,
              fontSize: 13,
              fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: kAdminAccent,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 28),
          ),
          child: Text(
            action,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _card(MatchHighlight h) {
    final busy = _busy.contains(h.id);
    final (start, end) = _draft[h.id] ?? (h.startSec, h.endSec);
    final dirty = _draft.containsKey(h.id);
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
              const BallIcon(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    if (h.minute != null) minuteLabel(h.minute, h.addedMinute),
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
          const SizedBox(height: 8),
          _editRow(
            icon: Icons.person_rounded,
            text: _scorers[h.id] == null
                ? 'Golü atan seçilmedi'
                : [
                    if (_scorers[h.id]!.jersey != null)
                      '${_scorers[h.id]!.jersey}',
                    _scorers[h.id]!.name,
                  ].join('  '),
            muted: _scorers[h.id] == null,
            action: _scorers[h.id] == null ? 'Seç' : 'Değiştir',
            onTap: busy ? null : () => _pickScorer(h),
          ),
          const SizedBox(height: 6),
          _editRow(
            icon: Icons.notes_rounded,
            text: (h.description ?? '').trim().isEmpty
                ? 'Açıklama yok'
                : h.description!.trim(),
            muted: (h.description ?? '').trim().isEmpty,
            action: 'Düzenle',
            onTap: busy ? null : () => _editDescription(h),
          ),
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
                  '${_clock(start)} – ${_clock(end)}  '
                  '(${end - start} sn)${dirty ? ' · kaydedilmedi' : ''}',
                  style: TextStyle(
                    color: dirty ? kAdminAmber : kAdminMuted,
                    fontSize: 12,
                    fontWeight: dirty ? FontWeight.w700 : FontWeight.w400,
                  ),
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
              nudge('−5 sn', start >= 5 ? () => _nudge(h, startBy: -5) : null),
              nudge(
                '+5 sn',
                end - start > 6 ? () => _nudge(h, startBy: 5) : null,
              ),
              const SizedBox(width: 6),
              const Text(
                'Bitiş',
                style: TextStyle(color: kAdminMuted, fontSize: 12),
              ),
              nudge(
                '−5 sn',
                end - start > 6 ? () => _nudge(h, endBy: -5) : null,
              ),
              nudge('+5 sn', () => _nudge(h, endBy: 5)),
            ],
          ),
          if (dirty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () {
                            setState(() => _draft.remove(h.id));
                            _play(h);
                          },
                    child: const Text('Vazgeç'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : () => _saveDraft(h),
                    style: FilledButton.styleFrom(
                      backgroundColor: kAdminAccent,
                    ),
                    child: Text(
                      h.isApproved ? 'Kaydet ve güncelle' : 'Kaydet',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
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
