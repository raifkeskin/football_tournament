import 'package:flutter/material.dart';
import '../models/league.dart';
import '../services/app_session.dart';
import '../services/interfaces/i_league_service.dart';
import '../services/service_locator.dart';

class AdminAddNewsScreen extends StatefulWidget {
  const AdminAddNewsScreen({super.key});

  @override
  State<AdminAddNewsScreen> createState() => _AdminAddNewsScreenState();
}

class _AdminAddNewsScreenState extends State<AdminAddNewsScreen> {
  final _newsController = TextEditingController();
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  bool _isLoading = false;
  String? _selectedTournamentId;

  @override
  void dispose() {
    _newsController.dispose();
    super.dispose();
  }

  Future<void> _haberYayinla() async {
    final tId = (_selectedTournamentId ?? '').trim();
    if (tId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen önce turnuva seçin.')),
      );
      return;
    }
    final text = _newsController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir haber metni girin.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _leagueService.addNews(tournamentId: tId, content: text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Haber başarıyla yayınlandı.'),
          backgroundColor: Colors.green,
        ),
      );
      _newsController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Son Dakika Haber Ekle')),
        body: const Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Son Dakika Haber Ekle')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            StreamBuilder<List<League>>(
              stream: _leagueService.watchLeagues(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const SizedBox(
                    height: 56,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final leagues = snap.data ?? const <League>[];
                if (leagues.isEmpty) {
                  return const SizedBox.shrink();
                }
                _selectedTournamentId ??= leagues.first.id;
                return DropdownButtonFormField<String>(
                  initialValue: _selectedTournamentId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Turnuva',
                    border: OutlineInputBorder(),
                  ),
                  items: leagues
                      .map((l) => DropdownMenuItem<String>(
                            value: l.id,
                            child: Text(
                              l.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedTournamentId = v),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newsController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Haber Metni',
                hintText: 'Örn: Turnuva final maçı yarın saat 20:00\'de!',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : FilledButton.icon(
                      onPressed: _haberYayinla,
                      icon: const Icon(Icons.send),
                      label: const Text('Yayınla'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
