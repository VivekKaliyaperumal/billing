import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_info.dart';
import 'data/app_database.dart';
import 'providers/cart_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/product_provider.dart';
import 'providers/sales_history_provider.dart';
import 'providers/settings_provider.dart';
import 'shell/home_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  final prefs = await SharedPreferences.getInstance();
  try {
    final db = await AppDatabase.open(prefs: prefs);
    final data = await db.loadAll();
    runApp(BillingApp(prefs: prefs, db: db, data: data));
  } catch (e, st) {
    debugPrint('startup failed: $e\n$st');
    runApp(const StartupErrorApp());
  }
}

void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Inter', 'Sora']) {
      final text = await rootBundle.loadString('assets/fonts/OFL-$font.txt');
      yield LicenseEntryWithLineBreaks(['$font font'], text);
    }
  });
}

class BillingApp extends StatelessWidget {
  const BillingApp({super.key, required this.prefs, required this.db, required this.data});
  final SharedPreferences prefs;
  final AppDatabase db;
  final ShopData data;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: db),
        ChangeNotifierProvider(create: (_) => SettingsProvider(prefs)),
        ChangeNotifierProvider(create: (_) => ProductProvider(db, data.products)),
        ChangeNotifierProvider(create: (_) => SalesHistoryProvider(data.sales)),
        ChangeNotifierProvider(create: (_) => CustomerProvider(db, data.customers)),
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          title: appName,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(AppPalette.light),
          darkTheme: buildTheme(AppPalette.dark),
          themeMode: settings.themeMode,
          home: const HomeShell(),
        ),
      ),
    );
  }
}

/// Shown if the database cannot be opened, instead of a crash loop. Data on
/// the device is left untouched.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(AppPalette.light),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Thyantra Billing could not open its data.\n\n'
                'Your records have not been changed. Please restart the app. '
                'If this keeps happening, free up storage space on the phone or contact $supportEmail.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
