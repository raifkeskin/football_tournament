import 'package:flutter/material.dart';
import 'package:football_tournament/features/admin/services/approval_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/app_session.dart';
import '../core/widgets/admin_page.dart';

/// Takım sorumlularının taleplerini listeler; admin ve turnuva sahibi onaylar.
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
  final _client = Supabase.instance.client;

  bool _busy = false;
  List<PendingAction> _actions = const [];

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
      final list = await _approval.fetchPendingActions();
      await _loadNames(list);
      if (!mounted) return;
      setState(() => _actions = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
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
                  fontWeight: FontWeight.w900,
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
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'VAZGEÇ',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
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
      body: _busy && _actions.isEmpty
          ? const LinearProgressIndicator(color: kAdminAccent)
          : _actions.isEmpty
          ? const Center(
              child: Text(
                'Bekleyen talep yok.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : RefreshIndicator(
              color: kAdminAccent,
              onRefresh: _reload,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _actions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _actionCard(_actions[index]),
              ),
            ),
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
              fontWeight: FontWeight.w900,
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
          Row(
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
                    onPressed: _busy ? null : () => _review(a, approve: true),
                    child: const Text(
                      'Onayla',
                      style: TextStyle(fontWeight: FontWeight.w800),
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
                      side: BorderSide(
                        color: kAdminDanger.withValues(alpha: 0.6),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _busy ? null : () => _review(a, approve: false),
                    child: const Text(
                      'Reddet',
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
