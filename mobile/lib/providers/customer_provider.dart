import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../utils/storage.dart';
import '../utils/validation.dart';

/// Customer credit ledger. State changes only after the database write
/// succeeds.
class CustomerProvider extends ChangeNotifier {
  CustomerProvider(this._db, List<Customer> initial) : _customers = List.of(initial);

  static const _uuid = Uuid();

  final AppDatabase _db;
  List<Customer> _customers;

  List<Customer> get customers => List.unmodifiable(_customers);

  int get totalPendingAmount => _customers.fold(0, (s, c) => s + c.pendingAmount);

  Customer? byId(String id) {
    for (final c in _customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Matches on the normalised number, so formatting differences don't
  /// create duplicate ledgers for the same person.
  Customer? byPhone(String phone) {
    final n = normalizePhone(phone);
    for (final c in _customers) {
      if (normalizePhone(c.phone) == n) return c;
    }
    return null;
  }

  /// Returns an error message, or null if the details are acceptable.
  /// [excludingId] lets an existing customer keep their own number.
  String? validateDetails(String name, String phone, {String? excludingId}) {
    final n = name.trim();
    if (n.isEmpty) return 'Please enter the customer name';
    if (n.length > maxNameLength) return 'Name must be less than $maxNameLength characters';
    if (!isValidPhone(phone)) return 'Please enter a valid phone number';
    final existing = byPhone(phone);
    if (existing != null && existing.id != excludingId) return 'This phone number already belongs to ${existing.name}';
    return null;
  }

  /// Builds (but does not save) a new customer from validated details.
  Customer draftCustomer({required String name, required String phone}) {
    final error = validateDetails(name, phone);
    if (error != null) throw ArgumentError(error);
    return Customer(
      id: _uuid.v4(),
      name: name.trim(),
      phone: normalizePhone(phone),
      pendingAmount: 0,
      createdAt: DateTime.now(),
      transactions: const [],
    );
  }

  /// Validates and saves a new customer. Returns null if saving failed.
  Future<Customer?> addCustomer({required String name, required String phone}) async {
    final customer = draftCustomer(name: name, phone: phone);
    try {
      await _db.insertCustomer(customer);
    } catch (e) {
      reportStorageIssue('Could not save the customer. Please try again.', e);
      return null;
    }
    _customers = [..._customers, customer];
    notifyListeners();
    return customer;
  }

  /// Validates and saves new contact details. Returns false if saving failed.
  Future<bool> updateDetails(String id, {required String name, required String phone}) async {
    final error = validateDetails(name, phone, excludingId: id);
    if (error != null) throw ArgumentError(error);
    final n = name.trim();
    final ph = normalizePhone(phone);
    try {
      await _db.updateCustomerDetails(id, name: n, phone: ph);
    } catch (e) {
      reportStorageIssue('Could not save the customer. Please try again.', e);
      return false;
    }
    _customers = _customers.map((c) => c.id == id ? c.copyWith(name: n, phone: ph) : c).toList();
    notifyListeners();
    return true;
  }

  /// Deletes a customer with no pending balance. Returns false otherwise.
  Future<bool> deleteCustomer(String id) async {
    if ((byId(id)?.pendingAmount ?? 1) != 0) return false;
    try {
      await _db.deleteCustomer(id);
    } catch (e) {
      reportStorageIssue('Could not delete the customer. Please try again.', e);
      return false;
    }
    _customers = _customers.where((c) => c.id != id).toList();
    notifyListeners();
    return true;
  }

  /// Builds (but does not save) a credit entry for a sale.
  CustomerTransaction draftCredit(int amount, String description, {String? saleId}) => CustomerTransaction(
        id: _uuid.v4(),
        amount: amount,
        type: TransactionType.credit,
        description: description,
        date: DateTime.now(),
        saleId: saleId,
      );

  /// Mirrors a credit sale the database has already recorded.
  void applyCredit(Customer customer, CustomerTransaction credit, {required bool isNew}) {
    final base = isNew ? customer : (byId(customer.id) ?? customer);
    final updated = base.copyWith(
      pendingAmount: base.pendingAmount + credit.amount,
      transactions: [...base.transactions, credit],
    );
    _customers = isNew ? [..._customers, updated] : _customers.map((c) => c.id == updated.id ? updated : c).toList();
    notifyListeners();
  }

  /// [amount] is in minor units and must be between 1 and the pending
  /// balance, so no part of a payment is silently discarded. Throws
  /// [ArgumentError] for an invalid amount; returns false if saving failed.
  Future<bool> addPayment(String customerId, int amount, String description) async {
    final customer = byId(customerId);
    if (customer == null) throw ArgumentError('Unknown customer');
    if (amount <= 0 || amount > customer.pendingAmount) {
      throw ArgumentError('Payment must be between 1 and the pending amount');
    }
    final payment = CustomerTransaction(
      id: _uuid.v4(),
      amount: amount,
      type: TransactionType.payment,
      description: description,
      date: DateTime.now(),
    );
    try {
      await _db.recordPayment(customerId, payment);
    } catch (e) {
      reportStorageIssue('Could not record the payment. Please try again.', e);
      return false;
    }
    _customers = _customers
        .map((c) => c.id == customerId
            ? c.copyWith(pendingAmount: c.pendingAmount - amount, transactions: [...c.transactions, payment])
            : c)
        .toList();
    notifyListeners();
    return true;
  }

  /// Replaces everything after a restore that has already been saved.
  void replaceAll(List<Customer> customers) {
    _customers = List.of(customers);
    notifyListeners();
  }
}
