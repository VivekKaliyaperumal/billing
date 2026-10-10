import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/suite.dart';

void main() {
  sqfliteFfiInit();
  runSuite(databaseFactoryFfi, () async => inMemoryDatabasePath);
}
