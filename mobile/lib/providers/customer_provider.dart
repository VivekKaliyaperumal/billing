import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';

/// Port of `src/context/CustomerContext.tsx`.
class CustomerProvider extends ChangeNotifier {
  CustomerProvider(this._prefs) {
    final stored = _prefs.getString(storageKey);
    _customers = stored != null
        ? (jsonDecode(stored) as List).map((e) => Customer.fromJson(e as Map<String, dynamic>)).toList()
        : [];
  }

  static const storageKey = 'shop_customers';
  static const _uuid = Uuid();

  final SharedPreferences _prefs;
  late List<Customer> _customers;

  List<Customer> get customers => List.unmodifiable(_customers);

  void _save() {
    _prefs.setString(storageKey, jsonEncode(_customers.map((c) => c.toJson()).toList()));
    notifyListeners();
  }

  Customer addCustomer({required String name, required String phone}) {
    final c = Customer(
      id: _uuid.v4(),
      name: name,
      phone: phone,
      pendingAmount: 0,
      createdAt: DateTime.now(),
      transactions: const [],
    );
    _customers = [..._customers, c];
    _save();
    return c;
  }

  void addCredit(String customerId, double amount, String description, {String? saleId}) {
    final t = CustomerTransaction(
      id: _uuid.v4(),
      amount: amount,
      type: TransactionType.credit,
      description: description,
      date: DateTime.now(),
      saleId: saleId,
    );
    _customers = _customers
        .map((c) => c.id == customerId
            ? c.copyWith(pendingAmount: c.pendingAmount + amount, transactions: [...c.transactions, t])
            : c)
        .toList();
    _save();
  }

  /// Pending never drops below 0 (overpayment is allowed, as on the web).
  void addPayment(String customerId, double amount, String description) {
    final t = CustomerTransaction(
      id: _uuid.v4(),
      amount: amount,
      type: TransactionType.payment,
      description: description,
      date: DateTime.now(),
    );
    _customers = _customers
        .map((c) => c.id == customerId
            ? c.copyWith(
                pendingAmount: math.max(0, c.pendingAmount - amount).toDouble(),
                transactions: [...c.transactions, t],
              )
            : c)
        .toList();
    _save();
  }

  double get totalPendingAmount => _customers.fold(0.0, (s, c) => s + c.pendingAmount);
}
