import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_info.dart';
import 'data/app_database.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/product_provider.dart';
import 'providers/sales_history_provider.dart';
import 'providers/settings_provider.dart';
import 'services/api_client.dart';
import 'services/sync_service.dart';
import 'shell/home_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  final prefs = await SharedPreferences.getInstance();
  try {
    final db = await AppDatabase.open(prefs: prefs);
    final data = await db.loadAll();
    // Reads the saved login from this phone only; never waits for the network.
    final api = ApiClient();
    final auth = AuthProvider(api, prefs);
    await auth.restore();
    runApp(BillingApp(prefs: prefs, db: db, data: data, api: api, auth: auth));
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

class BillingApp extends StatefulWidget {
  const BillingApp({
    super.key,
    required this.prefs,
    required this.db,
    required this.data,
    required this.api,
    required this.auth,
  });
  final SharedPreferences prefs;
  final AppDatabase db;
  final ShopData data;
  final ApiClient api;
  final AuthProvider auth;

  @override
  State<BillingApp> createState() => _BillingAppState();
}

/// Owns the providers, so the sync service can reload them after a download.
class _BillingAppState extends State<BillingApp> {
  late final _settings = SettingsProvider(widget.prefs, widget.db);
  late final _products = ProductProvider(widget.db, widget.data.products);
  late final _history = SalesHistoryProvider(widget.data.sales);
  late final _customers = CustomerProvider(widget.db, widget.data.customers);
  late final _cart = CartProvider();
  late final _sync = SyncService(
    db: widget.db,
    api: widget.api,
    auth: widget.auth,
    products: _products,
    history: _history,
    customers: _customers,
    settings: _settings,
  );

  @override
  void initState() {
    super.initState();
    // Signed out: the app works on this phone only, as before.
    if (widget.auth.isSignedIn) unawaited(_sync.start());
  }

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: widget.db),
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider.value(value: _products),
        ChangeNotifierProvider.value(value: _history),
        ChangeNotifierProvider.value(value: _customers),
        ChangeNotifierProvider.value(value: _cart),
        ChangeNotifierProvider.value(value: widget.auth),
        ChangeNotifierProvider.value(value: _sync),
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
