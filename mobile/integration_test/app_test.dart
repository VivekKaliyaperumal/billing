import 'dart:io';

import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../test/support/suite.dart';

/// Runs the logic suite on a real Android device or emulator:
///   `flutter test integration_test -d DEVICE_ID`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var n = 0;
  runSuite(databaseFactory, () async {
    final path = p.join(await getDatabasesPath(), 'test_${DateTime.now().microsecondsSinceEpoch}_${n++}.db');
    if (File(path).existsSync()) await deleteDatabase(path);
    return path;
  });
}
