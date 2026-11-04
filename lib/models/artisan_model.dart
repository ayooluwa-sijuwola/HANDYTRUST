import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';

/// One row of the trust score breakdown (see TrustScoreService.breakdown).
class TrustComponent {
  final String label;
  final double score;
  final double maxScore;

  const TrustComponent({
    required this.label,
    required this.score,
    required this.maxScore,
  });
}

/// Artisan approval lifecycle: pending → approved | rejected
/// Trust tiers: standard → trusted → elite (based on trustScore)
class ArtisanModel extends UserModel {
  final String skills;
  final double rating;
  final int totalRatings;
  final int totalJobs;
  final int completedJobs;
  final double responseTimeMinutes;
  /// Stage 6 (policy D8): the artisan's GPS service location, captured
  /// once on request (no background tracking). Null until they set it.
  final double? latitude;
  final double? longitude;
  /// Manually entered service address (D8), shown on their profile area.
  final String? serviceAddress;
  /// How far they travel for work; bounded by config/platform.
  final double? serviceRadiusKm;
  final String? serviceGeohash4;
  final String? bio;
  final String? profileImageUrl;
  final List<String> portfolioImageUrls;
  final bool isVerified;
  final bool isAvailable;

  /// 'pending' | 'approved' | 'rejected' — controls public visibility
  final String approvalStatus;

  /// 'unverified' | 'id_submitted' | 'id_verified' | 'trusted'
  final String verificationStatus;

  /// Admin-only, admin-set flag (see firestore.rules' artisans/{uid} update
  /// rule — not in the owner-writable field set). Lets an admin designate
  /// specific accounts as beta testers who may quote/be matched without
  /// completing real identity verification, without changing what
  /// verificationStatus itself means or how it's earned for anyone else.
  /// See design/BETA_TESTING_GUIDE.md.
  final bool betaTester;

  /// Composite trust score 0–100, updated by Cloud Function after each job
  final double trustScore;

  final double responseRatePercent;
  final double cancellationRatePercent;
  final int openDisputeCount;

  /// 'individual' | 'business'
  final String accountType;

  /// Set only when accountType == 'business'.
  final String? businessName;
  final String? businessRegistrationNumber;
  final String? businessAddress;

  /// What customers see as the artisan's name — the registered business
  /// name when operating as a business, otherwise the personal name.
  String get displayName =>
      accountType == 'business' &&
              businessName != null &&
              businessName!.isNotEmpty
          ? businessName!
          : name;

  double get completionRate =>
      totalJobs == 0 ? 0 : (completedJobs / totalJobs).clamp(0.0, 1.0);

  bool get isRising => totalJobs < 10 && totalRatings < 5;

  /// trust tier label for badge display
  String get trustTier {
    if (trustScore >= 90) return 'elite';
    if (trustScore >= 70) return 'trusted';
    return 'standard';
  }

  double get matchScore {
    final ratingScore = rating / 5.0 * 0.40;
    final completionScore = completionRate * 0.30;
    final responseScore = (1.0 - (responseTimeMinutes / 120.0).clamp(0.0, 1.0)) * 0.20;
    return (ratingScore + completionScore + responseScore).clamp(0.0, 1.0);
  }

  ArtisanModel({
    required super.uid,
    required super.name,
    super.username,
    super.photoUrl,
    super.email,
    super.phoneNumber,
    super.roles,
    super.activeRole,
    super.category,
    super.location,
    super.createdAt,
    super.emailVerified,
    super.notificationsEnabled,
    super.accountStatus,
    this.skills = '',
    this.rating = 0.0,
    this.totalRatings = 0,
    this.totalJobs = 0,
    this.completedJobs = 0,
    this.responseTimeMinutes = 30.0,
    this.latitude,
    this.longitude,
    this.serviceAddress,
    this.serviceRadiusKm,
    this.serviceGeohash4,
    this.bio,
    this.profileImageUrl,
    this.portfolioImageUrls = const [],
    this.isVerified = false,
    this.isAvailable = false,
    this.approvalStatus = 'pending',
    this.verificationStatus = 'unverified',
    this.betaTester = false,
    this.trustScore = 0.0,
    this.responseRatePercent = 100.0,
    this.cancellationRatePercent = 0.0,
    this.openDisputeCount = 0,
    this.accountType = 'individual',
    this.businessName,
    this.businessRegistrationNumber,
    this.businessAddress,
  });

  factory ArtisanModel.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];
    List<String> roles;
    if (rawRoles is List) {
      roles = List<String>.from(rawRoles);
    } else {
      roles = ['artisan'];
    }
    if (!roles.contains('artisan')) roles.add('artisan');

    return ArtisanModel(
      uid: json['uid'] as String,
      name: json['name'] as String? ?? '',
      username: json['username'] as String?,
      photoUrl: json['photoUrl'] as String?,
      email: json['email'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      roles: roles,
      activeRole: json['activeRole'] as String? ?? 'artisan',
      category: json['category'] as String?,
      location: json['location'] as String?,
      createdAt: _parseDate(json['createdAt']),
      emailVerified: json['emailVerified'] as bool? ?? false,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      accountStatus: json['accountStatus'] as String? ?? 'active',
      skills: json['skills'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      totalRatings: (json['totalRatings'] as num?)?.toInt() ?? 0,
      totalJobs: (json['totalJobs'] as num?)?.toInt() ?? 0,
      completedJobs: (json['completedJobs'] as num?)?.toInt() ?? 0,
      responseTimeMinutes: (json['responseTimeMinutes'] as num?)?.toDouble() ?? 30.0,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      serviceAddress: json['serviceAddress'] as String?,
      serviceRadiusKm: (json['serviceRadiusKm'] as num?)?.toDouble(),
      serviceGeohash4: json['serviceGeohash4'] as String?,
      bio: json['bio'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      portfolioImageUrls: List<String>.from(json['portfolioImageUrls'] ?? []),
      isVerified: json['isVerified'] as bool? ?? false,
      isAvailable: json['isAvailable'] as bool? ?? false,
      approvalStatus: json['approvalStatus'] as String? ?? 'pending',
      verificationStatus: json['verificationStatus'] as String? ?? 'unverified',
      betaTester: json['betaTester'] as bool? ?? false,
      trustScore: (json['trustScore'] as num?)?.toDouble() ?? 0.0,
      responseRatePercent: (json['responseRatePercent'] as num?)?.toDouble() ?? 100.0,
      cancellationRatePercent: (json['cancellationRatePercent'] as num?)?.toDouble() ?? 0.0,
      openDisputeCount: (json['openDisputeCount'] as num?)?.toInt() ?? 0,
      accountType: json['accountType'] as String? ?? 'individual',
      businessName: json['businessName'] as String?,
      businessRegistrationNumber: json['businessRegistrationNumber'] as String?,
      businessAddress: json['businessAddress'] as String?,
    );
  }

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  @override
  Map<String, dynamic> toJson() {
    final base = super.toJson();
    base.addAll({
      'skills': skills,
      'rating': rating,
      'totalRatings': totalRatings,
      'totalJobs': totalJobs,
      'completedJobs': completedJobs,
      'responseTimeMinutes': responseTimeMinutes,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (serviceAddress != null) 'serviceAddress': serviceAddress,
      if (serviceRadiusKm != null) 'serviceRadiusKm': serviceRadiusKm,
      if (serviceGeohash4 != null) 'serviceGeohash4': serviceGeohash4,
      if (bio != null) 'bio': bio,
      if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      'portfolioImageUrls': portfolioImageUrls,
      'isVerified': isVerified,
      'isAvailable': isAvailable,
      'approvalStatus': approvalStatus,
      'verificationStatus': verificationStatus,
      'betaTester': betaTester,
      'trustScore': trustScore,
      'responseRatePercent': responseRatePercent,
      'cancellationRatePercent': cancellationRatePercent,
      'openDisputeCount': openDisputeCount,
      'accountType': accountType,
      if (businessName != null) 'businessName': businessName,
      if (businessRegistrationNumber != null)
        'businessRegistrationNumber': businessRegistrationNumber,
      if (businessAddress != null) 'businessAddress': businessAddress,
    });
    return base;
  }

  @override
  ArtisanModel copyWith({
    String? name,
    String? username,
    String? photoUrl,
    String? email,
    String? phoneNumber,
    List<String>? roles,
    String? activeRole,
    String? category,
    String? location,
    bool? emailVerified,
    bool? notificationsEnabled,
    String? accountStatus,
    bool? accountDeletionRequested,
    double? rating,
    int? totalRatings,
    int? totalJobs,
    int? completedJobs,
    double? responseTimeMinutes,
    double? latitude,
    double? longitude,
    String? bio,
    String? profileImageUrl,
    List<String>? portfolioImageUrls,
    bool? isVerified,
    bool? isAvailable,
    String? approvalStatus,
    String? verificationStatus,
    bool? betaTester,
    double? trustScore,
    double? responseRatePercent,
    double? cancellationRatePercent,
    int? openDisputeCount,
    String? accountType,
    String? businessName,
    String? businessRegistrationNumber,
    String? businessAddress,
  }) =>
      ArtisanModel(
        uid: uid,
        name: name ?? this.name,
        username: username ?? this.username,
        photoUrl: photoUrl ?? this.photoUrl,
        email: email ?? this.email,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        roles: roles ?? this.roles,
        activeRole: activeRole ?? this.activeRole,
        category: category ?? this.category,
        location: location ?? this.location,
        createdAt: createdAt,
        emailVerified: emailVerified ?? this.emailVerified,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        accountStatus: accountStatus ?? this.accountStatus,
        skills: skills,
        rating: rating ?? this.rating,
        totalRatings: totalRatings ?? this.totalRatings,
        totalJobs: totalJobs ?? this.totalJobs,
        completedJobs: completedJobs ?? this.completedJobs,
        responseTimeMinutes: responseTimeMinutes ?? this.responseTimeMinutes,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        bio: bio ?? this.bio,
        profileImageUrl: profileImageUrl ?? this.profileImageUrl,
        portfolioImageUrls: portfolioImageUrls ?? this.portfolioImageUrls,
        isVerified: isVerified ?? this.isVerified,
        isAvailable: isAvailable ?? this.isAvailable,
        approvalStatus: approvalStatus ?? this.approvalStatus,
        verificationStatus: verificationStatus ?? this.verificationStatus,
        betaTester: betaTester ?? this.betaTester,
        trustScore: trustScore ?? this.trustScore,
        responseRatePercent: responseRatePercent ?? this.responseRatePercent,
        cancellationRatePercent: cancellationRatePercent ?? this.cancellationRatePercent,
        openDisputeCount: openDisputeCount ?? this.openDisputeCount,
        accountType: accountType ?? this.accountType,
        businessName: businessName ?? this.businessName,
        businessRegistrationNumber:
            businessRegistrationNumber ?? this.businessRegistrationNumber,
        businessAddress: businessAddress ?? this.businessAddress,
      );
}
