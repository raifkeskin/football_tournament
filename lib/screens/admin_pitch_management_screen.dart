import 'package:flutter/material.dart';

import '../models/league_extras.dart';
import '../services/app_session.dart';
import '../services/interfaces/i_league_service.dart';
import '../services/service_locator.dart';

class AdminPitchManagementScreen extends StatefulWidget {
  const AdminPitchManagementScreen({super.key});

  @override
  State<AdminPitchManagementScreen> createState() =>
      _AdminPitchManagementScreenState();
}

class _AdminPitchManagementScreenState extends State<AdminPitchManagementScreen> {
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

  void _snack(String text, {Color? bg}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: bg),
    );
  }

  Future<String?> _pickFromList({
    required String title,
    required List<String> items,
    required String searchHint,
    String? selected,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setLocal) {
            final filtered = items
                .where(
                  (e) => e.toLowerCase().contains(query.trim().toLowerCase()),
                )
                .toList();
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: TextField(
                        autofocus: true,
                        onChanged: (v) => setLocal(() => query = v),
                        decoration: InputDecoration(
                          hintText: searchHint,
                          prefixIcon: const Icon(Icons.search_rounded),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final value = filtered[index];
                          final isSelected = (selected ?? '').trim() == value;
                          return ListTile(
                            title: Text(value),
                            trailing: isSelected
                                ? const Icon(Icons.check_rounded)
                                : null,
                            onTap: () => Navigator.pop(context, value),
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

  Future<void> _openAddPitchPopup() async {
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    var selectedCity = '';
    var selectedCountry = '';
    var saving = false;

    Future<void> save(StateSetter setLocal) async {
      final name = nameController.text.trim();
      final loc = locationController.text.trim();
      if (name.isEmpty) {
        _snack('Saha adı boş olamaz.');
        return;
      }
      setLocal(() => saving = true);
      setState(() => _busy = true);
      try {
        await _leagueService.addPitch(
          name: name,
          city: selectedCity.trim().isEmpty ? null : selectedCity.trim(),
          country:
              selectedCountry.trim().isEmpty ? null : selectedCountry.trim(),
          location: loc.isEmpty ? null : loc,
        );
        if (!mounted) return;
        Navigator.pop(context);
        _snack(
          'Saha eklendi.',
          bg: Theme.of(context).colorScheme.primary,
        );
      } catch (e) {
        _snack('Hata: $e', bg: Theme.of(context).colorScheme.error);
      } finally {
        if (mounted) setState(() => _busy = false);
        setLocal(() => saving = false);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    enabled: !saving,
                    decoration: const InputDecoration(labelText: 'Saha Adı'),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: saving
                        ? null
                        : () async {
                            final picked = await _pickFromList(
                              title: 'İl Seç',
                              items: _turkiyeIlleri,
                              searchHint: 'İl ara...',
                              selected: selectedCity,
                            );
                            if (picked == null) return;
                            setLocal(() {
                              selectedCity = picked;
                              selectedCountry = '';
                            });
                          },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'İl',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_city_outlined),
                      ),
                      child: Text(
                        selectedCity.trim().isEmpty ? 'İl seç' : selectedCity,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (selectedCity.trim() == 'İstanbul')
                    InkWell(
                      onTap: saving
                          ? null
                          : () async {
                              final picked = await _pickFromList(
                                title: 'İlçe Seç',
                                items: _istanbulIlceleri,
                                searchHint: 'İlçe ara...',
                                selected: selectedCountry,
                              );
                              if (picked == null) return;
                              setLocal(() => selectedCountry = picked);
                            },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'İlçe',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.place_outlined),
                        ),
                        child: Text(
                          selectedCountry.trim().isEmpty
                              ? 'İlçe seç'
                              : selectedCountry,
                        ),
                      ),
                    )
                  else
                    TextField(
                      enabled: !saving,
                      onChanged: (v) => selectedCountry = v,
                      decoration: const InputDecoration(
                        labelText: 'İlçe',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: locationController,
                    enabled: !saving,
                    decoration: const InputDecoration(labelText: 'Konum'),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: saving ? null : () => save(setLocal),
                    label: const Text('KAYDET'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    nameController.dispose();
    locationController.dispose();
  }

  Future<void> _deletePitch(String pitchId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Saha Sil'),
        content: Text(
          "'$name' sahasını silmek istediğinize emin misiniz? Bu işlem geri alınamaz.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _leagueService.deletePitch(pitchId);
      if (!mounted) return;
      _snack(
        'Saha silindi.',
        bg: Theme.of(context).colorScheme.primary,
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Hata: $e', bg: Theme.of(context).colorScheme.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saha Yönetimi'),
        actions: [
          if (isAdmin)
            IconButton(
              onPressed: _busy ? null : _openAddPitchPopup,
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: !isAdmin
          ? const Center(child: Text('Bu sayfa sadece adminler içindir.'))
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    StreamBuilder<List<Pitch>>(
                      stream: _leagueService.watchPitches(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final pitches = snapshot.data ?? const <Pitch>[];
                        if (pitches.isEmpty) {
                          return const Center(child: Text('Saha bulunamadı.'));
                        }
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: pitches.length,
                            separatorBuilder: (context, index) =>
                                Divider(height: 1, color: cs.outlineVariant),
                            itemBuilder: (context, index) {
                              final p = pitches[index];
                              final name = p.name.trim();
                              final city = p.city.trim();
                              final country = p.country.trim();
                              final location = p.location.trim();
                              final region = [
                                if (city.isNotEmpty) city,
                                if (country.isNotEmpty) country,
                              ].join(' / ');
                              final subtitle = [
                                if (region.isNotEmpty) region,
                                if (location.isNotEmpty) location,
                              ].join('\n');
                              return ListTile(
                                leading: const Icon(Icons.location_on_outlined),
                                title: Text(name.isEmpty ? p.id : name),
                                subtitle:
                                    subtitle.isEmpty ? null : Text(subtitle),
                                trailing: IconButton(
                                  onPressed:
                                      _busy ? null : () => _deletePitch(p.id, name),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: cs.error,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (_busy)
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
