import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/league.dart';
import '../services/app_session.dart';
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
  final _managerNameController = TextEditingController();
  final _managerSurnameController = TextEditingController();
  final _managerPhoneController = TextEditingController();
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
    _managerNameController.dispose();
    _managerSurnameController.dispose();
    _managerPhoneController.dispose();
    _groupCountController.dispose();
    _teamsPerGroupController.dispose();
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

  Future<void> _tarihAraligiSec() async {
    final now = DateTime.now();
    final initialStart = _startDate ?? now;
    final initialEnd = _endDate ??
        (_startDate != null ? _startDate!.add(const Duration(days: 7)) : now);
    final initialRange = DateTimeRange(
      start: initialStart,
      end: initialEnd.isBefore(initialStart) ? initialStart : initialEnd,
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
      initialDateRange: initialRange,
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked.start;
      _endDate = picked.end;
    });
  }

  String _tarihYaz(DateTime? date) {
    if (date == null) return 'Tarih seç';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  String _tarihAraligiYaz() {
    if (_startDate == null || _endDate == null) return 'Tarih aralığı seç';
    return '${_tarihYaz(_startDate)} - ${_tarihYaz(_endDate)}';
  }

  Future<void> _turnuvaEkle() async {
    final leagueName = _leagueNameController.text.trim();
    final subtitle = _subtitleController.text.trim();
    final managerName = _managerNameController.text.trim();
    final managerSurname = _managerSurnameController.text.trim();
    final managerPhone = _managerPhoneController.text.trim();

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

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isLoading = true);

    try {
      String normalizePhoneToRaw10(String input) {
        final digits = input.replaceAll(RegExp(r'\D'), '');
        if (digits.isEmpty) return '';
        var d = digits;
        if (d.startsWith('90') && d.length >= 12) d = d.substring(2);
        if (d.startsWith('0')) d = d.substring(1);
        if (d.length > 10) d = d.substring(d.length - 10);
        return d;
      }

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
        managerName: managerName.isEmpty ? null : managerName,
        managerSurname: managerSurname.isEmpty ? null : managerSurname,
        managerPhoneRaw10:
            managerPhone.isEmpty ? null : normalizePhoneToRaw10(managerPhone),
        startDate: _startDate,
        endDate: _endDate,
        youtubeUrl: _youtubeController.text.trim(),
        twitterUrl: _twitterController.text.trim(),
        instagramUrl: _instagramController.text.trim(),
        numberOfGroups: int.tryParse(_groupCountController.text) ?? 1,
        groups: List.generate(
          int.tryParse(_groupCountController.text) ?? 1,
          (i) => String.fromCharCode(65 + i), // A, B, C...
        ),
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
        _managerNameController.clear();
        _managerSurnameController.clear();
        _managerPhoneController.clear();
        _leagueLogo = null;
        _startDate = null;
        _endDate = null;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final readable = msg.contains('requires an index') ||
              msg.contains('The query requires an index')
          ? 'Bu işlem için Firestore index hatası oluştu. Uygulama sorgusu sadeleştirildi; tekrar deneyin.'
          : 'Hata oluştu: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(readable), backgroundColor: Colors.red),
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
        appBar: AppBar(title: const Text('Turnuva Ekle')),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Turnuva Ekle')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _leagueNameController,
                decoration: const InputDecoration(labelText: 'Turnuva Adı'),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _subtitleController,
                decoration: const InputDecoration(
                  labelText: 'Alt Bilgi (Örn: Yaz Ligi 2024)',
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _managerNameController,
                decoration: const InputDecoration(
                  labelText: 'Turnuva Sorumlusu Ad',
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _managerSurnameController,
                decoration: const InputDecoration(
                  labelText: 'Turnuva Sorumlusu Soyad',
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _managerPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Turnuva Sorumlusu Telefon',
                  hintText: '0 (5XX) XXX XX XX',
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _isLoading ? null : _tarihAraligiSec,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Tarih Aralığı',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.date_range_outlined),
                  ),
                  child: Text(_tarihAraligiYaz()),
                ),
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
                onPressed: _isLoading ? null : _logoSec,
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
                      enabled: !_isLoading,
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
                      enabled: !_isLoading,
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
                enabled: !_isLoading,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _twitterController,
                decoration: const InputDecoration(
                  labelText: 'Twitter (X) Linki',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _instagramController,
                decoration: const InputDecoration(
                  labelText: 'Instagram Linki',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.camera_alt_outlined),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: _isLoading ? null : _turnuvaEkle,
                style: FilledButton.styleFrom(
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Turnuvayı Kaydet'),
              ),
            ],
          ),
          if (_isLoading)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: cs.surface.withValues(alpha: 0.55),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
