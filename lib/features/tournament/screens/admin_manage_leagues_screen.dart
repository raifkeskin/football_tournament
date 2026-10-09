import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:football_tournament/features/auth/widgets/phone_input.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/league.dart';
import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/table_feed.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../player/screens/admin_awards_screen.dart';
import 'season_management_screen.dart';
import '../widgets/league_owners_section.dart';
import 'package:football_tournament/core/widgets/picked_image.dart';

class AdminManageLeaguesScreen extends StatefulWidget {
  const AdminManageLeaguesScreen({super.key});

  @override
  State<AdminManageLeaguesScreen> createState() =>
      _AdminManageLeaguesScreenState();
}

class _AdminManageLeaguesScreenState extends State<AdminManageLeaguesScreen> {
  final _picker = ImagePicker();
  late final Stream<List<League>> _leaguesStream = _watchLeagues();

  SupabaseClient get _sb => Supabase.instance.client;

  Future<String> _uploadLeagueLogo({required XFile file}) async {
    final uploaded = await SupabaseImageUploadService().uploadImage(
      file,
      folder: MediaFolder.leagues,
    );
    final url = (uploaded ?? '').trim();
    if (url.isEmpty) {
      throw Exception('Logo yüklenemedi, lütfen tekrar deneyin.');
    }
    return url;
  }

  /// Pasifler de gelir (admin yeniden aktif edebilsin); aktifler önce.
  Stream<List<League>> _watchLeagues() {
    // Önce normal sorgu, canlı bağlantı arkadan (bkz. watchTableRows).
    return watchTableRows(_sb, table: 'leagues', orderBy: 'name').map((rows) {
      final list = rows.map((r) => League.fromJson(r)).toList();
      list.sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return list;
    });
  }

  static String _newAccessCode() {
    final n = 100000 + Random().nextInt(900000);
    return n.toString();
  }

  /// Turnuva ekleme ([league] null) ve düzenleme popup'ı.
  Future<void> _openLeagueForm({League? league}) async {
    final isEdit = league != null;
    final nameController = TextEditingController(text: league?.name ?? '');
    // Uygulama teması: kişi uygulamayı açınca bant bu renklerle boyanır.
    final shortNameController = TextEditingController(
      text: league?.shortName ?? '',
    );
    String? themePrimary = league?.themePrimary;
    String? themeSecondary = league?.themeSecondary;
    // Esame: takım sorumlusu kadroyu maçtan kaç saat önce girebilir.
    var rosterOpenHours = league?.rosterOpenHours ?? 1;
    var sponsorMainSeconds = league?.sponsorMainSeconds ?? 8;
    var sponsorSubSeconds = league?.sponsorSubSeconds ?? 4;
    // Sosyal medya / web: yan menüde turnuva adının altında simge olur.
    final igController = TextEditingController(
      text: league?.instagramUrl ?? '',
    );
    final fbController = TextEditingController(text: league?.facebookUrl ?? '');
    final ytController = TextEditingController(text: league?.youtubeUrl ?? '');
    final webController = TextEditingController(text: league?.websiteUrl ?? '');
    String? link(TextEditingController c) {
      final v = c.text.trim();
      if (v.isEmpty) return null;
      return v.startsWith('http') ? v : 'https://$v';
    }

    final accessCodeController = TextEditingController(
      text: (league?.accessCode ?? '').trim(),
    );
    final existingLogoUrl = (league?.logoUrl ?? '').trim();
    XFile? selectedLogo;
    var removedLogo = false;
    var isPrivate = league?.isPrivate ?? false;
    // Aktif/Pasif yalnızca admin'de; pasif turnuva listelerde görünmez.
    var isActive = league?.isActive ?? true;
    // Transfer dönemi: kapalı gelir; tarihleri sezonda, yalnızca admin görür.
    var transferEnabled = league?.transferEnabled ?? false;
    final isAdmin = AppSession.of(context).value.isAdmin;
    // Gizli turnuva özelliği kapalıyken alan gösterilmez; mevcut değer korunur.
    final privateOn = AppSettings.privateLeaguesEnabled.value;
    var saving = false;

    Future<void> submit(
      BuildContext popupContext,
      void Function(void Function()) setPopupState,
    ) async {
      final messenger = ScaffoldMessenger.of(context);
      final name = nameController.text.trim();
      final access = accessCodeController.text.trim();
      if (name.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Turnuva adı zorunludur.')),
        );
        return;
      }
      if (isPrivate && access.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Gizli turnuva için erişim kodu zorunludur.'),
          ),
        );
        return;
      }

      setPopupState(() => saving = true);
      try {
        // Önce resim yüklenir: yükleme başarısız olursa kayıt hiç değişmez.
        final newLogoUrl = selectedLogo == null
            ? null
            : await _uploadLeagueLogo(file: selectedLogo!);
        final payload = <String, dynamic>{
          if (isAdmin) 'name': name,
          'is_private': isPrivate,
          'access_code': isPrivate ? access : null,
          'logo_url': ?newLogoUrl,
          if (newLogoUrl == null && removedLogo) 'logo_url': null,
          'theme_primary': themePrimary,
          'theme_secondary': themePrimary == null ? null : themeSecondary,
          'short_name': shortNameController.text.trim().isEmpty
              ? null
              : shortNameController.text.trim(),
          'roster_open_hours': rosterOpenHours,
          'sponsor_main_seconds': sponsorMainSeconds,
          'sponsor_sub_seconds': sponsorSubSeconds,
          'instagram_url': link(igController),
          'facebook_url': link(fbController),
          'youtube_url': link(ytController),
          'website_url': link(webController),
          if (isAdmin) 'status': isActive ? 'active' : 'passive',
          if (isAdmin) 'transfer_enabled': transferEnabled,
        };
        if (isEdit) {
          await _sb.from('leagues').update(payload).eq('id', league.id);
          if (newLogoUrl != null || removedLogo) {
            await SupabaseImageUploadService().deleteImageByUrl(
              existingLogoUrl,
            );
          }
        } else {
          await _sb.from('leagues').insert(payload);
        }

        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isEdit ? 'Turnuva güncellendi.' : 'Turnuva oluşturuldu.',
            ),
          ),
        );
        if (popupContext.mounted) Navigator.of(popupContext).pop();
        // Uygulama bu turnuvanın kimliğindeyse yeni renkler hemen görünsün.
        if (isEdit && ActiveTournament.theme.value?.leagueId == league.id) {
          ActiveTournament.refresh();
        }
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
        if (popupContext.mounted) setPopupState(() => saving = false);
      }
    }

    await showAdminPopup<void>(
      context: context,
      builder: (popupContext) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            final viewInsets = MediaQuery.of(context).viewInsets;
            final showUrl = removedLogo || selectedLogo != null
                ? ''
                : existingLogoUrl;
            final hasLogo = selectedLogo != null || showUrl.isNotEmpty;

            Future<void> pickLogo() async {
              final picked = await _picker.pickImage(
                source: ImageSource.gallery,
              );
              if (picked == null) return;
              final logo = await preparePickedLogo(picked);
              setPopupState(() {
                selectedLogo = logo;
                removedLogo = false;
              });
            }

            final Widget logo;
            if (selectedLogo != null) {
              logo = Image(
                image: pickedImageProvider(selectedLogo!),
                fit: BoxFit.contain,
              );
            } else if (showUrl.isNotEmpty) {
              logo = WebSafeImage(
                url: showUrl,
                width: 168,
                height: 168,
                fit: BoxFit.contain,
                fallbackIconSize: 56,
              );
            } else {
              logo = const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    size: 56,
                    color: Color(0xFFF59E0B),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Logo ekle',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              );
            }

            return AdminDialogCloseOverlay(
              onClose: saving ? null : () => Navigator.of(popupContext).pop(),
              // Alanlar kayar; GÜNCELLE / KAYDET düğmesi altta sabit kalır.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        8,
                        20,
                        12 + viewInsets.bottom,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 6),
                          // Büyük logo: dokununca galeri açılır; çöp kutusu logoyu kaldırır.
                          Center(
                            child: GestureDetector(
                              onTap: saving ? null : pickLogo,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 168,
                                    height: 168,
                                    padding: const EdgeInsets.all(10),
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(32),
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF0F172A),
                                          Color(0xFF064E3B),
                                        ],
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black45,
                                          blurRadius: 18,
                                          offset: Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(22),
                                      child: SizedBox.expand(child: logo),
                                    ),
                                  ),
                                  if (hasLogo)
                                    Positioned(
                                      right: -8,
                                      bottom: -8,
                                      child: Material(
                                        color: kAdminDanger,
                                        shape: const CircleBorder(
                                          side: BorderSide(
                                            color: Color(0xFF1E293B),
                                            width: 3,
                                          ),
                                        ),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          // Logoyu tamamen kaldırır; değiştirmek için
                                          // logoya dokunmak yeterli.
                                          onTap: saving
                                              ? null
                                              : () => setPopupState(() {
                                                  selectedLogo = null;
                                                  removedLogo = true;
                                                }),
                                          child: const SizedBox(
                                            width: 42,
                                            height: 42,
                                            child: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          TextField(
                            controller: nameController,
                            // Turnuva adını yalnızca admin değiştirir.
                            enabled: !saving && isAdmin,
                            textCapitalization: TextCapitalization.words,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            cursorColor: kAdminAccent,
                            decoration: adminInputDecoration(
                              label: 'Turnuva Adı',
                              icon: Icons.emoji_events_outlined,
                            ),
                          ),
                          AdminFormSection(
                            title: 'Uygulama Teması',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    'Oyuncularınız uygulamayı açtığında üst bant, '
                                    'açılış ve menü turnuvanızın logosu, adı ve bu '
                                    'renklerle görünür. Ana renk boşsa genel '
                                    'görünüm kullanılır.',
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12.5,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                                TextField(
                                  controller: shortNameController,
                                  enabled: !saving,
                                  maxLength: 24,
                                  textCapitalization: TextCapitalization.words,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  cursorColor: kAdminAccent,
                                  decoration: adminInputDecoration(
                                    label:
                                        'Bantta görünen kısa ad (isteğe bağlı)',
                                    icon: Icons.short_text_rounded,
                                  ).copyWith(counterText: ''),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: AdminColorTile(
                                        label: 'Ana Renk',
                                        hex: themePrimary,
                                        onTap: saving
                                            ? null
                                            : () async {
                                                final c =
                                                    await showAdminColorPicker(
                                                      context: context,
                                                      title: 'Ana Renk',
                                                      initial: themePrimary,
                                                    );
                                                if (c != null) {
                                                  setPopupState(
                                                    () => themePrimary = c,
                                                  );
                                                }
                                              },
                                        onClear: () => setPopupState(
                                          () => themePrimary = null,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: AdminColorTile(
                                        label: 'Vurgu Rengi',
                                        hex: themeSecondary,
                                        onTap: saving
                                            ? null
                                            : () async {
                                                final c =
                                                    await showAdminColorPicker(
                                                      context: context,
                                                      title: 'Vurgu Rengi',
                                                      initial: themeSecondary,
                                                    );
                                                if (c != null) {
                                                  setPopupState(
                                                    () => themeSecondary = c,
                                                  );
                                                }
                                              },
                                        onClear: () => setPopupState(
                                          () => themeSecondary = null,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          AdminFieldGroup(
                            children: [
                              AdminFieldRow(
                                icon: Icons.lock_clock_rounded,
                                label: 'Esame açılışı',
                                enabled: !saving,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Azalt',
                                      icon: const Icon(
                                        Icons.remove_circle_outline_rounded,
                                        color: kAdminAccent,
                                      ),
                                      onPressed: saving || rosterOpenHours <= 0
                                          ? null
                                          : () => setPopupState(
                                              () => rosterOpenHours--,
                                            ),
                                    ),
                                    IconButton(
                                      tooltip: 'Artır',
                                      icon: const Icon(
                                        Icons.add_circle_outline_rounded,
                                        color: kAdminAccent,
                                      ),
                                      onPressed:
                                          saving || rosterOpenHours >= 168
                                          ? null
                                          : () => setPopupState(
                                              () => rosterOpenHours++,
                                            ),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  rosterOpenHours == 0
                                      ? 'Maç saatinde'
                                      : 'Maçtan $rosterOpenHours saat önce',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                            child: Text(
                              'Takım sorumluları kendi takımlarının esamesini bu '
                              'süreden itibaren girebilir. Yöneticiler ve gözlemci '
                              'için süre sınırı yoktur.',
                              style: TextStyle(
                                color: kAdminMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          AdminFieldGroup(
                            children: [
                              for (final (label, isMain) in const [
                                ('Ana sponsor süresi', true),
                                ('Alt sponsor süresi', false),
                              ])
                                AdminFieldRow(
                                  icon: isMain
                                      ? Icons.workspace_premium_rounded
                                      : Icons.handshake_rounded,
                                  label: label,
                                  enabled: !saving,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Azalt',
                                        icon: const Icon(
                                          Icons.remove_circle_outline_rounded,
                                          color: kAdminAccent,
                                        ),
                                        onPressed:
                                            saving ||
                                                (isMain
                                                        ? sponsorMainSeconds
                                                        : sponsorSubSeconds) <=
                                                    2
                                            ? null
                                            : () => setPopupState(() {
                                                if (isMain) {
                                                  sponsorMainSeconds--;
                                                } else {
                                                  sponsorSubSeconds--;
                                                }
                                              }),
                                      ),
                                      IconButton(
                                        tooltip: 'Artır',
                                        icon: const Icon(
                                          Icons.add_circle_outline_rounded,
                                          color: kAdminAccent,
                                        ),
                                        onPressed:
                                            saving ||
                                                (isMain
                                                        ? sponsorMainSeconds
                                                        : sponsorSubSeconds) >=
                                                    60
                                            ? null
                                            : () => setPopupState(() {
                                                if (isMain) {
                                                  sponsorMainSeconds++;
                                                } else {
                                                  sponsorSubSeconds++;
                                                }
                                              }),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '${isMain ? sponsorMainSeconds : sponsorSubSeconds} saniye',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                            child: Text(
                              'Ana sayfadaki sponsor şeridinde her logonun ekranda '
                              'kalma süresi. Sponsorlar Yönetim Paneli › Sponsor '
                              'Yönetimi\'nden eklenir.',
                              style: TextStyle(
                                color: kAdminMuted,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ),
                          AdminFormSection(
                            title: 'Sosyal Medya',
                            child: Column(
                              children: [
                                for (final (c, label, icon) in [
                                  (
                                    igController,
                                    'Instagram adresi',
                                    Icons.camera_alt_outlined,
                                  ),
                                  (
                                    fbController,
                                    'Facebook adresi',
                                    Icons.facebook,
                                  ),
                                  (
                                    ytController,
                                    'YouTube adresi',
                                    Icons.smart_display_outlined,
                                  ),
                                  (
                                    webController,
                                    'Web sitesi',
                                    Icons.language_rounded,
                                  ),
                                ]) ...[
                                  TextField(
                                    controller: c,
                                    enabled: !saving,
                                    keyboardType: TextInputType.url,
                                    style: const TextStyle(color: Colors.white),
                                    cursorColor: kAdminAccent,
                                    decoration: adminInputDecoration(
                                      label: label,
                                      icon: icon,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                              ],
                            ),
                          ),
                          if (isAdmin) ...[
                            const SizedBox(height: 12),
                            AdminFieldGroup(
                              children: [
                                AdminFieldRow(
                                  icon: isActive
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.pause_circle_outline_rounded,
                                  label: 'Durum',
                                  onTap: saving
                                      ? null
                                      : () => setPopupState(
                                          () => isActive = !isActive,
                                        ),
                                  trailing: Switch.adaptive(
                                    value: isActive,
                                    activeTrackColor: kAdminAccent,
                                    onChanged: saving
                                        ? null
                                        : (v) =>
                                              setPopupState(() => isActive = v),
                                  ),
                                  child: Text(
                                    isActive
                                        ? 'Aktif · uygulamada listelenir'
                                        : 'Pasif · listelerde görünmez',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                AdminFieldRow(
                                  icon: Icons.swap_horiz_rounded,
                                  label: 'Transfer',
                                  onTap: saving
                                      ? null
                                      : () => setPopupState(
                                          () => transferEnabled =
                                              !transferEnabled,
                                        ),
                                  trailing: Switch.adaptive(
                                    value: transferEnabled,
                                    activeTrackColor: kAdminAccent,
                                    onChanged: saving
                                        ? null
                                        : (v) => setPopupState(
                                            () => transferEnabled = v,
                                          ),
                                  ),
                                  child: Text(
                                    transferEnabled
                                        ? 'Aktif · tarihler sezonda girilir'
                                        : 'Pasif',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (privateOn) const SizedBox(height: 12),
                          if (privateOn)
                            AdminFieldGroup(
                              children: [
                                AdminFieldRow(
                                  icon: isPrivate
                                      ? Icons.lock_outline_rounded
                                      : Icons.public_rounded,
                                  label: 'Gizli turnuva',
                                  onTap: saving
                                      ? null
                                      : () => setPopupState(() {
                                          isPrivate = !isPrivate;
                                          if (isPrivate &&
                                              accessCodeController.text
                                                  .trim()
                                                  .isEmpty) {
                                            accessCodeController.text =
                                                _newAccessCode();
                                          }
                                          if (!isPrivate) {
                                            accessCodeController.clear();
                                          }
                                        }),
                                  trailing: Switch.adaptive(
                                    value: isPrivate,
                                    activeTrackColor: kAdminAccent,
                                    onChanged: saving
                                        ? null
                                        : (v) => setPopupState(() {
                                            isPrivate = v;
                                            if (isPrivate &&
                                                accessCodeController.text
                                                    .trim()
                                                    .isEmpty) {
                                              accessCodeController.text =
                                                  _newAccessCode();
                                            }
                                            if (!isPrivate) {
                                              accessCodeController.clear();
                                            }
                                          }),
                                  ),
                                  child: Text(
                                    isPrivate
                                        ? 'Açık · yalnızca üyeler ve kodu girenler görür'
                                        : 'Kapalı · herkes görür',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (privateOn && isPrivate) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: accessCodeController,
                              enabled: !saving,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                              cursorColor: kAdminAccent,
                              decoration:
                                  adminInputDecoration(
                                    label: 'Erişim Kodu',
                                    icon: Icons.key_rounded,
                                  ).copyWith(
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Kodu paylaş',
                                          icon: const Icon(
                                            Icons.share_rounded,
                                            color: kAdminAccent,
                                          ),
                                          onPressed: saving
                                              ? null
                                              : () => _shareLeagueCode(
                                                  nameController.text.trim(),
                                                  accessCodeController.text
                                                      .trim(),
                                                ),
                                        ),
                                        IconButton(
                                          tooltip: 'Kodu yenile',
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                            color: Colors.white54,
                                          ),
                                          onPressed: saving
                                              ? null
                                              : () async {
                                                  final code =
                                                      await _regenerateCode(
                                                        league,
                                                      );
                                                  if (code != null) {
                                                    setPopupState(
                                                      () =>
                                                          accessCodeController
                                                                  .text =
                                                              code,
                                                    );
                                                  }
                                                },
                                        ),
                                      ],
                                    ),
                                  ),
                            ),
                          ],
                          // Sahipler yalnız admin tarafından, kayıtlı turnuvaya eklenir.
                          if (AppSession.of(context).value.isAdmin) ...[
                            const SizedBox(height: 18),
                            if (isEdit)
                              LeagueOwnersSection(leagueId: league.id)
                            else
                              const Text(
                                'Turnuva sahiplerini, turnuvayı kaydettikten sonra '
                                'düzenle ekranından ekleyebilirsiniz.',
                                style: TextStyle(
                                  color: kAdminMuted,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                    child: AdminPrimaryButton(
                      label: isEdit ? 'GÜNCELLE' : 'KAYDET',
                      busy: saving,
                      onPressed: () => submit(popupContext, setPopupState),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // Popup kapanış animasyonu sürerken TextField'lar controller'ı kullanmaya
    // devam eder; hemen dispose etmek hataya yol açar.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      nameController.dispose();
      accessCodeController.dispose();
      shortNameController.dispose();
      igController.dispose();
      fbController.dispose();
      ytController.dispose();
      webController.dispose();
    });
  }

  /// Erişim kodunu WhatsApp'ta paylaşılacak hazır mesajla açar.
  Future<void> _shareLeagueCode(String leagueName, String code) async {
    if (code.isEmpty) return;
    final text =
        '${leagueName.isEmpty ? 'Turnuvamızı' : '$leagueName turnuvasını'} '
        'takip etmek için uygulamada menüden "Turnuva Kodu Gir"e '
        '$code yazın.\n\nUygulama: https://masterfutbol.web.app';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mesaj panoya kopyalandı.')));
    }
  }

  /// Kayıtlı turnuvada yeni kod üretir (eski kodla takip edenlerin erişimi
  /// kapanır, önce onay alınır); yeni turnuvada yalnızca kod üretir.
  Future<String?> _regenerateCode(League? league) async {
    if (league == null) return _newAccessCode();
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Kodu Yenile',
      message:
          'Yeni kod üretilecek. Eski kodla turnuvayı takip eden herkesin '
          'erişimi kapanacak; yeni kodu tekrar paylaşmanız gerekecek. '
          'Devam etmek istiyor musunuz?',
      confirmLabel: 'YENİLE',
      icon: Icons.refresh_rounded,
    );
    if (!ok || !mounted) return null;
    try {
      final code = await _sb.rpc(
        'regenerate_league_code',
        params: {'p_league_id': league.id},
      );
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Yeni kod oluşturuldu.')));
      return code?.toString();
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kod yenilenemedi: $e')));
      return null;
    }
  }

  void _openSeasons(League league) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeasonManagementScreen(
          leagueId: league.id,
          leagueName: league.name,
          leagueLogoUrl: league.logoUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Admin tüm turnuvaları; kurucu başkan ve bölge sorumlusu yalnızca
    // kendi turnuvalarını görür (turnuva ekleme/kaldırma admin'de).
    final session = AppSession.of(context).value;
    final isAdmin = session.isAdmin;
    final panelLeagueIds = session.panelLeagueIds;
    if (!session.hasManagementPanel) {
      return const AdminPageScaffold(
        title: 'Turnuva Yönetimi',
        body: Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return AdminPageScaffold(
      title: 'Turnuva Yönetimi',
      actions: [
        if (isAdmin || session.isLeagueOwner)
          AdminBarAction(
            icon: Icons.emoji_events_outlined,
            tooltip: 'Ödüller',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminAwardsScreen(),
              ),
            ),
          ),
        if (isAdmin)
          AdminBarAction(
            icon: Icons.add_rounded,
            tooltip: 'Yeni Turnuva',
            onPressed: () => _openLeagueForm(),
          ),
      ],
      body: StreamBuilder<List<League>>(
        stream: _leaguesStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Turnuvalar yüklenemedi.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: kAdminAccent),
            );
          }
          final leagues = [
            for (final l in snapshot.data!)
              if ((isAdmin || l.isActive) &&
                  (panelLeagueIds == null || panelLeagueIds.contains(l.id)))
                l,
          ];
          if (leagues.isEmpty) {
            return const Center(
              child: Text(
                'Turnuva bulunamadı.',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            itemCount: leagues.length,
            itemBuilder: (context, index) {
              final league = leagues[index];
              // Ink: renkli zemin Material üstüne boyanır, ListTile dokunma
              // efekti görünür (renkli kutu içinde ListTile uyarısı).
              // Satır: düzenleme popup'ı (yetki yoksa sezonlar); sağdaki ayrı
              // kare kutu: sezonlar.
              final canEdit = session.canManageLeague(league.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Ink(
                          decoration: adminCardDecoration(),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              12,
                              4,
                              10,
                              4,
                            ),
                            leading: SizedBox(
                              width: 40,
                              height: 40,
                              child: league.logoUrl.isNotEmpty
                                  ? WebSafeImage(
                                      url: league.logoUrl,
                                      width: 40,
                                      height: 40,
                                      borderRadius: BorderRadius.circular(10),
                                      fallbackIconSize: 20,
                                    )
                                  : Container(
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFF59E0B,
                                        ).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.emoji_events_outlined,
                                        color: Color(0xFFF59E0B),
                                        size: 22,
                                      ),
                                    ),
                            ),
                            title: Text(
                              league.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: () {
                              final private =
                                  league.isPrivate &&
                                  AppSettings.privateLeaguesEnabled.value;
                              if (league.isActive && !private) return null;
                              return Row(
                                children: [
                                  if (!league.isActive) ...[
                                    const Icon(
                                      Icons.pause_circle_outline_rounded,
                                      size: 12,
                                      color: kAdminDanger,
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Pasif',
                                      style: TextStyle(
                                        color: kAdminDanger,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (private) const SizedBox(width: 10),
                                  ],
                                  if (private) ...[
                                    const Icon(
                                      Icons.lock_outline_rounded,
                                      size: 12,
                                      color: Colors.white38,
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Gizli',
                                      style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            }(),
                            onTap: canEdit
                                ? () => _openLeagueForm(league: league)
                                : () => _openSeasons(league),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Sezonlar',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _openSeasons(league),
                            borderRadius: BorderRadius.circular(16),
                            child: Ink(
                              width: 52,
                              decoration: adminCardDecoration(),
                              child: const Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white70,
                                size: 26,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class EditLeagueScreen extends StatefulWidget {
  final League league;
  const EditLeagueScreen({super.key, required this.league});

  @override
  State<EditLeagueScreen> createState() => _EditLeagueScreenState();
}

class _EditLeagueScreenState extends State<EditLeagueScreen> {
  late TextEditingController _nameController;
  late TextEditingController _subtitleController;
  late TextEditingController _managerFullNameController;
  late TextEditingController _managerPhoneController;
  late TextEditingController _matchPeriodDurationController;
  late TextEditingController _groupCountController;
  late TextEditingController _teamsPerGroupController;
  late TextEditingController _ytController;
  late TextEditingController _igController;
  late TextEditingController _startDateController;
  late TextEditingController _endDateController;
  late TextEditingController _accessCodeController;
  DateTime? _startDate;
  DateTime? _endDate;
  XFile? _newLogo;
  bool _isLoading = false;
  bool _isPrivate = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.league.name);
    _managerFullNameController = TextEditingController(
      text: widget.league.managerFullName ?? '',
    );
    _managerPhoneController = TextEditingController(
      text: PhoneMaskFormatter.formatFromRaw(
        widget.league.managerPhoneRaw10 ?? '',
      ),
    );
    _matchPeriodDurationController = TextEditingController(
      text: widget.league.matchPeriodDuration.toString(),
    );
    _groupCountController = TextEditingController(
      text: widget.league.groupCount.toString(),
    );
    _teamsPerGroupController = TextEditingController(
      text: widget.league.teamsPerGroup.toString(),
    );
    _ytController = TextEditingController(text: widget.league.youtubeUrl);
    _igController = TextEditingController(text: widget.league.instagramUrl);
    _startDate = widget.league.startDate;
    _endDate = widget.league.endDate;
    _isPrivate = widget.league.isPrivate;
    _accessCodeController = TextEditingController(
      text: widget.league.accessCode ?? '',
    );
    if (_isPrivate && _accessCodeController.text.trim().isEmpty) {
      _accessCodeController.text = _generateAccessCode();
    }
    _startDateController = TextEditingController(
      text: _startDate == null ? '' : _formatDate(_startDate!),
    );
    _endDateController = TextEditingController(
      text: _endDate == null ? '' : _formatDate(_endDate!),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _subtitleController.dispose();
    _managerFullNameController.dispose();
    _managerPhoneController.dispose();
    _matchPeriodDurationController.dispose();
    _groupCountController.dispose();
    _teamsPerGroupController.dispose();
    _ytController.dispose();
    _igController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _accessCodeController.dispose();
    super.dispose();
  }

  static String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  static String _generateAccessCode() {
    final n = 100000 + Random().nextInt(900000);
    return n.toString();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startDate ?? now)
        : (_endDate ?? _startDate ?? now);
    final picked = await showAppDatePicker(
      context: context,
      initialDate: initial,
      firstYear: now.year - 5,
      lastYear: now.year + 10,
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
        if (_startDate != null && _endDate!.isBefore(_startDate!)) {
          _startDate = picked;
        }
      }
      _startDateController.text = _startDate == null
          ? ''
          : _formatDate(_startDate!);
      _endDateController.text = _endDate == null ? '' : _formatDate(_endDate!);
    });
  }

  Future<void> _update() async {
    final name = _nameController.text.trim();
    final groupCount = int.tryParse(_groupCountController.text.trim()) ?? 0;
    final teamsPerGroup =
        int.tryParse(_teamsPerGroupController.text.trim()) ?? 0;
    final managerFullName = _managerFullNameController.text.trim();
    final managerPhone = _managerPhoneController.text.trim();
    final matchPeriodDuration =
        int.tryParse(_matchPeriodDurationController.text.trim()) ?? 25;
    if (_isPrivate && _accessCodeController.text.trim().isEmpty) {
      _accessCodeController.text = _generateAccessCode();
    }
    if (name.isEmpty || _startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lütfen turnuva adı, başlangıç ve bitiş tarihini girin.',
          ),
        ),
      );
      return;
    }
    if (groupCount <= 0 || teamsPerGroup <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Grup sayısı ve grup başı takım 0 olamaz.'),
        ),
      );
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isLoading = true);

    // Değişiklik: Context'i değişkene alıp Navigator.pop() için kullanacağız.
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

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

      String logoUrl = widget.league.logoUrl;
      if (_newLogo != null) {
        final uploaded = await SupabaseImageUploadService().uploadImage(
          _newLogo!,
          folder: MediaFolder.leagues,
        );
        if (uploaded != null) {
          logoUrl = uploaded;
        } else {
          throw Exception('Logo yüklenemedi.');
        }
      }

      final updatedLeague = League(
        id: widget.league.id,
        name: name,
        logoUrl: logoUrl,
        country: widget.league.country,
        managerFullName: managerFullName.isEmpty ? null : managerFullName,
        managerPhoneRaw10: managerPhone.trim().isEmpty
            ? null
            : normalizePhoneToRaw10(managerPhone),
        matchPeriodDuration: matchPeriodDuration <= 0
            ? 25
            : matchPeriodDuration,
        startDate: _startDate,
        endDate: _endDate,
        season: widget.league.season,
        isActive: widget.league.isActive,
        isDefault: widget.league.isDefault,
        isPrivate: _isPrivate,
        accessCode: _isPrivate && _accessCodeController.text.trim().isNotEmpty
            ? _accessCodeController.text.trim()
            : null,
        youtubeUrl: _ytController.text.trim(),
        instagramUrl: _igController.text.trim(),
        numberOfGroups: groupCount,
        groups: List.generate(
          groupCount,
          (i) => String.fromCharCode(65 + i), // A, B, C...
        ),
        groupCount: groupCount,
        teamsPerGroup: teamsPerGroup,
      );

      await ServiceLocator.leagueService.updateLeague(updatedLeague);
      if (logoUrl != widget.league.logoUrl) {
        await SupabaseImageUploadService().deleteImageByUrl(
          widget.league.logoUrl,
        );
      }

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Turnuva başarıyla güncellendi.')),
      );

      // Sayfa kapatılacağı için setState ile loading durumunu değiştirmeye gerek yok
      nav.pop(true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final logo = await preparePickedLogo(picked);
    if (mounted) setState(() => _newLogo = logo);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Turnuvayı Düzenle')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Logo Düzenleme
              Center(
                child: Stack(
                  children: [
                    if (_newLogo != null)
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: pickedImageProvider(_newLogo!),
                      )
                    else if (widget.league.logoUrl.isNotEmpty)
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: WebSafeImage(
                          url: widget.league.logoUrl,
                          width: 120,
                          height: 120,
                          fit: BoxFit.contain,
                          fallbackIconSize: 40,
                        ),
                      )
                    else
                      const CircleAvatar(
                        radius: 60,
                        child: Icon(Icons.emoji_events, size: 40),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        backgroundColor: cs.primary,
                        child: IconButton(
                          icon: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                          ),
                          onPressed: _pickLogo,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Turnuva Adı',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _subtitleController,
                decoration: const InputDecoration(
                  labelText: 'Alt Bilgi (Örn: Yaz Ligi 2024)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gizlensin'),
                value: _isPrivate,
                onChanged: _isLoading
                    ? null
                    : (v) {
                        setState(() {
                          _isPrivate = v;
                          if (_isPrivate &&
                              _accessCodeController.text.trim().isEmpty) {
                            _accessCodeController.text = _generateAccessCode();
                          }
                          if (!_isPrivate) {
                            _accessCodeController.clear();
                          }
                        });
                      },
              ),
              if (_isPrivate) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _accessCodeController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Erişim Kodu (6 haneli)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ] else
                const SizedBox(height: 16),
              TextField(
                controller: _managerFullNameController,
                decoration: const InputDecoration(
                  labelText: 'Turnuva Sorumlusu (Ad Soyad)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _managerPhoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneMaskFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Turnuva Sorumlusu Telefon',
                  prefixText: '0 ',
                  hintText: '(5XX) XXX XX XX',
                  border: OutlineInputBorder(),
                ),
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
                      controller: _startDateController,
                      readOnly: true,
                      onTap: _isLoading ? null : () => _pickDate(isStart: true),
                      decoration: const InputDecoration(
                        hintText: 'Başlangıç Tarihi',
                        prefixIcon: Icon(Icons.calendar_month_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _endDateController,
                      readOnly: true,
                      onTap: _isLoading
                          ? null
                          : () => _pickDate(isStart: false),
                      decoration: const InputDecoration(
                        hintText: 'Bitiş Tarihi',
                        prefixIcon: Icon(Icons.calendar_month_outlined),
                      ),
                    ),
                  ),
                ],
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
                        labelText: 'Toplam Takım Sayısı',
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
                controller: _ytController,
                decoration: const InputDecoration(
                  labelText: 'YouTube Linki',
                  prefixIcon: Icon(Icons.play_circle_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _igController,
                decoration: const InputDecoration(
                  labelText: 'Instagram Linki',
                  prefixIcon: Icon(Icons.camera_alt_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _isLoading ? null : _update,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('GÜNCELLE'),
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
