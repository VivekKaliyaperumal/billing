import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';

/// Port of `src/context/ProductContext.tsx`.
class ProductProvider extends ChangeNotifier {
  ProductProvider(this._prefs) {
    final stored = _prefs.getString(storageKey);
    _products = stored != null
        ? (jsonDecode(stored) as List).map((e) => Product.fromJson(e as Map<String, dynamic>)).toList()
        : _defaultProducts();
  }

  static const storageKey = 'shop_products';
  static const _uuid = Uuid();

  final SharedPreferences _prefs;
  late List<Product> _products;

  List<Product> get products => List.unmodifiable(_products);

  static List<Product> _defaultProducts() {
    final now = DateTime.now();
    Product p(String id, String name, double price, int stock, int usage) =>
        Product(id: id, name: name, price: price, stock: stock, usageCount: usage, createdAt: now);
    return [
      p('1', 'Milk 1L', 60, 50, 120),
      p('2', 'Bread Loaf', 45, 30, 95),
      p('3', 'Eggs (12 pack)', 90, 25, 88),
      p('4', 'Butter 250g', 55, 20, 72),
      p('5', 'Cheese Block', 150, 15, 65),
      p('6', 'Orange Juice 1L', 80, 40, 58),
      p('7', 'Yogurt 500g', 35, 35, 45),
      p('8', 'Coffee Powder 500g', 250, 18, 40),
    ];
  }

  void _save() {
    _prefs.setString(storageKey, jsonEncode(_products.map((p) => p.toJson()).toList()));
    notifyListeners();
  }

  Product? byId(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  void addProduct({required String name, required double price, required int stock, String? image}) {
    _products = [
      ..._products,
      Product(
        id: _uuid.v4(),
        name: name,
        price: price,
        stock: stock,
        image: image,
        usageCount: 0,
        createdAt: DateTime.now(),
      ),
    ];
    _save();
  }

  void updateProduct(String id, {required String name, required double price, required int stock, String? image}) {
    _products = _products
        .map((p) => p.id == id ? p.copyWith(name: name, price: price, stock: stock, image: () => image) : p)
        .toList();
    _save();
  }

  void deleteProduct(String id) {
    _products = _products.where((p) => p.id != id).toList();
    _save();
  }

  /// Builds the sale, reduces stock and increases usage count.
  Sale completeSale(List<CartItem> items, {String? customerId, bool? isPending}) {
    final sale = Sale(
      id: _uuid.v4(),
      items: List.of(items),
      total: items.fold(0.0, (s, i) => s + i.product.price * i.quantity),
      date: DateTime.now(),
      customerId: customerId,
      isPending: isPending,
    );
    _products = _products.map((p) {
      final matches = items.where((i) => i.product.id == p.id);
      if (matches.isEmpty) return p;
      final qty = matches.first.quantity;
      return p.copyWith(stock: p.stock - qty, usageCount: p.usageCount + qty);
    }).toList();
    _save();
    return sale;
  }

  List<Product> getMostUsedProducts([int limit = 8]) {
    final list = _products.where((p) => p.stock > 0).toList()
      ..sort((a, b) => b.usageCount.compareTo(a.usageCount));
    return list.take(limit).toList();
  }

  List<Product> searchProducts(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return _products.where((p) => p.stock > 0).toList();
    return _products.where((p) => p.name.toLowerCase().contains(q) && p.stock > 0).toList();
  }
}
