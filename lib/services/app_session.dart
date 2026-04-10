import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

@immutable
class AppSessionState {
  const AppSessionState({
    required this.user,
    required this.isAdmin,
    required this.isLoading,
  });

  final User? user;
  final bool isAdmin;
  final bool isLoading;

  AppSessionState copyWith({User? user, bool? isAdmin, bool? isLoading}) {
    return AppSessionState(
      user: user ?? this.user,
      isAdmin: isAdmin ?? this.isAdmin,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AppSessionController extends ValueNotifier<AppSessionState> {
  AppSessionController({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        super(
          AppSessionState(
            user: (auth ?? FirebaseAuth.instance).currentUser,
            isAdmin: false,
            isLoading: true,
          ),
        ) {
    _sub = _auth.authStateChanges().listen(_onAuthChanged);
    _onAuthChanged(_auth.currentUser);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  StreamSubscription<User?>? _sub;

  Future<void> signInWithUsername({
    required String username,
    required String password,
  }) async {
    final u = username.trim();
    final localPart = (u.contains('@') ? u.split('@').first : u).trim();
    final email = '$localPart@masterclass.com';
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> _onAuthChanged(User? user) async {
    value = value.copyWith(user: user, isLoading: true, isAdmin: false);
    if (user == null) {
      value = value.copyWith(isLoading: false, isAdmin: false);
      return;
    }

    final isAdmin = await _checkAdmin(user);
    value = value.copyWith(isLoading: false, isAdmin: isAdmin);
  }

  Future<bool> _checkAdmin(User user) async {
    final admins = _firestore.collection('admins');

    try {
      final docByUid = await admins.doc(user.uid).get();
      if (docByUid.exists) return true;
    } catch (_) {}

    final email = user.email?.trim() ?? '';
    if (email.isNotEmpty) {
      try {
        final docByEmail = await admins.doc(email).get();
        if (docByEmail.exists) return true;
      } catch (_) {}

      try {
        final q = await admins.where('email', isEqualTo: email).limit(1).get();
        if (q.docs.isNotEmpty) return true;
      } catch (_) {}
    }

    try {
      final q = await admins.where('uid', isEqualTo: user.uid).limit(1).get();
      if (q.docs.isNotEmpty) return true;
    } catch (_) {}

    return false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class AppSession extends InheritedNotifier<AppSessionController> {
  const AppSession({
    super.key,
    required AppSessionController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppSessionController of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<AppSession>();
    if (w == null) {
      throw StateError('AppSession not found in widget tree.');
    }
    return w.notifier!;
  }
}

