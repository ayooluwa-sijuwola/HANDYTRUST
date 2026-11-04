import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../utils/image_privacy.dart';

/// Handles all user-profile mutations that sit above the Auth/Firestore split:
/// avatar upload, username changes, email/password changes, account deletion
/// requests, and active-role switching.
///
/// Does NOT touch artisan-specific fields (trustScore, verificationStatus,
/// completedJobs, etc.) — those are owned by JobService / Cloud Functions.
class ProfileService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  ProfileService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;

  // ─── Avatar ──────────────────────────────────────────────────────────────

  /// Upload (or replace) the avatar for [uid].
  /// [bytes] must be the raw image bytes (PNG/JPG). Compresses to ≤600 KB
  /// before uploading. Returns the public download URL.
  Future<String> uploadAvatar(String uid, Uint8List bytes) async {
    Uint8List compressed = bytes;
    if (bytes.lengthInBytes > 600 * 1024) {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 75,
        minWidth: 512,
        minHeight: 512,
      );
      compressed = Uint8List.fromList(result);
    }

    // Stage 7.1 (F-2): always strip GPS/EXIF, including small photos.
    compressed = await ImagePrivacy.sanitize(compressed);

    final ref = _storage.ref('profiles/$uid/avatar.jpg');
    await ref.putData(compressed, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();

    await _db.collection('users').doc(uid).update({'photoUrl': url});
    // Mirror to artisans doc if it exists (artisans already have profileImageUrl,
    // but we keep photoUrl in sync so the unified UserAvatar widget can use one field).
    final artisanSnap = await _db.collection('artisans').doc(uid).get();
    if (artisanSnap.exists) {
      await _db
          .collection('artisans')
          .doc(uid)
          .update({'profileImageUrl': url, 'photoUrl': url});
    }
    return url;
  }

  /// Remove the avatar: deletes from Storage and clears the field in Firestore.
  Future<void> removeAvatar(String uid) async {
    try {
      await _storage.ref('profiles/$uid/avatar.jpg').delete();
    } catch (_) {
      // Storage object may not exist if user never uploaded.
    }
    await _db.collection('users').doc(uid).update({
      'photoUrl': FieldValue.delete(),
    });
    final artisanSnap = await _db.collection('artisans').doc(uid).get();
    if (artisanSnap.exists) {
      await _db.collection('artisans').doc(uid).update({
        'profileImageUrl': FieldValue.delete(),
        'photoUrl': FieldValue.delete(),
      });
    }
  }

  // ─── Username ─────────────────────────────────────────────────────────────

  /// Update the user's chosen username. No uniqueness enforcement at this
  /// layer — add a Cloud Function if global uniqueness is required later.
  Future<void> updateUsername(String uid, String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) throw ArgumentError('Username cannot be empty');
    await _db.collection('users').doc(uid).update({'username': trimmed});
    final artisanSnap = await _db.collection('artisans').doc(uid).get();
    if (artisanSnap.exists) {
      await _db.collection('artisans').doc(uid).update({'username': trimmed});
    }
  }

  // ─── Display name ─────────────────────────────────────────────────────────

  Future<void> updateName(String uid, String name) async {
    final trimmed = name.trim();
    if (trimmed.length < 2) throw ArgumentError('Name is too short');
    await _db.collection('users').doc(uid).update({'name': trimmed});
    // Keep artisan displayName in sync.
    final artisanSnap = await _db.collection('artisans').doc(uid).get();
    if (artisanSnap.exists) {
      await _db.collection('artisans').doc(uid).update({'displayName': trimmed});
    }
  }

  // ─── Email & password ─────────────────────────────────────────────────────

  /// Re-authenticate then update email. Firebase requires recent sign-in.
  Future<void> updateEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final cred = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(cred);
    await user.verifyBeforeUpdateEmail(newEmail);
    // Firestore email field updated after the user verifies the new email
    // (handled separately via authStateChanges listener in the app layer).
  }

  /// Re-authenticate then change password.
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final cred = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(cred);
    await user.updatePassword(newPassword);
  }

  // ─── Active role switching ────────────────────────────────────────────────

  Future<void> setActiveRole(String uid, String role) async {
    assert(role == 'customer' || role == 'artisan');
    await _db.collection('users').doc(uid).update({'activeRole': role});
  }

  // ─── Account deletion request ─────────────────────────────────────────────

  /// Records a deletion request in `/account_deletion_requests/{uid}`.
  /// An admin reviews and processes it; the account is not deleted immediately.
  Future<void> requestAccountDeletion(String uid, {String? reason}) async {
    final batch = _db.batch();
    batch.set(
      _db.collection('account_deletion_requests').doc(uid),
      {
        'uid': uid,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      SetOptions(merge: true),
    );
    batch.update(
      _db.collection('users').doc(uid),
      {'accountDeletionRequested': true},
    );
    await batch.commit();
  }

  /// Cancel a pending account deletion request.
  Future<void> cancelDeletionRequest(String uid) async {
    final batch = _db.batch();
    batch.delete(_db.collection('account_deletion_requests').doc(uid));
    batch.update(
      _db.collection('users').doc(uid),
      {'accountDeletionRequested': false},
    );
    await batch.commit();
  }
}
