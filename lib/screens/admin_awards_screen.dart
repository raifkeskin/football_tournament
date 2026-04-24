import 'package:flutter/material.dart';

import '../models/league.dart';
import '../models/award.dart';
import '../services/app_session.dart';
import '../services/interfaces/i_league_service.dart';
import '../services/service_locator.dart';

class AdminAwardsScreen extends StatefulWidget {
  const AdminAwardsScreen({super.key});

  @override
  State<AdminAwardsScreen> createState() => _AdminAwardsScreenState();
}

class _AdminAwardsScreenState extends State<AdminAwardsScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  String? _selectedLeagueId;

  Future<void> _openAddSheet(String leagueId) async {
    final controller = TextEditingController();
    final descController = TextEditingController();
    final cs = Theme.of(context).colorScheme;
    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    'Yeni Ödül / Kupa',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(labelText: 'Ödül Adı'),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Açıklama (opsiyonel)'),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('KAYDET'),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (saved != true) return;
      await _leagueService.addAward(
        leagueId: leagueId,
        name: controller.text,
        description: descController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ödül kaydedildi.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      controller.dispose();
      descController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ödül / Kupa Yönetimi')),
        body: const Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ödül / Kupa Yönetimi')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StreamBuilder(
        stream: _leagueService.watchLeagues(),
        builder: (context, leaguesSnap) {
          if (!leaguesSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final leagues = leaguesSnap.data ?? const <League>[];
          if (leagues.isEmpty) {
            return const Center(child: Text('Turnuva bulunamadı.'));
          }
          _selectedLeagueId ??= leagues.first.id;
          final leagueId = _selectedLeagueId!;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  initialValue: leagueId,
                  decoration: const InputDecoration(labelText: 'Turnuva Seçimi'),
                  items: [
                    for (final l in leagues)
                      DropdownMenuItem(value: l.id, child: Text(l.name)),
                  ],
                  onChanged: (v) => setState(() => _selectedLeagueId = v),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Award>>(
                  stream: _leagueService.watchAwardsForLeague(leagueId),
                  builder: (context, awardsSnap) {
                    if (!awardsSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final awards = awardsSnap.data!;
                    if (awards.isEmpty) {
                      return Center(
                        child: Text(
                          'Bu turnuva için ödül yok.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: awards.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final a = awards[index];
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            title: Text(
                              a.awardName,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            subtitle: (a.description != null && a.description!.trim().isNotEmpty)
                                ? Text(a.description!)
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _leagueService.deleteAward(a.id),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _selectedLeagueId == null
          ? null
          : FloatingActionButton(
              onPressed: () => _openAddSheet(_selectedLeagueId!),
              child: const Icon(Icons.add),
            ),
    );
  }
}
