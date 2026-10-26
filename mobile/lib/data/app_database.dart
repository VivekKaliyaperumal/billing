import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../models/sync_models.dart';
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
///
/// While signed in ([syncEnabled]), each write also queues an outbox op in
/// the same transaction, so a change is never saved without being queued
/// for the server, or queued without being saved.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static const fileName = 'thyantra_billing.db';
  static const _schemaVersion = 2;
  static const _uuid = Uuid();

  // Keys used by the previous SharedPreferences storage, imported once.
  static const _legacyProducts = 'shop_products';
  static const _legacySales = 'shop_sales_history';
  static const _legacyCustomers = 'shop_customers';

  // sync_state keys.
  static const _cursorKey = 'cursor';
  static const _lastSyncedKey = 'last_synced_at';
  static const _shopKey = 'shop_id';
  static const _deviceKey = 'device_id';

  /// Set by the sync service while a user is signed in.
  bool syncEnabled = false;

  /// Called after a write that queued an op, so sync can run soon.
  void Function()? onLocalWrite;

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
          await _createSyncSchema(db);
          imported = await _importLegacy(db, prefs);
          if (!imported) await _seedProducts(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await _createSyncSchema(db);
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

  /// Version 2: changes waiting to be sent, and sync bookkeeping.
  static Future<void> _createSyncSchema(Database db) async {
    await db.execute('''
      CREATE TABLE outbox (
        op_id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
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

  /// Ids of the starter products added to a brand-new install.
  static const starterProductIds = {'1', '2', '3', '4', '5', '6', '7', '8'};

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

  /// Runs [body] in a transaction, then tells sync that ops may be waiting.
  Future<T> _write<T>(Future<T> Function(Transaction txn) body) async {
    final result = await _db.transaction(body);
    if (syncEnabled) onLocalWrite?.call();
    return result;
  }

  /// Queues an op for the server inside the caller's transaction.
  Future<void> _enqueue(DatabaseExecutor txn, String type, Map<String, Object?> payload) async {
    if (!syncEnabled) return;
    await txn.insert('outbox', {
      'op_id': _uuid.v4(),
      'type': type,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Queues an op that has no local table, e.g. a settings change.
  Future<void> enqueue(String type, Map<String, Object?> payload) => _write((txn) => _enqueue(txn, type, payload));

  Future<void> insertProduct(Product product) => _write((txn) async {
        await txn.insert('products', _productRow(product));
        await _enqueue(txn, 'product.upsert', _productOp(product));
      });

  /// Sends the stock the edit started from, so the server applies the
  /// difference and keeps sales made on other devices meanwhile.
  Future<void> updateProduct(Product product) => _write((txn) async {
        final before = await txn.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [product.id]);
        await txn.update('products', _productRow(product), where: 'id = ?', whereArgs: [product.id]);
        final baseStock = before.isEmpty ? null : before.first['stock']! as int;
        await _enqueue(txn, 'product.upsert', _productOp(product, baseStock: baseStock));
      });

  Future<void> deleteProduct(String id) => _write((txn) async {
        await txn.delete('products', where: 'id = ?', whereArgs: [id]);
        await _enqueue(txn, 'product.delete', {'id': id});
      });

  /// Records a sale in one transaction: decrements stock (refusing to go
  /// below zero), stores the sale and, for a credit sale, adds the customer
  /// if new and records the credit against them.
  Future<void> recordSale(
    Sale sale, {
    Customer? newCustomer,
    String? creditCustomerId,
    CustomerTransaction? credit,
  }) {
    return _write((txn) async {
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
      if (!syncEnabled) return;
      if (newCustomer != null) await _enqueue(txn, 'customer.create', _customerOp(newCustomer));
      final customerId = creditCustomerId ?? sale.customerId;
      Map<String, Object?>? customer;
      if (customerId != null) {
        // Lets the server recreate the customer if it no longer has them.
        final rows = await txn.query('customers', columns: ['name', 'phone'], where: 'id = ?', whereArgs: [customerId]);
        if (rows.isNotEmpty) customer = {'name': rows.first['name'], 'phone': rows.first['phone']};
      }
      await _enqueue(txn, 'sale.create', {
        'id': sale.id,
        'date': toServerDate(sale.date),
        'items': [
          for (final i in sale.items)
            {'productId': i.product.id, 'name': i.product.name, 'priceMinor': i.product.price, 'quantity': i.quantity},
        ],
        'customerId': customerId,
        'customer': customer,
        'credit': credit == null
            ? null
            : {'id': credit.id, 'description': credit.description, 'date': toServerDate(credit.date)},
      });
    });
  }

  Future<void> insertCustomer(Customer customer) => _write((txn) async {
        await txn.insert('customers', _customerRow(customer));
        await _enqueue(txn, 'customer.create', _customerOp(customer));
      });

  Future<void> updateCustomerDetails(String id, {required String name, required String phone}) =>
      _write((txn) async {
        await txn.update('customers', {'name': name, 'phone': phone}, where: 'id = ?', whereArgs: [id]);
        await _enqueue(txn, 'customer.update', {'id': id, 'name': name, 'phone': phone});
      });

  /// Deletes a customer with no outstanding balance, with their history.
  Future<void> deleteCustomer(String id) => _write((txn) async {
        final deleted = await txn.delete('customers', where: 'id = ? AND pending_minor = 0', whereArgs: [id]);
        if (deleted != 1) throw const ConflictException('Customer still has a pending balance');
        await _enqueue(txn, 'customer.delete', {'id': id});
      });

  /// Records a payment, refusing to take the balance below zero.
  Future<void> recordPayment(String customerId, CustomerTransaction payment) {
    return _write((txn) async {
      final updated = await txn.rawUpdate(
        'UPDATE customers SET pending_minor = pending_minor - ? WHERE id = ? AND pending_minor >= ?',
        [payment.amount, customerId, payment.amount],
      );
      if (updated != 1) throw const ConflictException('Payment is more than the pending amount');
      await txn.insert('customer_transactions', _transactionRow(customerId, payment));
      await _enqueue(txn, 'payment.create', {
        'id': payment.id,
        'customerId': customerId,
        'amountMinor': payment.amount,
        'description': payment.description,
        'date': toServerDate(payment.date),
      });
    });
  }

  /// Replaces all data (restore from backup) in one transaction. Nothing is
  /// queued: a restore while signed in goes to the server first.
  Future<void> replaceAll(ShopData data) {
    return _db.transaction((txn) async {
      await txn.delete('customer_transactions');
      await txn.delete('customers');
      await txn.delete('sales');
      await txn.delete('products');
      await _insertAll(txn, data.products, data.sales, data.customers);
    });
  }

  // ----------------------------------------------------------------- sync

  /// Oldest first.
  Future<List<OutboxOp>> pendingOps(int limit) async {
    final rows = await _db.query('outbox', orderBy: 'rowid', limit: limit);
    return [
      for (final r in rows)
        OutboxOp(
          opId: r['op_id']! as String,
          type: r['type']! as String,
          payload: jsonDecode(r['payload']! as String) as Map<String, dynamic>,
        ),
    ];
  }

  Future<int> pendingCount() async => Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  Future<void> removeOps(Iterable<String> opIds) {
    return _db.transaction((txn) async {
      for (final id in opIds) {
        await txn.delete('outbox', where: 'op_id = ?', whereArgs: [id]);
      }
    });
  }

  /// Saves a download from the server in one transaction. Refuses (returns
  /// false) while local changes are still waiting to be sent, because the
  /// download would overwrite them; sync pushes first and tries again.
  Future<bool> applyPull(PullPage page) {
    return _db.transaction((txn) async {
      final pending = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;
      if (pending > 0) return false;
      if (page.reset) {
        await txn.delete('customer_transactions');
        await txn.delete('customers');
        await txn.delete('sales');
        await txn.delete('products');
      }
      for (final id in page.deletedProducts) {
        await txn.delete('products', where: 'id = ?', whereArgs: [id]);
      }
      for (final x in page.products.values) {
        await _upsert(txn, 'products', _productRow(x));
      }
      // Deleting a customer removes their ledger too (ON DELETE CASCADE).
      for (final id in page.deletedCustomers) {
        await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
      }
      for (final c in page.customers.values) {
        // The server is the record now; a stale local customer holding the
        // same number would block it.
        await txn.delete('customers', where: 'phone = ? AND id != ?', whereArgs: [c.phone, c.id]);
        await _upsert(txn, 'customers', _customerRow(c));
      }
      for (final t in page.transactions.values) {
        final owner = await txn.query('customers', columns: ['id'], where: 'id = ?', whereArgs: [t.customerId]);
        if (owner.isEmpty) continue; // the customer was deleted
        await _upsert(txn, 'customer_transactions', _transactionRow(t.customerId, t.transaction));
      }
      for (final s in page.sales.values) {
        await _upsert(txn, 'sales', _saleRow(s));
      }
      return true;
    });
  }

  /// Update, or insert if missing. Not INSERT OR REPLACE: replacing a
  /// customer row would cascade-delete their ledger. Not UPSERT syntax:
  /// older Android versions ship SQLite without it.
  static Future<void> _upsert(DatabaseExecutor txn, String table, Map<String, Object?> row) async {
    final updated = await txn.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
    if (updated == 0) await txn.insert(table, row);
  }

  /// The server merged customer [from] into [to] (the same phone was added
  /// on two devices). Moves the ledger, sales and queued ops across.
  Future<void> remapCustomerId(String from, String to) {
    if (from == to) return Future.value();
    return _db.transaction((txn) async {
      final old = await txn.query('customers', where: 'id = ?', whereArgs: [from]);
      if (old.isNotEmpty) {
        final ledger = await txn.query('customer_transactions', where: 'customer_id = ?', whereArgs: [from]);
        // Foreign keys forbid changing the id in place; delete (cascading
        // the ledger) and re-insert under the new id.
        await txn.delete('customers', where: 'id = ?', whereArgs: [from]);
        final target = await txn.query('customers', columns: ['id'], where: 'id = ?', whereArgs: [to]);
        if (target.isEmpty) {
          await txn.insert('customers', {...old.first, 'id': to});
        } else {
          await txn.rawUpdate(
            'UPDATE customers SET pending_minor = pending_minor + ? WHERE id = ?',
            [old.first['pending_minor'], to],
          );
        }
        for (final row in ledger) {
          await txn.insert('customer_transactions', {...row, 'customer_id': to});
        }
      }
      await txn.update('sales', {'customer_id': to}, where: 'customer_id = ?', whereArgs: [from]);
      for (final row in await txn.query('outbox')) {
        final payload = jsonDecode(row['payload']! as String) as Map<String, dynamic>;
        var changed = false;
        if (payload['customerId'] == from) {
          payload['customerId'] = to;
          changed = true;
        }
        if ((row['type']! as String).startsWith('customer.') && payload['id'] == from) {
          payload['id'] = to;
          changed = true;
        }
        if (changed) {
          await txn.update('outbox', {'payload': jsonEncode(payload)}, where: 'op_id = ?', whereArgs: [row['op_id']]);
        }
      }
    });
  }

  Future<String?> _getState(String key) async {
    final rows = await _db.query('sync_state', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value']! as String;
  }

  Future<void> _setState(String key, String? value) async {
    if (value == null) {
      await _db.delete('sync_state', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert('sync_state', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<String?> getCursor() => _getState(_cursorKey);
  Future<void> setCursor(String? cursor) => _setState(_cursorKey, cursor);

  Future<DateTime?> getLastSyncedAt() async {
    final v = await _getState(_lastSyncedKey);
    return v == null ? null : DateTime.tryParse(v);
  }

  Future<void> setLastSyncedAt(DateTime at) => _setState(_lastSyncedKey, at.toIso8601String());

  /// The shop this phone last synced with.
  Future<String?> getSyncedShopId() => _getState(_shopKey);
  Future<void> setSyncedShopId(String? id) => _setState(_shopKey, id);

  /// Stable id for this install, sent with each push.
  Future<String> deviceId() async {
    final existing = await _getState(_deviceKey);
    if (existing != null) return existing;
    final id = _uuid.v4();
    await _setState(_deviceKey, id);
    return id;
  }

  /// Forgets queued ops and the sync position (sign-out, or switching to
  /// another shop's data). The device id is kept.
  Future<void> clearSyncState() {
    return _db.transaction((txn) async {
      await txn.delete('outbox');
      await txn.delete('sync_state', where: 'key != ?', whereArgs: [_deviceKey]);
    });
  }

  // ------------------------------------------------------------- mapping

  static Map<String, Object?> _productOp(Product x, {int? baseStock}) => {
        'id': x.id,
        'name': x.name,
        'priceMinor': x.price,
        'stock': x.stock,
        'image': x.image,
        'baseStock': ?baseStock,
        'createdAt': toServerDate(x.createdAt),
      };

  static Map<String, Object?> _customerOp(Customer x) => {
        'id': x.id,
        'name': x.name,
        'phone': x.phone,
        'createdAt': toServerDate(x.createdAt),
      };

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
