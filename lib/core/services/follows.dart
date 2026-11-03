import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../push/notification_prefs.dart';
import '../push/push_prompt.dart';
import 'app_session.dart';
import 'app_settings.dart';

enum FollowKind { league, team, player }

/// Takip Listem: yıldızla takip edilen turnuvalar (followed_leagues), takımlar
/// ve futbolcular (user_follows; eski tek takım followed_teams da okunur).
/// Misafire cihaza bağlı isimsiz oturum açılır (bildirim gidebilsin).
class Follows {
  Follows._();

  static final leagues = ValueNotifier<Set<String>>(const {});
  static final teams = ValueNotifier<Set<String>>(const {});
  static final players = ValueNotifier<Set<String>>(const {});

  static SupabaseClient get _sb => Supabase.instance.client;
  static String? _loadedFor;

  /// Yeni özellik: admin her zaman, diğerleri ayar açıksa.
  static bool visible(BuildContext context) {
    if (AppSettings.followListEnabled.value) return true;
    try {
      return AppSession.of(context).value.isAdmin;
    } catch (_) {
      return false;
    }
  }

  static ValueNotifier<Set<String>> of(FollowKind k) => switch (k) {
    FollowKind.league => leagues,
    FollowKind.team => teams,
    FollowKind.player => players,
  };

  /// Oturumun takipleri (oturum başına bir kez; [force] ile yeniden).
  static Future<void> load({bool force = false}) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      _loadedFor = null;
      leagues.value = teams.value = players.value = const {};
      return;
    }
    if (!force && _loadedFor == uid) return;
    _loadedFor = uid;
    try {
      final res = await Future.wait([
        _sb.from('user_follows').select('kind, target_id').eq('user_id', uid),
        _sb.from('followed_teams').select('team_id').eq('user_id', uid),
        _sb.from('followed_leagues').select('league_id').eq('user_id', uid),
      ]);
      teams.value = {
        for (final r in res[0])
          if (r['kind'] == 'team') r['target_id'].toString(),
        for (final r in res[1]) r['team_id'].toString(),
      };
      players.value = {
        for (final r in res[0])
          if (r['kind'] == 'player') r['target_id'].toString(),
      };
      leagues.value = {for (final r in res[2]) r['league_id'].toString()};
    } catch (_) {
      _loadedFor = null;
    }
  }

  static bool isFollowing(FollowKind k, String id) => of(k).value.contains(id);

  /// Takibi açar/kapatır; yeni durumu döner (hata: eski durum).
  static Future<bool> set(
    FollowKind k,
    String id, {
    required bool follow,
    String? leagueId,
  }) async {
    final n = of(k);
    final before = n.value;
    n.value = follow ? {...before, id} : ({...before}..remove(id));
    try {
      final uid = await NotificationPrefsService.ensureUser();
      if (uid == null) throw Exception('Oturum açılamadı.');
      _loadedFor ??= uid;
      if (k == FollowKind.league) {
        await NotificationPrefsService.setFollowedLeague(id, follow);
      } else {
        final kind = k == FollowKind.team ? 'team' : 'player';
        if (follow) {
          await _sb.from('user_follows').upsert({
            'user_id': uid,
            'kind': kind,
            'target_id': id,
            'league_id': ?leagueId,
          }, onConflict: 'user_id,kind,target_id');
        } else {
          await _sb
              .from('user_follows')
              .delete()
              .eq('user_id', uid)
              .eq('kind', kind)
              .eq('target_id', id);
          // Ana sayfadaki eski "Takımımı takip et" kaydı da bırakılır.
          if (k == FollowKind.team) {
            await _sb
                .from('followed_teams')
                .delete()
                .eq('user_id', uid)
                .eq('team_id', id);
          }
        }
      }
      return follow;
    } catch (_) {
      n.value = before;
      return !follow;
    }
  }
}

/// Sarı yıldız: dolu = takipte. [label] varsa hap düğme ("Takip et" /
/// "Takiptesin"), yoksa yalnız ikon. Özellik kapalıysa hiçbir şey çizmez.
class FollowStar extends StatefulWidget {
  const FollowStar({
    super.key,
    required this.kind,
    required this.id,
    this.leagueId,
    this.label = false,
    this.size = 22,
    this.idleColor = const Color(0xFF94A3B8),
    this.dense = false,
  });

  final FollowKind kind;
  final String id;
  final String? leagueId;
  final bool label;
  final double size;
  final Color idleColor;

  /// Sıkışık başlıklarda 34 px dokunma alanı (ör. takım kartı).
  final bool dense;

  @override
  State<FollowStar> createState() => _FollowStarState();
}

class _FollowStarState extends State<FollowStar> {
  static const _gold = Color(0xFFFBBF24);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Follows.load();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final follow = !Follows.isFollowing(widget.kind, widget.id);
    setState(() => _busy = true);
    final now = await Follows.set(
      widget.kind,
      widget.id,
      follow: follow,
      leagueId: widget.leagueId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (now != follow) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Kaydedilemedi. Tekrar deneyin.')),
      );
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            follow ? 'Takip listene eklendi.' : 'Takip listenden çıkarıldı.',
          ),
          action: SnackBarAction(
            label: 'Geri al',
            onPressed: () => Follows.set(
              widget.kind,
              widget.id,
              follow: !follow,
              leagueId: widget.leagueId,
            ),
          ),
        ),
      );
    if (follow) PushPrompt.maybeShow(context, PushPromptReason.follow);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppSettings.followListEnabled,
        Follows.of(widget.kind),
      ]),
      builder: (context, _) {
        if (!Follows.visible(context)) return const SizedBox.shrink();
        final on = Follows.isFollowing(widget.kind, widget.id);
        final icon = Icon(
          on ? Icons.star_rounded : Icons.star_outline_rounded,
          size: widget.size,
          color: on ? _gold : widget.idleColor,
        );
        if (!widget.label) {
          return IconButton(
            tooltip: on ? 'Takibi bırak' : 'Takip et',
            onPressed: _toggle,
            icon: icon,
            padding: widget.dense ? EdgeInsets.zero : null,
            constraints: widget.dense
                ? const BoxConstraints(minWidth: 34, minHeight: 34)
                : null,
          );
        }
        return Material(
          color: on ? _gold.withValues(alpha: 0.14) : Colors.white12,
          shape: StadiumBorder(
            side: BorderSide(color: on ? _gold : Colors.white38, width: 1.2),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: 6),
                  Text(
                    on ? 'Takiptesin' : 'Takip et',
                    style: TextStyle(
                      color: on ? _gold : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
