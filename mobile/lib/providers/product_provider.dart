import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../utils/storage.dart';

/// Inventory. State changes only after the database write succeeds, so the
/// screen never shows something that was not saved.
class ProductProvider extends ChangeNotifier {
  ProductProvider(this._db, List<Product> initial) : _products = List.of(initial);

  static const _uuid = Uuid();
  static const _saveFailed = 'Could not save the product. Please try again.';

  final AppDatabase _db;
  List<Product> _products;

  List<Product> get products => List.unmodifiable(_products);

  Product? byId(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// [price] is in minor units. Returns false if saving failed.
  Future<bool> addProduct({required String name, required int price, required int stock, String? image}) async {
    final product = Product(
      id: _uuid.v4(),
      name: name,
      price: price,
      stock: stock,
      image: image,
      usageCount: 0,
      createdAt: DateTime.now(),
    );
    try {
      await _db.insertProduct(product);
    } catch (e) {
      reportStorageIssue(_saveFailed, e);
      return false;
    }
    _products = [..._products, product];
    notifyListeners();
    return true;
  }

  /// [price] is in minor units. Returns false if saving failed.
  Future<bool> updateProduct(String id, {required String name, required int price, required int stock, String? image}) async {
    final current = byId(id);
    if (current == null) return false;
    final updated = current.copyWith(name: name, price: price, stock: stock, image: () => image);
    try {
      await _db.updateProduct(updated);
    } catch (e) {
      reportStorageIssue(_saveFailed, e);
      return false;
    }
    _products = _products.map((p) => p.id == id ? updated : p).toList();
    notifyListeners();
    return true;
  }

  /// Returns false if saving failed. Past sales keep their own copy of the
  /// product, so history is unaffected.
  Future<bool> deleteProduct(String id) async {
    try {
      await _db.deleteProduct(id);
    } catch (e) {
      reportStorageIssue('Could not delete the product. Please try again.', e);
      return false;
    }
    _products = _products.where((p) => p.id != id).toList();
    notifyListeners();
    return true;
  }

  /// Builds a sale from [items], which must match current inventory (see
  /// [CartProvider.reconcile]); a [StateError] is thrown otherwise so a sale
  /// is never priced from a stale snapshot or oversold. Nothing is saved.
  Sale buildSale(List<CartItem> items, {String? customerId}) {
    for (final item in items) {
      final current = byId(item.product.id);
      if (current == null || current.price != item.product.price || current.stock < item.quantity) {
        throw StateError('Cart is out of date for ${item.product.name}');
      }
    }
    return Sale(
      id: _uuid.v4(),
      items: List.of(items),
      total: items.fold(0, (s, i) => s + i.subtotal),
      date: DateTime.now(),
      customerId: customerId,
      isPending: customerId != null ? true : null,
    );
  }

  /// Mirrors a sale the database has already recorded: lowers stock and
  /// raises usage counts in memory.
  void applySale(Sale sale) {
    final qtyById = {for (final i in sale.items) i.product.id: i.quantity};
    _products = _products.map((p) {
      final qty = qtyById[p.id];
      return qty == null ? p : p.copyWith(stock: p.stock - qty, usageCount: p.usageCount + qty);
    }).toList();
    notifyListeners();
  }

  /// Replaces everything after a restore that has already been saved.
  void replaceAll(List<Product> products) {
    _products = List.of(products);
    notifyListeners();
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
