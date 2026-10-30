import 'package:flutter/material.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/widgets/app_name_band.dart';
import '../../../core/services/active_tournament.dart';
import '../../tournament/models/league_extras.dart';
import '../news_talk.dart';

const _card = Color(0xFF1E293B);
const _tile = Color(0xFF0D1729);
const _muted = Color(0xFF94A3B8);
const _soft = Color(0xFFE2E8F0);
const _amber = Color(0xFFFBBF24);
const _red = Color(0xFFF87171);
const _green = Color(0xFF22C55E);

Color _accent() =>
    ActiveTournament.theme.value?.secondary ?? const Color(0xFF10B981);

TextStyle _cond(double size, {Color color = Colors.white}) => TextStyle(
  fontFamily: 'BarlowCondensed',
  fontSize: size,
  height: 1.05,
  color: color,
  fontWeight: FontWeight.w800,
);

/// Tepki ve yorumlar bu kullanıcıya açık mı (kapalıyken yalnız admin).
bool newsTalkOn(BuildContext context) =>
    AppSession.of(context).value.isAdmin ||
    AppSettings.newsCommentsEnabled.value;

String _ago(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 1) return 'şimdi';
  if (d.inMinutes < 60) return '${d.inMinutes} dk';
  if (d.inHours < 24) return '${d.inHours} sa';
  return '${d.inDays} gün';
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Haber kartlarında tepki ve yorum sayıları; hiç yoksa görünmez.
class NewsTalkSummary extends StatelessWidget {
  const NewsTalkSummary({super.key, required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    if (!newsTalkOn(context)) return const SizedBox.shrink();
    final labels = {for (final r in newsReactionsFor(item)) r.slot: r.emoji};
    final counts =
        item.reactions.entries
            .where((e) => e.value > 0 && labels.containsKey(e.key))
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (counts.isEmpty && item.commentCount == 0) {
      return const SizedBox.shrink();
    }
    Widget chip(String emoji, int n, {bool outline = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: outline ? null : _tile,
        borderRadius: BorderRadius.circular(9),
        border: outline
            ? Border.all(color: Colors.white.withValues(alpha: 0.12))
            : null,
      ),
      child: Text(
        '$emoji $n',
        style: const TextStyle(
          color: _soft,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(
        spacing: 5,
        runSpacing: 4,
        children: [
          for (final e in counts) chip(labels[e.key]!, e.value),
          if (item.commentCount > 0)
            chip('💬', item.commentCount, outline: true),
        ],
      ),
    );
  }
}

/// Haber detayında tribün (tepkiler) ve kapalı duran yorumlar.
class NewsTalkSection extends StatefulWidget {
  const NewsTalkSection({super.key, required this.item});

  final NewsItem item;

  @override
  State<NewsTalkSection> createState() => _NewsTalkSectionState();
}

class _NewsTalkSectionState extends State<NewsTalkSection> {
  late Map<int, int> _counts = Map.of(widget.item.reactions);
  late int _commentCount = widget.item.commentCount;
  int? _mine;
  bool _reacting = false;

  bool _open = false;
  List<NewsComment>? _comments;
  bool _loadFailed = false;

  String? get _uid => AppSession.of(context).value.user?.id;

  @override
  void initState() {
    super.initState();
    NewsTalkService.myReaction(widget.item.id).then((v) {
      if (mounted) setState(() => _mine = v);
    }, onError: (_) {});
  }

  Future<void> _react(int slot) async {
    if (_uid == null) {
      _snack(context, 'Tepki vermek için giriş yap.');
      return;
    }
    if (_reacting) return;
    final before = (_mine, Map.of(_counts));
    final next = _mine == slot ? null : slot;
    setState(() {
      _reacting = true;
      if (_mine != null) _counts[_mine!] = (_counts[_mine!] ?? 1) - 1;
      if (next != null) _counts[next] = (_counts[next] ?? 0) + 1;
      _mine = next;
    });
    try {
      await NewsTalkService.react(widget.item.id, slot);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mine = before.$1;
        _counts = before.$2;
      });
      _snack(context, NewsTalkService.message(e));
    } finally {
      if (mounted) setState(() => _reacting = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final list = await NewsTalkService.comments(widget.item.id);
      if (!mounted) return;
      setState(() {
        _comments = list;
        _commentCount = list.where((c) => !c.isPending).length;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open && _comments == null) _load();
  }

  Future<void> _write() async {
    if (_uid == null) {
      _snack(context, 'Yorum yazmak için giriş yap.');
      return;
    }
    final status = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ComposeSheet(newsId: widget.item.id),
    );
    if (status == null || !mounted) return;
    _snack(
      context,
      status == 'pending'
          ? 'Yorumun onaya gönderildi; onaylanınca herkes görecek.'
          : 'Yorumun yayınlandı.',
    );
    setState(() => _open = true);
    await _load();
  }

  Future<void> _act(Future<void> Function() run, String done) async {
    try {
      await run();
      if (!mounted) return;
      _snack(context, done);
      await _load();
    } catch (e) {
      if (mounted) _snack(context, NewsTalkService.message(e));
    }
  }

  Future<bool> _confirm(String title, String body, String ok) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(body, style: const TextStyle(color: _soft)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ok, style: const TextStyle(color: _red)),
          ),
        ],
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.item;
    final reactions = newsReactionsFor(n);
    final total = _counts.values.fold<int>(0, (a, b) => a + b);
    final accent = _accent();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A2A46), Color(0xFF141F33)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'TRİBÜN',
                      style: _cond(17).copyWith(letterSpacing: 0.8),
                    ),
                    const Spacer(),
                    Text(
                      total == 0 ? 'İlk tepkiyi sen ver' : '$total tepki',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final r in reactions) ...[
                      if (r.slot > 1) const SizedBox(width: 6),
                      Expanded(
                        child: _ReactionBox(
                          emoji: r.emoji,
                          label: r.label,
                          count: _counts[r.slot] ?? 0,
                          selected: _mine == r.slot,
                          accent: accent,
                          onTap: () => _react(r.slot),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: _soft,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _commentCount == 0
                          ? 'YORUMLAR'
                          : 'YORUMLAR · $_commentCount',
                      style: _cond(16).copyWith(letterSpacing: 0.8),
                    ),
                    const Spacer(),
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: _muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open) ..._commentsBody(),
        ],
      ),
    );
  }

  List<Widget> _commentsBody() {
    final session = AppSession.of(context).value;
    final n = widget.item;
    final reviewer = session.canManageRegion(n.tournamentId, n.regionId);
    final list = _comments;
    return [
      const SizedBox(height: 8),
      Material(
        color: _tile,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _write,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 11, 8, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _uid == null ? 'Yorum yazmak için giriş yap' : 'Yorum yaz…',
                    style: const TextStyle(color: _muted, fontSize: 14),
                  ),
                ),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _accent(),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (list == null && !_loadFailed)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      else if (_loadFailed)
        TextButton(
          onPressed: _load,
          child: const Text('Yorumlar yüklenemedi · Yeniden dene'),
        )
      else if (list!.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'Henüz yorum yok. İlk yorumu sen yaz.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 13.5),
          ),
        )
      else
        for (final c in list)
          _CommentTile(
            comment: c,
            mine: c.userId == _uid,
            reviewer: reviewer,
            canReport: _uid != null && c.userId != _uid && !c.isPending,
            onDelete: () async {
              if (!await _confirm(
                'Yorumu sil',
                'Bu yorum silinsin mi?',
                'Sil',
              )) {
                return;
              }
              await _act(() => NewsTalkService.delete(c.id), 'Yorum silindi.');
            },
            onReport: () async {
              if (!await _confirm(
                'Şikâyet et',
                'Bu yorum kurallara uymuyor mu? 3 şikâyet alan yorum '
                    'incelenene dek gizlenir.',
                'Şikâyet et',
              )) {
                return;
              }
              await _act(
                () => NewsTalkService.report(c.id),
                'Şikâyetin alındı.',
              );
            },
            onReview: (action) => _act(
              () => NewsTalkService.review(c.id, action),
              switch (action) {
                'publish' => 'Yorum yayınlandı.',
                'ban' => 'Yorum reddedildi, kişinin yorum yazması kapatıldı.',
                _ => 'Yorum reddedildi.',
              },
            ),
          ),
    ];
  }
}

class _ReactionBox extends StatelessWidget {
  const _ReactionBox({
    required this.emoji,
    required this.label,
    required this.count,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final int count;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _tile,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: selected
            ? BorderSide(color: accent, width: 2)
            : BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          child: Column(
            children: [
              Text(
                '$count',
                style: _cond(
                  21,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 3),
              Text(
                '$emoji $label',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.mine,
    required this.reviewer,
    required this.canReport,
    required this.onDelete,
    required this.onReport,
    required this.onReview,
  });

  final NewsComment comment;
  final bool mine;
  final bool reviewer;
  final bool canReport;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final void Function(String action) onReview;

  @override
  Widget build(BuildContext context) {
    final c = comment;
    final pending = c.isPending;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: pending ? _amber.withValues(alpha: 0.07) : null,
        borderRadius: BorderRadius.circular(12),
        border: pending
            ? Border(left: BorderSide(color: _amber, width: 3))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommentAvatar(name: c.authorName),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CommentAuthorLine(comment: c),
                const SizedBox(height: 3),
                Text(
                  c.body,
                  style: const TextStyle(
                    color: _soft,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if (pending && mine && !reviewer)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '⏳ Onay bekliyor · yalnız sen görüyorsun',
                      style: TextStyle(
                        color: _amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (pending && reviewer) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '⏳ Onay bekliyor${c.flagReason == null ? '' : ' · ${c.flagReason}'}',
                      style: const TextStyle(
                        color: _amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  CommentReviewButtons(onReview: onReview),
                ],
                if (!pending && (mine || canReport || reviewer))
                  Row(
                    children: [
                      if (mine || reviewer)
                        _link('Sil', onDelete)
                      else if (canReport)
                        _link('Şikâyet et', onReport),
                    ],
                  ),
                if (pending && mine && !reviewer)
                  Row(children: [_link('Sil', onDelete)]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _link(String text, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: _muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// Ad soyadın baş harfleri, isme göre sabit renk.
class CommentAvatar extends StatelessWidget {
  const CommentAvatar({super.key, required this.name});

  final String name;

  static const _colors = [
    Color(0xFFB45309),
    Color(0xFF1D4ED8),
    Color(0xFF047857),
    Color(0xFF7C3AED),
    Color(0xFFBE123C),
    Color(0xFF0E7490),
    Color(0xFF4D7C0F),
  ];

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = [
      for (final p in parts.take(2))
        if (p.isNotEmpty) p.characters.first,
    ].join().toUpperCase();
    final color = _colors[name.hashCode.abs() % _colors.length];
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// "Ad Soyad  TAKIM  12 dk"
class CommentAuthorLine extends StatelessWidget {
  const CommentAuthorLine({super.key, required this.comment});

  final NewsComment comment;

  @override
  Widget build(BuildContext context) {
    final c = comment;
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          c.authorName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (c.authorTeam != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: _accent().withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              c.authorTeam!.toUpperCase(),
              style: TextStyle(
                color: _accent(),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        Text(
          _ago(c.createdAt),
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Sorumlunun kararı: Yayınla / Reddet / Yasakla.
class CommentReviewButtons extends StatelessWidget {
  const CommentReviewButtons({super.key, required this.onReview});

  final void Function(String action) onReview;

  @override
  Widget build(BuildContext context) {
    Widget btn(String text, String action, Color bg, Color fg) => Expanded(
      child: SizedBox(
        height: 34,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          onPressed: () => onReview(action),
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
        ),
      ),
    );
    return Row(
      children: [
        btn('Yayınla', 'publish', _green, const Color(0xFF052E16)),
        const SizedBox(width: 6),
        btn('Reddet', 'reject', _card, Colors.white),
        const SizedBox(width: 6),
        btn('Yasakla', 'ban', _red.withValues(alpha: 0.16), _red),
      ],
    );
  }
}

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet({required this.newsId});

  final String newsId;

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final status = await NewsTalkService.add(widget.newsId, body);
      if (mounted) Navigator.of(context).pop(status);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = NewsTalkService.message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('YORUM YAZ', style: _cond(18).copyWith(letterSpacing: 0.8)),
            const SizedBox(height: 4),
            const Text(
              'Adın ve soyadın yorumla birlikte görünür. Küfür ve hakaret '
              'içeren yorumlar yayınlanmaz.',
              style: TextStyle(color: _muted, fontSize: 12.5, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Yorumun…',
                hintStyle: const TextStyle(color: _muted),
                filled: true,
                fillColor: _tile,
                counterStyle: const TextStyle(color: _muted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: _red,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            SizedBox(
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: accent.computeLuminance() > 0.35
                      ? const Color(0xFF04241A)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _text.text.trim().isEmpty || _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'GÖNDER',
                        style: TextStyle(
                          fontFamily: 'BarlowCondensed',
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: 0.8,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Turnuvada onay bekleyen yorumlar (admin, kurucu başkan, bölge sorumlusu).
class NewsCommentReviewScreen extends StatefulWidget {
  const NewsCommentReviewScreen({super.key, required this.leagueId});

  final String leagueId;

  static Future<void> open(BuildContext context, String leagueId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'NewsCommentReviewScreen'),
          builder: (_) => NewsCommentReviewScreen(leagueId: leagueId),
        ),
      );

  @override
  State<NewsCommentReviewScreen> createState() =>
      _NewsCommentReviewScreenState();
}

class _NewsCommentReviewScreenState extends State<NewsCommentReviewScreen> {
  List<NewsComment>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await NewsTalkService.pending(widget.leagueId);
      if (mounted) setState(() => _items = list);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _review(NewsComment c, String action) async {
    try {
      await NewsTalkService.review(c.id, action);
      if (!mounted) return;
      setState(() => _items = [...?_items]..remove(c));
      _snack(
        context,
        action == 'publish' ? 'Yorum yayınlandı.' : 'Yorum reddedildi.',
      );
    } catch (e) {
      if (mounted) _snack(context, NewsTalkService.message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return BandBackPage(
      theme: ActiveTournament.theme.value,
      subtitle: 'Onay Bekleyen Yorumlar',
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: _failed
            ? const Center(
                child: Text(
                  'Yorumlar yüklenemedi.',
                  style: TextStyle(color: _muted),
                ),
              )
            : items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
            ? const Center(
                child: Text(
                  'Onay bekleyen yorum yok.',
                  style: TextStyle(color: _muted),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final c = items[i];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (c.flagReason != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _amber.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              c.flagReason!,
                              style: const TextStyle(
                                color: _amber,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CommentAvatar(name: c.authorName),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CommentAuthorLine(comment: c),
                                  const SizedBox(height: 3),
                                  Text(
                                    c.body,
                                    style: const TextStyle(
                                      color: _soft,
                                      fontSize: 14.5,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (c.newsTitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Haber: ${c.newsTitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        CommentReviewButtons(
                          onReview: (action) => _review(c, action),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
