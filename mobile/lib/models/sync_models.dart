import 'models.dart';

/// A change made on this phone, waiting to be sent to the server.
class OutboxOp {
  const OutboxOp({required this.opId, required this.type, required this.payload});
  final String opId;

  /// One of the server's op types, e.g. `sale.create`.
  final String type;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {'opId': opId, 'type': type, 'payload': payload};
}

/// The shop's settings as the server holds them.
class ShopInfo {
  const ShopInfo({required this.id, required this.name, required this.currency, required this.currencySymbol});
  final String id;
  final String name;
  final String currency;
  final String currencySymbol;

  factory ShopInfo.fromJson(Map<String, dynamic> j) => ShopInfo(
    id: j['id'] as String,
    name: j['name'] as String,
    currency: j['currency'] as String,
    currencySymbol: j['currencySymbol'] as String,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'currency': currency, 'currencySymbol': currencySymbol};
}

/// A credit or payment and the customer it belongs to.
typedef PulledTransaction = ({String customerId, CustomerTransaction transaction});

/// Changes downloaded from the server (`GET /sync/pull`). Pages are merged
/// into one before anything is saved, so a transaction is never applied
/// before the customer it belongs to arrives in a later page.
class PullPage {
  PullPage({
    required this.reset,
    required this.cursor,
    required this.hasMore,
    required this.shop,
    required this.products,
    required this.deletedProducts,
    required this.customers,
    required this.deletedCustomers,
    required this.sales,
    required this.transactions,
  });

  /// The phone must replace everything it has with this download.
  final bool reset;
  final String cursor;
  final bool hasMore;
  final ShopInfo shop;
  final Map<String, Product> products;
  final Set<String> deletedProducts;

  /// Without transactions; those arrive separately in [transactions].
  final Map<String, Customer> customers;
  final Set<String> deletedCustomers;
  final Map<String, Sale> sales;
  final Map<String, PulledTransaction> transactions;

  bool get hasChanges =>
      reset ||
      products.isNotEmpty ||
      deletedProducts.isNotEmpty ||
      customers.isNotEmpty ||
      deletedCustomers.isNotEmpty ||
      sales.isNotEmpty ||
      transactions.isNotEmpty;

  factory PullPage.fromJson(Map<String, dynamic> j) {
    final products = <String, Product>{};
    final deletedProducts = <String>{};
    for (final raw in j['products'] as List<dynamic>) {
      final m = raw as Map<String, dynamic>;
      if (m['deleted'] == true) {
        deletedProducts.add(m['id'] as String);
      } else {
        final p = Product(
          id: m['id'] as String,
          name: m['name'] as String,
          price: (m['priceMinor'] as num).toInt(),
          stock: (m['stock'] as num).toInt(),
          image: m['image'] as String?,
          usageCount: (m['usageCount'] as num).toInt(),
          createdAt: serverDate(m['createdAt']),
        );
        products[p.id] = p;
      }
    }
    final customers = <String, Customer>{};
    final deletedCustomers = <String>{};
    for (final raw in j['customers'] as List<dynamic>) {
      final m = raw as Map<String, dynamic>;
      if (m['deleted'] == true) {
        deletedCustomers.add(m['id'] as String);
      } else {
        final c = Customer(
          id: m['id'] as String,
          name: m['name'] as String,
          phone: m['phone'] as String,
          pendingAmount: (m['pendingMinor'] as num).toInt(),
          createdAt: serverDate(m['createdAt']),
          transactions: const [],
        );
        customers[c.id] = c;
      }
    }
    final sales = <String, Sale>{};
    for (final raw in j['sales'] as List<dynamic>) {
      final m = raw as Map<String, dynamic>;
      final date = serverDate(m['date']);
      final sale = Sale(
        id: m['id'] as String,
        date: date,
        total: (m['totalMinor'] as num).toInt(),
        customerId: m['customerId'] as String?,
        isPending: m['isPending'] as bool?,
        items: [
          for (final i in (m['items'] as List<dynamic>).cast<Map<String, dynamic>>())
            CartItem(
              // The server keeps a name/price snapshot; stock and usage are not part of a sale.
              product: Product(
                id: i['productId'] as String,
                name: i['name'] as String,
                price: (i['priceMinor'] as num).toInt(),
                stock: 0,
                usageCount: 0,
                createdAt: date,
              ),
              quantity: (i['quantity'] as num).toInt(),
            ),
        ],
      );
      sales[sale.id] = sale;
    }
    final transactions = <String, PulledTransaction>{};
    for (final raw in j['transactions'] as List<dynamic>) {
      final m = raw as Map<String, dynamic>;
      final t = CustomerTransaction(
        id: m['id'] as String,
        amount: (m['amountMinor'] as num).toInt(),
        type: TransactionType.values.byName(m['type'] as String),
        description: m['description'] as String,
        date: serverDate(m['date']),
        saleId: m['saleId'] as String?,
      );
      transactions[t.id] = (customerId: m['customerId'] as String, transaction: t);
    }
    return PullPage(
      reset: j['reset'] as bool,
      cursor: j['cursor'] as String,
      hasMore: j['hasMore'] as bool,
      shop: ShopInfo.fromJson(j['shop'] as Map<String, dynamic>),
      products: products,
      deletedProducts: deletedProducts,
      customers: customers,
      deletedCustomers: deletedCustomers,
      sales: sales,
      transactions: transactions,
    );
  }

  /// This page followed by [later]: newer records win, and a deletion and
  /// an update of the same record keep whichever came last.
  PullPage merge(PullPage later) {
    final products = {...this.products};
    final deletedProducts = {...this.deletedProducts};
    for (final id in later.deletedProducts) {
      products.remove(id);
      deletedProducts.add(id);
    }
    for (final p in later.products.values) {
      deletedProducts.remove(p.id);
      products[p.id] = p;
    }
    final customers = {...this.customers};
    final deletedCustomers = {...this.deletedCustomers};
    for (final id in later.deletedCustomers) {
      customers.remove(id);
      deletedCustomers.add(id);
    }
    for (final c in later.customers.values) {
      deletedCustomers.remove(c.id);
      customers[c.id] = c;
    }
    return PullPage(
      reset: reset,
      cursor: later.cursor,
      hasMore: later.hasMore,
      shop: later.shop,
      products: products,
      deletedProducts: deletedProducts,
      customers: customers,
      deletedCustomers: deletedCustomers,
      sales: {...sales, ...later.sales},
      transactions: {...transactions, ...later.transactions},
    );
  }
}

/// Server timestamps are UTC; the phone stores and shows local time.
DateTime serverDate(Object? value) => DateTime.parse(value as String).toLocal();

/// Timestamps sent to the server carry their offset (a trailing `Z`), so
/// they are not read as the server's own time zone.
String toServerDate(DateTime d) => d.toUtc().toIso8601String();
