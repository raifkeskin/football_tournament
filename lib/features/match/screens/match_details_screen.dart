import 'package:flutter/material.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../../tournament/models/league_extras.dart';
import '../models/match.dart';
import '../models/match_media.dart';
import '../../team/models/team.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/image_upload_service.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import 'admin_match_event_screen.dart';
import '../../tournament/screens/formation_tab.dart';

// --- YARDIMCI WIDGETLAR ---

class _SecondYellowCardIcon extends StatelessWidget {
  const _SecondYellowCardIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 20,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.white24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.yellow, Colors.red],
          stops: [0.45, 0.55],
        ),
      ),
    );
  }
}

class _TeamInfo extends StatelessWidget {
  final String name;
  final String logoUrl;

  const _TeamInfo({required this.name, required this.logoUrl});

  String _smartAbbreviate(String val) {
    if (val.length <= 20) return val;
    return val
        .replaceAll(RegExp(r'Masterlar(ı)?', caseSensitive: false), 'M.')
        .replaceAll(RegExp(r'Master', caseSensitive: false), 'M.')
        .replaceAll(RegExp(r'Spor Kulübü', caseSensitive: false), 'SK')
        .replaceAll(RegExp(r'Futbol Kulübü', caseSensitive: false), 'FK')
        .replaceAll(RegExp(r'Gençlik', caseSensitive: false), 'Gnç.')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _smartAbbreviate(name);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        WebSafeImage(
          url: logoUrl,
          width: 54,
          height: 54,
          isCircle: true,
          fallbackIconSize: 26,
        ),
        const SizedBox(height: 4),
        Text(
          displayName,
          textAlign: TextAlign.center,
          softWrap: true,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
            shadows: [
              Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
            ],
          ),
        ),
      ],
    );
  }
}

// --- ANA EKRAN ---

class MatchDetailsScreen extends StatefulWidget {
  final MatchModel match;
  final bool isAdmin;
  final int initialTabIndex;
  const MatchDetailsScreen({
    super.key,
    required this.match,
    this.isAdmin = false,
    this.initialTabIndex = 0,
  });

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen>
    with SingleTickerProviderStateMixin {
  final ITeamService _teamService = ServiceLocator.teamService;
  final IMatchService _matchService = ServiceLocator.matchService;
  final ILeagueService _leagueService = ServiceLocator.leagueService;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  int _refreshKey = 0;

  void _triggerRefresh() {
    if (mounted) {
      setState(() => _refreshKey++);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _friendlyLoadError(Object? error) {
    final s = (error ?? '').toString();
    final lower = s.toLowerCase();
    if (lower.contains('permission-denied')) {
      return 'Yetki hatası. Giriş yapıldı mı ve kullanıcı yetkisi doğru mu kontrol edin.\n\n$s';
    }
    if (lower.contains('requires an index') ||
        lower.contains('failed-precondition')) {
      return 'Sorgu için Firestore index gerekli olabilir.\n\n$s';
    }
    if (lower.contains('unavailable') || lower.contains('network')) {
      return 'Bağlantı hatası. İnternet bağlantısını kontrol edin.\n\n$s';
    }
    return s;
  }

  String _resolvePitchLocation({
    required List<Pitch> pitches,
    required String pitchId,
    required String pitchName,
  }) {
    final id = pitchId.trim();
    final name = pitchName.trim();

    if (id.isNotEmpty) {
      for (final p in pitches) {
        if (p.id.trim() == id) {
          return p.location;
        }
      }
    }

    if (name.isNotEmpty) {
      for (final p in pitches) {
        if (p.name.trim().toLowerCase() == name.toLowerCase()) {
          return p.location;
        }
      }
    }

    return '';
  }

  Future<void> _openPitchLocation(
    BuildContext context,
    String rawLocation,
  ) async {
    if (rawLocation.isEmpty) return;
    final uri = Uri.tryParse(rawLocation);
    if (uri == null || uri.scheme.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Konum linki geçersiz.')));
      return;
    }

    try {
      final can = await canLaunchUrl(uri);
      if (!can) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Link açılamadı.')));
        return;
      }
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (!ok) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Link açılamadı.')));
      }
    }
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty || dateStr == '__NO_DATE__') {
      return 'Tarih Belirlenmedi';
    }
    try {
      final p = dateStr.split('-');
      if (p.length != 3) return dateStr;
      return "${p[2]}/${p[1]}/${p[0]}";
    } catch (e) {
      return dateStr;
    }
  }

  Widget? _buildTabFab({required MatchModel match, required int tabIndex}) {
    if (tabIndex == 1 || tabIndex == 3) return null;

    if (tabIndex == 0) {
      return _SpeedDialFab(
        key: const ValueKey('fab_detail'),
        actions: [
          _SpeedDialAction(
            label: 'Maç Detayı Gir',
            icon: Icons.edit_note_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminMatchEventScreen(match: match),
              ),
            ),
          ),
          _SpeedDialAction(
            label: 'Stad Seç',
            icon: Icons.location_on,
            onTap: () => _openPitchEditor(match),
          ),
        ],
      );
    }

    if (tabIndex == 2) {
      return _SpeedDialFab(
        key: const ValueKey('fab_highlights'),
        actions: [
          _SpeedDialAction(
            label: 'Medya Ekle',
            icon: Icons.perm_media_rounded,
            onTap: () => _openHighlightMediaAdder(match, _triggerRefresh),
          ),
        ],
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;

    return StreamBuilder<MatchModel>(
      stream: _matchService.watchMatch(widget.match.id),
      initialData: widget.match,
      builder: (context, matchSnap) {
        if (matchSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Maç Detayı')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Maç verisi yüklenemedi.\n\n${_friendlyLoadError(matchSnap.error)}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final m = matchSnap.data ?? widget.match;

        final bool isSuperAdmin = session.isAdmin;
        final bool isTeamManager =
            session.teamId == m.homeTeamId || session.teamId == m.awayTeamId;
        final bool isAdminAccess = isSuperAdmin || isTeamManager;

        return StreamBuilder<List<Team>>(
          stream: _teamService.watchAllTeams(),
          builder: (context, teamsSnap) {
            if (teamsSnap.hasError) {
              return Scaffold(
                appBar: AppBar(title: const Text('Maç Detayı')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Takım verileri yüklenemedi.\n\n${_friendlyLoadError(teamsSnap.error)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            final Map<String, String> logoMap = {};
            final Map<String, String> nameMap = {};
            if (teamsSnap.hasData) {
              for (final team in teamsSnap.data!) {
                logoMap[team.id] = team.logoUrl;
                nameMap[team.id] = team.name;
              }
            }

            final homeLogo = (logoMap[m.homeTeamId] ?? '').trim();
            final awayLogo = (logoMap[m.awayTeamId] ?? '').trim();
            final homeName = (nameMap[m.homeTeamId] ?? '').trim().isEmpty
                ? 'Ev Sahibi'
                : (nameMap[m.homeTeamId] ?? '').trim();
            final awayName = (nameMap[m.awayTeamId] ?? '').trim().isEmpty
                ? 'Deplasman'
                : (nameMap[m.awayTeamId] ?? '').trim();

            return Scaffold(
              extendBodyBehindAppBar: true,
              appBar: AppBar(
                title: const Text(
                  'Maç Detayı',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                centerTitle: true,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
              ),
              floatingActionButton: !isSuperAdmin
                  ? null
                  : _buildTabFab(match: m, tabIndex: _tabController.index),
              body: Column(
                children: [
                  Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/anasayfa.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          top:
                              MediaQuery.of(context).padding.top +
                              (kToolbarHeight - 16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _TeamInfo(
                                      name: homeName,
                                      logoUrl: homeLogo,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 0,
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          "${m.homeScore} - ${m.awayScore}",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 38,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black,
                                                blurRadius: 10,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (m.status == MatchStatus.live)
                                          const Text(
                                            "CANLI",
                                            style: TextStyle(
                                              color: Colors.amber,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 10,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: _TeamInfo(
                                      name: awayName,
                                      logoUrl: awayLogo,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.access_time_filled_rounded,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "${_formatDate(m.matchDate ?? '')}  |  ${m.matchTime}",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 10,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if ((m.pitchId ?? '').isNotEmpty) ...[
                                    const SizedBox(width: 12),
                                    const Text(
                                      "|",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black,
                                            blurRadius: 10,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(
                                      Icons.location_on_rounded,
                                      size: 14,
                                      color: Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: StreamBuilder<List<Pitch>>(
                                        stream: _leagueService.watchPitches(),
                                        builder: (context, pitchSnap) {
                                          final pitchId = (m.pitchId ?? '')
                                              .trim();
                                          final pitches =
                                              pitchSnap.data ?? const <Pitch>[];

                                          // pitchId ile eşleşen stadı bul
                                          String displayPitchName =
                                              'Bilinmeyen Saha';
                                          String location = '';

                                          for (final p in pitches) {
                                            if (p.id == pitchId) {
                                              displayPitchName = p.name;
                                              location = p.location;
                                              break;
                                            }
                                          }

                                          return InkWell(
                                            onTap: location.isEmpty
                                                ? null
                                                : () => _openPitchLocation(
                                                    context,
                                                    location,
                                                  ),
                                            child: Text(
                                              displayPitchName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black,
                                                    blurRadius: 10,
                                                    offset: Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  TabBar(
                    controller: _tabController,
                    labelStyle: const TextStyle(
                      fontFamily: 'Batangas',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontFamily: 'Batangas',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    tabs: const [
                      Tab(text: 'Detay'),
                      Tab(text: 'Kadrolar'),
                      Tab(text: 'Önemli Anlar'),
                      Tab(text: 'Diziliş'),
                    ],
                  ),
                  Expanded(
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _DetailTab(match: m),

                          // İŞTE DEĞİŞİKLİK YAPILAN YER: YENİ _LineupTab BAĞLANTISI
                          _LineupTab(
                            match: m,
                            isAdminAccess: isAdminAccess,
                            homeName: homeName,
                            awayName: awayName,
                          ),

                          _HighlightsTab(
                            key: ValueKey(_refreshKey),
                            match: m,
                            isSuperAdmin: isSuperAdmin,
                            onDataChanged: _triggerRefresh,
                          ),
                          FormationTab.fromMatch(
                            match: m,
                            isTeamManager: isAdminAccess,
                            homeName: homeName,
                            awayName: awayName,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openPitchEditor(MatchModel m) async {
    final list = await _leagueService.listPitchesOnce();
    String? sel = m.pitchName;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setS) {
          return AlertDialog(
            title: const Text('Saha Seçimi'),
            content: DropdownButton<String>(
              value: list.contains(sel) ? sel : null,
              isExpanded: true,
              items: list
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setS(() => sel = v),
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  await _matchService.updateMatchPitchName(
                    matchId: m.id,
                    pitchName: sel,
                  );
                  Navigator.pop(c);
                },
                child: const Text('KAYDET'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openHighlightMediaAdder(
    MatchModel matchModel,
    VoidCallback onSuccess,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) =>
          _MediaAdderDialog(match: matchModel, onSuccess: onSuccess),
    );
  }
}

class _MediaAdderDialog extends StatefulWidget {
  final MatchModel match;
  final VoidCallback onSuccess;
  const _MediaAdderDialog({required this.match, required this.onSuccess});

  @override
  State<_MediaAdderDialog> createState() => _MediaAdderDialogState();
}

class _MediaAdderDialogState extends State<_MediaAdderDialog> {
  String _selectedType = 'Maç Yayın Linki';
  final _urlCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isHomeTeam = true;
  File? _pickedFile;
  bool _isUploading = false;

  final List<String> _types = [
    'Maç Yayın Linki',
    'Takım Fotosu',
    'Önemli An',
    'Maçın Adamı',
    'Diğer',
  ];

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    return AlertDialog(
      title: const Text('Medya Ekle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedType,
              items: _types
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedType = v;
                    _pickedFile = null;
                  });
                }
              },
              decoration: const InputDecoration(labelText: 'Medya Türü'),
            ),
            const SizedBox(height: 16),
            if (_selectedType == 'Maç Yayın Linki')
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(labelText: 'YouTube URL'),
              )
            else ...[
              if (_pickedFile != null)
                Image.file(_pickedFile!, height: 100, fit: BoxFit.cover),
              ElevatedButton.icon(
                onPressed: () async {
                  final picked = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 85,
                  );
                  if (picked != null) {
                    setState(() => _pickedFile = File(picked.path));
                  }
                },
                icon: const Icon(Icons.image),
                label: const Text('Galeriden Seç'),
              ),
            ],
            const SizedBox(height: 16),
            if (_selectedType == 'Takım Fotosu')
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<bool>(
                      title: const Text(
                        'Ev Sahibi',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: true,
                      groupValue: _isHomeTeam,
                      onChanged: (v) => setState(() => _isHomeTeam = v!),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<bool>(
                      title: const Text(
                        'Deplasman',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: false,
                      groupValue: _isHomeTeam,
                      onChanged: (v) => setState(() => _isHomeTeam = v!),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Açıklama (Opsiyonel)',
              ),
              maxLines: 2,
            ),
            if (_isUploading) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _save,
          child: const Text('KAYDET'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final m = widget.match;
    String finalUrl = '';

    if (_selectedType == 'Maç Yayın Linki') {
      finalUrl = _urlCtrl.text.trim();
      if (finalUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen geçerli bir yayın linki girin.'),
          ),
        );
        return;
      }
    } else {
      if (_pickedFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen bir görsel seçin.')),
        );
        return;
      }
      setState(() => _isUploading = true);
      try {
        final uploadedUrl = await ImgBBUploadService().uploadImage(
          _pickedFile!,
        );
        if (uploadedUrl == null) {
          throw Exception('Görsel yüklenemedi.');
        }
        finalUrl = uploadedUrl;
      } catch (e) {
        setState(() => _isUploading = false);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Yükleme hatası: $e')));
        }
        return;
      }
    }

    final media = MatchMediaModel(
      id: '',
      matchId: m.id,
      mediaType: _selectedType,
      url: finalUrl,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      teamId: _selectedType == 'Takım Fotosu'
          ? (_isHomeTeam ? m.homeTeamId : m.awayTeamId)
          : null,
      createdAt: DateTime.now(),
    );

    try {
      await ServiceLocator.matchService.addMatchMedia(media);

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medya başarıyla eklendi.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kayıt Hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted && _isUploading) {
        setState(() => _isUploading = false);
      }
    }
  }
}

class _SpeedDialAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SpeedDialAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class _SpeedDialFab extends StatefulWidget {
  final List<_SpeedDialAction> actions;

  const _SpeedDialFab({super.key, required this.actions});

  @override
  State<_SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends State<_SpeedDialFab> {
  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final actions = widget.actions;

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        if (_open)
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.shrink(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ...List.generate(actions.length, (i) {
                final a = actions[i];
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: !_open
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surface.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: cs.outlineVariant),
                                ),
                                child: Text(
                                  a.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FloatingActionButton(
                                heroTag: 'speed_${a.label}_$i',
                                mini: true,
                                onPressed: () {
                                  _close();
                                  a.onTap();
                                },
                                child: Icon(a.icon),
                              ),
                            ],
                          ),
                        ),
                );
              }),
              FloatingActionButton(
                heroTag: 'speed_main',
                onPressed: _toggle,
                child: AnimatedRotation(
                  turns: _open ? 0.125 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(Icons.add),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- TAB İÇERİKLERİ ---

class _HighlightsTab extends StatelessWidget {
  final MatchModel match;
  final bool isSuperAdmin;
  final VoidCallback onDataChanged;
  const _HighlightsTab({
    super.key,
    required this.match,
    required this.isSuperAdmin,
    required this.onDataChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchMediaModel>>(
      stream: ServiceLocator.matchService.watchMatchMedia(match.id),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final mediaList = snap.data ?? [];
        if (mediaList.isEmpty) {
          return const Center(child: Text('Henüz medya eklenmedi.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: mediaList.length,
          separatorBuilder: (c, i) =>
              const Divider(color: Colors.white10, height: 1, indent: 72),
          itemBuilder: (context, index) =>
              _buildCompactMediaItem(context, mediaList[index]),
        );
      },
    );
  }

  Widget _buildCompactMediaItem(BuildContext context, MatchMediaModel media) {
    final bool isVideo = media.mediaType == 'Maç Yayın Linki';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isVideo
              ? Colors.red.withOpacity(0.1)
              : Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isVideo ? Icons.play_arrow_rounded : Icons.camera_alt_rounded,
          color: isVideo ? Colors.redAccent : Colors.blueAccent,
        ),
      ),
      title: Text(
        media.mediaType,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        media.description ??
            (isVideo ? 'Maç videosunu izle' : 'Görseli görüntüle'),
        style: const TextStyle(color: Colors.white60, fontSize: 12),
      ),
      trailing: isSuperAdmin
          ? IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
                size: 22,
              ),
              onPressed: () => _confirmDelete(context, media),
            )
          : const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
      onTap: () => _openFullScreenMedia(context, media),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    MatchMediaModel media,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Medyayı Sil'),
        content: const Text('Bu medya kalıcı olarak silinecek. Emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await ServiceLocator.matchService.deleteMatchMedia(media.id);

      if (context.mounted) {
        onDataChanged();
      }
    }
  }
}

Future<void> _openFullScreenMedia(
  BuildContext context,
  MatchMediaModel media,
) async {
  if (media.mediaType == 'Maç Yayın Linki') {
    final uri = Uri.parse(media.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video linki açılamadı.')));
      }
    }
    return;
  }

  if (!context.mounted) return;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () async {
                final uri = Uri.parse(media.url);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            child: WebSafeImage(
              url: media.url,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// YENİ EKLENEN KADROLAR (ESAME) TABI WIDGET'I
// -----------------------------------------------------------------------------

class _LineupTab extends StatefulWidget {
  final MatchModel match;
  final bool isAdminAccess;
  final String homeName;
  final String awayName;

  const _LineupTab({
    super.key,
    required this.match,
    required this.isAdminAccess,
    required this.homeName,
    required this.awayName,
  });

  @override
  State<_LineupTab> createState() => _LineupTabState();
}

class _LineupTabState extends State<_LineupTab> {
  int _selectedTeamIndex = 0; // 0: Ev Sahibi, 1: Deplasman

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedTeamId = _selectedTeamIndex == 0
        ? widget.match.homeTeamId
        : widget.match.awayTeamId;

    return Column(
      children: [
        // 1. ÜST KISIM: TAKIM SEÇİCİ BUTONLAR (TOGGLE)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: _TeamToggleButton(
                  title: widget.homeName,
                  isSelected: _selectedTeamIndex == 0,
                  onTap: () => setState(() => _selectedTeamIndex = 0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TeamToggleButton(
                  title: widget.awayName,
                  isSelected: _selectedTeamIndex == 1,
                  onTap: () => setState(() => _selectedTeamIndex = 1),
                ),
              ),
            ],
          ),
        ),

        // 2. YETKİLİ MENÜSÜ: ESAME DÜZENLE BUTONU
        if (widget.isAdminAccess)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
            child: Align(
              alignment: _selectedTeamIndex == 0
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () {
                  _showRosterEditSheet(context, selectedTeamId);
                },
                icon: const Icon(Icons.edit_document, size: 16),
                label: const Text(
                  'Esame Listesi',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primaryContainer,
                  foregroundColor: cs.onPrimaryContainer,
                  minimumSize: const Size(0, 36),
                ),
              ),
            ),
          ),

        // 3. OYUNCU LİSTESİ (Gerçek Veri)
        Expanded(
          child: StreamBuilder<List<PlayerModel>>(
            stream: ServiceLocator.teamService.watchPlayers(
              teamId: selectedTeamId,
              tournamentId: widget.match.seasonId,
            ),
            builder: (ctx, playerSnap) {
              final pList = playerSnap.data ?? [];
              
              return StreamBuilder<List<MatchRosterModel>>(
                stream: ServiceLocator.matchService.watchMatchRosters(
                  widget.match.id,
                  selectedTeamId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Kadro yüklenirken hata oluştu: ${snapshot.error}',
                      ),
                    );
                  }
                  final rosters = snapshot.data ?? [];
                  if (rosters.isEmpty) {
                    return const Center(
                      child: Text(
                        'Henüz maç kadrosu girilmemiş.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    );
                  }

                  // Sadece isStarting=true olanlar İlk 11, false olanlar Yedek
                  final starters = rosters.where((r) => r.isStarting).toList();
                  final substitutes = rosters.where((r) => !r.isStarting).toList();

                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      if (starters.isNotEmpty) ...[
                        _buildSectionHeader('İlk 11'),
                        ...starters.map((r) {
                          final p = pList.where((x) => x.id == r.playerId).firstOrNull;
                          final name = p?.name ?? '-';
                          final jersey = r.jerseyNumber ?? p?.number ?? '-';
                          return _buildPlayerTile(
                            jersey: jersey,
                            name: name,
                            isStarter: true,
                            photoUrl: p?.photoUrl,
                          );
                        }),
                      ],

                      if (substitutes.isNotEmpty) ...[
                        if (starters.isNotEmpty) const SizedBox(height: 12),
                        _buildSectionHeader('Yedekler'),
                        ...substitutes.map((r) {
                          final p = pList.where((x) => x.id == r.playerId).firstOrNull;
                          final name = p?.name ?? '-';
                          final jersey = r.jerseyNumber ?? p?.number ?? '-';
                          return _buildPlayerTile(
                            jersey: jersey,
                            name: name,
                            isStarter: false,
                            photoUrl: p?.photoUrl,
                          );
                        }),
                      ],
                    ],
                  );
                },
              );
            }
          ),
        ),
      ],
    );
  }

  // LİSTE BAŞLIĞI WIDGET'I
  Widget _buildSectionHeader(String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
    );
  }

  // OYUNCU SATIRI WIDGET'I
  Widget _buildPlayerTile({
    required String jersey,
    required String name,
    required bool isStarter,
    String? photoUrl,
  }) {
    return Container(
      height: 45,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        children: [
          WebSafeImage(
            url: photoUrl ?? '',
            width: 32,
            height: 32,
            isCircle: true,
            fit: BoxFit.cover,
          ),
          SizedBox(
            width: 36,
            child: Center(
              child: Text(
                jersey,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showRosterEditSheet(BuildContext context, String teamId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        return _RosterEditSheet(
          match: widget.match,
          teamId: teamId,
          isHome: teamId == widget.match.homeTeamId,
        );
      },
    );
  }
}

class _RosterEditSheet extends StatefulWidget {
  final MatchModel match;
  final String teamId;
  final bool isHome;

  const _RosterEditSheet({
    required this.match,
    required this.teamId,
    required this.isHome,
  });

  @override
  State<_RosterEditSheet> createState() => _RosterEditSheetState();
}

class _RosterEditSheetState extends State<_RosterEditSheet>
    with SingleTickerProviderStateMixin {
  final _teamService = ServiceLocator.teamService;
  final _matchService = ServiceLocator.matchService;

  late TabController _tabController;
  List<PlayerModel> _teamPlayers = [];
  final Set<String> _starterIds = {};
  final Set<String> _subIds = {};
  Map<String, TextEditingController> _jerseyControllers = {};
  bool _isLoading = true;
  bool _isSaving = false;

  int _startingLimit = 11;
  int _subLimit = 7;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var c in _jerseyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      print('--- DEBUG: UI Veri Yükleme ---');
      print('Match ID: ${widget.match.id}');
      print(
        'Match League ID (Sezon ID olarak kullanılıyor): ${widget.match.seasonId}',
      );
      print('Team ID: ${widget.teamId}');

      int sCount = 11;
      int subCount = 7;
      if (widget.match.seasonId != null && widget.match.seasonId!.isNotEmpty) {
        try {
          final sRes = await Supabase.instance.client
              .from('seasons')
              .select('starting_player_count, sub_player_count')
              .eq('id', widget.match.seasonId!)
              .maybeSingle();
          if (sRes != null) {
            sCount = sRes['starting_player_count'] ?? 11;
            subCount = sRes['sub_player_count'] ?? 7;
          }
        } catch (_) {}
      }

      final players = await _teamService.getEligiblePlayers(
        widget.teamId,
        widget.match.seasonId ?? '',
      );
      final rosters = await _matchService
          .watchMatchRosters(widget.match.id, widget.teamId)
          .first;

      setState(() {
        _startingLimit = sCount;
        _subLimit = subCount;
        _teamPlayers = players;
        for (var p in _teamPlayers) {
          final pid = p.id; // (p.phone ?? p.id) yerine sadece p.id
          final r = rosters.where((x) => x.playerId == pid).firstOrNull;
          if (r == null) {
            _jerseyControllers[pid] = TextEditingController(
              text: p.number ?? '',
            );
          } else {
            if (r.isStarting) {
              _starterIds.add(pid);
            } else {
              _subIds.add(pid);
            }
            _jerseyControllers[pid] = TextEditingController(
              text: r.jerseyNumber ?? p.number ?? '',
            );
          }
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    final selectedIds = {..._starterIds, ..._subIds};
    final numericRegExp = RegExp(r'^\d+$');
    final usedNumbers = <String>{};

    for (final pid in selectedIds) {
      final numberText = _jerseyControllers[pid]?.text.trim() ?? '';
      if (numberText.isEmpty || !numericRegExp.hasMatch(numberText)) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hata'),
            content: const Text(
              'Lütfen seçilen tüm oyuncuların forma numaralarını kontrol ediniz (Sadece sayı girilmelidir).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
        return;
      }

      if (usedNumbers.contains(numberText)) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hata'),
            content: const Text(
              'Aynı takımda birden fazla oyuncu aynı forma numarasını kullanamaz.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
        return;
      }
      usedNumbers.add(numberText);
    }

    setState(() => _isSaving = true);
    try {
      final newRosters = <MatchRosterModel>[];
      for (var p in _teamPlayers) {
        final pid = p.id;
        final isStarter = _starterIds.contains(pid);
        final isSub = _subIds.contains(pid);

        if (!isStarter && !isSub) continue;

        newRosters.add(
          MatchRosterModel(
            id: '',
            matchId: widget.match.id,
            leagueId: widget.match.leagueId,
            seasonId: widget.match.seasonId,
            teamId: widget.teamId,
            playerId: pid,
            isHome: widget.isHome,
            isStarting: isStarter,
            jerseyNumber: _jerseyControllers[pid]?.text.trim(),
          ),
        );
      }

      await _matchService.updateMatchRoster(
        matchId: widget.match.id,
        leagueId: widget.match.leagueId,
        seasonId: widget.match.seasonId,
        teamId: widget.teamId,
        isHome: widget.isHome,
        rosters: newRosters,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildPlayerList(bool isStarterTab) {
    final filteredPlayers = _teamPlayers.where((p) {
      // İlk 11 Tabı: Yedeklerde (subIds) olanları gösterme
      // Yedekler Tabı: İlk 11'de (starterIds) olanları gösterme
      if (isStarterTab) {
        return !_subIds.contains(p.id);
      } else {
        return !_starterIds.contains(p.id);
      }
    }).toList();

    // Sort by: 'Kaleci', 'Defans', 'Orta Saha', 'Forvet'
    filteredPlayers.sort((a, b) {
      final posA = (a.mainPosition ?? a.position ?? '').trim();
      final posB = (b.mainPosition ?? b.position ?? '').trim();

      int getPosOrder(String pos) {
        final p = pos.toLowerCase();
        if (p.contains('kaleci')) return 0;
        if (p.contains('defans')) return 1;
        if (p.contains('orta saha')) return 2;
        if (p.contains('forvet')) return 3;
        return 4;
      }

      final orderA = getPosOrder(posA);
      final orderB = getPosOrder(posB);
      if (orderA != orderB) return orderA.compareTo(orderB);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: filteredPlayers.length,
      itemBuilder: (context, index) {
        final p = filteredPlayers[index];
        final pid = p.id;
        final isChecked = isStarterTab
            ? _starterIds.contains(pid)
            : _subIds.contains(pid);

        final positionText = (p.mainPosition ?? p.position ?? '').trim();
        final displayPos = positionText.isNotEmpty ? ' ($positionText)' : '';

        return GestureDetector(
          onTap: () {
            setState(() {
              if (!isChecked) {
                // Check if limit is reached
                if (isStarterTab) {
                  if (_starterIds.length >= _startingLimit) return;
                  _starterIds.add(pid);
                  _subIds.remove(pid);
                } else {
                  if (_subIds.length >= _subLimit) return;
                  _subIds.add(pid);
                  _starterIds.remove(pid);
                }
              } else {
                if (isStarterTab) {
                  _starterIds.remove(pid);
                } else {
                  _subIds.remove(pid);
                }
              }
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isChecked
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                SizedBox(
                  width: 50,
                  child: TextFormField(
                    controller: _jerseyControllers[pid],
                    enabled: isChecked,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: '#',
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '${p.name}$displayPos',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isChecked
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.90,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Esame Listesi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            if (!_isLoading)
              TabBar(
                controller: _tabController,
                indicatorColor: Theme.of(context).colorScheme.primary,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: [
                  Tab(text: 'İlk $_startingLimit'),
                  Tab(text: 'Yedekler ($_subLimit)'),
                ],
              ),
            const SizedBox(height: 8),
            if (!_isLoading)
              AnimatedBuilder(
                animation: _tabController,
                builder: (context, _) {
                  final isStarterTab = _tabController.index == 0;
                  final current = isStarterTab
                      ? _starterIds.length
                      : _subIds.length;
                  final limit = isStarterTab ? _startingLimit : _subLimit;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Seçilen: $current / $limit',
                      style: TextStyle(
                        color: current == limit ? Colors.green : Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildPlayerList(true),
                        _buildPlayerList(false),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Kaydet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// TAKIM SEÇİCİ BUTON TASARIMI
class _TeamToggleButton extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _TeamToggleButton({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF10B981)
              : Colors.transparent, // Seçiliyse yeşil
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981) : Colors.white24,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DETAY TABI (MAÇ AKIŞI)
// -----------------------------------------------------------------------------

class _DetailTab extends StatelessWidget {
  final MatchModel match;
  const _DetailTab({required this.match});

  String _friendlyLoadError(Object? error) {
    final s = (error ?? '').toString();
    final lower = s.toLowerCase();
    if (lower.contains('permission-denied')) {
      return 'Yetki hatası. Giriş yapıldı mı ve kullanıcı yetkisi doğru mu kontrol edin.\n\n$s';
    }
    if (lower.contains('requires an index') ||
        lower.contains('failed-precondition')) {
      return 'Sorgu için Firestore index gerekli olabilir.\n\n$s';
    }
    if (lower.contains('unavailable') || lower.contains('network')) {
      return 'Bağlantı hatası. İnternet bağlantısını kontrol edin.\n\n$s';
    }
    return s;
  }

  int _readMinute(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    final s = v.toString().replaceAll('\u0000', '').trim();
    return int.tryParse(s) ??
        double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
        0;
  }

  String _readString(dynamic v) => (v ?? '').toString().trim();

  Map<String, dynamic> _asMap(dynamic v) =>
      (v is Map) ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  List<Map<String, dynamic>> _fallbackSystemStory() {
    switch (match.status) {
      case MatchStatus.notStarted:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Henüz Başlamadı'},
        ];
      case MatchStatus.postponed:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Ertelendi'},
        ];
      case MatchStatus.cancelled:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç İptal Edildi'},
        ];
      case MatchStatus.live:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Başladı'},
        ];
      case MatchStatus.halftime:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Başladı'},
          {'minute': 45, 'type': 'status', 'title': 'İlk Yarı Bitti'},
        ];
      case MatchStatus.finished:
        return <Map<String, dynamic>>[
          {'minute': 0, 'type': 'status', 'title': 'Maç Başladı'},
          {'minute': 45, 'type': 'status', 'title': 'İlk Yarı Bitti'},
          {'minute': 90, 'type': 'status', 'title': 'Maç Bitti'},
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ServiceLocator.matchService.watchInlineMatchEvents(match.id),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Maç akışı yüklenemedi.\n\n${_friendlyLoadError(snap.error)}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final raw = snap.data ?? const <Map<String, dynamic>>[];

        final systemStory = _fallbackSystemStory();
        final List<Map<String, dynamic>> normalized = raw
            .map((e) => _asMap(e))
            .toList();

        String pickType(Map<String, dynamic> e) {
          return _readString(e['type']).isNotEmpty
              ? _readString(e['type'])
              : _readString(e['eventType']).isNotEmpty
              ? _readString(e['eventType'])
              : _readString(e['event_type']);
        }

        String pickTitle(Map<String, dynamic> e) {
          final a = _readString(e['playerName']);
          if (a.isNotEmpty) return a;
          final b = _readString(e['player_name']);
          if (b.isNotEmpty) return b;
          final c = _readString(e['title']);
          if (c.isNotEmpty) return c;
          return _readString(e['eventType']).isNotEmpty
              ? _readString(e['eventType'])
              : _readString(e['event_type']);
        }

        String pickTeamId(Map<String, dynamic> e) {
          final a = _readString(e['teamId']);
          if (a.isNotEmpty) return a;
          return _readString(e['team_id']);
        }

        bool isSystem(Map<String, dynamic> e) {
          final t = pickType(e);
          final et = _readString(e['eventType']).isNotEmpty
              ? _readString(e['eventType'])
              : _readString(e['event_type']);
          if (t == 'status' || t == 'system') return true;
          if (et == 'status' || et == 'system') return true;
          if (pickTeamId(e).isEmpty && pickTitle(e).isNotEmpty) return true;
          return false;
        }

        if (normalized.isEmpty) {
          normalized.addAll(systemStory);
        } else {
          final existingTitleKeys = normalized
              .map((e) => pickTitle(e).toLowerCase())
              .where((s) => s.isNotEmpty)
              .toSet();
          for (final s in systemStory) {
            final key = pickTitle(s).toLowerCase();
            if (key.isNotEmpty && !existingTitleKeys.contains(key)) {
              normalized.add(s);
            }
          }
        }

        normalized.sort((a, b) {
          final am = _readMinute(a['minute']);
          final bm = _readMinute(b['minute']);
          if (am != bm) return am.compareTo(bm);
          final at = pickType(a);
          final bt = pickType(b);
          return at.compareTo(bt);
        });

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: normalized.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            if (i == 0) {
              return const Text(
                'Maç Akışı',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              );
            }
            final e = normalized[i - 1];
            final type = pickType(e);
            final title = pickTitle(e);
            final minute = _readMinute(e['minute']);
            final teamId = pickTeamId(e);
            final system = isSystem(e);

            final subIn = _readString(e['subInPlayerName']).isNotEmpty
                ? _readString(e['subInPlayerName'])
                : _readString(e['sub_in_player_name']);
            final assist = _readString(e['assistPlayerName']).isNotEmpty
                ? _readString(e['assistPlayerName'])
                : _readString(e['assist_player_name']);
            final isOwnGoal =
                (e['isOwnGoal'] as bool?) ??
                (e['is_own_goal'] as bool?) ??
                false;

            String displayTitle() {
              if (type == 'substitution') {
                final outName = title;
                final inName = subIn;
                if (outName.isNotEmpty && inName.isNotEmpty) {
                  return '$outName → $inName';
                }
                return outName.isEmpty ? 'Değişiklik' : outName;
              }
              if (type == 'goal') {
                final suffix = isOwnGoal ? ' (KK)' : '';
                final a = assist.isNotEmpty ? ' (Asist: $assist)' : '';
                return '${title.isEmpty ? 'Gol' : title}$suffix$a';
              }
              return title;
            }

            return _DetailEventTile(
              minute: minute,
              type: type,
              title: displayTitle(),
              teamId: teamId,
              homeTeamId: match.homeTeamId,
              system: system,
            );
          },
        );
      },
    );
  }
}

class _DetailEventTile extends StatelessWidget {
  final int minute;
  final String type;
  final String title;
  final String teamId;
  final String homeTeamId;
  final bool system;
  const _DetailEventTile({
    required this.minute,
    required this.type,
    required this.title,
    required this.teamId,
    required this.homeTeamId,
    required this.system,
  });

  Widget _systemIcon(String title) {
    final t = title.toLowerCase();
    if (t.contains('başla')) {
      return const Icon(Icons.play_arrow_rounded, size: 18);
    }
    if (t.contains('devre') || t.contains('yarı')) {
      return const Icon(Icons.timelapse_rounded, size: 18);
    }
    if (t.contains('bitti') || t.contains('son')) {
      return const Icon(Icons.flag_rounded, size: 18);
    }
    return const Icon(Icons.info_outline, size: 18);
  }

  @override
  Widget build(BuildContext context) {
    final bool isHome = teamId == homeTeamId;
    final String min = "$minute'";

    Widget icon;
    if (system) {
      icon = _systemIcon(title);
    } else {
      switch (type) {
        case 'goal':
          icon = const Icon(Icons.sports_soccer, size: 18, color: Colors.white);
          break;
        case 'yellow_card':
          icon = const Icon(Icons.rectangle, color: Colors.yellow, size: 18);
          break;
        case 'red_card':
          icon = const Icon(Icons.rectangle, color: Colors.red, size: 18);
          break;
        case 'second_yellow':
          icon = const _SecondYellowCardIcon();
          break;
        case 'substitution':
          icon = const Icon(Icons.swap_horiz_rounded, size: 18);
          break;
        default:
          icon = const Icon(Icons.info_outline, size: 18);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: system
          ? Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      min,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(width: 10),
                    icon,
                    const SizedBox(width: 10),
                    Text(
                      title.isEmpty ? '-' : title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            )
          : Row(
              mainAxisAlignment: isHome
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.end,
              children: isHome
                  ? [
                      Text(
                        min,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 8),
                      icon,
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          title.isEmpty ? '-' : title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]
                  : [
                      Flexible(
                        child: Text(
                          title.isEmpty ? '-' : title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(width: 8),
                      icon,
                      const SizedBox(width: 8),
                      Text(
                        min,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
            ),
    );
  }
}
