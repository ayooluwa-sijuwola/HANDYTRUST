import 'package:cloud_firestore/cloud_firestore.dart';

/// A user can hold multiple roles simultaneously (customer + artisan).
/// [activeRole] tracks which dashboard they're currently viewing.
enum UserRole { customer, artisan }

class UserModel {
  final String uid;
  final String name;
  /// Chosen handle displayed in greetings and reviews. Falls back to [name].
  final String? username;
  /// Profile photo URL in Firebase Storage (profiles/{uid}/avatar.jpg).
  final String? photoUrl;
  final String? email;
  final String? phoneNumber;
  /// All roles this account holds. At least one element always present.
  final List<String> roles;
  /// Which role the user is currently operating as.
  final String activeRole;
  final String? category;
  final String? location;
  final DateTime createdAt;
  final bool emailVerified;
  final bool notificationsEnabled;
  /// 'active' | 'suspended' — admin-only field, see [isSuspended].
  final String accountStatus;
  /// Stage 4/5 (D9): 'administrative' | 'verification' | 'fraud' | 'safety' |
  /// 'security'. Admin/server-written only (firestore.rules).
  final String? suspensionType;
  /// True when the user has submitted an account deletion request.
  final bool accountDeletionRequested;

  /// Q-5 (Stage 8.2): server-written payout freeze, parsed for read-only
  /// display. Written only by the `adminSetPayoutFreeze` Cloud Function;
  /// never serialised by the client.
  final bool payoutFrozen;
  final String? payoutFreezeReason;

  UserModel({
    required this.uid,
    required this.name,
    this.username,
    this.photoUrl,
    this.email,
    this.phoneNumber,
    List<String>? roles,
    String? activeRole,
    this.category,
    this.location,
    DateTime? createdAt,
    this.emailVerified = false,
    this.notificationsEnabled = true,
    this.accountStatus = 'active',
    this.suspensionType,
    this.accountDeletionRequested = false,
    this.payoutFrozen = false,
    this.payoutFreezeReason,
  })  : roles = roles ?? const ['customer'],
        activeRole = activeRole ?? (roles?.first ?? 'customer'),
        createdAt = createdAt ?? DateTime.now();

  bool get isSuspended => accountStatus == 'suspended';

  /// Restricted existing-jobs mode (D9): administrative / verification
  /// suspensions may still access and complete their existing jobs.
  bool get hasRestrictedSuspension =>
      isSuspended && (suspensionType == 'administrative' || suspensionType == 'verification');

  /// Fraud / safety / security — or an unclassified suspension (fails
  /// closed, mirroring the server): existing jobs are visible and disputes
  /// stay open, but nothing can progress or move money.
  bool get hasFreezingSuspension => isSuspended && !hasRestrictedSuspension;

  /// Display name: prefers [username], falls back to first word of [name].
  String get displayUsername => username?.isNotEmpty == true
      ? username!
      : name.split(' ').first;

  /// Legacy accessor — returns the primary role as enum.
  UserRole get role {
    if (activeRole == 'artisan' ||
        (roles.contains('artisan') && !roles.contains('customer'))) {
      return UserRole.artisan;
    }
    return UserRole.customer;
  }

  bool get isArtisan => roles.contains('artisan');
  bool get isCustomer => roles.contains('customer');
  bool get isAdmin => roles.contains('admin');
  bool get hasBothRoles => isArtisan && isCustomer;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];
    List<String> roles;
    if (rawRoles is List) {
      roles = List<String>.from(rawRoles);
    } else {
      final legacyRole = json['role'] as String?;
      roles = legacyRole != null ? [legacyRole] : ['customer'];
    }

    return UserModel(
      uid: json['uid'] as String,
      name: json['name'] as String? ?? '',
      username: json['username'] as String?,
      photoUrl: json['photoUrl'] as String?,
      email: json['email'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      roles: roles,
      activeRole: json['activeRole'] as String? ?? roles.first,
      category: json['category'] as String?,
      location: json['location'] as String?,
      createdAt: _parseDate(json['createdAt']),
      emailVerified: json['emailVerified'] as bool? ?? false,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      accountStatus: json['accountStatus'] as String? ?? 'active',
      suspensionType: json['suspensionType'] as String?,
      accountDeletionRequested:
          json['accountDeletionRequested'] as bool? ?? false,
      payoutFrozen: json['payoutFrozen'] == true,
      payoutFreezeReason: json['payoutFreezeReason'] as String?,
    );
  }

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      if (username != null) 'username': username,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'email': email,
      'phoneNumber': phoneNumber,
      'roles': roles,
      'activeRole': activeRole,
      'category': category,
      'location': location,
      'createdAt': Timestamp.fromDate(createdAt),
      'emailVerified': emailVerified,
      'notificationsEnabled': notificationsEnabled,
      'accountStatus': accountStatus,
      'accountDeletionRequested': accountDeletionRequested,
    };
  }

  UserModel copyWith({
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
  }) {
    return UserModel(
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
      accountDeletionRequested:
          accountDeletionRequested ?? this.accountDeletionRequested,
      payoutFrozen: payoutFrozen,
      payoutFreezeReason: payoutFreezeReason,
    );
  }
}
