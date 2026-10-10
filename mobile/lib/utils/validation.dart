/// Input rules shared by the product and customer forms.
library;

const maxNameLength = 100;
const maxStock = 1000000;
const maxImageUrlLength = 500;

/// Strips spaces, dashes, dots and brackets so "+91 98765-43210" and
/// "+919876543210" compare equal.
String normalizePhone(String input) => input.replaceAll(RegExp(r'[\s\-().]'), '');

final _phonePattern = RegExp(r'^\+?\d{7,15}$');

/// True for 7–15 digits with an optional leading "+", after [normalizePhone].
bool isValidPhone(String input) => _phonePattern.hasMatch(normalizePhone(input));

/// Product images must be https: cleartext URLs are blocked on Android and
/// would leak which products a shop sells to anyone on the network.
bool isValidImageUrl(String input) {
  final uri = Uri.tryParse(input);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}
