import 'package:vaden/vaden.dart';

@DTO()
class UserDTO {
  final int? id;
  final String name;
  final String? email;
  final bool active;

  UserDTO({this.id, required this.name, this.email, this.active = true});
}

@DTO()
class UpdateUserDTO {
  final int? id;
  final String? name;
  final String? email;
  final bool? active;

  UpdateUserDTO({this.id, this.name, this.email, this.active});
}
