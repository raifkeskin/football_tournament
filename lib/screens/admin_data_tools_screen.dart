import 'package:flutter/material.dart';
import '../services/app_session.dart';
import '../services/database_service.dart';

class AdminDataToolsScreen extends StatefulWidget {
  const AdminDataToolsScreen({super.key});

  @override
  State<AdminDataToolsScreen> createState() => _AdminDataToolsScreenState();
}

class _AdminDataToolsScreenState extends State<AdminDataToolsScreen> {
  final _db = DatabaseService();
  bool _busy = false;
  String? _lastResult;

  Future<bool> _confirmDanger() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dikkat'),
        content: const Text(
          'Mevcut tüm maçlar ve maç olayları kalıcı olarak silinecek. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Evet, Sil'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _clearMatches() async {
    final ok = await _confirmDanger();
    if (!ok) return;
    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      final deleted = await _db.deleteAllMatchesAndEvents();
      setState(() {
        _lastResult = 'Silinen toplam kayıt: $deleted';
      });
    } catch (e) {
      setState(() {
        _lastResult = 'Hata: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAndSeedOneWeek() async {
    final ok = await _confirmDanger();
    if (!ok) return;
    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      final deleted = await _db.deleteAllMatchesAndEvents();
      final created = await _db.seedDummyFixtureOneWeek();
      setState(() {
        _lastResult = 'Silinen: $deleted • Oluşturulan maç: $created';
      });
    } catch (e) {
      setState(() {
        _lastResult = 'Hata: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('Veri Araçları')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: !isAdmin
          ? const Center(child: Text('Bu sayfa sadece adminler içindir.'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _clearMatches,
                    icon: const Icon(Icons.delete_forever_rounded),
                    label: const Text('Maçları ve Olayları Temizle'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _clearAndSeedOneWeek,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text(
                      'Temizle + Dummy Veri Oluştur (15 Oyuncu + 3 Maç/Takım)',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_busy) const LinearProgressIndicator(),
                  if (_lastResult != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _lastResult!,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
