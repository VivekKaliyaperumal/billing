import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../utils/format.dart';

/// Port of `src/context/SettingsContext.tsx` plus the theme preference
/// from `src/components/ThemeProvider.tsx`.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._prefs) {
    final stored = _prefs.getString(storageKey);
    _settings = stored != null
        ? AppSettings.fromJson(jsonDecode(stored) as Map<String, dynamic>)
        : AppSettings.defaults;
    _themeMode = _prefs.getString(themeKey) == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  static const storageKey = 'shop_settings';
  static const themeKey = 'shop-ui-theme';

  final SharedPreferences _prefs;
  late AppSettings _settings;
  late ThemeMode _themeMode;

  AppSettings get settings => _settings;
  ThemeMode get themeMode => _themeMode;

  /// Changing the currency also updates its symbol.
  void updateSettings({String? shopName, String? currency}) {
    var symbol = _settings.currencySymbol;
    if (currency != null) {
      for (final c in currencies) {
        if (c.code == currency) symbol = c.symbol;
      }
    }
    _settings = AppSettings(
      currency: currency ?? _settings.currency,
      currencySymbol: symbol,
      shopName: shopName ?? _settings.shopName,
    );
    _prefs.setString(storageKey, jsonEncode(_settings.toJson()));
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs.setString(themeKey, mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  String formatPrice(double amount) => '${_settings.currencySymbol}${formatIndian(amount)}';
}
