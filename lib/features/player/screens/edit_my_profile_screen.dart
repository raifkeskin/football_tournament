import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/photo_crop_screen.dart';
import '../../../core/widgets/picked_image.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../auth/widgets/phone_input.dart';
import '../../identity/change_phone_screen.dart';
import '../../identity/identity_access.dart';
import '../../identity/identity_service.dart';
import '../services/player_profile_service.dart';

/// Futbolcunun kendi bilgileri. Değişiklikler turnuva sorumlusu onayına
/// gider; onay bekleyen alanlar kilitlidir. Kaydedilirse true döner.
class EditMyProfileScreen extends StatefulWidget {
  const EditMyProfileScreen({
    super.key,
    required this.player,
    required this.pending,
    required this.service,
  });

  final MyPlayer player;

  /// Bekleyen talepler: içlerindeki alanlar kilitli, bekleyen değer gösterilir.
  final List<ProfileChangeRequest> pending;
  final PlayerProfileService service;

  @override
  State<EditMyProfileScreen> createState() => _EditMyProfileScreenState();
}

class _EditMyProfileScreenState extends State<EditMyProfileScreen> {
  late final _heightController = TextEditingController(
    text: widget.player.height?.toString() ?? '',
  );
  late final _weightController = TextEditingController(
    text: widget.player.weight?.toString() ?? '',
  );
  late String? _mainPosition = widget.player.mainPosition;
  late String? _subPosition = widget.player.subPosition;
  late final String? _birthDate = widget.player.birthDate;
  XFile? _photo;
  bool _busy = false;
  String? _error;

  /// Onay bekleyen alan → bekleyen değer.
  late final Map<String, dynamic> _pendingValues = {
    for (final r in widget.pending) ...r.changes,
  };

  bool _locked(String key) => _pendingValues.containsKey(key);

  bool get _positionLocked =>
      _locked(ProfileField.mainPosition) || _locked(ProfileField.subPosition);

  @override
  void initState() {
    super.initState();
    _heightController.addListener(_onEdit);
    _weightController.addListener(_onEdit);
  }

  void _onEdit() => setState(() => _error = null);

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  /// Formdaki değerlerden yalnızca değişenler (fotoğraf hariç).
  Map<String, dynamic> _changedFields() {
    final cur = widget.player.values;
    final next = <String, dynamic>{
      ProfileField.height: int.tryParse(_heightController.text.trim()),
      ProfileField.weight: int.tryParse(_weightController.text.trim()),
      ProfileField.mainPosition: _mainPosition,
      ProfileField.subPosition: _subPosition,
    };
    return {
      for (final e in next.entries)
        if (!_locked(e.key) && e.value != null && e.value != cur[e.key])
          e.key: e.value,
    };
  }

  int get _changeCount {
    final fields = _changedFields().keys.toSet();
    // Mevki + alt mevki tek değişiklik sayılır.
    if (fields.contains(ProfileField.subPosition)) {
      fields
        ..remove(ProfileField.subPosition)
        ..add(ProfileField.mainPosition);
    }
    return fields.length + (_photo == null ? 0 : 1);
  }

  Future<void> _pickPhoto() async {
    final picked = await pickAndCropPortraitPhoto(context);
    _setPhoto(picked);
  }

  /// Seçili ya da yüklü fotoğrafın kadrajını yeniden ayarlar.
  Future<void> _reframePhoto() async {
    final current = (widget.player.photoUrl ?? '').trim();
    final XFile? picked;
    if (_photo != null) {
      final bytes = await _photo!.readAsBytes();
      if (!mounted) return;
      picked = await cropPortraitPhoto(context, bytes);
    } else {
      picked = await cropPortraitPhotoFromUrl(context, current);
    }
    _setPhoto(picked);
  }

  void _setPhoto(XFile? picked) {
    if (picked == null || !mounted) return;
    setState(() {
      _photo = picked;
      _error = null;
    });
  }

  Future<void> _pickMainPosition() async {
    final v = await showAdminOptionPicker<String>(
      context: context,
      title: 'Mevki',
      items: kMainPositions,
      labelBuilder: (s) => s,
      selected: _mainPosition,
    );
    if (v == null || !mounted || v == _mainPosition) return;
    setState(() {
      _mainPosition = v;
      final subs = kSubPositionsByMain[v] ?? const [];
      // Kalecinin alt mevkisi yok: eskisi boşaltılır.
      _subPosition = subs.isEmpty ? '' : null;
      _error = null;
    });
  }

  Future<void> _pickSubPosition() async {
    final subs = kSubPositionsByMain[_mainPosition] ?? const <String>[];
    final v = await showAdminOptionPicker<String>(
      context: context,
      title: 'Alt Mevki',
      items: subs,
      labelBuilder: (s) => s,
      selected: _subPosition,
    );
    if (v == null || !mounted) return;
    setState(() {
      _subPosition = v;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final changes = _changedFields();
    if (changes.isEmpty && _photo == null) {
      setState(() => _error = 'Değişiklik yapmadınız.');
      return;
    }
    if (changes.containsKey(ProfileField.mainPosition) &&
        (kSubPositionsByMain[_mainPosition] ?? const []).isNotEmpty &&
        (_subPosition ?? '').isEmpty) {
      setState(() => _error = 'Alt mevkiyi de seçin.');
      return;
    }
    if (changes.containsKey(ProfileField.mainPosition) &&
        _subPosition != null) {
      changes[ProfileField.subPosition] = _subPosition;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    String? uploaded;
    try {
      if (_photo != null) {
        uploaded = await widget.service.uploadPendingPhoto(_photo!);
        changes[ProfileField.photoUrl] = uploaded;
      }
      await widget.service.submit(changes);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Talebin turnuva sorumlusu onayına gönderildi.'),
        ),
      );
    } catch (e) {
      // Talep açılamadıysa yüklenen fotoğraf boşta kalmasın.
      if (uploaded != null) await widget.service.deletePhoto(uploaded);
      if (!mounted) return;
      setState(() => _error = _readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _readableError(Object e) {
    final s = e.toString();
    final m = RegExp(r'message: ([^,]+)').firstMatch(s);
    return (m?.group(1) ?? s).replaceFirst('Exception: ', '');
  }

  /// Telefon: onaylı profil numarasını kimliğini yeniden okutarak
  /// değiştirebilir (kimlik doğrulama açık olanlara).
  Widget _phoneSection() {
    final session = AppSession.of(context).value;
    final phone = normalizePhoneToRaw10(session.phone);
    if (!IdentityAccess.visible(session)) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: _verifiedFuture ??= IdentityService.isVerified(widget.player.id),
      initialData: IdentityService.cached(widget.player.id),
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return AdminFormSection(
          title: 'Telefon',
          child: AdminFieldGroup(
            children: [
              AdminFieldRow(
                icon: Icons.phone_iphone_rounded,
                label: 'Giriş numaram',
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final changed = await ChangePhoneScreen.open(context);
                          if (changed == true && mounted) setState(() {});
                        },
                  child: const Text(
                    'Değiştir',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                child: Text(
                  phone.length == 10 ? '0 ${formatPhoneRaw10(phone)}' : '-',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool>? _verifiedFuture;

  Widget _lockedTrailing(String key, {String? label}) {
    final v = label ?? ProfileField.display(key, _pendingValues[key]);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline_rounded, color: kAdminAmber, size: 14),
        const SizedBox(width: 4),
        Text(
          'Onayda: $v',
          style: const TextStyle(
            color: kAdminAmber,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _numberRow({
    required IconData icon,
    required String label,
    required String key,
    required TextEditingController controller,
  }) {
    final locked = _locked(key);
    return AdminFieldRow(
      icon: icon,
      label: label,
      trailing: locked ? _lockedTrailing(key) : null,
      child: TextField(
        controller: controller,
        enabled: !locked && !_busy,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        style: TextStyle(
          color: locked ? Colors.white54 : Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        decoration: adminInlineInputDecoration(hint: '-'),
      ),
    );
  }

  Widget _photoSection() {
    final locked = _locked(ProfileField.photoUrl);
    final current = (widget.player.photoUrl ?? '').trim();
    final Widget image = _photo != null
        ? CircleAvatar(
            radius: 54,
            backgroundImage: pickedImageProvider(_photo!),
          )
        : current.isNotEmpty
        ? WebSafeImage(url: current, width: 108, height: 108, isCircle: true)
        : const CircleAvatar(
            radius: 54,
            backgroundColor: Color(0xFF334155),
            child: Icon(Icons.person_rounded, color: Colors.white54, size: 52),
          );
    return Column(
      children: [
        SizedBox(
          width: 116,
          height: 116,
          child: Stack(
            children: [
              Container(
                width: 116,
                height: 116,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _photo != null || locked
                        ? kAdminAmber
                        : Colors.white24,
                    width: 2,
                  ),
                ),
                child: ClipOval(child: image),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: locked ? const Color(0xFF475569) : kAdminAccent,
                  shape: const CircleBorder(
                    side: BorderSide(color: kAdminBg, width: 3),
                  ),
                  child: IconButton(
                    tooltip: locked ? 'Fotoğraf onayda' : 'Fotoğrafı değiştir',
                    onPressed: locked || _busy ? null : _pickPhoto,
                    icon: Icon(
                      locked
                          ? Icons.lock_outline_rounded
                          : Icons.photo_camera_outlined,
                      color: locked ? Colors.white70 : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!locked && (_photo != null || current.isNotEmpty))
          TextButton.icon(
            onPressed: _busy ? null : _reframePhoto,
            style: TextButton.styleFrom(foregroundColor: kAdminAccent),
            icon: const Icon(Icons.crop_rounded, size: 18),
            label: const Text('Kadrajı düzenle'),
          ),
        if (locked || _photo != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: kAdminAmber.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              locked ? 'Yeni fotoğraf onayda' : 'Fotoğraf değişti',
              style: const TextStyle(
                color: kAdminAmber,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final positionLocked = _positionLocked;
    // Mevki sekmesi açıksa mevkiler oyuncu kartının Mevki sekmesinden düzenlenir.
    final positionsInTab =
        AppSettings.positionsTabEnabled.value ||
        AppSession.of(context).value.isAdmin;
    final pendingPos = [
      _pendingValues[ProfileField.mainPosition],
      _pendingValues[ProfileField.subPosition],
    ].whereType<String>().join(' · ');
    final subs = kSubPositionsByMain[_mainPosition] ?? const <String>[];
    final count = _changeCount;

    return AdminPageScaffold(
      title: 'Bilgilerim',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _photoSection(),
          const SizedBox(height: 22),
          _phoneSection(),
          AdminFormSection(
            title: 'Fiziksel',
            child: AdminFieldGroup(
              children: [
                _numberRow(
                  icon: Icons.height_rounded,
                  label: 'Boy (cm)',
                  key: ProfileField.height,
                  controller: _heightController,
                ),
                _numberRow(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Kilo (kg)',
                  key: ProfileField.weight,
                  controller: _weightController,
                ),
              ],
            ),
          ),
          AdminFormSection(
            title: 'Futbol ve Kişisel',
            child: AdminFieldGroup(
              children: [
                if (!positionsInTab && positionLocked)
                  AdminFieldRow(
                    icon: Icons.sports_soccer_rounded,
                    label: 'Mevki',
                    trailing: _lockedTrailing(
                      ProfileField.mainPosition,
                      label: pendingPos,
                    ),
                    child: Text(
                      _mainPosition ?? '-',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else if (!positionsInTab)
                  AdminSelectRow(
                    icon: Icons.sports_soccer_rounded,
                    label: 'Mevki',
                    value: _mainPosition,
                    placeholder: 'Seçin',
                    onTap: _busy ? null : _pickMainPosition,
                  ),
                if (!positionsInTab && !positionLocked && subs.length > 1)
                  AdminSelectRow(
                    icon: Icons.tune_rounded,
                    label: 'Alt Mevki',
                    value: _subPosition,
                    placeholder: 'Seçin',
                    onTap: _busy ? null : _pickSubPosition,
                  ),
                // Doğum tarihi uygulamadan değiştirilemez (kimlikten gelir).
                AdminFieldRow(
                  icon: Icons.cake_outlined,
                  label: 'Doğum Tarihi',
                  trailing: const Icon(
                    Icons.lock_outline_rounded,
                    color: Colors.white38,
                    size: 15,
                  ),
                  child: Text(
                    ProfileField.display(ProfileField.birthDate, _birthDate),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kAdminAmber.withValues(alpha: 0.08),
              border: Border.all(color: kAdminAmber.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: kAdminAmber,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _pendingValues.isEmpty
                        ? 'Değişiklikler turnuva sorumlusu onayladıktan sonra '
                              'profilinde görünür. Onaylanana kadar talebini '
                              'geri çekebilirsin.'
                        : 'Kilitli alanlar için gönderdiğin talep onay '
                              'bekliyor; talep sonuçlanana ya da sen geri '
                              'çekene kadar değiştirilemez. Diğer alanları '
                              'ayrı bir talep olarak gönderebilirsin.',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kAdminDanger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 22),
          AdminPrimaryButton(
            label: count == 0
                ? 'ONAYA GÖNDER'
                : 'ONAYA GÖNDER ($count DEĞİŞİKLİK)',
            busy: _busy,
            onPressed: count == 0 ? null : _submit,
          ),
          const SizedBox(height: 10),
          AdminSecondaryButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
