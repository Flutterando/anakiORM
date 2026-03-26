import 'dart:convert';

import 'package:vaden/vaden.dart';

import 'dto/user_dto.dart';
import 'repository/user_repository.dart';

@Api(tag: 'Users', description: 'User CRUD operations')
@Controller('/users')
class UserController {
  final UserRepository _repository;
  final DSON _dson;

  UserController(this._repository, this._dson);

  @Get('/')
  Future<List<UserDTO>> findAll() {
    return _repository.findAll();
  }

  @Get('/active')
  Future<List<UserDTO>> findActive() {
    return _repository.findActive();
  }

  @Get('/<id>')
  Future<Response> findById(@Param('id') int id) async {
    final user = await _repository.findById(id);
    if (user == null) {
      throw ResponseException.notFound('User not found');
    }
    final json = _dson.toJson<UserDTO>(user);
    return Response.ok(jsonEncode(json));
  }

  @Post('/')
  Future<Response> create(@Body() UserDTO user) async {
    await _repository.create(user);
    return Response(201);
  }

  @Put('/<id>')
  Future<Response> update(
    @Param('id') int id,
    @Body() UpdateUserDTO user,
  ) async {
    final affected = await _repository.update(id, user);
    if (affected == 0) {
      throw ResponseException.notFound('User not found');
    }
    return Response.ok('updated');
  }

  @Delete('/<id>')
  Future<Response> delete(@Param('id') int id) async {
    final affected = await _repository.delete(id);
    if (affected == 0) {
      throw ResponseException.notFound('User not found');
    }
    return Response.ok('deleted');
  }
}
