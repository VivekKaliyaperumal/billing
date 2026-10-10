import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../utils/format.dart';

class MonthlySalesData {
  MonthlySalesData({required this.month, required this.year, required this.monthNum, this.total = 0, this.count = 0});

  final String month; // short month name, e.g. "Oct"
  final int year;
  final int monthNum; // 0-based, like JS getMonth()
  double total;
  int count;

  /// Select value used by the web app: "year-month" with 0-based month.
  String get key => '$year-$monthNum';
}

class ProductSalesData {
  ProductSalesData(this.productName, {this.quantity = 0, this.revenue = 0});
  final String productName;
  int quantity;
  double revenue;
}

/// Port of `src/context/SalesHistoryContext.tsx`.
class SalesHistoryProvider extends ChangeNotifier {
  SalesHistoryProvider(this._prefs) {
    final stored = _prefs.getString(storageKey);
    _sales = stored != null
        ? (jsonDecode(stored) as List).map((e) => Sale.fromJson(e as Map<String, dynamic>)).toList()
        : [];
  }

  static const storageKey = 'shop_sales_history';

  final SharedPreferences _prefs;
  late List<Sale> _sales;

  /// Newest first.
  List<Sale> get sales => List.unmodifiable(_sales);

  void addSale(Sale sale) {
    _sales = [sale, ..._sales];
    _prefs.setString(storageKey, jsonEncode(_sales.map((s) => s.toJson()).toList()));
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

  static List<ProductSalesData> _aggregate(Iterable<Sale> sales, int limit) {
    final data = <String, ProductSalesData>{};
    for (final sale in sales) {
      for (final item in sale.items) {
        final p = data.putIfAbsent(item.product.name, () => ProductSalesData(item.product.name));
        p.quantity += item.quantity;
        p.revenue += item.product.price * item.quantity;
      }
    }
    final list = data.values.toList()..sort((a, b) => b.quantity.compareTo(a.quantity));
    return list.take(limit).toList();
  }
}
