/// Data Transfer Object for a Todo item.
///
/// Compatible with Vaden's @DTO() pattern — uses fromJson/toJson convention.
class TodoDTO {
  final int? id;
  final String title;
  final String? description;
  final bool completed;

  TodoDTO({
    this.id,
    required this.title,
    this.description,
    this.completed = false,
  });

  factory TodoDTO.fromJson(Map<String, dynamic> json) => TodoDTO(
        id: json['id'] as int?,
        title: json['title'] as String,
        description: json['description'] as String?,
        completed: json['completed'] == true || json['completed'] == 1,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'title': title,
        'description': description,
        'completed': completed,
      };

  TodoDTO copyWith({
    int? id,
    String? title,
    String? description,
    bool? completed,
  }) =>
      TodoDTO(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        completed: completed ?? this.completed,
      );
}
