import 'dart:convert';

import 'package:billing_mobile/data/app_database.dart';
import 'package:billing_mobile/models/models.dart';
import 'package:billing_mobile/providers/cart_provider.dart';
import 'package:billing_mobile/providers/customer_provider.dart';
import 'package:billing_mobile/providers/product_provider.dart';
import 'package:billing_mobile/providers/sales_history_provider.dart';
import 'package:billing_mobile/providers/settings_provider.dart';
import 'package:billing_mobile/services/backup_service.dart';
import 'package:billing_mobile/services/checkout_service.dart';
import 'package:billing_mobile/utils/csv_export.dart';
import 'package:billing_mobile/utils/format.dart';
import 'package:billing_mobile/utils/money.dart';
import 'package:billing_mobile/utils/storage.dart';
import 'package:billing_mobile/utils/validation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// The full logic suite, run on the desktop VM with in-memory SQLite
/// (test/widget_test.dart) and on an Android device with the real sqflite
/// plugin (integration_test/app_test.dart).
///
/// [newPath] returns a fresh, empty database location for each call.
void runSuite(DatabaseFactory factory, Future<String> Function() newPath) {
  late SharedPreferences prefs;

  Future<AppDatabase> openDb([Map<String, Object> legacy = const {}]) async {
    SharedPreferences.setMockInitialValues(legacy);
    prefs = await SharedPreferences.getInstance();
    return AppDatabase.open(prefs: prefs, factory: factory, path: await newPath());
  }

  setUp(() => storageIssues.value = null);

  Product prod(String id, int price, {int stock = 9}) =>
      Product(id: id, name: id, price: price, stock: stock, usageCount: 0, createdAt: DateTime(2026));

  group('money', () {
    test('formatIndian uses en-IN grouping with 2 decimals', () {
      expect(formatIndian(0), '0.00');
      expect(formatIndian(6000), '60.00');
      expect(formatIndian(123456), '1,234.56');
      expect(formatIndian(123456789), '12,34,567.89');
      expect(formatIndian(-5), '-0.05');
    });

    test('parseAmount accepts plain amounts only', () {
      expect(parseAmount('60'), 6000);
      expect(parseAmount('60.5'), 6050);
      expect(parseAmount(' 0.05 '), 5);
      for (final bad in ['NaN', 'Infinity', '1e5', '-1', '1.234', '', 'abc', '1,000', '100000000']) {
        expect(parseAmount(bad), isNull, reason: bad);
      }
    });

    test('integer totals have no floating-point drift', () {
      final cart = CartProvider()
        ..add(prod('a', 10), 9)
        ..add(prod('b', 20), 9);
      expect(cart.total, 30);
      expect(formatIndian(cart.total), '0.30');
    });

    test('legacy decimal JSON is read as minor units', () {
      final p = Product.fromJson({
        'id': '1', 'name': 'Milk', 'price': 60.5, 'stock': 1, 'usageCount': 0,
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(p.price, 6050);
      expect(p.toJson()['priceMinor'], 6050);
    });
  });

  group('database', () {
    test('a new install is seeded with the starter products', () async {
      final db = await openDb();
      expect((await db.loadAll()).products, hasLength(8));
      await db.close();
    });

    test('legacy SharedPreferences data is imported, cleaned and removed', () async {
      final legacyProducts = jsonEncode([
        {'id': 'p1', 'name': 'Tea', 'price': 10.5, 'stock': -3, 'usageCount': 2, 'createdAt': '2026-01-01T00:00:00.000'},
        {'id': 'bad', 'name': 'broken'},
      ]);
      final legacyCustomers = jsonEncode([
        for (final id in ['c1', 'c2'])
          {'id': id, 'name': 'Asha', 'phone': '98765 43210', 'pendingAmount': 50, 'createdAt': '2026-01-01T00:00:00.000', 'transactions': <Object>[]},
      ]);
      final db = await openDb({'shop_products': legacyProducts, 'shop_customers': legacyCustomers});
      final data = await db.loadAll();
      expect(data.products.single.price, 1050);
      expect(data.products.single.stock, 0, reason: 'negative stock from the old bug is clamped');
      expect(data.customers.single.phone, '9876543210', reason: 'duplicate phone dropped');
      expect(prefs.containsKey('shop_products'), isFalse);
      expect(prefs.getKeys().where((k) => k.startsWith('shop_products_corrupt_')), hasLength(1));
      await db.close();
    });
  });

  group('checkout', () {
    late AppDatabase db;
    late ProductProvider products;
    late CartProvider cart;
    late SalesHistoryProvider history;
    late CustomerProvider customers;
    late CheckoutService service;

    setUp(() async {
      db = await openDb();
      final data = await db.loadAll();
      products = ProductProvider(db, data.products);
      cart = CartProvider();
      history = SalesHistoryProvider(data.sales);
      customers = CustomerProvider(db, data.customers);
      service = CheckoutService(db: db, cart: cart, products: products, history: history, customers: customers);
    });

    tearDown(() => db.close());

    test('cash sale is saved with stock changes and clears the cart', () async {
      cart
        ..add(products.byId('1')!, 50)
        ..add(products.byId('1')!, 50);
      expect(await service.checkout(), isA<CheckoutCompleted>());
      expect(cart.isEmpty, isTrue);
      final saved = await db.loadAll();
      expect(saved.sales.single.total, 12000);
      expect(saved.products.firstWhere((p) => p.id == '1').stock, 48);
      expect(products.byId('1')!.stock, 48);
    });

    test('price edited after adding to cart: cart repriced, nothing sold', () async {
      final milk = products.byId('1')!;
      cart.add(milk, 50);
      await products.updateProduct('1', name: milk.name, price: 7000, stock: 50);
      expect(await service.checkout(), isA<CheckoutCartChanged>());
      expect(history.sales, isEmpty);
      expect(cart.total, 7000);
      expect(((await service.checkout()) as CheckoutCompleted).sale.total, 7000);
    });

    test('stock reduced or product deleted after adding: cart corrected, stock never negative', () async {
      final milk = products.byId('1')!;
      for (var i = 0; i < 10; i++) {
        cart.add(milk, 50);
      }
      cart.add(products.byId('2')!, 30);
      await products.updateProduct('1', name: milk.name, price: milk.price, stock: 4);
      await products.deleteProduct('2');
      final result = (await service.checkout()) as CheckoutCartChanged;
      expect(result.changes, hasLength(2));
      expect(cart.items.single.quantity, 4);
      await service.checkout();
      expect((await db.loadAll()).products.firstWhere((p) => p.id == '1').stock, 0);
    });

    test('the database refuses to oversell even if memory is stale', () async {
      final oversell = Sale(
        id: 'x',
        items: [CartItem(product: products.byId('1')!, quantity: 51)],
        total: 1,
        date: DateTime(2026),
      );
      await expectLater(db.recordSale(oversell), throwsA(isA<ConflictException>()));
      expect((await db.loadAll()).sales, isEmpty, reason: 'transaction rolled back');
    });

    test('credit sale saves sale, new customer and credit together', () async {
      cart.add(products.byId('1')!, 50);
      final result = await service.creditCheckout(name: ' Asha ', phone: '98765 43210');
      expect(result, isA<CheckoutCompleted>());
      final c = (await db.loadAll()).customers.single;
      expect(c.name, 'Asha');
      expect(c.phone, '9876543210');
      expect(c.pendingAmount, 6000);
      expect(c.transactions.single.saleId, (result as CheckoutCompleted).sale.id);
      expect(customers.customers.single.pendingAmount, 6000);
    });

    test('credit sale rejects blank names, bad phones and duplicate phones', () async {
      await customers.addCustomer(name: 'Asha', phone: '9876543210');
      cart.add(products.byId('1')!, 50);
      expect(await service.creditCheckout(name: '   ', phone: '9876500000'), isA<CheckoutCustomerError>());
      expect(await service.creditCheckout(name: 'Ravi', phone: '12ab'), isA<CheckoutCustomerError>());
      expect(await service.creditCheckout(name: 'Ravi', phone: '98765-43210'), isA<CheckoutCustomerError>());
      expect(customers.customers, hasLength(1));
      expect(history.sales, isEmpty);
      expect(cart.isEmpty, isFalse);
    });
  });

  group('customers', () {
    late AppDatabase db;
    late CustomerProvider customers;

    setUp(() async {
      db = await openDb();
      customers = CustomerProvider(db, const []);
    });

    tearDown(() => db.close());

    Future<Customer> withDues(int amount) async {
      final c = (await customers.addCustomer(name: 'Asha', phone: '9876543210'))!;
      final credit = customers.draftCredit(amount, 'Sale');
      final sale = Sale(id: 's', items: const [], total: amount, date: DateTime(2026));
      await db.recordSale(sale, creditCustomerId: c.id, credit: credit);
      customers.applyCredit(c, credit, isNew: false);
      return c;
    }

    test('payments cannot exceed the pending amount', () async {
      final c = await withDues(50000);
      expect(() => customers.addPayment(c.id, 70000, 'Payment'), throwsArgumentError);
      expect(await customers.addPayment(c.id, 20000, 'Payment'), isTrue);
      final saved = (await db.loadAll()).customers.single;
      expect(saved.pendingAmount, 30000);
      expect(saved.transactions.map((t) => t.type), [TransactionType.credit, TransactionType.payment]);
    });

    test('edit keeps own phone, rejects another customer\'s', () async {
      final a = (await customers.addCustomer(name: 'Asha', phone: '9876543210'))!;
      await customers.addCustomer(name: 'Ravi', phone: '9000000000');
      expect(await customers.updateDetails(a.id, name: 'Asha K', phone: '98765 43210'), isTrue);
      expect(() => customers.updateDetails(a.id, name: 'Asha', phone: '9000000000'), throwsArgumentError);
      expect((await db.loadAll()).customers.first.name, 'Asha K');
    });

    test('customers with dues cannot be deleted', () async {
      final c = await withDues(100);
      expect(await customers.deleteCustomer(c.id), isFalse);
      await customers.addPayment(c.id, 100, 'Payment');
      expect(await customers.deleteCustomer(c.id), isTrue);
      expect((await db.loadAll()).customers, isEmpty);
    });
  });

  group('backup', () {
    test('round-trips all data and settings', () async {
      final db = await openDb();
      final data = await db.loadAll();
      final text = BackupService.encode(data, AppSettings.defaults, now: DateTime(2026, 10, 1));
      final backup = BackupService.decode(text);
      expect(backup.data.products.map((p) => p.id), data.products.map((p) => p.id));
      expect(backup.settings.shopName, AppSettings.defaults.shopName);
      await db.replaceAll(backup.data);
      expect((await db.loadAll()).products, hasLength(8));
      await db.close();
    });

    test('rejects other files, damaged data and invalid records', () {
      Map<String, Object?> valid() => {
            'app': 'thyantra_billing',
            'formatVersion': 1,
            'exportedAt': '2026-10-01T00:00:00.000',
            'settings': AppSettings.defaults.toJson(),
            'products': <Object>[],
            'sales': <Object>[],
            'customers': <Object>[],
          };
      expect(() => BackupService.decode('not json'), throwsFormatException);
      expect(() => BackupService.decode(jsonEncode({'app': 'other'})), throwsFormatException);
      expect(() => BackupService.decode(jsonEncode(valid()..['formatVersion'] = 99)), throwsFormatException);
      expect(() => BackupService.decode(jsonEncode(valid()..['products'] = 'x')), throwsFormatException);
      final negativeStock = valid()
        ..['products'] = [prod('a', 100, stock: -1).toJson()];
      expect(() => BackupService.decode(jsonEncode(negativeStock)), throwsFormatException);
      final dupPhones = valid()
        ..['customers'] = [
          for (final id in ['a', 'b'])
            Customer(id: id, name: 'X', phone: '9876543210', pendingAmount: 0, createdAt: DateTime(2026), transactions: const [])
                .toJson(),
        ];
      expect(() => BackupService.decode(jsonEncode(dupPhones)), throwsFormatException);
      expect(BackupService.decode(jsonEncode(valid())).data.products, isEmpty);
    });
  });

  test('settings: currency change updates symbol; blank shop name is ignored', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final settings = SettingsProvider(p);
    expect(settings.formatPrice(123450), '₹1,234.50');
    settings.updateSettings(currency: 'USD', shopName: '   ');
    expect(settings.settings.currencySymbol, r'$');
    expect(settings.settings.shopName, AppSettings.defaults.shopName);
    expect(SettingsProvider(p).formatPrice(1000), r'$10.00');
  });

  test('validation helpers', () {
    expect(isValidPhone('+91 98765-43210'), isTrue);
    expect(isValidPhone('12345'), isFalse);
    expect(isValidImageUrl('https://example.com/a.jpg'), isTrue);
    expect(isValidImageUrl('http://example.com/a.jpg'), isFalse);
    expect(isValidImageUrl('javascript:alert(1)'), isFalse);
  });

  test('monthly data, top products (grouped by id) and CSV', () {
    final history = SalesHistoryProvider(const []);
    Product named(String id, String n, int price) =>
        Product(id: id, name: n, price: price, stock: 9, usageCount: 0, createdAt: DateTime(2026));
    history
      ..applySale(Sale(
        id: 's1',
        items: [CartItem(product: named('m', 'Milk', 6000), quantity: 2)],
        total: 12000,
        date: DateTime(2026, 9, 5, 10, 30),
      ))
      ..applySale(Sale(
        id: 's2',
        items: [CartItem(product: named('b', 'Bread Loaf', 4500), quantity: 1), CartItem(product: named('m', 'Milk 1L', 6000), quantity: 1)],
        total: 10500,
        date: DateTime(2026, 10, 1, 9, 5),
      ));
    final monthly = history.getMonthlySalesData();
    expect(monthly.map((m) => m.key), ['2026-8', '2026-9']);
    expect(monthly.first.month, 'Sep');
    final top = history.getTopProductsAllTime().first;
    expect(top.productName, 'Milk 1L', reason: 'renamed product grouped under its latest name');
    expect(top.revenue, 18000);
    expect(
      buildSalesCsv(history.sales),
      'Date,Items,Total\r\n2026-10-01 09:05,Bread Loaf x1; Milk 1L x1,105.00\r\n2026-09-05 10:30,Milk x2,120.00',
    );
  });

  test('CSV escapes commas and quotes and neutralises formulas', () {
    expect(csvField('Rice, 5kg "Gold"'), '"Rice, 5kg ""Gold"""');
    expect(csvField('=HYPERLINK("x")'), '"\'=HYPERLINK(""x"")"');
    expect(csvField('-2+3'), "'-2+3");
    expect(csvField('Milk 1L'), 'Milk 1L');
  });
}
