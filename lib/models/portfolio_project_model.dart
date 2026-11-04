import 'package:cloud_firestore/cloud_firestore.dart';

/// A single portfolio project belonging to an artisan.
///
/// Stored at `portfolio_projects/{projectId}` (top-level collection) with an
/// `artisanId` field for querying. Distinct from the legacy `portfolioImageUrls`
/// array on the artisan doc — the legacy field is preserved for backward compat
/// and shown alongside projects on the artisan profile.
class PortfolioProjectModel {
  final String id;
  final String artisanId;
  final String title;
  final String description;
  final String category;
  final List<String> imageUrls;
  final DateTime createdAt;

  const PortfolioProjectModel({
    required this.id,
    required this.artisanId,
    required this.title,
    required this.description,
    required this.category,
    this.imageUrls = const [],
    required this.createdAt,
  });

  factory PortfolioProjectModel.fromJson(Map<String, dynamic> json) =>
      PortfolioProjectModel(
        id: json['id'] as String? ?? '',
        artisanId: json['artisanId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        category: json['category'] as String? ?? '',
        imageUrls: List<String>.from(json['imageUrls'] ?? []),
        createdAt: _toDate(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'artisanId': artisanId,
        'title': title,
        'description': description,
        'category': category,
        'imageUrls': imageUrls,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  PortfolioProjectModel copyWith({
    String? title,
    String? description,
    String? category,
    List<String>? imageUrls,
  }) =>
      PortfolioProjectModel(
        id: id,
        artisanId: artisanId,
        title: title ?? this.title,
        description: description ?? this.description,
        category: category ?? this.category,
        imageUrls: imageUrls ?? this.imageUrls,
        createdAt: createdAt,
      );

  static DateTime _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }
}
