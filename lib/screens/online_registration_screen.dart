import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      final db = FirebaseFirestore.instance;
      final otp = generateOtp6();
      final expiresAt = Timestamp.fromDate(
        DateTime.now().add(const Duration(minutes: 3)),
      );
      await db.collection('otp_requests').doc(raw10).set({
        'phone': raw10,
        'code': otp,
        'expiresAt': expiresAt,
        'createdAt': FieldValue.serverTimestamp(),
      });
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
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('otp_requests').doc(raw10).get();
      final data = snap.data();
      if (data == null) {
        throw Exception('Doğrulama kodu bulunamadı.');
      }
      final storedCode = (data['code'] ?? '').toString().trim();
      final expiresAt = data['expiresAt'];
      final exp = expiresAt is Timestamp ? expiresAt.toDate() : null;
      if (exp == null) {
        throw Exception('Doğrulama kodu geçersiz.');
      }
      if (DateTime.now().isAfter(exp)) {
        throw Exception('Doğrulama kodunun süresi doldu.');
      }
      if (storedCode != code) {
        throw Exception('Doğrulama kodu hatalı.');
      }
      await db.collection('otp_requests').doc(raw10).delete();
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
    final db = FirebaseFirestore.instance;

    setState(() => _busy = true);
    try {
      debugPrint(
        "DEBUG: Querying phone: '$raw10' | Length: ${raw10.length}",
      );
      try {
        final sample = await db.collection('players').limit(2).get();
        for (final doc in sample.docs) {
          final data = doc.data();
          final phone = data['phone'];
          final phoneRaw10 = data['phoneRaw10'];
          debugPrint(
            "DEBUG: DB Sample Player ${doc.id} phone='$phone' (${phone.runtimeType}) phoneRaw10='$phoneRaw10' (${phoneRaw10.runtimeType})",
          );
        }
      } catch (e) {
        debugPrint('DEBUG: Sample fetch failed: $e');
      }

      _profileFound = false;
      _matchedPlayerId = null;
      _matchedLeagues = const [];
      _selectedLeagueId = null;
      _resolvedTournamentId = null;
      String? name;
      String? teamId;
      String role = 'player';

      QuerySnapshot<Map<String, dynamic>> leaguesSnap = await db
          .collection('leagues')
          .where('managerPhoneRaw10', isEqualTo: raw10)
          .limit(10)
          .get();
      if (leaguesSnap.docs.isEmpty) {
        leaguesSnap = await db
            .collection('leagues')
            .where('managerPhone', isEqualTo: raw10)
            .limit(10)
            .get();
      }
      if (leaguesSnap.docs.isNotEmpty) {
        _matchedLeagues = leaguesSnap.docs
            .map(
              (d) => {
                ...d.data(),
                'id': d.id,
              },
            )
            .toList();
        _selectedLeagueId = _matchedLeagues.first['id']?.toString();
        role = 'tournament_admin';
        _profileFound = true;
        _welcomeText = _buildTournamentAdminWelcome(_matchedLeagues.first);
        _resolvedRole = role;
        _resolvedTeamId = null;
        if (!mounted) return;
        setState(() {
          _step = 2;
        });
        return;
      }

      QuerySnapshot<Map<String, dynamic>> playersSnap = await db
          .collection('players')
          .where('phoneRaw10', isEqualTo: raw10)
          .limit(1)
          .get();
      if (playersSnap.docs.isEmpty) {
        playersSnap = await db
            .collection('players')
            .where('phone', isEqualTo: raw10)
            .limit(1)
            .get();
      }
      if (playersSnap.docs.isEmpty) {
        playersSnap = await db
            .collection('players')
            .where('phone', isEqualTo: '0$raw10')
            .limit(1)
            .get();
      }
      if (playersSnap.docs.isEmpty) {
        playersSnap = await db
            .collection('players')
            .where('phone', isEqualTo: '+90$raw10')
            .limit(1)
            .get();
      }
      if (playersSnap.docs.isEmpty) {
        playersSnap = await db
            .collection('players')
            .where('phone', isEqualTo: '90$raw10')
            .limit(1)
            .get();
      }
      if (playersSnap.docs.isNotEmpty) {
        final doc = playersSnap.docs.first;
        final d = doc.data();
        _matchedPlayerId = doc.id;
        name = (d['name'] ?? '').toString().trim();
        teamId = (d['teamId'] ?? '').toString().trim();
        final pr = (d['role'] ?? '').toString().trim();
        role = (pr == 'Takım Sorumlusu' || pr == 'Her İkisi')
            ? 'manager'
            : 'player';
        _profileFound = true;
      }

      String? teamName;
      if (teamId != null && teamId.isNotEmpty && teamId != 'free_agent_pool') {
        final t = await db.collection('teams').doc(teamId).get();
        teamName = (t.data()?['name'] as String?)?.trim();
        _resolvedTournamentId = (t.data()?['leagueId'] as String?)?.trim();
      }

      if (_profileFound) {
        final resolvedName = (name ?? '').trim().isEmpty ? 'Oyuncu' : name!;
        final tn = (teamName ?? '').trim().isEmpty ? 'Takım' : teamName!;
        String roleLabel = role;
        if (role == 'player') roleLabel = 'Futbolcu';
        if (role == 'manager') roleLabel = 'Takım Sorumlusu';
        if (role == 'admin') roleLabel = 'admin';
        _welcomeText =
            'Hoş geldin $resolvedName, $tn - $roleLabel olarak kaydın hazır.\nLütfen giriş şifreni belirle.';
        _resolvedRole = role;
        _resolvedTeamId = (teamId ?? '').trim().isEmpty ? null : teamId;
      } else {
        _welcomeText =
            "Sistemde kaydınız bulunamadı. 'Boşta Futbolcu' olarak profilinizi oluşturabilirsiniz.";
        _resolvedRole = 'player';
        _resolvedTeamId = 'free_agent_pool';
        _resolvedTournamentId = null;
      }

      if (!mounted) return;
      setState(() {
        _step = 2;
      });
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

    final email = '$raw10@masterclass.com';
    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;

    setState(() => _busy = true);
    final sm = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      UserCredential userCred;
      try {
        userCred = await auth.createUserWithEmailAndPassword(
          email: email,
          password: p1,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          throw Exception('Bu telefon numarası ile zaten kayıt var. Lütfen giriş yapın.');
        }
        rethrow;
      }

      final user = userCred.user;
      if (user == null) throw Exception('Kullanıcı oluşturulamadı.');

      final users = db.collection('users');
      final batch = db.batch();

      final fullName = (_profileFound)
          ? null
          : '${_nameController.text.trim()} ${_surnameController.text.trim()}'
              .trim();

      Map<String, dynamic>? roleEntry;
      String? accessRole;
      if (_resolvedRole == 'tournament_admin') {
        accessRole = 'tournament_admin';
        roleEntry = {
          'tournamentId': (_selectedLeagueId ?? '').trim(),
          'teamId': null,
          'role': 'turnuva yöneticisi',
        };
      } else {
        accessRole = null;
        final roleTr = _resolvedRole == 'manager' ? 'takım sorumlusu' : 'futbolcu';
        roleEntry = {
          'tournamentId': (_resolvedTournamentId ?? '').trim().isEmpty
              ? null
              : (_resolvedTournamentId ?? '').trim(),
          'teamId': (_resolvedTeamId ?? '').trim().isEmpty
              ? null
              : (_resolvedTeamId ?? '').trim(),
          'role': roleTr,
        };
      }

      batch.set(
        users.doc(user.uid),
        {
          'accessRole': ?accessRole,
          'phone': raw10,
          if (fullName != null && fullName.isNotEmpty) 'fullName': fullName,
          if (_nameController.text.trim().isNotEmpty)
            'name': _nameController.text.trim(),
          if (_surnameController.text.trim().isNotEmpty)
            'surname': _surnameController.text.trim(),
          'roles': FieldValue.arrayUnion([roleEntry]),
          if (_resolvedRole == 'tournament_admin')
            'tournamentIds': _matchedLeagues
                .map((e) => (e['id'] ?? '').toString())
                .where((e) => e.trim().isNotEmpty)
                .toList(),
          if (_resolvedRole == 'tournament_admin')
            'activeTournamentId': (_selectedLeagueId ?? '').trim(),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (_resolvedRole == 'tournament_admin') {
      } else if (_profileFound) {
        final pid = (_matchedPlayerId ?? '').trim();
        if (pid.isNotEmpty) {
          batch.update(db.collection('players').doc(pid), {
            'authUid': user.uid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        batch.set(
          db.collection('players').doc(),
          {
            'teamId': 'free_agent_pool',
            'name': fullName,
            'role': 'Futbolcu',
            'phone': raw10,
            'authUid': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      }

      await batch.commit();

      if (!mounted) return;
      final isTournamentAdmin = _resolvedRole == 'tournament_admin';
      final tid = (_selectedLeagueId ?? '').trim();
      if (isTournamentAdmin && tid.isNotEmpty) {
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
