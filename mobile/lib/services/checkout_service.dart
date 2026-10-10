import '../data/app_database.dart';
import '../models/models.dart';
import '../providers/cart_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/product_provider.dart';
import '../providers/sales_history_provider.dart';
import '../utils/storage.dart';

sealed class CheckoutResult {
  const CheckoutResult();
}

class CheckoutCompleted extends CheckoutResult {
  const CheckoutCompleted(this.sale);
  final Sale sale;
}

/// The cart no longer matched inventory and has been corrected; nothing was
/// sold. The cashier should review the cart and confirm again.
class CheckoutCartChanged extends CheckoutResult {
  const CheckoutCartChanged(this.changes);
  final List<String> changes;
}

/// The credit customer was missing or invalid; nothing was sold.
class CheckoutCustomerError extends CheckoutResult {
  const CheckoutCustomerError(this.message);
  final String message;
}

/// The sale could not be saved; nothing was sold and the cart is kept.
class CheckoutFailed extends CheckoutResult {
  const CheckoutFailed();
}

/// Turns the cart into a recorded sale. The order is: validate the cart
/// against inventory → resolve the customer → save everything in one
/// database transaction → update the in-memory state. If saving fails,
/// nothing changes and the cart is kept.
class CheckoutService {
  const CheckoutService({
    required this.db,
    required this.cart,
    required this.products,
    required this.history,
    required this.customers,
  });

  final AppDatabase db;
  final CartProvider cart;
  final ProductProvider products;
  final SalesHistoryProvider history;
  final CustomerProvider customers;

  /// Cash sale.
  Future<CheckoutResult> checkout() async {
    final changes = _reconcile();
    if (changes != null) return changes;
    final sale = products.buildSale(cart.items);
    if (!await _save(() => db.recordSale(sale))) return const CheckoutFailed();
    _apply(sale);
    return CheckoutCompleted(sale);
  }

  /// Credit sale for an existing customer ([selectedId]) or a new one
  /// described by [name] and [phone].
  Future<CheckoutResult> creditCheckout({String? selectedId, required String name, required String phone}) async {
    final changes = _reconcile();
    if (changes != null) return changes;

    final Customer customer;
    final bool isNew;
    if (selectedId != null) {
      final existing = customers.byId(selectedId);
      if (existing == null) return const CheckoutCustomerError('Selected customer no longer exists');
      customer = existing;
      isNew = false;
    } else {
      if (name.trim().isEmpty && phone.trim().isEmpty) {
        return const CheckoutCustomerError('Please select or add a customer');
      }
      final error = customers.validateDetails(name, phone);
      if (error != null) return CheckoutCustomerError(error);
      customer = customers.draftCustomer(name: name, phone: phone);
      isNew = true;
    }

    final sale = products.buildSale(cart.items, customerId: customer.id);
    final credit = customers.draftCredit(sale.total, 'Sale #${sale.id.substring(0, 8)}', saleId: sale.id);
    final saved = await _save(() => db.recordSale(
          sale,
          newCustomer: isNew ? customer : null,
          creditCustomerId: customer.id,
          credit: credit,
        ));
    if (!saved) return const CheckoutFailed();
    _apply(sale);
    customers.applyCredit(customer, credit, isNew: isNew);
    return CheckoutCompleted(sale);
  }

  CheckoutResult? _reconcile() {
    if (cart.isEmpty) return const CheckoutCartChanged(['Cart is empty']);
    final changes = cart.reconcile(products.products);
    return changes.isEmpty ? null : CheckoutCartChanged(changes);
  }

  Future<bool> _save(Future<void> Function() write) async {
    try {
      await write();
      return true;
    } on ConflictException catch (e) {
      reportStorageIssue(e.message, e);
      return false;
    } catch (e) {
      reportStorageIssue('Could not save the sale. Nothing was charged; please try again.', e);
      return false;
    }
  }

  void _apply(Sale sale) {
    products.applySale(sale);
    history.applySale(sale);
    cart.clear();
  }
}
