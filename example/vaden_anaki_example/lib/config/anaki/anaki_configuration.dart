import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_postgres/anaki_postgres.dart';
import 'package:vaden/vaden.dart';

@Configuration()
class AnakiConfiguration {
  @Bean()
  AnakiDb anakiDb(ApplicationSettings settings) {
    final db = settings['database'] as Map;
    return AnakiDb(
      PostgresDriver(
        host: db['host'] as String,
        port: db['port'] as int,
        username: db['username'] as String,
        password: db['password'] as String,
        database: db['database'] as String,
        sslMode: db['ssl_mode'] as String?,
      ),
    );
  }

  @Bean()
  AnakiQueryBuilder rowAdapter(DSON dson, AnakiDb db) {
    return AnakiQueryBuilder(db, RowAdapter(dson.fromJson, dson.toJson));
  }
}
