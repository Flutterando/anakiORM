import 'package:anaki_orm/anaki_orm.dart';
import 'package:vaden/vaden.dart';

@Component()
class DatabaseRunner implements ApplicationRunner {
  final AnakiDb _db;

  DatabaseRunner(this._db);

  @override
  Future<void> run(VadenApplication app) async {
    await _db.open();
    print('[Anaki] Database connected.');

    final executed = await Migrator(_db).run('migrations/');
    if (executed.isNotEmpty) {
      print('[Anaki] Migrations applied: ${executed.join(', ')}');
    } else {
      print('[Anaki] No pending migrations.');
    }

    final seeded = await Seeder(_db).run('seeds/');
    if (seeded.isNotEmpty) {
      print('[Anaki] Seeds applied: ${seeded.join(', ')}');
    } else {
      print('[Anaki] No pending seeds.');
    }
  }
}
