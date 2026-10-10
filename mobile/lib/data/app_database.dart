import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../utils/storage.dart';
import '../utils/validation.dart';

/// Thrown when a write would oversell stock or overpay a balance. The
/// transaction is rolled back, so nothing is saved.
class ConflictException implements Exception {
  const ConflictException(this.message);
  final String message;

  @override
  String toString() => 'ConflictException: $message';
}

/// Everything the app stores, loaded once at startup.
class ShopData {
  const ShopData({required this.products, required this.sales, required this.customers});
  final List<Product> products;

  /// Newest first.
  final List<Sale> sales;
  final List<Customer> customers;
}

/// SQLite storage. Every operation that touches more than one row runs in a
/// single transaction, so a sale, its stock changes and any customer credit
/// are saved together or not at all.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static const fileName = 'thyantra_billing.db';
  static const _schemaVersion = 1;

  // Keys used by the previous SharedPreferences storage, imported once.
  static const _legacyProducts = 'shop_products';
  static const _legacySales = 'shop_sales_history';
  static const _legacyCustomers = 'shop_customers';

  /// Opens (creating on first launch) the database. On creation, data from
  /// the earlier SharedPreferences storage is imported, or the starter
  /// products are added for a brand-new install.
  static Future<AppDatabase> open({
    required SharedPreferences prefs,
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    var imported = false;
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        singleInstance: path == null,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await _createSchema(db);
          imported = await _importLegacy(db, prefs);
          if (!imported) await _seedProducts(db);
        },
      ),
    );
    if (imported) {
      // Only after the import has committed.
      for (final key in [_legacyProducts, _legacySales, _legacyCustomers]) {
        await prefs.remove(key);
      }
    }
    return AppDatabase._(db);
  }

  Future<void> close() => _db.close();

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        price_minor INTEGER NOT NULL CHECK (price_minor >= 0),
        stock INTEGER NOT NULL CHECK (stock >= 0),
        image TEXT,
        usage_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NOT NULL UNIQUE,
        pending_minor INTEGER NOT NULL DEFAULT 0 CHECK (pending_minor >= 0),
        created_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        total_minor INTEGER NOT NULL,
        customer_id TEXT,
        is_pending INTEGER,
        items TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX sales_date ON sales (date)');
    await db.execute('''
      CREATE TABLE customer_transactions (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL REFERENCES customers (id) ON DELETE CASCADE,
        amount_minor INTEGER NOT NULL,
        type TEXT NOT NULL,
        description TEXT NOT NULL,
        date TEXT NOT NULL,
        sale_id TEXT
      )''');
    await db.execute('CREATE INDEX transactions_customer ON customer_transactions (customer_id)');
  }

  static Future<bool> _importLegacy(DatabaseExecutor db, SharedPreferences prefs) async {
    final products = readJsonList(prefs, _legacyProducts, Product.fromJson);
    final sales = readJsonList(prefs, _legacySales, Sale.fromJson);
    final customers = readJsonList(prefs, _legacyCustomers, Customer.fromJson);
    if (products == null && sales == null && customers == null) return false;
    await _insertAll(
      db,
      [for (final x in products ?? const <Product>[]) x.stock < 0 ? x.copyWith(stock: 0) : x],
      sales ?? const [],
      _sanitiseCustomers(customers ?? const []),
      skipDuplicates: true,
    );
    return true;
  }

  /// Older data could hold unformatted or duplicate phone numbers and
  /// negative balances; the new schema allows none of these. The first
  /// customer with a given number is kept.
  static List<Customer> _sanitiseCustomers(List<Customer> customers) {
    final seen = <String>{};
    return [
      for (final c in customers)
        if (seen.add(normalizePhone(c.phone)))
          c.copyWith(phone: normalizePhone(c.phone), pendingAmount: c.pendingAmount < 0 ? 0 : c.pendingAmount),
    ];
  }

  static Future<void> _seedProducts(DatabaseExecutor db) async {
    final now = DateTime.now();
    Product p(String id, String name, int price, int stock) =>
        Product(id: id, name: name, price: price, stock: stock, usageCount: 0, createdAt: now);
    await _insertAll(db, [
      p('1', 'Milk 1L', 6000, 50),
      p('2', 'Bread Loaf', 4500, 30),
      p('3', 'Eggs (12 pack)', 9000, 25),
      p('4', 'Butter 250g', 5500, 20),
      p('5', 'Cheese Block', 15000, 15),
      p('6', 'Orange Juice 1L', 8000, 40),
      p('7', 'Yogurt 500g', 3500, 35),
      p('8', 'Coffee Powder 500g', 25000, 18),
    ], const [], const []);
  }

  static Future<void> _insertAll(
    DatabaseExecutor db,
    List<Product> products,
    List<Sale> sales,
    List<Customer> customers, {
    bool skipDuplicates = false,
  }) async {
    final conflict = skipDuplicates ? ConflictAlgorithm.ignore : ConflictAlgorithm.abort;
    final batch = db.batch();
    for (final x in products) {
      batch.insert('products', _productRow(x), conflictAlgorithm: conflict);
    }
    for (final x in sales) {
      batch.insert('sales', _saleRow(x), conflictAlgorithm: conflict);
    }
    for (final c in customers) {
      batch.insert('customers', _customerRow(c), conflictAlgorithm: conflict);
      for (final t in c.transactions) {
        batch.insert('customer_transactions', _transactionRow(c.id, t), conflictAlgorithm: conflict);
      }
    }
    await batch.commit(noResult: true);
  }

  // ---------------------------------------------------------------- reads

  Future<ShopData> loadAll() async {
    final products = (await _db.query('products', orderBy: 'created_at, rowid')).map(_productFrom).toList();
    final sales = (await _db.query('sales', orderBy: 'date DESC')).map(_saleFrom).toList();
    final txByCustomer = <String, List<CustomerTransaction>>{};
    for (final row in await _db.query('customer_transactions', orderBy: 'date, rowid')) {
      txByCustomer.putIfAbsent(row['customer_id']! as String, () => []).add(_transactionFrom(row));
    }
    final customers = [
      for (final row in await _db.query('customers', orderBy: 'created_at, rowid'))
        _customerFrom(row, txByCustomer[row['id']] ?? const []),
    ];
    return ShopData(products: products, sales: sales, customers: customers);
  }

  // --------------------------------------------------------------- writes

  Future<void> insertProduct(Product product) => _db.insert('products', _productRow(product));

  Future<void> updateProduct(Product product) =>
      _db.update('products', _productRow(product), where: 'id = ?', whereArgs: [product.id]);

  Future<void> deleteProduct(String id) => _db.delete('products', where: 'id = ?', whereArgs: [id]);

  /// Records a sale in one transaction: decrements stock (refusing to go
  /// below zero), stores the sale and, for a credit sale, adds the customer
  /// if new and records the credit against them.
  Future<void> recordSale(
    Sale sale, {
    Customer? newCustomer,
    String? creditCustomerId,
    CustomerTransaction? credit,
  }) {
    return _db.transaction((txn) async {
      for (final item in sale.items) {
        final updated = await txn.rawUpdate(
          'UPDATE products SET stock = stock - ?, usage_count = usage_count + ? WHERE id = ? AND stock >= ?',
          [item.quantity, item.quantity, item.product.id, item.quantity],
        );
        if (updated != 1) throw ConflictException('Not enough stock for ${item.product.name}');
      }
      await txn.insert('sales', _saleRow(sale));
      if (newCustomer != null) await txn.insert('customers', _customerRow(newCustomer));
      if (credit != null && creditCustomerId != null) {
        await txn.insert('customer_transactions', _transactionRow(creditCustomerId, credit));
        final updated = await txn.rawUpdate(
          'UPDATE customers SET pending_minor = pending_minor + ? WHERE id = ?',
          [credit.amount, creditCustomerId],
        );
        if (updated != 1) throw const ConflictException('Customer not found');
      }
    });
  }

  Future<void> insertCustomer(Customer customer) => _db.insert('customers', _customerRow(customer));

  Future<void> updateCustomerDetails(String id, {required String name, required String phone}) =>
      _db.update('customers', {'name': name, 'phone': phone}, where: 'id = ?', whereArgs: [id]);

  /// Deletes a customer with no outstanding balance, with their history.
  Future<void> deleteCustomer(String id) async {
    final deleted = await _db.delete('customers', where: 'id = ? AND pending_minor = 0', whereArgs: [id]);
    if (deleted != 1) throw const ConflictException('Customer still has a pending balance');
  }

  /// Records a payment, refusing to take the balance below zero.
  Future<void> recordPayment(String customerId, CustomerTransaction payment) {
    return _db.transaction((txn) async {
      final updated = await txn.rawUpdate(
        'UPDATE customers SET pending_minor = pending_minor - ? WHERE id = ? AND pending_minor >= ?',
        [payment.amount, customerId, payment.amount],
      );
      if (updated != 1) throw const ConflictException('Payment is more than the pending amount');
      await txn.insert('customer_transactions', _transactionRow(customerId, payment));
    });
  }

  /// Replaces all data (restore from backup) in one transaction.
  Future<void> replaceAll(ShopData data) {
    return _db.transaction((txn) async {
      await txn.delete('customer_transactions');
      await txn.delete('customers');
      await txn.delete('sales');
      await txn.delete('products');
      await _insertAll(txn, data.products, data.sales, data.customers);
    });
  }

  // ------------------------------------------------------------- mapping

  static Map<String, Object?> _productRow(Product x) => {
        'id': x.id,
        'name': x.name,
        'price_minor': x.price,
        'stock': x.stock,
        'image': x.image,
        'usage_count': x.usageCount,
        'created_at': x.createdAt.toIso8601String(),
      };

  static Product _productFrom(Map<String, Object?> r) => Product(
        id: r['id']! as String,
        name: r['name']! as String,
        price: r['price_minor']! as int,
        stock: r['stock']! as int,
        image: r['image'] as String?,
        usageCount: r['usage_count']! as int,
        createdAt: DateTime.parse(r['created_at']! as String),
      );

  static Map<String, Object?> _saleRow(Sale x) => {
        'id': x.id,
        'date': x.date.toIso8601String(),
        'total_minor': x.total,
        'customer_id': x.customerId,
        'is_pending': x.isPending == null ? null : (x.isPending! ? 1 : 0),
        'items': jsonEncode(x.items.map((i) => i.toJson()).toList()),
      };

  static Sale _saleFrom(Map<String, Object?> r) => Sale(
        id: r['id']! as String,
        date: DateTime.parse(r['date']! as String),
        total: r['total_minor']! as int,
        customerId: r['customer_id'] as String?,
        isPending: r['is_pending'] == null ? null : r['is_pending'] == 1,
        items: (jsonDecode(r['items']! as String) as List<dynamic>)
            .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static Map<String, Object?> _customerRow(Customer x) => {
        'id': x.id,
        'name': x.name,
        'phone': x.phone,
        'pending_minor': x.pendingAmount,
        'created_at': x.createdAt.toIso8601String(),
      };

  static Customer _customerFrom(Map<String, Object?> r, List<CustomerTransaction> transactions) => Customer(
        id: r['id']! as String,
        name: r['name']! as String,
        phone: r['phone']! as String,
        pendingAmount: r['pending_minor']! as int,
        createdAt: DateTime.parse(r['created_at']! as String),
        transactions: transactions,
      );

  static Map<String, Object?> _transactionRow(String customerId, CustomerTransaction t) => {
        'id': t.id,
        'customer_id': customerId,
        'amount_minor': t.amount,
        'type': t.type.name,
        'description': t.description,
        'date': t.date.toIso8601String(),
        'sale_id': t.saleId,
      };

  static CustomerTransaction _transactionFrom(Map<String, Object?> r) => CustomerTransaction(
        id: r['id']! as String,
        amount: r['amount_minor']! as int,
        type: TransactionType.values.byName(r['type']! as String),
        description: r['description']! as String,
        date: DateTime.parse(r['date']! as String),
        saleId: r['sale_id'] as String?,
      );
}
