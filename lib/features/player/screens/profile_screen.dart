import '../../../core/widgets/app_name_band.dart';
import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/app_navigator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Supabase kontrolü için
import 'package:football_tournament/screens/admin_panel_screen.dart';
import '../../home/screens/main_navigator.dart';
import '../../../core/services/app_session.dart';
import '../../auth/screens/login_screen.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/admin_form.dart';
import 'my_profile_view.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/widgets/web_safe_image.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onRequestHomeTab});

  final VoidCallback onRequestHomeTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// Yönetim paneli görünürken bantta menü + çıkış (paneli bu ekran açtı mı).
  bool _bandOwned = false;

  /// Bu ekranın banda koyduğu düğmeler (başka ekranınkini silmemek için).
  BandActions? _myActions;

  void _syncBand(bool on, VoidCallback onLogout) {
    if (on == _bandOwned && !on) return;
    _bandOwned = on;
    // Çizim sırasında bant yeniden çizilemez; ertelenir.
    Future.microtask(() {
      if (on) {
        _myActions = BandActions(
          onMenu: MainNavigator.openMenu,
          onLogout: onLogout,
          // Ev: panelden açılan alt ekranlar kapanır, Ana Sayfa sekmesi açılır.
          onHome: () {
            appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
            widget.onRequestHomeTab();
          },
        );
        AppNameBand.panelActions.value = _myActions;
      } else {
        _clearBand();
      }
    });
  }

  /// Bantta hâlâ bu ekranın düğmeleri varsa kaldırır. Ekran yeniden
  /// kurulduğunda eskisinin kapanışı yenisinin düğmelerini silmez.
  void _clearBand() {
    if (_myActions != null &&
        identical(AppNameBand.panelActions.value, _myActions)) {
      AppNameBand.panelActions.value = null;
    }
    _myActions = null;
  }

  @override
  void initState() {
    super.initState();
    LoginScreen.redirecting.addListener(_onRedirecting);
  }

  void _onRedirecting() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LoginScreen.redirecting.removeListener(_onRedirecting);
    if (_bandOwned) Future.microtask(_clearBand);
    super.dispose();
  }

  bool _isLoading = false;

  /// Hesap menüsü: çıkış ya da hesabı silme (mağaza şartı: hesap silme
  /// uygulama içinden kolayca bulunabilmeli).
  Future<void> _logout(dynamic session) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: AdminDialogCloseOverlay(
          onClose: () => Navigator.pop(ctx),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: adminDialogDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, color: kAdminDanger, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Çıkış Yap',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 16),
                const Text(
                  'Oturumunuzu kapatmak istediğinize emin misiniz?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, 'logout'),
                    child: const Text(
                      'ÇIKIŞ YAP',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                  child: const Text(
                    'Hesabımı Sil',
                    style: TextStyle(
                      color: Colors.white54,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == 'logout') {
      // Önce giriş ekranı, sonra oturum kapanır: kapanış anında ekranların
      // misafir olarak yeniden çizildiği ara görüntü kullanıcıya görünmez.
      await _toLoginGate();
      await session.signOut();
    } else if (choice == 'delete') {
      await _deleteAccount(session);
    }
  }

  /// Çıkıştan / silmeden sonra uygulama açılışındaki giriş ekranı (misafir
  /// seçeneğiyle).
  Future<void> _toLoginGate() async {
    await GuestMode.set(false);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen(gate: true)),
      (route) => false,
    );
  }

  Future<void> _deleteAccount(dynamic session) async {
    final confirmed = await showAdminConfirmDialog(
      context: context,
      title: 'Hesabımı Sil',
      message:
          'Hesabınız kalıcı olarak silinir ve tekrar giriş yapamazsınız. '
          'Telefon, TC kimlik no, fotoğraf, boy-kilo bilgileriniz ve '
          'yönetici yetkileriniz silinir.\n\n'
          'Katıldığınız turnuvaların kayıtlarında (kadro, gol, istatistik) '
          'adınız-soyadınız ve doğum tarihiniz kalır.\n\n'
          'Bu işlem geri alınamaz.',
      confirmLabel: 'HESABIMI SİL',
      icon: Icons.person_remove_rounded,
    );
    if (!confirmed || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.rpc('delete_my_account');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final msg = e.message.startsWith('SOLE_OWNER:')
          ? 'Şu turnuvaların tek kurucu başkanısınız: '
                '${e.message.substring('SOLE_OWNER:'.length).trim()}. '
                'Hesabınızı silmeden önce turnuvaya başka bir kurucu başkan '
                'ekleyin.'
          : 'Hesap silinemedi: ${e.message}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hesap silinemedi: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    // Hesap sunucuda silindi; cihazdaki oturum da kapatılır.
    try {
      await session.signOut();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
    final messenger = ScaffoldMessenger.of(context);
    await _toLoginGate();
    messenger.showSnackBar(
      const SnackBar(content: Text('Hesabınız silindi.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dynamic session = AppSession.of(context);
    final sessionData = session.value;
    final user = sessionData.user;

    // YENİ VE GÜVENLİ GİRİŞ KONTROLÜ
    // Önce User objesinin ID'sinin gerçekten var olup olmadığına bakıyoruz
    final String uid = user != null ? (user.id?.toString().trim() ?? '') : '';
    bool isRealUser =
        uid.isNotEmpty && uid != 'guest' && uid != 'anonymous' && uid != '0';

    // Eğer Supabase kullanılıyorsa, "Sahte Giriş" hatasını önlemek için kesin kontrolü oradan yapıyoruz
    final su = Supabase.instance.client.auth.currentUser;
    if (su == null || (su.isAnonymous ?? false)) {
      isRealUser =
          false; // Supabase oturumu yoksa kesinlikle Login Ekranı çıkmalı
    } else {
      isRealUser = true;
    }

    final isAdminPanelVisible = sessionData.isAdmin;

    // Yönetim paneli (admin, kurucu, bölge sorumlusu): başlık çubuğu yok;
    // menü ve çıkış üst bantta, sayfa arka planı düz.
    final panelMode =
        isRealUser && (isAdminPanelVisible || sessionData.hasManagementPanel);
    final panelOn = panelMode && TickerMode.of(context);
    if (panelOn != _bandOwned) {
      _syncBand(panelOn, () => _logout(session));
    }

    const bgDark = Color(0xFF0F172A);

    // Giriş yeni yapıldı, profil (rol, oyuncu kaydı) henüz yüklenmedi: ara
    // yazı ("eşleşmedi" vb.) yerine yalnızca bekleme göstergesi.
    if (isRealUser &&
        (sessionData.isLoading || LoginScreen.redirecting.value)) {
      return const Scaffold(
        backgroundColor: bgDark,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Profil bilgisi oturumdan gelir (app_users + players üzerinden
    // AppSessionController tarafından yüklenir).
    return Builder(
      builder: (context) {
        final state = ProfileState(
          displayName: sessionData.displayName,
          phone: sessionData.phone,
          role: sessionData.role,
          isAdmin: sessionData.isAdmin,
          isLoading: sessionData.isLoading,
        );

        final showAppBar = !panelMode && (isRealUser || isAdminPanelVisible);

        return PopScope(
          canPop: !isAdminPanelVisible,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (isAdminPanelVisible) {
              widget.onRequestHomeTab();
            }
          },
          child: Scaffold(
            backgroundColor: bgDark,
            extendBodyBehindAppBar:
                true, // KİLİT NOKTA: Arka planı AppBar'ın altına iter
            appBar: !showAppBar
                ? null
                : AppBar(
                    centerTitle: true,
                    backgroundColor:
                        Colors.transparent, // Yeşil renk iptal, tamamen şeffaf
                    elevation: 0,
                    iconTheme: const IconThemeData(color: Colors.white),
                    // Ana sayfa: admin için yeni gezinme yığını; diğer
                    // kullanıcılar için ana sekmeye geçiş (menü oradan açılır).
                    leading: IconButton(
                      icon: const Icon(Icons.home_rounded),
                      tooltip: 'Ana Sayfa',
                      onPressed: () {
                        if (!isAdminPanelVisible) {
                          widget.onRequestHomeTab();
                          return;
                        }
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const MainNavigator(initialTabIndex: 0),
                          ),
                          (route) => false,
                        );
                      },
                    ),
                    // Çıkış: başlığın sağında kırmızı ikon (admin paneli ve
                    // profil için ortak).
                    actions: [
                      IconButton(
                        tooltip: 'Çıkış Yap',
                        onPressed: _isLoading ? null : () => _logout(session),
                        icon: const Icon(
                          Icons.logout_rounded,
                          color: Color(0xFFF87171),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isAdminPanelVisible
                              ? Icons.admin_panel_settings_rounded
                              : Icons.person_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isAdminPanelVisible ? 'Admin Panel' : 'Profil',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
            body: Stack(
              // ... geri kalanı aynı
              children: [
                SafeArea(
                  child: isAdminPanelVisible
                      ? Column(children: [Expanded(child: AdminPanelWidget())])
                      : (isRealUser
                            ? _buildLoggedInProfileBody(context, state, session)
                            : const LoginScreen()), // Doğrulanmamışsa şifre ekranını (LoginScreen) çağır
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoggedInProfileBody(
    BuildContext context,
    ProfileState state,
    dynamic session,
  ) {
    final phone = state.phone ?? '';

    final sessionValue = session.value as AppSessionState;
    // Kurucu başkan / bölge sorumlusu: bilgi kartı + yetkili olduğu yönetim
    // kartları (admin panelinin süzülmüş hâli).
    if (sessionValue.hasManagementPanel) {
      return AdminPanelWidget(
        header: _staffInfoCard(context, state, phone, sessionValue),
      );
    }
    // Futbolcu (ya da oyuncu kaydı olan herkes): kart, maçlar, talepler.
    // Oyuncu kaydı olmayan takım sorumlusu: bilgi kartı.
    final isStaffOnly =
        sessionValue.playerId == null && state.role == 'manager';
    if (!isStaffOnly) {
      return MyProfileView(
        playerId: sessionValue.playerId,
        displayName: state.displayName,
        phone: phone,
        roleLabels: [
          'Futbolcu',
          if (sessionValue.managedTeams.isNotEmpty) 'Takım Sorumlusu',
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [_staffInfoCard(context, state, phone, sessionValue)],
    );
  }

  /// Ad, telefon, rol (ve sorumlu olduğu turnuva/bölgeler) kartı.
  Widget _staffInfoCard(
    BuildContext context,
    ProfileState state,
    String phone,
    AppSessionState session,
  ) {
    final roleText = state.isAdmin
        ? 'Sistem Yöneticisi'
        : session.isLeagueOwner
        ? 'Kurucu Başkan'
        : session.isRegionOwner
        ? 'Bölge Sorumlusu'
        : (state.role == 'manager' ? 'Takım Sorumlusu' : 'Futbolcu');
    return _StaffHeaderCard(
      name:
          state.displayName ??
          (state.isLoading ? 'Yükleniyor...' : 'Belirtilmemiş'),
      phone: phone,
      roleText: roleText,
      session: session,
    );
  }
}

class ProfileState {
  final String? displayName;
  final String? phone;
  final String? role;
  final bool isAdmin;
  final bool isLoading;

  const ProfileState({
    this.displayName,
    this.phone,
    this.role,
    this.isAdmin = false,
    this.isLoading = false,
  });
}

/// Yönetici profil kartı (futbolcu kartı tarzında): fotoğraf (dokununca
/// değişir), ad, telefon, rol ve sorumlu olduğu turnuva/bölgeler.
class _StaffHeaderCard extends StatefulWidget {
  const _StaffHeaderCard({
    required this.name,
    required this.phone,
    required this.roleText,
    required this.session,
  });

  final String name;
  final String phone;
  final String roleText;
  final AppSessionState session;

  @override
  State<_StaffHeaderCard> createState() => _StaffHeaderCardState();
}

class _StaffHeaderCardState extends State<_StaffHeaderCard> {
  static const _accent = Color(0xFF10B981);
  bool _uploading = false;

  Future<void> _changePhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = AppSession.of(context);
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final upload = SupabaseImageUploadService();
      final url = await upload.uploadImage(
        file,
        folder: MediaFolder.staff,
        subfolder: uid,
      );
      if (url == null) throw Exception('Fotoğraf yüklenemedi.');
      await Supabase.instance.client.rpc(
        'set_my_photo',
        params: {'p_url': url},
      );
      final old = widget.session.photoUrl;
      controller.setPhotoUrl(url);
      if ((old ?? '').isNotEmpty) await upload.deleteImageByUrl(old);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final photo = (session.photoUrl ?? '').trim();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 5, color: _accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _uploading ? null : _changePhoto,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _accent, width: 3),
                        ),
                        child: ClipOval(
                          child: _uploading
                              ? const ColoredBox(
                                  color: Color(0xFF334155),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _accent,
                                      ),
                                    ),
                                  ),
                                )
                              : photo.isEmpty
                              ? const ColoredBox(
                                  color: Color(0xFF334155),
                                  child: Center(
                                    child: Icon(
                                      Icons.person_rounded,
                                      color: Colors.white54,
                                      size: 40,
                                    ),
                                  ),
                                )
                              : WebSafeImage(url: photo, width: 74, height: 74),
                        ),
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF1E293B),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.photo_camera_outlined,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      // Kurucu başkan / bölge sorumlusunda telefon gösterilmez.
                      if (widget.phone.isNotEmpty &&
                          !session.isLeagueOwner &&
                          !session.isRegionOwner) ...[
                        const SizedBox(height: 3),
                        Text(
                          widget.phone,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _accent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          widget.roleText,
                          style: const TextStyle(
                            color: _accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (session.isLeagueOwner || session.isRegionOwner) ...[
                        const SizedBox(height: 6),
                        _ScopeText(session: session),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (session.playerId != null)
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    backgroundColor: const Color(0xFF0F172A),
                    appBar: AppBar(
                      title: const Text('Futbolcu Profilim'),
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                    ),
                    body: SafeArea(
                      child: MyProfileView(
                        playerId: session.playerId,
                        displayName: widget.name,
                        phone: widget.phone,
                      ),
                    ),
                  ),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sports_soccer_rounded, color: _accent, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Futbolcu Profilim',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rolün altındaki sorumluluk satırı: kurucu başkanın turnuvaları, bölge
/// sorumlusunun bölgeleri. Diğer rollerde rol adı yazılır.
class _ScopeText extends StatefulWidget {
  const _ScopeText({required this.session});

  final AppSessionState session;

  @override
  State<_ScopeText> createState() => _ScopeTextState();
}

class _ScopeTextState extends State<_ScopeText> {
  late final Future<String> _text = _load();

  Future<String> _load() async {
    final session = widget.session;
    final parts = <String>[];
    if (session.ownedLeagueIds.isNotEmpty) {
      final rows = await Supabase.instance.client
          .from('leagues')
          .select('name')
          .inFilter('id', session.ownedLeagueIds.toList())
          .order('name', ascending: true);
      parts.addAll(rows.map((r) => (r['name'] ?? '').toString()));
    }
    parts.addAll(session.ownedRegions.map((r) => r.name));
    return parts.where((p) => p.trim().isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _text,
      builder: (context, snap) => Text(
        snap.data ?? '…',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13,
          color: Colors.white70,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}
