import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Future<ConfirmationResult> startPhoneAuthWeb({
    required String phoneNumber,
  }) async {
    if (!kIsWeb) {
      throw StateError('startPhoneAuthWeb sadece Web platformunda kullanılabilir.');
    }
    return _auth.signInWithPhoneNumber(phoneNumber);
  }
}

