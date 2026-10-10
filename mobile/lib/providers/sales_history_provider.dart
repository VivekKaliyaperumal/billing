import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../utils/format.dart';

class MonthlySalesData {
  MonthlySalesData({required this.month, required this.year, required this.monthNum, this.total = 0, this.count = 0});

  final String month; // short month name, e.g. "Oct"
  final int year;
  final int monthNum; // 0-based, like JS getMonth()
  int total; // minor units
  int count;

  /// Select value used by the web app: "year-month" with 0-based month.
  String get key => '$year-$monthNum';
}

class ProductSalesData {
  ProductSalesData(this.productName, {this.quantity = 0, this.revenue = 0});
  final String productName;
  int quantity;
  int revenue; // minor units
}

/// Sales history. Sales are written by [CheckoutService]; this provider
/// mirrors them in memory for the reports.
class SalesHistoryProvider extends ChangeNotifier {
  SalesHistoryProvider(List<Sale> initial) : _sales = List.of(initial);

  List<Sale> _sales;

  /// Newest first.
  List<Sale> get sales => List.unmodifiable(_sales);

  /// Mirrors a sale the database has already recorded.
  void applySale(Sale sale) {
    _sales = [sale, ..._sales];
    notifyListeners();
  }

  /// Replaces everything after a restore that has already been saved.
  void replaceAll(List<Sale> sales) {
    _sales = List.of(sales)..sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }

  List<Sale> getSalesByDateRange(DateTime start, DateTime end) =>
      _sales.where((s) => !s.date.isBefore(start) && !s.date.isAfter(end)).toList();

  List<MonthlySalesData> getMonthlySalesData() {
    final data = <String, MonthlySalesData>{};
    for (final sale in _sales) {
      final key = '${sale.date.year}-${sale.date.month - 1}';
      final m = data.putIfAbsent(
        key,
        () => MonthlySalesData(month: monthShort.format(sale.date), year: sale.date.year, monthNum: sale.date.month - 1),
      );
      m.total += sale.total;
      m.count += 1;
    }
    return data.values.toList()
      ..sort((a, b) => a.year != b.year ? a.year - b.year : a.monthNum - b.monthNum);
  }

  /// [month] is 0-based, as in the web app.
  List<ProductSalesData> getTopProductsByMonth(int year, int month) =>
      _aggregate(_sales.where((s) => s.date.year == year && s.date.month - 1 == month), 10);

  List<ProductSalesData> getTopProductsAllTime([int limit = 5]) => _aggregate(_sales, limit);

  /// Groups by product id so a renamed product keeps one entry; it is shown
  /// under its most recent name (sales are newest first).
  static List<ProductSalesData> _aggregate(Iterable<Sale> sales, int limit) {
    final data = <String, ProductSalesData>{};
    for (final sale in sales) {
      for (final item in sale.items) {
        final p = data.putIfAbsent(item.product.id, () => ProductSalesData(item.product.name));
        p.quantity += item.quantity;
        p.revenue += item.subtotal;
      }
    }
    final list = data.values.toList()..sort((a, b) => b.quantity.compareTo(a.quantity));
    return list.take(limit).toList();
  }
}
