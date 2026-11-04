import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../models/user_model.dart';

/// The subset of [AuthService] that [AuthNotifier] depends on. Exists so
/// tests can supply a fake implementation without triggering a real
/// `FirebaseAuth.instance` call — [AuthService] itself has eager field
/// initializers that make it otherwise impossible to construct in a plain
/// unit test (see design/P0_REMEDIATION_PLAN.md §6.3,
/// test/auth_provider_password_reset_test.dart).
abstract class IAuthService {
  User? get currentUser;

  Future<UserCredential> createAccount({
    required String email,
    required String password,
    required UserModel profile,
  });

  Future<UserCredential> signIn({
    required String email,
    required String password,
  });

  Future<void> sendEmailVerification();

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}

class AuthService implements IAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  User? get currentUser => _auth.currentUser;

  /// Uses userChanges() rather than authStateChanges(): authStateChanges()
  /// only fires on sign-in/sign-out, so a verified-email check that calls
  /// currentUser.reload() would never propagate to listeners (router
  /// redirect included). userChanges() also emits after reload().
  Stream<User?> authStateChanges() => _auth.userChanges();

  /// Creates a new Firebase Auth account and stores the user profile.
  @override
  Future<UserCredential> createAccount({
    required String email,
    required String password,
    required UserModel profile,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user!.sendEmailVerification();
    final doc = profile.copyWith(
      email: email,
    );
    await _db.collection('users').doc(credential.user!.uid).set({
      ...doc.toJson(),
      'uid': credential.user!.uid,
    });
    return credential;
  }

  /// Signs in with email and password.
  @override
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Sends an email verification link. Call after createAccount or on demand.
  @override
  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Sends a password reset email.
  @override
  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Live stream of the current user's profile document.
  ///
  /// Self-heals a missing doc: an Auth account can end up with no
  /// /users/{uid} document if the profile write in createAccount() failed
  /// after the Auth account itself was already created (e.g. a transient
  /// network error between the two awaits) — Auth and Firestore are two
  /// separate writes, not one atomic operation. Without this, every screen
  /// depending on this stream would observe a permanent null and silently
  /// stop working (the "user not found" symptom). Only called with the
  /// signed-in user's own uid, so recreating it here is always correct.
  Stream<UserModel?> userProfileStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().asyncMap((snap) async {
      if (snap.exists) {
        final data = snap.data();
        if (data == null) {
          debugPrint('[auth_service] userProfileStream: doc exists but data() == null for uid=${snap.id}');
          return null;
        }
        return UserModel.fromJson({...data, 'uid': snap.id});
      }

      final authUser = _auth.currentUser;
      if (authUser == null || authUser.uid != uid) return null;

      final recovered = UserModel(uid: uid, name: _fallbackName(authUser), email: authUser.email);
      try {
        await _db.collection('users').doc(uid).set(
          {...recovered.toJson(), 'uid': uid},
          SetOptions(merge: true),
        );
      } catch (_) {
        // Recovery write failed (e.g. offline) — return null; callers
        // already handle a null profile without crashing.
        return null;
      }
      return recovered;
    });
  }

  /// 'name' must satisfy the Firestore create rule (string, length >= 2);
  /// falls back to a safe placeholder when nothing usable is available.
  static String _fallbackName(User u) {
    final base = (u.displayName?.trim().isNotEmpty == true)
        ? u.displayName!.trim()
        : (u.email?.split('@').first ?? '');
    return base.length >= 2 ? base : 'New User';
  }

  Future<UserModel?> fetchUserProfile(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) {
      debugPrint('[auth_service] fetchUserProfile: doc exists but data() == null for uid=$uid');
      return null;
    }
    return UserModel.fromJson({...data, 'uid': snap.id});
  }

  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Friendly error message for Firebase Auth exception codes.
  static String friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
