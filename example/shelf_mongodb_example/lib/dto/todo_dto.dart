import 'package:anaki_mongodb/anaki_mongodb.dart';

class TodoDTO {
  final ObjectId? id;
  final String title;
  final String? description;
  final bool completed;
  final DateTime createdAt;

  TodoDTO({
    this.id,
    required this.title,
    this.description,
    this.completed = false,
    required this.createdAt,
  });

  factory TodoDTO.fromJson(Map<String, dynamic> json) {
    return TodoDTO(
      id: json['_id'] as ObjectId?,
      title: json['title'] as String,
      description: json['description'] as String?,
      completed: json['completed'] as bool? ?? false,
      createdAt: json['createdAt'] as DateTime,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) '_id': id,
        'title': title,
        'description': description,
        'completed': completed,
        'createdAt': createdAt,
      };

  /// JSON-safe form for HTTP responses.
  Map<String, dynamic> toApiJson() => {
        'id': id?.hexString,
        'title': title,
        'description': description,
        'completed': completed,
        'createdAt': createdAt.toIso8601String(),
      };
}
