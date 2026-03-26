import 'package:anaki_orm/anaki_orm.dart';
import 'package:vaden/vaden.dart';

import '../dto/user_dto.dart';

@Repository()
class UserRepository {
  final AnakiQueryBuilder _qb;

  UserRepository(this._qb);

  Future<List<UserDTO>> findAll() {
    return _qb.select<UserDTO>('users').orderBy('id').list();
  }

  Future<UserDTO?> findById(int id) {
    return _qb.select<UserDTO>('users').where('id = @id', {'id': id}).first();
  }

  Future<List<UserDTO>> findActive() {
    return _qb
        .select<UserDTO>('users')
        .where('active = @active', {'active': true})
        .orderBy('name')
        .list();
  }

  Future<PagedResult<UserDTO>> findPaged({int page = 1, int pageSize = 20}) {
    return _qb
        .select<UserDTO>('users')
        .orderBy('id')
        .paged(page: page, pageSize: pageSize);
  }

  Future<int> create(UserDTO user) {
    return _qb.insert<UserDTO>('users').entity(user).run();
  }

  Future<int> update(int id, UpdateUserDTO user) {
    if (user.name == null && user.email == null && user.active == null) {
      return Future.value(0);
    }

    return _qb.update('users').setEntity<UpdateUserDTO>(user).where(
      'id = @id',
      {'id': id},
    ).run();
  }

  Future<int> delete(int id) {
    return _qb.delete('users').where('id = @id', {'id': id}).run();
  }
}
