import 'package:billing_mobile/models/models.dart';
import 'package:billing_mobile/providers/cart_provider.dart';
import 'package:billing_mobile/providers/customer_provider.dart';
import 'package:billing_mobile/providers/product_provider.dart';
import 'package:billing_mobile/providers/sales_history_provider.dart';
import 'package:billing_mobile/providers/settings_provider.dart';
import 'package:billing_mobile/utils/csv_export.dart';
import 'package:billing_mobile/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('formatIndian uses en-IN grouping with 2 decimals', () {
    expect(formatIndian(0), '0.00');
    expect(formatIndian(60), '60.00');
    expect(formatIndian(1234.56), '1,234.56');
    expect(formatIndian(1234567.891), '12,34,567.89');
  });

  test('seeds the 8 default products and most-used ordering', () {
    final products = ProductProvider(prefs);
    expect(products.products.length, 8);
    expect(products.getMostUsedProducts(3).map((p) => p.name), ['Milk 1L', 'Bread Loaf', 'Eggs (12 pack)']);
    expect(products.searchProducts('juice').single.name, 'Orange Juice 1L');
  });

  test('completeSale reduces stock, raises usage and persists', () {
    final products = ProductProvider(prefs);
    final milk = products.byId('1')!;
    final sale = products.completeSale([CartItem(product: milk, quantity: 3)]);
    expect(sale.total, 180);
    expect(products.byId('1')!.stock, 47);
    expect(products.byId('1')!.usageCount, 123);
    expect(ProductProvider(prefs).byId('1')!.stock, 47);
  });

  test('cart respects the stock limit', () {
    final cart = CartProvider();
    final p = Product(id: 'x', name: 'X', price: 10, stock: 2, usageCount: 0, createdAt: DateTime.now());
    expect(cart.add(p, 2), isTrue);
    expect(cart.add(p, 2), isTrue);
    expect(cart.add(p, 2), isFalse);
    expect(cart.itemCount, 2);
    expect(cart.total, 20);
  });

  test('credit and payment, pending never below 0', () {
    final customers = CustomerProvider(prefs);
    final c = customers.addCustomer(name: 'Asha', phone: '98765');
    customers.addCredit(c.id, 500, 'Sale #abc');
    customers.addPayment(c.id, 700, 'Payment received');
    final saved = CustomerProvider(prefs).customers.single;
    expect(saved.pendingAmount, 0);
    expect(saved.transactions.map((t) => t.type), [TransactionType.credit, TransactionType.payment]);
  });

  test('settings: currency change updates symbol and formatPrice', () {
    final settings = SettingsProvider(prefs);
    expect(settings.formatPrice(1234.5), '₹1,234.50');
    settings.updateSettings(currency: 'USD');
    expect(settings.settings.currencySymbol, r'$');
    expect(SettingsProvider(prefs).formatPrice(10), r'$10.00');
  });

  test('monthly data, top products and CSV match the web format', () {
    final history = SalesHistoryProvider(prefs);
    Product prod(String n, double price) =>
        Product(id: n, name: n, price: price, stock: 9, usageCount: 0, createdAt: DateTime(2026));
    history.addSale(Sale(
      id: 's1',
      items: [CartItem(product: prod('Milk 1L', 60), quantity: 2)],
      total: 120,
      date: DateTime(2026, 9, 5, 10, 30),
    ));
    history.addSale(Sale(
      id: 's2',
      items: [CartItem(product: prod('Bread Loaf', 45), quantity: 1), CartItem(product: prod('Milk 1L', 60), quantity: 1)],
      total: 105,
      date: DateTime(2026, 10, 1, 9, 5),
    ));
    final monthly = history.getMonthlySalesData();
    expect(monthly.map((m) => m.key), ['2026-8', '2026-9']);
    expect(monthly.first.month, 'Sep');
    expect(history.getTopProductsAllTime().first.productName, 'Milk 1L');
    expect(history.getTopProductsByMonth(2026, 9).length, 2);
    expect(
      buildSalesCsv(history.sales),
      'Date,Items,Total\n2026-10-01 09:05,Bread Loaf x1; Milk 1L x1,105.00\n2026-09-05 10:30,Milk 1L x2,120.00',
    );
  });
}
