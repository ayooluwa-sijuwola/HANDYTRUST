import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? jobId;
  /// Stage 6: server-set deep link (e.g. /job/{id}); see safeNotificationRoute.
  final String? route;

  /// Stage 8.2 (F-1): for `message_received`, the other participant of the
  /// conversation (the chat route is built from it; `route` stays /job/{id}
  /// for older app versions).
  final String? chatWith;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.isRead = false,
    required this.createdAt,
    this.readAt,
    this.jobId,
    this.route,
    this.chatWith,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    DateTime toDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return DateTime.tryParse(v as String? ?? '') ?? DateTime.now();
    }

    DateTime? toDateNullable(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      return DateTime.tryParse(v as String? ?? '');
    }

    return NotificationModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      isRead: json['isRead'] as bool? ?? false,
      createdAt: toDate(json['createdAt']),
      readAt: toDateNullable(json['readAt']),
      jobId: json['jobId'] as String?,
      route: json['route'] as String?,
      chatWith: json['chatWith'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'type': type,
        'title': title,
        'body': body,
        'isRead': isRead,
        'createdAt': Timestamp.fromDate(createdAt),
        if (readAt != null) 'readAt': Timestamp.fromDate(readAt!),
        if (jobId != null) 'jobId': jobId,
        if (route != null) 'route': route,
        if (chatWith != null) 'chatWith': chatWith,
      };
}
