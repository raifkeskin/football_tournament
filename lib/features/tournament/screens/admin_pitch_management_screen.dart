import 'package:flutter/material.dart';

import '../../../core/utils/resilient_stream.dart';
import '../../../core/widgets/master_class_app_bar.dart';
import '../models/league_extras.dart';
import '../../../core/services/app_session.dart';
import '../services/interfaces/i_league_service.dart';
import '../../../core/services/service_locator.dart';

class AdminPitchManagementScreen extends StatefulWidget {
  const AdminPitchManagementScreen({super.key});

  @override
  State<AdminPitchManagementScreen> createState() =>
      _AdminPitchManagementScreenState();
}

class _AdminPitchManagementScreenState
    extends State<AdminPitchManagementScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  bool _busy = false;

  static const _turkiyeIlleri = <String>[
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

  static const _istanbulIlceleri = <String>[
    'Adalar',
    'Arnavutköy',
    'Ataşehir',
    'Avcılar',
    'Bağcılar',
    'Bahçelievler',
    'Bakırköy',
    'Başakşehir',
    'Bayrampaşa',
    'Beşiktaş',
    'Beykoz',
    'Beylikdüzü',
    'Beyoğlu',
    'Büyükçekmece',
    'Çatalca',
    'Çekmeköy',
    'Esenler',
    'Esenyurt',
    'Eyüpsultan',
    'Fatih',
    'Gaziosmanpaşa',
    'Güngören',
    'Kadıköy',
    'Kağıthane',
    'Kartal',
    'Küçükçekmece',
    'Maltepe',
    'Pendik',
    'Sancaktepe',
    'Sarıyer',
    'Silivri',
    'Sultanbeyli',
    'Sultangazi',
    'Şile',
    'Şişli',
    'Tuzla',
    'Ümraniye',
    'Üsküdar',
    'Zeytinburnu',
  ];

  static const _bgDark = Color(0xFF0F172A);
  static const _accent = Color(0xFF10B981);
  static const _mid = Color(0xFF94A3B8);

  // Uygulama arka plandan dönünce kopan bağlantı otomatik yenilenir.
  late final Stream<List<Pitch>> _pitches = resilientStream(
    () => _leagueService.watchPitches(),
  );

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : null,
      ),
    );
  }

  /// Fikstür ekranındaki ortak popup: ortada açılan gradientli dialog.
  Future<T?> _showCenteredDialog<T>({
    required Widget Function(BuildContext ctx, StateSetter setLocal) builder,
    bool tall = false,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final mq = MediaQuery.of(ctx);
          final maxH = mq.size.height - mq.viewInsets.bottom - 80;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            child: Container(
              constraints: BoxConstraints(maxHeight: maxH),
              height: tall ? maxH * 0.85 : null,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E293B), Color(0xFF064E3B)],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 15,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: builder(ctx, setLocal),
            ),
          );
        },
      ),
    );
  }

  Widget _dialogHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: _accent, size: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white24, height: 1),
        ],
      ),
    );
  }

  ButtonStyle get _primaryStyle => ElevatedButton.styleFrom(
    backgroundColor: _accent,
    foregroundColor: Colors.white,
    disabledBackgroundColor: _accent.withValues(alpha: 0.5),
    minimumSize: const Size(double.infinity, 50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  ButtonStyle get _cancelStyle => OutlinedButton.styleFrom(
    foregroundColor: Colors.white70,
    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
    minimumSize: const Size(double.infinity, 50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  InputDecoration _fieldDeco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    filled: true,
    fillColor: Colors.black.withValues(alpha: 0.3),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _accent, width: 1.5),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    ),
  );

  Future<String?> _pickFromList({
    required String title,
    required List<String> items,
    required String searchHint,
    String? selected,
  }) {
    var query = '';
    return _showCenteredDialog<String>(
      tall: true,
      builder: (ctx, setLocal) {
        final q = query.trim().toLowerCase();
        final filtered = items
            .where((e) => e.toLowerCase().contains(q))
            .toList();
        return Column(
          children: [
            _dialogHeader(Icons.location_city_outlined, title),
            TextField(
              autofocus: true,
              onChanged: (v) => setLocal(() => query = v),
              decoration: _fieldDeco(searchHint, Icons.search_rounded),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: Colors.white12, height: 1),
                itemBuilder: (context, index) {
                  final value = filtered[index];
                  final isSelected = (selected ?? '').trim() == value;
                  return ListTile(
                    dense: true,
                    title: Text(
                      value,
                      style: TextStyle(
                        color: isSelected ? _accent : Colors.white,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_rounded, color: _accent)
                        : null,
                    onTap: () => Navigator.pop(ctx, value),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Saha ekleme ve düzenleme için ortak form ([editing] null ise ekleme).
  Future<void> _openPitchForm({Pitch? editing}) async {
    final isEdit = editing != null;
    final nameController = TextEditingController(text: editing?.name ?? '');
    final locationController = TextEditingController(
      text: editing?.location ?? '',
    );
    final districtController = TextEditingController(
      text: editing?.country ?? '',
    );
    var selectedCity = (editing?.city ?? '').trim();
    var selectedDistrict = (editing?.country ?? '').trim();
    var saving = false;

    Future<void> save(BuildContext ctx, StateSetter setLocal) async {
      final name = nameController.text.trim();
      final loc = locationController.text.trim();
      final district = selectedCity == 'İstanbul'
          ? selectedDistrict
          : districtController.text.trim();
      if (name.isEmpty) {
        _snack('Saha adı boş olamaz.', error: true);
        return;
      }
      setLocal(() => saving = true);
      try {
        if (isEdit) {
          await _leagueService.updatePitch(
            pitchId: editing.id,
            name: name,
            city: selectedCity,
            country: district,
            location: loc,
          );
        } else {
          await _leagueService.addPitch(
            name: name,
            city: selectedCity.isEmpty ? null : selectedCity,
            country: district.isEmpty ? null : district,
            location: loc.isEmpty ? null : loc,
          );
        }
        if (ctx.mounted) Navigator.pop(ctx);
        if (mounted) _snack(isEdit ? 'Saha güncellendi.' : 'Saha eklendi.');
      } catch (e) {
        if (mounted) _snack('Hata: $e', error: true);
        if (ctx.mounted) setLocal(() => saving = false);
      }
    }

    await _showCenteredDialog<void>(
      builder: (ctx, setLocal) {
        Widget picker({
          required String label,
          required IconData icon,
          required String value,
          required String placeholder,
          required VoidCallback onTap,
        }) {
          return InkWell(
            onTap: saving ? null : onTap,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: _fieldDeco(label, icon),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value.isEmpty ? placeholder : value,
                      style: TextStyle(
                        color: value.isEmpty ? Colors.white54 : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.white70),
                ],
              ),
            ),
          );
        }

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dialogHeader(
                isEdit ? Icons.edit_location_alt_outlined : Icons.stadium,
                isEdit ? 'Sahayı Düzenle' : 'Saha Ekle',
              ),
              TextField(
                controller: nameController,
                enabled: !saving,
                decoration: _fieldDeco('Saha Adı', Icons.stadium_outlined),
              ),
              const SizedBox(height: 12),
              picker(
                label: 'İl',
                icon: Icons.location_city_outlined,
                value: selectedCity,
                placeholder: 'İl seç',
                onTap: () async {
                  final picked = await _pickFromList(
                    title: 'İl Seç',
                    items: _turkiyeIlleri,
                    searchHint: 'İl ara...',
                    selected: selectedCity,
                  );
                  if (picked == null) return;
                  setLocal(() {
                    if (picked != selectedCity) {
                      selectedDistrict = '';
                      districtController.clear();
                    }
                    selectedCity = picked;
                  });
                },
              ),
              const SizedBox(height: 12),
              if (selectedCity == 'İstanbul')
                picker(
                  label: 'İlçe',
                  icon: Icons.place_outlined,
                  value: selectedDistrict,
                  placeholder: 'İlçe seç',
                  onTap: () async {
                    final picked = await _pickFromList(
                      title: 'İlçe Seç',
                      items: _istanbulIlceleri,
                      searchHint: 'İlçe ara...',
                      selected: selectedDistrict,
                    );
                    if (picked == null) return;
                    setLocal(() => selectedDistrict = picked);
                  },
                )
              else
                TextField(
                  controller: districtController,
                  enabled: !saving,
                  decoration: _fieldDeco('İlçe', Icons.place_outlined),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                enabled: !saving,
                decoration: _fieldDeco(
                  'Konum (harita bağlantısı)',
                  Icons.map_outlined,
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                style: _primaryStyle,
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
                    : Text(
                        isEdit ? 'GÜNCELLE' : 'KAYDET',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: _cancelStyle,
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text(
                  'VAZGEÇ',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        );
      },
    );

    // Dialog kapanış animasyonu bitene kadar alanlar controller'ı kullanır.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      nameController.dispose();
      locationController.dispose();
      districtController.dispose();
    });
  }

  Future<void> _deletePitch(Pitch p) async {
    final name = p.name.trim().isEmpty ? p.id : p.name.trim();
    final ok = await _showCenteredDialog<bool>(
      builder: (ctx, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dialogHeader(Icons.delete_outline_rounded, 'Saha Sil'),
          Text(
            "'$name' sahasını silmek istediğinize emin misiniz? "
            'Bu işlem geri alınamaz.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            style: _primaryStyle.copyWith(
              backgroundColor: const WidgetStatePropertyAll(Color(0xFFDC2626)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'SİL',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: _cancelStyle,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'VAZGEÇ',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _leagueService.deletePitch(p.id);
      if (mounted) _snack('Saha silindi.');
    } catch (e) {
      if (mounted) {
        _snack(
          'Saha silinemedi. Bu sahaya bağlı maçlar olabilir.\n$e',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _pitchCard(Pitch p) {
    final name = p.name.trim();
    final region = [
      if (p.city.trim().isNotEmpty) p.city.trim(),
      if (p.country.trim().isNotEmpty) p.country.trim(),
    ].join(' / ');
    final hasMap = p.location.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.stadium_outlined, color: _accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? p.id : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (region.isNotEmpty || hasMap) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (region.isNotEmpty)
                        Flexible(
                          child: Text(
                            region,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _mid, fontSize: 12),
                          ),
                        ),
                      if (hasMap) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.map_outlined, color: _mid, size: 14),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _actionButton(
            icon: Icons.edit_outlined,
            tooltip: 'Düzenle',
            color: Colors.white70,
            onTap: _busy ? null : () => _openPitchForm(editing: p),
          ),
          const SizedBox(width: 6),
          _actionButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Sil',
            color: const Color(0xFFF87171),
            onTap: _busy ? null : () => _deletePitch(p),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    return Scaffold(
      backgroundColor: _bgDark,
      extendBodyBehindAppBar: true,
      appBar: MasterClassAppBar(
        title: 'Saha Yönetimi',
        actions: [
          if (isAdmin)
            IconButton(
              onPressed: _busy ? null : () => _openPitchForm(),
              icon: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 28,
              ),
              tooltip: 'Saha Ekle',
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.15,
              child: Image.asset(
                'assets/images/background_ball.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          SafeArea(
            child: !isAdmin
                ? const Center(
                    child: Text(
                      'Bu sayfa sadece adminler içindir.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : StreamBuilder<List<Pitch>>(
                    stream: _pitches,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: _accent),
                        );
                      }
                      final pitches = [...snapshot.data!]
                        ..sort(
                          (a, b) => a.name.toLowerCase().compareTo(
                            b.name.toLowerCase(),
                          ),
                        );
                      if (pitches.isEmpty) {
                        return const Center(
                          child: Text(
                            'Saha bulunamadı.\nSağ üstteki + ile saha ekleyin.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54),
                          ),
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: pitches.map(_pitchCard).toList(),
                      );
                    },
                  ),
          ),
          if (_busy)
            const Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: Color(0x660F172A),
                  child: Center(
                    child: CircularProgressIndicator(color: _accent),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
