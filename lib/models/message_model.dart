import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, negotiation, system }

class MessageModel {
  final String id;
  final String jobId;
  final String senderId;
  final String receiverId;
  final String text;
  final MessageType type;
  final String? imageUrl;
  final double? proposedAmount;
  final bool isRead;

  /// Stage 8.2: true while the message exists only in the local Firestore
  /// cache (`hasPendingWrites`), i.e. not yet acknowledged by the server.
  /// Never serialised; set by ChatService from snapshot metadata so the UI
  /// can show "Sending" instead of a false "Sent".
  final bool isPending;

  /// Stage 8.2: server time the recipient's device first had the message
  /// (set once by the recipient's app) and the time it was read.
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime createdAt;

  const MessageModel({
    required this.id,
    required this.jobId,
    required this.senderId,
    required this.receiverId,
    required this.text,
    this.type = MessageType.text,
    this.imageUrl,
    this.proposedAmount,
    this.isRead = false,
    required this.createdAt,
    this.isPending = false,
    this.deliveredAt,
    this.readAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    DateTime created;
    final raw = json['createdAt'];
    if (raw is Timestamp) {
      created = raw.toDate();
    } else {
      created = DateTime.tryParse(raw as String? ?? '') ?? DateTime.now();
    }

    return MessageModel(
      id: json['id'] as String,
      jobId: json['jobId'] as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String,
      text: json['text'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      imageUrl: json['imageUrl'] as String?,
      deliveredAt: json['deliveredAt'] is Timestamp ? (json['deliveredAt'] as Timestamp).toDate() : null,
      readAt: json['readAt'] is Timestamp ? (json['readAt'] as Timestamp).toDate() : null,
      proposedAmount: (json['proposedAmount'] as num?)?.toDouble(),
      isRead: json['isRead'] as bool? ?? false,
      createdAt: created,
    );
  }

  MessageModel withPending(bool pending) => pending == isPending
      ? this
      : MessageModel(
          id: id,
          jobId: jobId,
          senderId: senderId,
          receiverId: receiverId,
          text: text,
          type: type,
          imageUrl: imageUrl,
          proposedAmount: proposedAmount,
          isRead: isRead,
          createdAt: createdAt,
          isPending: pending,
          deliveredAt: deliveredAt,
          readAt: readAt,
        );

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'senderId': senderId,
        'receiverId': receiverId,
        'text': text,
        'type': type.name,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (proposedAmount != null) 'proposedAmount': proposedAmount,
        'isRead': isRead,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  MessageModel copyWith({bool? isRead}) => MessageModel(
        id: id,
        jobId: jobId,
        senderId: senderId,
        receiverId: receiverId,
        text: text,
        type: type,
        imageUrl: imageUrl,
        proposedAmount: proposedAmount,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );
}
