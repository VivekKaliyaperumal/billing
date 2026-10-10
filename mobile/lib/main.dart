import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/cart_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/product_provider.dart';
import 'providers/sales_history_provider.dart';
import 'providers/settings_provider.dart';
import 'shell/home_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(BillingApp(prefs: prefs));
}

class BillingApp extends StatelessWidget {
  const BillingApp({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider(prefs)),
        ChangeNotifierProvider(create: (_) => ProductProvider(prefs)),
        ChangeNotifierProvider(create: (_) => SalesHistoryProvider(prefs)),
        ChangeNotifierProvider(create: (_) => CustomerProvider(prefs)),
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          title: 'Billing App',
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
