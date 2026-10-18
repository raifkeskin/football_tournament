import 'package:flutter/material.dart';
import 'package:football_tournament/features/admin/services/approval_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/app_session.dart';
import '../core/widgets/admin_page.dart';
import '../core/widgets/admin_form.dart';
import '../core/widgets/web_safe_image.dart';
import '../features/player/screens/my_profile_view.dart';
import '../features/player/services/player_profile_service.dart';
import '../features/match/services/youtube_autolink_service.dart';
import '../features/match/widgets/youtube_find_sheet.dart';
import '../core/utils/team_name.dart';

enum _Filter { all, profile, roster, broadcast, news, history }

/// Takım sorumlularının kadro talepleri, futbolcuların profil değişiklik
/// talepleri ve #ligmasasi etiketsiz Instagram gönderileri; admin ve turnuva
/// sahibi onaylar. Profil talebinde ilk karar
/// geçerlidir, sonuçlanan talepler "Geçmiş"te kalır.
/// Hangi taleplerin görüneceğini veritabanı belirler: admin hepsini, turnuva
/// sahibi yalnızca kendi turnuvalarınınkini görür.
class AdminPendingActionsScreen extends StatefulWidget {
  const AdminPendingActionsScreen({super.key});

  @override
  State<AdminPendingActionsScreen> createState() =>
      _AdminPendingActionsScreenState();
}

class _AdminPendingActionsScreenState extends State<AdminPendingActionsScreen> {
  final _approval = ApprovalService();
  final _profiles = PlayerProfileService();
  final _youtube = YoutubeAutolinkService();
  final _client = Supabase.instance.client;

  bool _busy = false;
  _Filter _filter = _Filter.all;
  List<PendingAction> _actions = const [];
  List<ProfileChangeRequest> _profileRequests = const [];
  List<ProfileChangeRequest> _history = const [];
  List<YoutubeLinkConflict> _conflicts = const [];
  List<_IgNews> _igNews = const [];

  /// Uyuşmazlık kartındaki maç bilgisi (maç id -> başlık / alt satır).
  Map<String, (String, String)> _conflictMatches = const {};

  // Listede gösterilecek adlar (id -> ad).
  Map<String, String> _teamNames = const {};
  Map<String, String> _playerNames = const {};
  Map<String, String> _seasonTitles = const {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _busy = true);
    try {
      final results = await Future.wait([
        _approval.fetchPendingActions(),
        _profiles.listRequests(onlyPending: true),
        _loadConflicts(),
        _loadIgNews(),
        if (_filter == _Filter.history)
          _profiles.listRequests(onlyPending: false),
      ]);
      final list = results[0] as List<PendingAction>;
      await _loadNames(list);
      if (!mounted) return;
      setState(() {
        _actions = list;
        _profileRequests = results[1] as List<ProfileChangeRequest>;
        _conflicts = results[2] as List<YoutubeLinkConflict>;
        _igNews = results[3] as List<_IgNews>;
        if (results.length > 4) {
          _history = (results[4] as List<ProfileChangeRequest>)
              .where((r) => r.status != ProfileChangeStatus.pending)
              .toList();
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Etiketsiz (yayınlanmamış) Instagram haberleri. Hangi turnuvanınkilerin
  /// görüneceğini RLS belirler. Hata olursa boş liste.
  Future<List<_IgNews>> _loadIgNews() async {
    try {
      final rows = await _client
          .from('news')
          .select(
            'id, content, image_url, created_at, auto_data, '
            'seasons(leagues(name))',
          )
          .eq('auto_kind', 'instagram')
          .eq('is_published', false)
          .order('created_at', ascending: false)
          .limit(50);
      return [for (final r in rows) _IgNews.fromMap(r)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _decideIgNews(_IgNews n, {required bool publish}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (publish) {
        await _client.from('news').update({'is_published': true}).eq('id', n.id);
      } else {
        // Gönderi instagram_seen_media'da kaldığı için tekrar aktarılmaz.
        await _client.from('news').delete().eq('id', n.id);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            publish ? 'Haber yayınlandı.' : 'Gönderi Haberler\'e alınmadı.',
          ),
        ),
      );
      await _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Yayın linki uyuşmazlıkları + maç başlıkları. Tablo yoksa ya da hata
  /// olursa boş liste (diğer talepler yine görünür).
  Future<List<YoutubeLinkConflict>> _loadConflicts() async {
    try {
      final list = await _youtube.pendingConflicts();
      final ids = list.map((c) => c.matchId).toSet().toList();
      final info = <String, (String, String)>{};
      if (ids.isNotEmpty) {
        final rows = await _client
            .from('matches')
            .select(
              'id, week, match_date, match_time, leagues(name), '
              'home:teams!matches_home_team_id_fkey(name), '
              'away:teams!matches_away_team_id_fkey(name)',
            )
            .inFilter('id', ids);
        for (final r in rows) {
          String name(String k) => r[k] is Map
              ? shortTeamName(((r[k] as Map)['name'] ?? '').toString())
              : '';
          final date = DateTime.tryParse((r['match_date'] ?? '').toString());
          final time = (r['match_time'] ?? '').toString();
          info[r['id'].toString()] = (
            '${name('home')} – ${name('away')}',
            [
              if (r['leagues'] is Map) (r['leagues'] as Map)['name'] ?? '',
              if (r['week'] != null) '${r['week']}. Hafta',
              if (date != null)
                [
                  broadcastDate(date).split(' · ').first,
                  if (time.length >= 5) time.substring(0, 5),
                ].join(' '),
            ].where((e) => '$e'.isNotEmpty).join(' · '),
          );
        }
      }
      _conflictMatches = info;
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _resolveConflict(
    YoutubeLinkConflict c, {
    required bool useAuto,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _youtube.resolve(c.id, useAuto: useAuto);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            useAuto
                ? 'Maçın yayın linki kanaldaki yayınla değiştirildi.'
                : 'Elle girilen link korundu.',
          ),
        ),
      );
      await _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadNames(List<PendingAction> list) async {
    final teamIds = list.map((a) => a.teamId).toSet().toList();
    final playerIds = list
        .map((a) => a.playerId)
        .whereType<String>()
        .toSet()
        .toList();
    final seasonIds = list.map((a) => a.seasonId).toSet().toList();

    final teams = <String, String>{};
    if (teamIds.isNotEmpty) {
      final rows = await _client
          .from('teams')
          .select('id, name')
          .inFilter('id', teamIds);
      for (final r in rows) {
        teams[r['id'].toString()] = (r['name'] ?? '').toString();
      }
    }

    final players = <String, String>{};
    if (playerIds.isNotEmpty) {
      final rows = await _client
          .from('players_public')
          .select('id, name, surname')
          .inFilter('id', playerIds);
      for (final r in rows) {
        players[r['id'].toString()] = [
          (r['name'] ?? '').toString().trim(),
          (r['surname'] ?? '').toString().trim(),
        ].where((e) => e.isNotEmpty).join(' ');
      }
    }

    final seasons = <String, String>{};
    if (seasonIds.isNotEmpty) {
      final rows = await _client
          .from('seasons')
          .select('id, name, leagues(name)')
          .inFilter('id', seasonIds);
      for (final r in rows) {
        final league = r['leagues'] is Map
            ? ((r['leagues'] as Map)['name'] ?? '').toString()
            : '';
        final season = (r['name'] ?? '').toString();
        seasons[r['id'].toString()] = [
          league,
          season,
        ].where((e) => e.isNotEmpty).join(' • ');
      }
    }

    _teamNames = teams;
    _playerNames = players;
    _seasonTitles = seasons;
  }

  String _playerLabel(PendingAction a) {
    final newName = a.newPlayerName;
    if (newName != null) return '$newName (yeni oyuncu)';
    return _playerNames[a.playerId] ?? '-';
  }

  Future<String?> _askNote({required bool approve}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: AdminDialogCloseOverlay(
          onClose: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: adminDialogDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  approve ? 'Talebi Onayla' : 'Talebi Reddet',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: approve
                        ? 'Not (isteğe bağlı)'
                        : 'Red nedeni (sorumluya gösterilir)',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.3),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kAdminAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: approve ? kAdminAccent : kAdminDanger,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: Text(
                      approve ? 'ONAYLA' : 'REDDET',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _review(PendingAction action, {required bool approve}) async {
    final note = await _askNote(approve: approve);
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (approve) {
        await _approval.approveAction(actionId: action.id, reviewNote: note);
      } else {
        await _approval.rejectAction(actionId: action.id, reviewNote: note);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Onaylandı.' : 'Reddedildi.'),
          backgroundColor: approve ? Colors.green : Colors.orange,
        ),
      );
      await _reload();
    } on PostgrestException catch (e) {
      // Sunucunun kontrol mesajı (ör. "Oyuncu bu sezon başka bir takımda
      // kayıtlı.") doğrudan gösterilir.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewProfile(
    ProfileChangeRequest r, {
    required bool approve,
  }) async {
    final note = await _askNote(approve: approve);
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _profiles.review(r.id, approve: approve, note: note);
      // Depoda boşta dosya kalmasın: reddedilen yeni fotoğraf ya da onayla
      // yerini yenisine bırakan eski talep fotoğrafı silinir.
      final unused = approve
          ? (r.changes.containsKey(ProfileField.photoUrl)
                ? r.previous[ProfileField.photoUrl]?.toString()
                : null)
          : r.changes[ProfileField.photoUrl]?.toString();
      if (unused != null && unused.contains('/media/profile_requests/')) {
        await _profiles.deletePhoto(unused);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Onaylandı.' : 'Reddedildi.'),
          backgroundColor: approve ? Colors.green : Colors.orange,
        ),
      );
    } on PostgrestException catch (e) {
      // Ör. "Talep zaten sonuçlanmış." (başka bir sorumlu önce karar verdi).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      await _reload();
    }
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '-';
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    if (!session.canReviewApprovals) {
      return const AdminPageScaffold(
        title: 'Bekleyen Onaylar',
        body: Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return AdminPageScaffold(
      title: 'Bekleyen Onaylar',
      actions: [
        AdminBarAction(
          icon: Icons.refresh_rounded,
          tooltip: 'Yenile',
          onPressed: _busy ? null : _reload,
        ),
      ],
      body: Column(
        children: [
          _filterBar(),
          if (_busy) const LinearProgressIndicator(color: kAdminAccent),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _filterBar() {
    Widget chip(_Filter f, String label) {
      final sel = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          showCheckmark: false,
          onSelected: (_) {
            if (sel) return;
            setState(() => _filter = f);
            if (f == _Filter.history) _reload();
          },
          labelStyle: TextStyle(
            color: sel ? const Color(0xFF04120D) : Colors.white70,
            fontWeight: FontWeight.w800,
          ),
          selectedColor: kAdminAccent,
          backgroundColor: Colors.transparent,
          side: BorderSide(
            color: sel ? kAdminAccent : Colors.white.withValues(alpha: 0.15),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
    }

    final total =
        _actions.length +
        _profileRequests.length +
        _conflicts.length +
        _igNews.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          chip(_Filter.all, 'Tümü ($total)'),
          chip(_Filter.profile, 'Profil (${_profileRequests.length})'),
          chip(_Filter.roster, 'Kadro (${_actions.length})'),
          chip(_Filter.broadcast, 'Yayın (${_conflicts.length})'),
          chip(_Filter.news, 'Haber (${_igNews.length})'),
          chip(_Filter.history, 'Geçmiş'),
        ],
      ),
    );
  }

  Widget _list() {
    final List<Widget> cards = switch (_filter) {
      _Filter.all => [
        ..._profileRequests.map(_profileCard),
        ..._actions.map(_actionCard),
        ..._conflicts.map(_conflictCard),
        ..._igNews.map(_igNewsCard),
      ],
      _Filter.profile => _profileRequests.map(_profileCard).toList(),
      _Filter.roster => _actions.map(_actionCard).toList(),
      _Filter.broadcast => _conflicts.map(_conflictCard).toList(),
      _Filter.news => _igNews.map(_igNewsCard).toList(),
      _Filter.history => _history.map(_historyCard).toList(),
    };
    if (cards.isEmpty) {
      return Center(
        child: Text(
          _busy
              ? ''
              : _filter == _Filter.history
              ? 'Sonuçlanmış profil talebi yok.'
              : 'Bekleyen talep yok.',
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return RefreshIndicator(
      color: kAdminAccent,
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, kAdminFabClearance),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => cards[index],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );

  Widget _profileHeader(ProfileChangeRequest r, Widget chip) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.playerName ?? '-',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (r.teamName != null) r.teamName!,
                  'Talep: ${_formatDate(r.createdAt)}',
                ].join(' · '),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        chip,
      ],
    );
  }

  Widget _photoCompare(ProfileChangeRequest r) {
    Widget box(String? url, String label, Color color) => Expanded(
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color, width: 2),
              ),
              child: (url ?? '').isEmpty
                  ? const Icon(
                      Icons.person_rounded,
                      color: Colors.white38,
                      size: 48,
                    )
                  : WebSafeImage(url: url!),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        box(
          r.previous[ProfileField.photoUrl]?.toString(),
          'Mevcut',
          Colors.white24,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 50, 8, 0),
          child: Icon(Icons.arrow_forward_rounded, color: Colors.white54),
        ),
        box(
          r.changes[ProfileField.photoUrl]?.toString(),
          'Yeni',
          const Color(0xFFFBBF24),
        ),
      ],
    );
  }

  Widget _profileCard(ProfileChangeRequest r) {
    final hasPhoto = r.changes.containsKey(ProfileField.photoUrl);
    final hasOther = r.changes.keys.any((k) => k != ProfileField.photoUrl);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _profileHeader(r, _chip('Profil', const Color(0xFF60A5FA))),
          if (hasPhoto) ...[const SizedBox(height: 12), _photoCompare(r)],
          if (hasOther) ...[
            const SizedBox(height: 12),
            ProfileChangeDiff(request: r, showPhoto: false),
          ],
          const SizedBox(height: 12),
          _decisionButtons(
            onApprove: () => _reviewProfile(r, approve: true),
            onReject: () => _reviewProfile(r, approve: false),
          ),
        ],
      ),
    );
  }

  Widget _historyCard(ProfileChangeRequest r) {
    final (label, color) = switch (r.status) {
      ProfileChangeStatus.approved => ('Onaylandı', kAdminAccent),
      ProfileChangeStatus.rejected => ('Reddedildi', kAdminDanger),
      ProfileChangeStatus.withdrawn => (
        'Geri çekildi',
        const Color(0xFF94A3B8),
      ),
      ProfileChangeStatus.pending => ('Bekliyor', const Color(0xFFFBBF24)),
    };
    final who = r.status == ProfileChangeStatus.withdrawn
        ? 'Futbolcu geri çekti'
        : 'Karar: ${r.reviewerName ?? '-'}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _profileHeader(r, _chip(label, color)),
          const SizedBox(height: 10),
          ProfileChangeDiff(request: r),
          const SizedBox(height: 8),
          Text(
            [
              who,
              _formatDate(r.reviewedAt),
              if ((r.reviewNote ?? '').isNotEmpty) '"${r.reviewNote}"',
            ].join(' · '),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _decisionButtons({
    required VoidCallback onApprove,
    required VoidCallback onReject,
    String approveLabel = 'Onayla',
    String rejectLabel = 'Reddet',
  }) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kAdminAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _busy ? null : onApprove,
              child: Text(
                approveLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 44,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: kAdminDanger,
                side: BorderSide(color: kAdminDanger.withValues(alpha: 0.6)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _busy ? null : onReject,
              child: Text(
                rejectLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionCard(PendingAction a) {
    final jersey = a.jerseyNumber;
    Widget info(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            a.typeLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _seasonTitles[a.seasonId] ?? '-',
            style: const TextStyle(color: kAdminAccent, fontSize: 12),
          ),
          const SizedBox(height: 6),
          info('Takım', _teamNames[a.teamId] ?? '-'),
          info('Oyuncu', _playerLabel(a)),
          if (a.type != PendingActionType.rosterRemove)
            info('Forma', jersey?.toString() ?? '-'),
          const SizedBox(height: 6),
          Text(
            'Talep: ${_formatDate(a.createdAt)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _decisionButtons(
            onApprove: () => _review(a, approve: true),
            onReject: () => _review(a, approve: false),
          ),
        ],
      ),
    );
  }

  /// Etiketsiz Instagram gönderisi: görsel + açıklama; yayınla ya da alma.
  Widget _igNewsCard(_IgNews n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    if (n.league != null) n.league!,
                    if (n.username != null) '@${n.username}',
                  ].join(' · '),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _chip(
                n.video ? 'Instagram video' : 'Instagram',
                const Color(0xFFE1306C),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Paylaşım: ${_formatDate(n.createdAt)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (n.imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 96,
                    height: 120,
                    child: WebSafeImage(url: n.imageUrl!),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  n.content,
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: kAdminAmber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Açıklamada #ligmasasi etiketi yok. Haberlere alınsın mı? '
              'Etiketli gönderiler onay beklemeden yayınlanır.',
              style: TextStyle(color: kAdminAmber, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 12),
          _decisionButtons(
            onApprove: () => _decideIgNews(n, publish: true),
            onReject: () => _decideIgNews(n, publish: false),
            approveLabel: 'Yayınla',
            rejectLabel: 'Haberlere alma',
          ),
        ],
      ),
    );
  }

  /// Elle girilen ve kanalda bulunan yayın yan yana; karar ikisinden biri.
  Widget _conflictCard(YoutubeLinkConflict c) {
    final (title, sub) = _conflictMatches[c.matchId] ?? ('Maç', '');
    Widget side(FoundBroadcast? b, String label, Color color, {String? url}) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (b != null)
                      BroadcastThumb(videoId: b.videoId, radius: 0)
                    else
                      const AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Icon(Icons.link_rounded, color: Colors.white38),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (b?.title ?? '').isNotEmpty
                                ? b!.title
                                : (url ?? 'Başlık alınamadı'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          if (b?.at != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              broadcastDate(b!.at),
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color == kAdminAccent ? kAdminAccent : Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
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
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _chip('Yayın linki', const Color(0xFFFF4D6A)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              side(
                c.manual,
                'Elle girilen',
                Colors.white24,
                url: c.manualUrl,
              ),
              const SizedBox(width: 10),
              side(c.auto, 'Kanalda bulunan', kAdminAccent),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: kAdminAmber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Elle girilen yayının başlığı bu maçın takımlarıyla uyuşmuyor. '
              'Hangisinin doğru olduğunu seçin.',
              style: TextStyle(color: kAdminAmber, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _busy
                        ? null
                        : () => _resolveConflict(c, useAuto: false),
                    child: const Text(
                      'Elle gireni koru',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAdminAccent,
                      foregroundColor: const Color(0xFF04120D),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _busy
                        ? null
                        : () => _resolveConflict(c, useAuto: true),
                    child: const Text(
                      'Kanaldakini kullan',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Onay bekleyen (etiketsiz) Instagram haberi.
class _IgNews {
  const _IgNews({
    required this.id,
    required this.content,
    this.imageUrl,
    this.createdAt,
    this.league,
    this.username,
    this.video = false,
  });

  final String id;
  final String content;
  final String? imageUrl;
  final DateTime? createdAt;
  final String? league;
  final String? username;
  final bool video;

  factory _IgNews.fromMap(Map<String, dynamic> r) {
    final data = r['auto_data'] is Map ? r['auto_data'] as Map : const {};
    final season = r['seasons'] is Map ? r['seasons'] as Map : const {};
    final league = season['leagues'] is Map ? season['leagues'] as Map : const {};
    String? text(dynamic v) => (v ?? '').toString().trim().isEmpty ? null : '$v';
    return _IgNews(
      id: r['id'].toString(),
      content: (r['content'] ?? '').toString(),
      imageUrl: text(r['image_url']),
      createdAt: DateTime.tryParse((r['created_at'] ?? '').toString()),
      league: text(league['name']),
      username: text(data['username']),
      video: data['video'] == true,
    );
  }
}
