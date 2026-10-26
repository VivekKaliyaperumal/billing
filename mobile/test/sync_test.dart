import 'package:billing_mobile/data/app_database.dart';
import 'package:billing_mobile/models/models.dart';
import 'package:billing_mobile/models/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Outbox and download handling in the database (no network).
void main() {
  sqfliteFfiInit();
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await AppDatabase.open(
      prefs: await SharedPreferences.getInstance(),
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() => db.close());

  Product prod(String id, {int price = 1000, int stock = 10}) =>
      Product(id: id, name: 'P$id', price: price, stock: stock, usageCount: 0, createdAt: DateTime(2026));

  Customer cust(String id, String phone, {int pending = 0}) => Customer(
    id: id,
    name: 'C$id',
    phone: phone,
    pendingAmount: pending,
    createdAt: DateTime(2026),
    transactions: const [],
  );

  Map<String, dynamic> pull({
    bool reset = false,
    List<Map<String, dynamic>> products = const [],
    List<Map<String, dynamic>> customers = const [],
    List<Map<String, dynamic>> sales = const [],
    List<Map<String, dynamic>> transactions = const [],
  }) => {
    'reset': reset,
    'cursor': '1.10',
    'hasMore': false,
    'shop': {'id': 's', 'name': 'Shop', 'currency': 'INR', 'currencySymbol': '₹'},
    'products': products,
    'customers': customers,
    'sales': sales,
    'transactions': transactions,
  };

  Map<String, dynamic> serverProduct(String id, {int stock = 5, bool deleted = false}) => {
    'id': id,
    'name': 'Server $id',
    'priceMinor': 2500,
    'stock': stock,
    'image': null,
    'usageCount': 3,
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-01T00:00:00.000Z',
    'deleted': deleted,
  };

  test('nothing is queued while signed out', () async {
    await db.insertProduct(prod('a'));
    expect(await db.pendingCount(), 0);
  });

  test('each write queues its op in the same transaction, oldest first', () async {
    db.syncEnabled = true;
    var notified = 0;
    db.onLocalWrite = () => notified++;

    await db.insertProduct(prod('a', stock: 10));
    await db.updateProduct(prod('a', stock: 14));
    await db.deleteProduct('a');
    final c = cust('c1', '9876543210');
    final credit = CustomerTransaction(
      id: 't1',
      amount: 6000,
      type: TransactionType.credit,
      description: 'Sale #s1',
      date: DateTime(2026, 10, 1),
    );
    await db.recordSale(
      Sale(
        id: 's1',
        items: [CartItem(product: prod('1', price: 6000), quantity: 1)],
        total: 6000,
        date: DateTime(2026, 10, 1),
        customerId: 'c1',
        isPending: true,
      ),
      newCustomer: c,
      creditCustomerId: 'c1',
      credit: credit,
    );
    await db.recordPayment(
      'c1',
      CustomerTransaction(
        id: 't2',
        amount: 1000,
        type: TransactionType.payment,
        description: 'Payment',
        date: DateTime(2026, 10, 2),
      ),
    );

    final ops = await db.pendingOps(50);
    expect(ops.map((o) => o.type), [
      'product.upsert',
      'product.upsert',
      'product.delete',
      'customer.create',
      'sale.create',
      'payment.create',
    ]);
    expect(ops[0].payload.containsKey('baseStock'), isFalse);
    expect(ops[1].payload['baseStock'], 10, reason: 'stock before the edit, so the server applies +4');
    expect(ops[1].payload['stock'], 14);
    final sale = ops[4].payload;
    expect(sale['customerId'], 'c1');
    expect(sale['customer'], {'name': 'Cc1', 'phone': '9876543210'});
    expect(sale['items'], [
      {'productId': '1', 'name': 'P1', 'priceMinor': 6000, 'quantity': 1},
    ]);
    expect((sale['credit'] as Map)['id'], 't1');
    expect(sale['date'], endsWith('Z'), reason: 'sent as UTC');
    expect(ops[5].payload, containsPair('amountMinor', 1000));
    expect(notified, 5);
  });

  test('a write that fails queues nothing', () async {
    db.syncEnabled = true;
    final oversell = Sale(
      id: 'x',
      items: [CartItem(product: prod('1'), quantity: 999)],
      total: 1,
      date: DateTime(2026),
    );
    await expectLater(db.recordSale(oversell), throwsA(isA<ConflictException>()));
    expect(await db.pendingCount(), 0);
  });

  test('a download is refused while changes are waiting to be sent', () async {
    db.syncEnabled = true;
    await db.insertProduct(prod('a'));
    final page = PullPage.fromJson(pull(products: [serverProduct('a', stock: 1)]));
    expect(await db.applyPull(page), isFalse);
    expect((await db.loadAll()).products.firstWhere((p) => p.id == 'a').stock, 10);

    await db.removeOps((await db.pendingOps(10)).map((o) => o.opId));
    expect(await db.applyPull(page), isTrue);
    expect((await db.loadAll()).products.firstWhere((p) => p.id == 'a').stock, 1);
  });

  test('a reset download replaces everything; deletions remove records and ledgers', () async {
    await db.insertCustomer(cust('old', '9000000000'));
    final reset = PullPage.fromJson(
      pull(
        reset: true,
        products: [serverProduct('p1'), serverProduct('p2')],
        customers: [
          {
            'id': 'c1',
            'name': 'Asha',
            'phone': '9876543210',
            'pendingMinor': 500,
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-01-01T00:00:00.000Z',
            'deleted': false,
          },
        ],
        transactions: [
          {
            'id': 't1',
            'customerId': 'c1',
            'type': 'credit',
            'amountMinor': 500,
            'description': 'Sale #s1',
            'date': '2026-01-02T00:00:00.000Z',
            'saleId': 's1',
          },
          {
            'id': 't9',
            'customerId': 'gone',
            'type': 'credit',
            'amountMinor': 1,
            'description': 'x',
            'date': '2026-01-02T00:00:00.000Z',
            'saleId': null,
          },
        ],
        sales: [
          {
            'id': 's1',
            'date': '2026-01-02T00:00:00.000Z',
            'totalMinor': 500,
            'customerId': 'c1',
            'isPending': true,
            'source': 'web',
            'items': [
              {'productId': 'p1', 'name': 'Server p1', 'priceMinor': 500, 'quantity': 1, 'shortfall': 0},
            ],
          },
        ],
      ),
    );
    expect(await db.applyPull(reset), isTrue);
    var data = await db.loadAll();
    expect(data.products.map((p) => p.id), ['p1', 'p2'], reason: 'starter products replaced');
    expect(data.customers.single.id, 'c1');
    expect(data.customers.single.transactions.single.id, 't1');
    expect(data.sales.single.items.single.product.name, 'Server p1');
    expect(data.sales.single.date.isUtc, isFalse, reason: 'stored in local time');

    final delta = PullPage.fromJson(
      pull(
        products: [serverProduct('p2', deleted: true)],
        customers: [
          {
            'id': 'c1',
            'name': 'Asha',
            'phone': '9876543210',
            'pendingMinor': 0,
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-01-03T00:00:00.000Z',
            'deleted': true,
          },
        ],
      ),
    );
    expect(await db.applyPull(delta), isTrue);
    data = await db.loadAll();
    expect(data.products.map((p) => p.id), ['p1']);
    expect(data.customers, isEmpty);
    expect(data.sales, hasLength(1), reason: 'sales are history and stay');
  });

  test('merged pages keep the latest version of each record', () {
    final first = PullPage.fromJson(pull(reset: true, products: [serverProduct('a', stock: 1), serverProduct('b')]));
    final second = PullPage.fromJson(pull(products: [serverProduct('a', stock: 7), serverProduct('b', deleted: true)]));
    final merged = first.merge(second);
    expect(merged.reset, isTrue);
    expect(merged.products['a']!.stock, 7);
    expect(merged.products.containsKey('b'), isFalse);
    expect(merged.deletedProducts, {'b'});
  });

  test('remapCustomerId moves the ledger, sales and queued ops to the merged customer', () async {
    db.syncEnabled = true;
    final c = cust('dup', '9876543210');
    await db.insertCustomer(c);
    final credit = CustomerTransaction(
      id: 't1',
      amount: 2000,
      type: TransactionType.credit,
      description: 'Sale #s1',
      date: DateTime(2026),
    );
    await db.recordSale(
      Sale(
        id: 's1',
        items: [CartItem(product: prod('1', price: 2000), quantity: 1)],
        total: 2000,
        date: DateTime(2026),
        customerId: 'dup',
        isPending: true,
      ),
      creditCustomerId: 'dup',
      credit: credit,
    );

    await db.remapCustomerId('dup', 'real');
    final data = await db.loadAll();
    expect(data.customers.single.id, 'real');
    expect(data.customers.single.pendingAmount, 2000);
    expect(data.customers.single.transactions.single.id, 't1');
    expect(data.sales.single.customerId, 'real');
    final ops = await db.pendingOps(10);
    expect(ops.firstWhere((o) => o.type == 'customer.create').payload['id'], 'real');
    expect(ops.firstWhere((o) => o.type == 'sale.create').payload['customerId'], 'real');
  });

  test('sync state survives until cleared; the device id is kept', () async {
    db.syncEnabled = true;
    await db.insertProduct(prod('a'));
    await db.setCursor('1.42');
    await db.setLastSyncedAt(DateTime(2026, 10, 1));
    final device = await db.deviceId();
    expect(await db.getCursor(), '1.42');
    await db.clearSyncState();
    expect(await db.getCursor(), isNull);
    expect(await db.getLastSyncedAt(), isNull);
    expect(await db.pendingCount(), 0);
    expect(await db.deviceId(), device);
  });
}
