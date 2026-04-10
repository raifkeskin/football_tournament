import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/league.dart';
import '../services/database_service.dart';
import '../services/image_upload_service.dart';

/// Admin için turnuva ekleme formu.
class AdminAddLeagueScreen extends StatefulWidget {
  const AdminAddLeagueScreen({super.key});

  @override
  State<AdminAddLeagueScreen> createState() => _AdminAddLeagueScreenState();
}

class _AdminAddLeagueScreenState extends State<AdminAddLeagueScreen> {
  final _leagueNameController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _groupCountController = TextEditingController(text: '1');
  final _teamsPerGroupController = TextEditingController(text: '4');
  final _youtubeController = TextEditingController();
  final _twitterController = TextEditingController();
  final _instagramController = TextEditingController();
  final _picker = ImagePicker();
  final _imageUploadService = ImgBBUploadService();
  final _databaseService = DatabaseService();

  XFile? _leagueLogo;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = false;

  @override
  void dispose() {
    _leagueNameController.dispose();
    _subtitleController.dispose();
    _youtubeController.dispose();
    _twitterController.dispose();
    _instagramController.dispose();
    super.dispose();
  }

  Future<void> _logoSec() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _leagueLogo = picked);
  }

  Future<void> _tarihSec({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? now)
          : (_endDate ?? _startDate ?? now),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  String _tarihYaz(DateTime? date) {
    if (date == null) return 'Tarih seç';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Future<void> _turnuvaEkle() async {
    final leagueName = _leagueNameController.text.trim();
    final subtitle = _subtitleController.text.trim();

    if (leagueName.isEmpty || _startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lütfen turnuva adı, başlangıç ve bitiş tarihini girin.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final unique = await _databaseService.isLeagueUnique(
        name: leagueName,
        subtitle: subtitle,
      );
      if (!unique) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu isim ve alt bilgi kombinasyonuna sahip bir turnuva zaten var!'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      String logoUrl = '';
      if (_leagueLogo != null) {
        final uploadedUrl = await _imageUploadService.uploadImage(
          File(_leagueLogo!.path),
        );
        if (uploadedUrl != null) {
          logoUrl = uploadedUrl;
        } else {
          throw Exception('Logo yüklenemedi, lütfen tekrar deneyin.');
        }
      }

      // Veritabanına kaydet
      final league = League(
        id: '', // Firestore auto-id kullanacak
        name: leagueName,
        subtitle: subtitle.isEmpty ? null : subtitle,
        logoUrl: logoUrl,
        country: 'Türkiye', // Varsayılan veya bir input eklenebilir
        startDate: _startDate,
        endDate: _endDate,
        youtubeUrl: _youtubeController.text.trim(),
        twitterUrl: _twitterController.text.trim(),
        instagramUrl: _instagramController.text.trim(),
        groupCount: int.tryParse(_groupCountController.text) ?? 1,
        teamsPerGroup: int.tryParse(_teamsPerGroupController.text) ?? 4,
      );

      await _databaseService.addLeague(league);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Turnuva başarıyla kaydedildi.'),
          backgroundColor: Colors.green,
        ),
      );

      // Formu temizle
      setState(() {
        _leagueNameController.clear();
        _subtitleController.clear();
        _leagueLogo = null;
        _startDate = null;
        _endDate = null;
      });
    } catch (e) {
      print("Turnuva ekleme hatası: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata oluştu: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Turnuva Ekle')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _leagueNameController,
                  decoration: const InputDecoration(labelText: 'Turnuva Adı'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _subtitleController,
                  decoration: const InputDecoration(
                    labelText: 'Alt Bilgi (Örn: Yaz Ligi 2024)',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _tarihSec(isStart: true),
                        icon: const Icon(Icons.event_outlined),
                        label: Text('Başlangıç: ${_tarihYaz(_startDate)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _tarihSec(isStart: false),
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text('Bitiş: ${_tarihYaz(_endDate)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_leagueLogo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(_leagueLogo!.path),
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _logoSec,
                  style: OutlinedButton.styleFrom(
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _leagueLogo == null
                        ? 'Turnuva Logosu Seç (Galeri)'
                        : 'Seçildi: ${_leagueLogo!.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _groupCountController,
                        decoration: const InputDecoration(
                          labelText: 'Grup Sayısı',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _teamsPerGroupController,
                        decoration: const InputDecoration(
                          labelText: 'Grup Başı Takım',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _youtubeController,
                  decoration: const InputDecoration(
                    labelText: 'YouTube Linki',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.play_circle_outline),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _twitterController,
                  decoration: const InputDecoration(
                    labelText: 'Twitter (X) Linki',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _instagramController,
                  decoration: const InputDecoration(
                    labelText: 'Instagram Linki',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.camera_alt_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: _turnuvaEkle,
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Turnuvayı Kaydet'),
                ),
              ],
            ),
    );
  }
}
