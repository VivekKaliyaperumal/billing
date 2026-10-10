import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../utils/format.dart';
import '../utils/validation.dart';

/// A parsed, validated backup file.
class Backup {
  const Backup({required this.data, required this.settings, required this.exportedAt});
  final ShopData data;
  final AppSettings settings;
  final DateTime exportedAt;
}

/// Exports all shop data to a JSON file and restores it again.
///
/// A backup file comes from outside the app, so restoring treats it as
/// untrusted: size is capped and every record is validated before anything
/// is replaced. A file that fails any check is rejected as a whole.
class BackupService {
  static const _app = 'thyantra_billing';
  static const _formatVersion = 1;
  static const maxFileBytes = 20 * 1024 * 1024;

  static String encode(ShopData data, AppSettings settings, {DateTime? now}) => const JsonEncoder.withIndent(' ').convert({
        'app': _app,
        'formatVersion': _formatVersion,
        'exportedAt': (now ?? DateTime.now()).toIso8601String(),
        'settings': settings.toJson(),
        'products': data.products.map((p) => p.toJson()).toList(),
        'sales': data.sales.map((s) => s.toJson()).toList(),
        'customers': data.customers.map((c) => c.toJson()).toList(),
      });

  /// Throws [FormatException] with a user-facing message if the file is not
  /// a valid backup.
  static Backup decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      throw const FormatException('This file is not a Thyantra Billing backup.');
    }
    if (json is! Map<String, dynamic> || json['app'] != _app) {
      throw const FormatException('This file is not a Thyantra Billing backup.');
    }
    final map = json;
    if (map['formatVersion'] != _formatVersion) {
      throw const FormatException('This backup was made by a newer version of the app. Please update first.');
    }
    try {
      List<T> list<T>(String key, T Function(Map<String, dynamic>) fromJson) =>
          (map[key] as List<dynamic>).map((e) => fromJson(e as Map<String, dynamic>)).toList();
      // Images that aren't https (allowed by older versions) are dropped
      // rather than failing the whole restore.
      final products = [
        for (final p in list('products', Product.fromJson))
          p.image == null || isValidImageUrl(p.image!) ? p : p.copyWith(image: () => null),
      ];
      final sales = list('sales', Sale.fromJson);
      final customers = list('customers', Customer.fromJson);
      final settings = AppSettings.fromJson(map['settings'] as Map<String, dynamic>);
      _validate(products, sales, customers, settings);
      return Backup(
        data: ShopData(products: products, sales: sales..sort((a, b) => b.date.compareTo(a.date)), customers: customers),
        settings: settings,
        exportedAt: DateTime.parse(map['exportedAt'] as String),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('The backup file is damaged and cannot be restored.');
    }
  }

  static void _validate(List<Product> products, List<Sale> sales, List<Customer> customers, AppSettings settings) {
    void check(bool ok) {
      if (!ok) throw const FormatException('The backup file is damaged and cannot be restored.');
    }

    bool unique(Iterable<String> ids) => ids.toSet().length == ids.length;
    check(unique(products.map((p) => p.id)));
    check(unique(sales.map((s) => s.id)));
    check(unique(customers.map((c) => c.id)));
    check(unique(customers.map((c) => normalizePhone(c.phone))));
    check(unique(customers.expand((c) => c.transactions).map((t) => t.id)));
    for (final p in products) {
      check(p.name.trim().isNotEmpty && p.price >= 0 && p.stock >= 0 && p.usageCount >= 0);
    }
    for (final c in customers) {
      check(c.name.trim().isNotEmpty && isValidPhone(c.phone) && c.pendingAmount >= 0);
    }
    for (final s in sales) {
      check(s.items.isNotEmpty && s.items.every((i) => i.quantity > 0 && i.product.price >= 0));
    }
    check(currencies.any((c) => c.code == settings.currency && c.symbol == settings.currencySymbol));
  }

  /// Writes the backup to a temporary file and opens the share sheet so the
  /// user can save it to Drive, email it, etc.
  static Future<void> share(ShopData data, AppSettings settings) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/thyantra-billing-backup-${dateFile.format(DateTime.now())}.json');
    await file.writeAsString(encode(data, settings));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: 'Thyantra Billing backup',
    ));
  }

  /// Lets the user choose a backup file. Returns null if they cancel.
  /// Throws [FormatException] if the file is too large or unreadable.
  static Future<String?> pickFile() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
    if (file == null) return null;
    final size = await file.length();
    if (size != null && size > maxFileBytes) throw const FormatException('This file is too large to be a backup.');
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      throw const FormatException('Could not read the selected file.');
    }
    if (bytes.length > maxFileBytes) throw const FormatException('This file is too large to be a backup.');
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('This file is not a Thyantra Billing backup.');
    }
  }
}
