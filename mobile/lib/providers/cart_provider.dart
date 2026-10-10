import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Current cart. In-memory only, like the `useState` cart in SalesPage.tsx.
class CartProvider extends ChangeNotifier {
  List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  /// Total in minor units.
  int get total => _items.fold(0, (s, i) => s + i.subtotal);
  int get itemCount => _items.fold(0, (s, i) => s + i.quantity);

  int quantityOf(String productId) {
    for (final i in _items) {
      if (i.product.id == productId) return i.quantity;
    }
    return 0;
  }

  /// Adds one unit. Returns false if the stock limit is reached.
  bool add(Product product, int maxStock) {
    final existing = quantityOf(product.id);
    if (existing >= maxStock) return false;
    if (existing > 0) {
      _items = _items.map((i) => i.product.id == product.id ? i.copyWith(quantity: i.quantity + 1) : i).toList();
    } else {
      _items = [..._items, CartItem(product: product, quantity: 1)];
    }
    notifyListeners();
    return true;
  }

  void setQuantity(String productId, int quantity) {
    _items = _items.map((i) => i.product.id == productId ? i.copyWith(quantity: quantity) : i).toList();
    notifyListeners();
  }

  void remove(String productId) {
    _items = _items.where((i) => i.product.id != productId).toList();
    notifyListeners();
  }

  void clear() {
    _items = [];
    notifyListeners();
  }

  /// Brings the cart in line with the current inventory: refreshes each
  /// product snapshot (so the latest price is charged), caps quantities at
  /// available stock and drops deleted or sold-out products. Returns a
  /// description of each change; empty when the cart was already current.
  List<String> reconcile(List<Product> inventory) {
    final byId = {for (final p in inventory) p.id: p};
    final changes = <String>[];
    final next = <CartItem>[];
    for (final item in _items) {
      final current = byId[item.product.id];
      if (current == null) {
        changes.add('${item.product.name} was removed from inventory');
        continue;
      }
      if (current.stock <= 0) {
        changes.add('${current.name} is out of stock');
        continue;
      }
      if (current.price != item.product.price) {
        changes.add('${current.name} price changed');
      }
      var quantity = item.quantity;
      if (quantity > current.stock) {
        quantity = current.stock;
        changes.add('${current.name} reduced to ${current.stock} (stock available)');
      }
      next.add(CartItem(product: current, quantity: quantity));
    }
    _items = next;
    if (changes.isNotEmpty) notifyListeners();
    return changes;
  }
}
