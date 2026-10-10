// Data models ported from `src/types/product.ts`.
// JSON shape matches what the web app writes to localStorage.

class Product {
  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    this.image,
    required this.usageCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final double price;
  final int stock;
  final String? image;
  final int usageCount;
  final DateTime createdAt;

  Product copyWith({String? name, double? price, int? stock, String? Function()? image, int? usageCount}) => Product(
        id: id,
        name: name ?? this.name,
        price: price ?? this.price,
        stock: stock ?? this.stock,
        image: image != null ? image() : this.image,
        usageCount: usageCount ?? this.usageCount,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'stock': stock,
        if (image != null) 'image': image,
        'usageCount': usageCount,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        name: j['name'] as String,
        price: (j['price'] as num).toDouble(),
        stock: (j['stock'] as num).toInt(),
        image: j['image'] as String?,
        usageCount: (j['usageCount'] as num).toInt(),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class CartItem {
  CartItem({required this.product, required this.quantity});

  /// Snapshot of the product at the time of sale.
  final Product product;
  final int quantity;

  double get subtotal => product.price * quantity;

  CartItem copyWith({int? quantity}) => CartItem(product: product, quantity: quantity ?? this.quantity);

  Map<String, dynamic> toJson() => {'product': product.toJson(), 'quantity': quantity};

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
        product: Product.fromJson(j['product'] as Map<String, dynamic>),
        quantity: (j['quantity'] as num).toInt(),
      );
}

class Sale {
  Sale({
    required this.id,
    required this.items,
    required this.total,
    required this.date,
    this.customerId,
    this.isPending,
  });

  final String id;
  final List<CartItem> items;
  final double total;
  final DateTime date;
  final String? customerId;
  final bool? isPending;

  int get itemCount => items.fold(0, (s, i) => s + i.quantity);

  Map<String, dynamic> toJson() => {
        'id': id,
        'items': items.map((i) => i.toJson()).toList(),
        'total': total,
        'date': date.toIso8601String(),
        if (customerId != null) 'customerId': customerId,
        if (isPending != null) 'isPending': isPending,
      };

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        id: j['id'] as String,
        items: (j['items'] as List).map((e) => CartItem.fromJson(e as Map<String, dynamic>)).toList(),
        total: (j['total'] as num).toDouble(),
        date: DateTime.parse(j['date'] as String),
        customerId: j['customerId'] as String?,
        isPending: j['isPending'] as bool?,
      );
}

enum TransactionType { credit, payment }

class CustomerTransaction {
  CustomerTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.description,
    required this.date,
    this.saleId,
  });

  final String id;
  final double amount;
  final TransactionType type;
  final String description;
  final DateTime date;
  final String? saleId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'type': type.name,
        'description': description,
        'date': date.toIso8601String(),
        if (saleId != null) 'saleId': saleId,
      };

  factory CustomerTransaction.fromJson(Map<String, dynamic> j) => CustomerTransaction(
        id: j['id'] as String,
        amount: (j['amount'] as num).toDouble(),
        type: TransactionType.values.byName(j['type'] as String),
        description: j['description'] as String,
        date: DateTime.parse(j['date'] as String),
        saleId: j['saleId'] as String?,
      );
}

class Customer {
  Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.pendingAmount,
    required this.createdAt,
    required this.transactions,
  });

  final String id;
  final String name;
  final String phone;
  final double pendingAmount;
  final DateTime createdAt;
  final List<CustomerTransaction> transactions;

  Customer copyWith({double? pendingAmount, List<CustomerTransaction>? transactions}) => Customer(
        id: id,
        name: name,
        phone: phone,
        pendingAmount: pendingAmount ?? this.pendingAmount,
        createdAt: createdAt,
        transactions: transactions ?? this.transactions,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'pendingAmount': pendingAmount,
        'createdAt': createdAt.toIso8601String(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
      };

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String,
        pendingAmount: (j['pendingAmount'] as num).toDouble(),
        createdAt: DateTime.parse(j['createdAt'] as String),
        transactions: (j['transactions'] as List)
            .map((e) => CustomerTransaction.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AppSettings {
  const AppSettings({required this.currency, required this.currencySymbol, required this.shopName});

  final String currency;
  final String currencySymbol;
  final String shopName;

  static const defaults = AppSettings(currency: 'INR', currencySymbol: '₹', shopName: 'ShopEase');

  Map<String, dynamic> toJson() => {'currency': currency, 'currencySymbol': currencySymbol, 'shopName': shopName};

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        currency: j['currency'] as String,
        currencySymbol: j['currencySymbol'] as String,
        shopName: j['shopName'] as String,
      );
}

class Currency {
  const Currency(this.code, this.symbol, this.name);
  final String code;
  final String symbol;
  final String name;
}

const currencies = [
  Currency('INR', '₹', 'Indian Rupee'),
  Currency('USD', r'$', 'US Dollar'),
  Currency('EUR', '€', 'Euro'),
  Currency('GBP', '£', 'British Pound'),
];
