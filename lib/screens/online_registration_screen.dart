import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/sms/sms_service_locator.dart';
import '../utils/otp_utils.dart';
import 'tournament_admin_dashboard_screen.dart';

class OnlineRegistrationScreen extends StatefulWidget {
  const OnlineRegistrationScreen({super.key});

  @override
  State<OnlineRegistrationScreen> createState() =>
      _OnlineRegistrationScreenState();
}

class _OnlineRegistrationScreenState extends State<OnlineRegistrationScreen> {
  final _authService = AuthService();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _pass1Controller = TextEditingController();
  final _pass2Controller = TextEditingController();

  bool _busy = false;
  int _step = 0;

  bool _otpVerified = false;

  String _raw10 = '';
  String _welcomeText = '';
  String _resolvedRole = 'player';
  String? _resolvedTeamId;
  String? _resolvedTournamentId;
  bool _profileFound = false;
  String? _matchedPlayerId;
  List<Map<String, dynamic>> _matchedLeagues = const [];
  String? _selectedLeagueId;

  String _buildTournamentAdminWelcome(Map<String, dynamic> league) {
    final leagueName = (league['name'] ?? '').toString().trim();
    final mn = (league['managerName'] ?? '').toString().trim();
    final ms = (league['managerSurname'] ?? '').toString().trim();
    final fullName = ('$mn $ms').trim();
    final resolvedName = fullName.isEmpty ? 'Turnuva Sorumlusu' : fullName;
    final tn = leagueName.isEmpty ? 'Turnuva' : leagueName;
    return 'Hoş geldin $resolvedName, $tn - Turnuva Yöneticisi olarak kaydın hazır.\nLütfen giriş şifreni belirle.';
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    _surnameController.dispose();
    _pass1Controller.dispose();
    _pass2Controller.dispose();
    super.dispose();
  }

  String _normalizePhoneToRaw10(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    var d = digits;
    if (d.startsWith('90') && d.length >= 12) d = d.substring(2);
    if (d.startsWith('0')) d = d.substring(1);
    if (d.length > 10) d = d.substring(d.length - 10);
    return d;
  }

  bool _validPassword(String s) {
    final v = s.trim();
    if (v.length < 6 || v.length > 10) return false;
    final hasDigit = RegExp(r'\d').hasMatch(v);
    final hasSpecial = RegExp(r'[^A-Za-z0-9]').hasMatch(v);
    return hasDigit || hasSpecial;
  }

  Widget _passwordChecklist(String s) {
    final v = s.trim();
    final lenOk = v.length >= 6 && v.length <= 10;
    final hasDigit = RegExp(r'\d').hasMatch(v);
    final hasSpecial = RegExp(r'[^A-Za-z0-9]').hasMatch(v);
    final cs = Theme.of(context).colorScheme;

    Widget row(String text, bool ok) {
      return Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: ok ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('6-10 karakter', lenOk),
        const SizedBox(height: 6),
        row('En az 1 rakam veya özel karakter', hasDigit || hasSpecial),
      ],
    );
  }

  Future<void> _sendOtp() async {
    final raw10 = _normalizePhoneToRaw10(_phoneController.text);
    if (raw10.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefon numarası geçerli olmalı.')),
      );
      return;
    }
    setState(() {
      _busy = true;
      _raw10 = raw10;
      _otpVerified = false;
    });

    try {
      final otp = generateOtp6();
      final expiresAt = DateTime.now().add(const Duration(minutes: 3));
      await _authService.createOtpRequest(
        phoneRaw10: raw10,
        code: otp,
        expiresAt: expiresAt,
      );
      await SmsServiceLocator.sms.sendOtp(raw10, otp);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Doğrulama kodu gönderilemedi: $e')),
      );
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.replaceAll(RegExp(r'\D'), '').trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen 6 haneli kodu girin.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final raw10 = _raw10;
      if (raw10.length != 10) return;
      final req = await _authService.getOtpRequest(raw10);
      if (req == null) {
        throw Exception('Doğrulama kodu bulunamadı.');
      }
      if (DateTime.now().isAfter(req.expiresAt)) {
        throw Exception('Doğrulama kodunun süresi doldu.');
      }
      if (req.code != code) {
        throw Exception('Doğrulama kodu hatalı.');
      }
      await _authService.deleteOtpRequest(raw10);
      _otpVerified = true;
      await _loadProfileAfterOtp();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kod doğrulanamadı: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadProfileAfterOtp() async {
    final raw10 = _raw10;
    if (raw10.length != 10) return;
    setState(() => _busy = true);
    try {
      _profileFound = false;
      _matchedPlayerId = null;
      _matchedLeagues = const [];
      _selectedLeagueId = null;
      _resolvedTournamentId = null;
      final result = await _authService.lookupProfileByPhoneRaw10(raw10);

      _profileFound = result.profileFound;
      _matchedPlayerId = result.matchedPlayerId;
      _resolvedTournamentId = result.resolvedTournamentId;
      _resolvedRole = result.resolvedRole;
      _resolvedTeamId = result.resolvedTeamId;

      if (result.resolvedRole == 'tournament_admin') {
        _matchedLeagues = result.leagues;
        _selectedLeagueId = _matchedLeagues.isEmpty
            ? null
            : _matchedLeagues.first['id']?.toString();
        _welcomeText = _matchedLeagues.isEmpty
            ? 'Hoş geldin! Turnuva yöneticisi kaydın hazır.\nLütfen giriş şifreni belirle.'
            : _buildTournamentAdminWelcome(_matchedLeagues.first);
        if (!mounted) return;
        setState(() => _step = 2);
        return;
      }

      if (_profileFound) {
        final resolvedName =
            (result.playerName ?? '').trim().isEmpty ? 'Oyuncu' : result.playerName!.trim();
        final tn =
            (result.resolvedTeamName ?? '').trim().isEmpty ? 'Takım' : result.resolvedTeamName!;
        String roleLabel = _resolvedRole;
        if (_resolvedRole == 'player') roleLabel = 'Futbolcu';
        if (_resolvedRole == 'manager') roleLabel = 'Takım Sorumlusu';
        _welcomeText =
            'Hoş geldin $resolvedName, $tn - $roleLabel olarak kaydın hazır.\nLütfen giriş şifreni belirle.';
      } else {
        _welcomeText =
            "Sistemde kaydınız bulunamadı. 'Boşta Futbolcu' olarak profilinizi oluşturabilirsiniz.";
        _resolvedRole = 'player';
        _resolvedTeamId = 'free_agent_pool';
        _resolvedTournamentId = null;
      }

      if (!mounted) return;
      setState(() => _step = 2);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishRegistration() async {
    final raw10 = _raw10;
    if (raw10.length != 10 || !_otpVerified) return;

    if (_resolvedRole == 'tournament_admin') {
      final selected = (_selectedLeagueId ?? '').trim();
      if (selected.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen turnuva seçin.')),
        );
        return;
      }
    }

    if (!_profileFound) {
      if (_nameController.text.trim().isEmpty ||
          _surnameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen ad ve soyad girin.')),
        );
        return;
      }
    }

    final p1 = _pass1Controller.text;
    final p2 = _pass2Controller.text;
    if (p1 != p2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifreler eşleşmiyor.')),
      );
      return;
    }
    if (!_validPassword(p1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Şifreniz biraz daha 'takım kaptanı' sertliğinde olmalı! Lütfen en az bir rakam veya özel karakter ekleyerek 6-10 karakter arası bir şifre belirleyin.",
          ),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final sm = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final matchedTournamentIds = _matchedLeagues
          .map((e) => (e['id'] ?? '').toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();

      final result = await _authService.registerOnlineUser(
        phoneRaw10: raw10,
        password: p1,
        profileFound: _profileFound,
        resolvedRole: _resolvedRole,
        resolvedTeamId: _resolvedTeamId,
        resolvedTournamentId: _resolvedTournamentId,
        matchedPlayerId: _matchedPlayerId,
        matchedTournamentIds: matchedTournamentIds,
        selectedTournamentId: _selectedLeagueId,
        name: _nameController.text,
        surname: _surnameController.text,
      );

      if (!mounted) return;
      if (result.isTournamentAdmin && (result.tournamentId ?? '').trim().isNotEmpty) {
        final tid = result.tournamentId!.trim();
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => TournamentAdminDashboardScreen(tournamentId: tid),
          ),
          (Route<dynamic> route) => false,
        );
        return;
      }
      nav.pop();
      sm.showSnackBar(const SnackBar(content: Text('Kayıt tamamlandı.')));
    } catch (e) {
      if (!mounted) return;
      sm.showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final inputTheme = theme.copyWith(
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        labelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
        hintStyle: const TextStyle(color: Colors.white70),
        prefixStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      textTheme: theme.textTheme.apply(bodyColor: Colors.white),
    );

    return Theme(
      data: inputTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Online Kayıt Formu'),
          centerTitle: true,
        ),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_step == 0) ...[
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [_PhoneMaskFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Telefon Numarası',
                        prefixText: '0 ',
                        prefixIcon: Icon(Icons.phone_outlined),
                        hintText: '(5XX) XXX XX XX',
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                        ),
                        onPressed: _sendOtp,
                        child: const Text(
                          'Doğrulama Kodu Gönder',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                  if (_step == 1) ...[
                    Text(
                      'Doğrulama Kodu',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        hintText: '6 haneli kod',
                        prefixIcon: Icon(Icons.password_outlined),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                        ),
                        onPressed: _verifyOtp,
                        child: const Text(
                          'Kodu Doğrula',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                  if (_step == 2) ...[
                    Text(
                      _welcomeText,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_resolvedRole == 'tournament_admin' &&
                        _matchedLeagues.length > 1) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _selectedLeagueId,
                        decoration: const InputDecoration(
                          labelText: 'Yöneteceğiniz Turnuvayı Seçin',
                          prefixIcon: Icon(Icons.emoji_events_outlined),
                        ),
                        items: _matchedLeagues
                            .map(
                              (l) => DropdownMenuItem<String>(
                                value: l['id']?.toString(),
                                child: Text(
                                  (l['name'] ?? '').toString(),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null || v.trim().isEmpty) return;
                          final league = _matchedLeagues.firstWhere(
                            (e) => (e['id'] ?? '').toString() == v,
                            orElse: () => _matchedLeagues.first,
                          );
                          setState(() {
                            _selectedLeagueId = v;
                            _welcomeText = _buildTournamentAdminWelcome(league);
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (!_profileFound) ...[
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Ad',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _surnameController,
                        decoration: const InputDecoration(
                          labelText: 'Soyad',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _pass1Controller,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Şifre',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    _passwordChecklist(_pass1Controller.text),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass2Controller,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Şifre (Tekrar)',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                        ),
                        onPressed: _finishRegistration,
                        child: const Text(
                          'Kaydet',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _PhoneMaskFormatter extends TextInputFormatter {
  static String _formatFromRaw10(String raw10) {
    final clipped = raw10.length > 10 ? raw10.substring(0, 10) : raw10;
    final a = clipped.length >= 3 ? clipped.substring(0, 3) : clipped;
    final b = clipped.length > 3
        ? clipped.substring(3, clipped.length >= 6 ? 6 : clipped.length)
        : '';
    final c = clipped.length > 6
        ? clipped.substring(6, clipped.length >= 8 ? 8 : clipped.length)
        : '';
    final d = clipped.length > 8 ? clipped.substring(8) : '';
    final sb = StringBuffer();
    if (a.isNotEmpty) {
      sb.write('(');
      sb.write(a);
      if (a.length == 3) sb.write(') ');
    }
    if (b.isNotEmpty) {
      sb.write(b);
      if (b.length == 3) sb.write(' ');
    }
    if (c.isNotEmpty) {
      sb.write(c);
      if (c.length == 2) sb.write(' ');
    }
    if (d.isNotEmpty) sb.write(d);
    return sb.toString().trimRight();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('90')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length > 10) digits = digits.substring(digits.length - 10);
    final formatted = _formatFromRaw10(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
