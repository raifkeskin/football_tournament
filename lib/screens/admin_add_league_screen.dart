import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/league.dart';
import '../services/app_session.dart';
import '../services/image_upload_service.dart';
import '../services/interfaces/i_league_service.dart';
import '../services/service_locator.dart';

/// Admin için turnuva ekleme formu.
class AdminAddLeagueScreen extends StatefulWidget {
  const AdminAddLeagueScreen({super.key});

  @override
  State<AdminAddLeagueScreen> createState() => _AdminAddLeagueScreenState();
}

class _AdminAddLeagueScreenState extends State<AdminAddLeagueScreen> {
  final _leagueNameController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _managerFullNameController = TextEditingController();
  final _managerPhoneController = TextEditingController();
  final _matchPeriodDurationController = TextEditingController(text: '25');
  final _startingPlayerCountController = TextEditingController(text: '11');
  final _subPlayerCountController = TextEditingController(text: '7');
  final _groupCountController = TextEditingController(text: '1');
  final _teamsPerGroupController = TextEditingController(text: '4');
  final _cityController = TextEditingController();
  final _accessCodeController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _instagramController = TextEditingController();
  final _picker = ImagePicker();
  final _imageUploadService = ImgBBUploadService();
  final ILeagueService _leagueService = ServiceLocator.leagueService;

  XFile? _leagueLogo;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isPrivate = false;
  bool _isLoading = false;

  static const List<String> _turkiyeIlleri = <String>[
    'Adana',
    'Adıyaman',
    'Afyonkarahisar',
    'Ağrı',
    'Amasya',
    'Ankara',
    'Antalya',
    'Artvin',
    'Aydın',
    'Balıkesir',
    'Bilecik',
    'Bingöl',
    'Bitlis',
    'Bolu',
    'Burdur',
    'Bursa',
    'Çanakkale',
    'Çankırı',
    'Çorum',
    'Denizli',
    'Diyarbakır',
    'Edirne',
    'Elazığ',
    'Erzincan',
    'Erzurum',
    'Eskişehir',
    'Gaziantep',
    'Giresun',
    'Gümüşhane',
    'Hakkâri',
    'Hatay',
    'Isparta',
    'Mersin',
    'İstanbul',
    'İzmir',
    'Kars',
    'Kastamonu',
    'Kayseri',
    'Kırklareli',
    'Kırşehir',
    'Kocaeli',
    'Konya',
    'Kütahya',
    'Malatya',
    'Manisa',
    'Kahramanmaraş',
    'Mardin',
    'Muğla',
    'Muş',
    'Nevşehir',
    'Niğde',
    'Ordu',
    'Rize',
    'Sakarya',
    'Samsun',
    'Siirt',
    'Sinop',
    'Sivas',
    'Tekirdağ',
    'Tokat',
    'Trabzon',
    'Tunceli',
    'Şanlıurfa',
    'Uşak',
    'Van',
    'Yozgat',
    'Zonguldak',
    'Aksaray',
    'Bayburt',
    'Karaman',
    'Kırıkkale',
    'Batman',
    'Şırnak',
    'Bartın',
    'Ardahan',
    'Iğdır',
    'Yalova',
    'Karabük',
    'Kilis',
    'Osmaniye',
    'Düzce',
  ];

  Future<String?> _sehirSec({String? initialValue}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? _turkiyeIlleri
                : _turkiyeIlleri
                    .where((c) => c.toLowerCase().contains(q))
                    .toList();
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Şehir Ara',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setModalState(() => query = v),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final city = filtered[index];
                          final selected =
                              (initialValue ?? '').trim().toLowerCase() ==
                                  city.toLowerCase();
                          return ListTile(
                            title: Text(city),
                            trailing: selected
                                ? const Icon(Icons.check_rounded)
                                : null,
                            onTap: () => Navigator.pop(context, city),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _leagueNameController.dispose();
    _subtitleController.dispose();
    _managerFullNameController.dispose();
    _managerPhoneController.dispose();
    _matchPeriodDurationController.dispose();
    _startingPlayerCountController.dispose();
    _subPlayerCountController.dispose();
    _groupCountController.dispose();
    _teamsPerGroupController.dispose();
    _cityController.dispose();
    _accessCodeController.dispose();
    _youtubeController.dispose();
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
    final managerFullName = _managerFullNameController.text.trim();
    final managerPhone = _managerPhoneController.text.trim();
    final city = _cityController.text.trim();
    final accessCode = _accessCodeController.text.trim();
    final matchPeriodDuration =
        int.tryParse(_matchPeriodDurationController.text.trim()) ?? 25;
    final startingPlayerCount =
        int.tryParse(_startingPlayerCountController.text.trim()) ?? 11;
    final subPlayerCount =
        int.tryParse(_subPlayerCountController.text.trim()) ?? 7;

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

    if (_isPrivate && accessCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Özel turnuva için erişim kodu zorunludur.'),
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
        id: '',
        name: leagueName,
        subtitle: subtitle.isEmpty ? null : subtitle,
        logoUrl: logoUrl,
        country: 'Türkiye',
        city: city.isEmpty ? null : city,
        managerFullName: managerFullName.isEmpty ? null : managerFullName,
        managerPhoneRaw10:
            managerPhone.isEmpty ? null : normalizePhoneToRaw10(managerPhone),
        startDate: _startDate,
        endDate: _endDate,
        isPrivate: _isPrivate,
        accessCode: _isPrivate ? accessCode : null,
        youtubeUrl: _youtubeController.text.trim(),
        instagramUrl: _instagramController.text.trim(),
        matchPeriodDuration: matchPeriodDuration <= 0 ? 25 : matchPeriodDuration,
        startingPlayerCount: startingPlayerCount <= 0 ? 11 : startingPlayerCount,
        subPlayerCount: subPlayerCount < 0 ? 7 : subPlayerCount,
        numberOfGroups: int.tryParse(_groupCountController.text) ?? 1,
        groups: List.generate(
          int.tryParse(_groupCountController.text) ?? 1,
          (i) => String.fromCharCode(65 + i),
        ),
        groupCount: int.tryParse(_groupCountController.text) ?? 1,
        teamsPerGroup: int.tryParse(_teamsPerGroupController.text) ?? 4,
      );

      final newId = await _leagueService.addLeague(league);
      if (newId.trim().isEmpty) {
        throw Exception('Turnuva kaydı başarısız (id dönmedi).');
      }

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
        _managerFullNameController.clear();
        _managerPhoneController.clear();
        _matchPeriodDurationController.text = '25';
        _startingPlayerCountController.text = '11';
        _subPlayerCountController.text = '7';
        _groupCountController.text = '1';
        _teamsPerGroupController.text = '4';
        _cityController.clear();
        _accessCodeController.clear();
        _isPrivate = false;
        _youtubeController.clear();
        _instagramController.clear();
        _leagueLogo = null;
        _startDate = null;
        _endDate = null;
      });
    } catch (e) {
      print('Turnuva ekleme hatası: $e');
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
                controller: _managerFullNameController,
                decoration: const InputDecoration(
                  labelText: 'Turnuva Sorumlusu (Ad Soyad)',
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
              TextField(
                controller: _cityController,
                decoration: const InputDecoration(
                  labelText: 'Şehir',
                  border: OutlineInputBorder(),
                ),
                readOnly: true,
                onTap: _isLoading
                    ? null
                    : () async {
                        final picked = await _sehirSec(
                          initialValue: _cityController.text,
                        );
                        if (picked == null || !mounted) return;
                        setState(() => _cityController.text = picked);
                      },
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _matchPeriodDurationController,
                decoration: const InputDecoration(
                  labelText: 'Maç Süresi (Dakika)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startingPlayerCountController,
                      decoration: const InputDecoration(
                        labelText: 'Sahadaki Oyuncu',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      enabled: !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _subPlayerCountController,
                      decoration: const InputDecoration(
                        labelText: 'Yedek Oyuncu',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      enabled: !_isLoading,
                    ),
                  ),
                ],
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
              const SizedBox(height: 8),
              SwitchListTile(
                value: _isPrivate,
                onChanged: _isLoading
                    ? null
                    : (v) {
                        setState(() => _isPrivate = v);
                      },
                title: const Text('Özel Turnuva'),
                contentPadding: EdgeInsets.zero,
              ),
              if (_isPrivate) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _accessCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Erişim Kodu',
                    hintText: 'Örn: 437153',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  enabled: !_isLoading,
                ),
              ],
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
