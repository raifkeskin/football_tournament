import 'package:flutter/material.dart';

import '../../tournament/models/league.dart';
import '../models/award.dart';
import '../../../core/services/app_session.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/custom_popup_selector.dart';

class AdminAwardsScreen extends StatefulWidget {
  const AdminAwardsScreen({super.key});

  @override
  State<AdminAwardsScreen> createState() => _AdminAwardsScreenState();
}

class _AdminAwardsScreenState extends State<AdminAwardsScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  late final Stream<List<League>> _leaguesStream = _leagueService
      .watchLeagues();
  String? _selectedLeagueId;

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : null,
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.black.withValues(alpha: 0.3),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kAdminAccent),
    ),
  );

  Future<void> _openAddDialog() async {
    final leagueId = (_selectedLeagueId ?? '').trim();
    if (leagueId.isEmpty) {
      _snack('Lütfen önce turnuva seçin.');
      return;
    }
    final nameController = TextEditingController();
    final descController = TextEditingController();
    var saving = false;

    Future<void> save(BuildContext ctx, StateSetter setLocal) async {
      if (nameController.text.trim().isEmpty) {
        _snack('Ödül adı boş olamaz.', error: true);
        return;
      }
      setLocal(() => saving = true);
      try {
        await _leagueService.addAward(
          leagueId: leagueId,
          name: nameController.text,
          description: descController.text,
        );
        if (ctx.mounted) Navigator.pop(ctx);
        if (mounted) _snack('Ödül kaydedildi.');
      } catch (e) {
        if (mounted) _snack('Hata: $e', error: true);
        if (ctx.mounted) setLocal(() => saving = false);
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: AdminDialogCloseOverlay(
            onClose: saving ? null : () => Navigator.pop(ctx),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: adminDialogDecoration(),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.emoji_events_outlined, color: kAdminAccent),
                        SizedBox(width: 8),
                        Text(
                          'Yeni Ödül / Kupa',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: Colors.white24, height: 1),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      enabled: !saving,
                      style: const TextStyle(color: Colors.white),
                      decoration: _fieldDecoration('Ödül Adı'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      enabled: !saving,
                      style: const TextStyle(color: Colors.white),
                      decoration: _fieldDecoration('Açıklama (isteğe bağlı)'),
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAdminAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: saving ? null : () => save(ctx, setLocal),
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
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Dialog kapanış animasyonu bitene kadar alanlar controller'ı kullanır.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      nameController.dispose();
      descController.dispose();
    });
  }

  Future<void> _deleteAward(Award award) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Ödülü Sil',
      message: '"${award.awardName}" silinecek. Devam edilsin mi?',
    );
    if (!ok) return;
    try {
      await _leagueService.deleteAward(award.id);
      if (mounted) _snack('Ödül silindi.');
    } catch (e) {
      if (mounted) _snack('Hata: $e', error: true);
    }
  }

  Widget _awardCard(Award a) {
    final desc = (a.description ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: adminCardDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: Color(0xFFFBBF24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.awardName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          AdminSmallAction(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Sil',
            color: kAdminDanger,
            onTap: () => _deleteAward(a),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    if (!session.isAdmin && !session.isLeagueOwner) {
      return const AdminPageScaffold(
        title: 'Ödül / Kupa Yönetimi',
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
      title: 'Ödül / Kupa Yönetimi',
      actions: [
        AdminBarAction(
          icon: Icons.add_rounded,
          tooltip: 'Ödül Ekle',
          onPressed: _openAddDialog,
        ),
      ],
      body: StreamBuilder<List<League>>(
        stream: _leaguesStream,
        builder: (context, leaguesSnap) {
          if (!leaguesSnap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: kAdminAccent),
            );
          }
          // Admin her turnuvayı, turnuva sahibi sadece kendisininkileri görür.
          final leagues = (leaguesSnap.data ?? const <League>[])
              .where((l) => session.canManageLeague(l.id))
              .toList();
          if (leagues.isEmpty) {
            return const Center(
              child: Text(
                'Turnuva bulunamadı.',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }
          if (leagues.every((l) => l.id != _selectedLeagueId)) {
            _selectedLeagueId = leagues.first.id;
          }
          final leagueId = _selectedLeagueId!;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: CustomPopupSelector<String>(
                  label: 'Turnuva',
                  selectedValue: leagueId,
                  items: leagues.map((l) => l.id).toList(),
                  labelBuilder: (id) => leagues
                      .firstWhere(
                        (l) => l.id == id,
                        orElse: () => leagues.first,
                      )
                      .name,
                  onChanged: (v) => setState(() => _selectedLeagueId = v),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<List<Award>>(
                  stream: _leagueService.watchAwardsForLeague(leagueId),
                  builder: (context, awardsSnap) {
                    if (!awardsSnap.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: kAdminAccent),
                      );
                    }
                    final awards = awardsSnap.data!;
                    if (awards.isEmpty) {
                      return const Center(
                        child: Text(
                          'Bu turnuva için ödül yok.\n'
                          'Sağ üstteki butondan ödül ekleyebilirsiniz.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: awards.map(_awardCard).toList(),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
