import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../models/sync_models.dart';
import '../utils/format.dart';
import '../utils/storage.dart';

/// Port of `src/context/SettingsContext.tsx` plus the theme preference
/// from `src/components/ThemeProvider.tsx`.
class SettingsProvider extends ChangeNotifier {
  /// [db] is used to queue settings changes for the shop while signed in.
  SettingsProvider(this._prefs, [this._db]) {
    _settings = readJsonObject(_prefs, storageKey, AppSettings.fromJson) ?? AppSettings.defaults;
    _themeMode = _prefs.getString(themeKey) == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  static const storageKey = 'shop_settings';
  static const themeKey = 'shop-ui-theme';

  final SharedPreferences _prefs;
  final AppDatabase? _db;
  late AppSettings _settings;
  late ThemeMode _themeMode;

  AppSettings get settings => _settings;
  ThemeMode get themeMode => _themeMode;

  /// Changing the currency also updates its symbol. A blank shop name is
  /// ignored so the header and receipts always show a name.
  void updateSettings({String? shopName, String? currency}) {
    final name = shopName?.trim();
    var symbol = _settings.currencySymbol;
    if (currency != null) {
      for (final c in currencies) {
        if (c.code == currency) symbol = c.symbol;
      }
    }
    _settings = AppSettings(
      currency: currency ?? _settings.currency,
      currencySymbol: symbol,
      shopName: name == null || name.isEmpty ? _settings.shopName : name,
    );
    writeJson(_prefs, storageKey, _settings.toJson());
    notifyListeners();
    final db = _db;
    if (db != null && db.syncEnabled) {
      unawaited(
        db
            .enqueue('settings.update', {'shopName': _settings.shopName, 'currency': _settings.currency})
            .catchError((Object e) => reportStorageIssue('Could not queue the settings change for the shop.', e)),
      );
    }
  }

  /// Takes the shop's settings from the server. Not queued back.
  void applyServerSettings(ShopInfo shop) {
    if (shop.name == _settings.shopName &&
        shop.currency == _settings.currency &&
        shop.currencySymbol == _settings.currencySymbol) {
      return;
    }
    _settings = AppSettings(currency: shop.currency, currencySymbol: shop.currencySymbol, shopName: shop.name);
    writeJson(_prefs, storageKey, _settings.toJson());
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    writeString(_prefs, themeKey, mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  /// [amount] is in minor units.
  String formatPrice(int amount) => '${_settings.currencySymbol}${formatIndian(amount)}';
}
