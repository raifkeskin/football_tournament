import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/push/push_bridge_stub.dart'
    if (dart.library.js_interop) '../../core/push/push_bridge_web.dart'
    as bridge;
import '../../core/services/app_session.dart';
import '../match/models/match.dart';
import '../match/screens/match_details_screen.dart';
import '../news/screens/news_feed_screen.dart';
import '../tournament/screens/admin_penalty_management_screen.dart';
import '../../screens/admin_pending_actions_screen.dart';
import '../tournament/screens/tournament_hub_screen.dart';

/// Bildirimin açtığı ekran: maç bildirimleri maç detayını, haber Turnuva
/// Sayfası'nın Haberler sekmesini, onay bekleyen ceza ceza onaylarını açar.
/// Uygulama içi listeden ve telefon bildiriminden (`/?n=<tür>-<id>`) aynı yol.
class NotificationRouter {
  NotificationRouter._();

  /// Telefon bildiriminden gelen, ana ekran hazır olunca açılacak hedef.
  static final pending = ValueNotifier<({String kind, String? ref})?>(null);

  /// Açılış adresindeki ve açıkken gelen bildirim tıklamalarını dinler.
  static void init() {
    if (!kIsWeb) return;
    final tag = Uri.base.queryParameters['n'];
    if (tag != null && tag.isNotEmpty) _queue(tag);
    bridge.pushOnOpen((url) {
      final t = Uri.tryParse(url)?.queryParameters['n'];
      if (t != null && t.isNotEmpty) _queue(t);
    });
  }

  static void _queue(String tag) {
    final i = tag.indexOf('-');
    final kind = i < 0 ? tag : tag.substring(0, i);
    final ref = i < 0 ? null : tag.substring(i + 1);
    pending.value = (kind: kind, ref: ref);
  }

  static Future<void> open(
    BuildContext context,
    String kind,
    String? ref,
  ) async {
    switch (kind) {
      case 'result':
      case 'schedule':
      case 'reminder':
      case 'live':
      case 'goal':
        if (ref != null) await _openMatch(context, ref);
      case 'news':
        if (ref != null) await _openNews(context, ref);
      case 'approval':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AdminPendingActionsScreen(),
          ),
        );
      case 'penalty':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AdminPenaltyManagementScreen(),
          ),
        );
    }
  }

  /// Haberin turnuva sayfası, Haberler sekmesi; haber açık gelir.
  static Future<void> _openNews(BuildContext context, String id) async {
    final row = await Supabase.instance.client
        .from('news')
        .select('season_id, seasons(league_id)')
        .eq('id', id)
        .maybeSingle();
    final leagueId = ((row?['seasons'] as Map?)?['league_id'] ?? '').toString();
    if (!context.mounted || leagueId.isEmpty) return;
    NewsView.focusNewsId.value = id;
    await TournamentHubScreen.open(
      context,
      leagueId: leagueId,
      seasonId: row?['season_id']?.toString(),
      initialTab: TournamentHubTab.news,
    );
  }

  static Future<void> _openMatch(BuildContext context, String id) async {
    final isAdmin = AppSession.of(context).value.isAdmin;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final row = await Supabase.instance.client
          .from('matches')
          .select('*, pitches(name)')
          .eq('id', id)
          .maybeSingle();
      if (row == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Bu maç artık bulunamadı.')),
        );
        return;
      }
      final match = MatchModel.fromMap(
        Map<String, dynamic>.from(row)
          ..['pitch_name'] = (row['pitches'] as Map?)?['name'],
        id,
      );
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => MatchDetailsScreen(match: match, isAdmin: isAdmin),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Maç açılamadı. Lütfen tekrar deneyin.')),
      );
    }
  }
}
