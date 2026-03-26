import 'package:vaden_anaki_example/vaden_application.dart';

Future<void> main(List<String> args) async {
  final vaden = VadenApp();
  await vaden.setup();
  final server = await vaden.run(args);
  print('Server listening on port ${server.port}');
}

