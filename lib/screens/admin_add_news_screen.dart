import 'package:flutter/material.dart';
import '../services/database_service.dart';

class AdminAddNewsScreen extends StatefulWidget {
  const AdminAddNewsScreen({super.key});

  @override
  State<AdminAddNewsScreen> createState() => _AdminAddNewsScreenState();
}

class _AdminAddNewsScreenState extends State<AdminAddNewsScreen> {
  final _newsController = TextEditingController();
  final _dbService = DatabaseService();
  bool _isLoading = false;

  @override
  void dispose() {
    _newsController.dispose();
    super.dispose();
  }

  Future<void> _haberYayinla() async {
    final text = _newsController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir haber metni girin.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _dbService.addNews(text);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Son Dakika Haber Ekle')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
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
