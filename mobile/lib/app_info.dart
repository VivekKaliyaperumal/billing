/// App identity shown in the UI and used for outbound links.
library;

const appName = 'Thyantra Billing';
const publisherName = 'Thyantra Technologies';
const supportEmail = 'hello@thyantra.com';
const websiteUrl = 'https://thyantra.com';
const privacyPolicyUrl = 'https://thyantra.com/billing-privacy-policy';

/// Sync server. Defaults to the dev backend as seen from the Android
/// emulator; set the real one at build time with
/// `--dart-define=API_BASE_URL=https://api.example.com/api/v1`.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3100/api/v1');
