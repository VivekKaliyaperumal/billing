import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Current cart. In-memory only, like the `useState` cart in SalesPage.tsx.
class CartProvider extends ChangeNotifier {
  List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  double get total => _items.fold(0.0, (s, i) => s + i.subtotal);
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
    if (existing > 0) {
      if (existing >= maxStock) return false;
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
}
