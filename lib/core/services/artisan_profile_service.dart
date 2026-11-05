import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/geo.dart';

/// Bank details as stored in `artisan_private/{uid}` (owner + admin access).
class ArtisanBankDetails {
  const ArtisanBankDetails({this.bankName, this.accountName = '', this.accountNumber = ''});
  final String? bankName;
  final String accountName;
  final String accountNumber;
}

/// Stage 8.1 (D-5): artisan profile writes that used to live inside the
/// artisan widgets (open jobs feed, business profile, service area card,
/// bank details, artisan registration). Moved here unchanged — same
/// collections, documents, fields, merge semantics and batches — so the
/// existing firestore.rules and rules tests keep governing them.
class ArtisanProfileService {
  ArtisanProfileService(this._db);
  final FirebaseFirestore _db;

  static const nigerianBanks = [
    'Access Bank',
    'Ecobank Nigeria',
    'Fidelity Bank',
    'First Bank of Nigeria',
    'First City Monument Bank (FCMB)',
    'Guaranty Trust Bank (GTBank)',
    'Heritage Bank',
    'Keystone Bank',
    'Kuda Bank',
    'Moniepoint MFB',
    'Opay',
    'PalmPay',
    'Polaris Bank',
    'Providus Bank',
    'Stanbic IBTC Bank',
    'Sterling Bank',
    'Union Bank',
    'United Bank for Africa (UBA)',
    'Wema Bank',
    'Zenith Bank',
  ];

  /// Was `_OpenJobsFeedScreenState._toggleAvailability`.
  Future<void> setAvailability(String uid, bool available) {
    final batch = _db.batch();
    batch.set(_db.collection('artisans').doc(uid), {'isAvailable': available}, SetOptions(merge: true));
    batch.set(_db.collection('users').doc(uid), {'isAvailable': available}, SetOptions(merge: true));
    return batch.commit();
  }

  /// Was `_BusinessProfileScreenState._save`.
  Future<void> saveBusinessProfile(
    String uid, {
    required bool isBusiness,
    String? businessName,
    String? registrationNumber,
    String? businessAddress,
  }) =>
      _db.collection('artisans').doc(uid).update({
        'accountType': isBusiness ? 'business' : 'individual',
        'businessName': isBusiness ? businessName?.trim() : null,
        'businessRegistrationNumber': isBusiness ? registrationNumber?.trim() : null,
        'businessAddress': isBusiness ? businessAddress?.trim() : null,
      });

  /// Was `_ServiceAreaCardState._save` (radius already clamped by caller).
  Future<void> saveServiceArea(String uid, {required double lat, required double lng, required String address, required double radiusKm}) =>
      _db.collection('artisans').doc(uid).update({
        'latitude': lat,
        'longitude': lng,
        'serviceGeohash3': Geo.geohash(lat, lng, 3),
        'serviceGeohash4': Geo.geohash(lat, lng, 4),
        'serviceAddress': address.trim(),
        'serviceRadiusKm': radiusKm,
        'serviceLocationUpdatedAt': FieldValue.serverTimestamp(),
      });

  /// Was `_BankDetailsScreenState._loadExisting`.
  Future<ArtisanBankDetails> loadBankDetails(String uid) async {
    final doc = await _db.collection('artisan_private').doc(uid).get();
    final d = doc.data();
    if (d == null) return const ArtisanBankDetails();
    final bank = d['bankName'] as String?;
    return ArtisanBankDetails(
      bankName: nigerianBanks.contains(bank) ? bank : null,
      accountName: d['accountName'] as String? ?? '',
      accountNumber: d['accountNumber'] as String? ?? '',
    );
  }

  /// Was `_BankDetailsScreenState._save`.
  Future<void> saveBankDetails(String uid, {required String bankName, required String accountName, required String accountNumber}) =>
      _db.collection('artisan_private').doc(uid).set({
        'uid': uid,
        'bankName': bankName,
        'accountName': accountName.trim(),
        'accountNumber': accountNumber.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  /// Bank account number rule (10-digit NUBAN), as in the previous screen.
  static String? validateAccountNumber(String? v) =>
      (v == null || v.trim().length != 10 || int.tryParse(v.trim()) == null) ? 'Account number must be exactly 10 digits' : null;

  /// Was `_ArtisanRegistrationScreenState._save`: the users doc (roles +
  /// artisan fields) then the public artisans doc.
  Future<void> registerArtisan({
    required String uid,
    required String name,
    required String? email,
    required String bio,
    required String skills,
    required String location,
    required String category,
  }) async {
    final artisanFields = {
      'bio': bio.trim(),
      'skills': skills.trim(),
      'location': location.trim(),
      'category': category,
      'approvalStatus': 'pending',
      'verificationStatus': 'unverified',
      'isAvailable': false,
      'rating': 0.0,
      'totalRatings': 0,
      'totalJobs': 0,
      'completedJobs': 0,
      'responseTimeMinutes': 30.0,
      'trustScore': 0.0,
      'portfolioImageUrls': <String>[],
    };
    await _db.collection('users').doc(uid).set({
      ...artisanFields,
      'roles': FieldValue.arrayUnion(['artisan']),
      'activeRole': 'artisan',
      'responseRatePercent': 100.0,
      'cancellationRatePercent': 0.0,
      'openDisputeCount': 0,
    }, SetOptions(merge: true));
    await _db.collection('artisans').doc(uid).set({
      ...artisanFields,
      'uid': uid,
      'name': name,
      'email': email,
      'roles': ['artisan'],
      'activeRole': 'artisan',
      'isVerified': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

final artisanProfileServiceProvider = Provider<ArtisanProfileService>((ref) => ArtisanProfileService(FirebaseFirestore.instance));
