import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../models/models.dart';
import '../models/sync_models.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/product_provider.dart';
import '../providers/sales_history_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/storage.dart';
import 'api_client.dart';
import 'backup_service.dart';

/// What to do with this phone's data on the first sync with a shop.
enum FirstSyncPlan {
  /// Already synced with this shop: carry on.
  resume,

  /// Nothing worth keeping on the phone: download the shop.
  download,

  /// The shop is empty and the phone has data: upload it to the shop.
  upload,

  /// Both have data: the user must agree to replace the phone's copy.
  confirmReplace,
}

/// Keeps this phone and the shop's server in step while signed in.
///
/// A sync pushes the outbox oldest first, then downloads everything changed
/// since the last sync and saves it in one transaction. The download is
/// only saved when nothing new was queued meanwhile; otherwise the next sync
/// picks it up. If the server refused any change, the next download is a
/// full one, so the phone drops what the server did not accept.
class SyncService extends ChangeNotifier {
  SyncService({
    required this._db,
    required this._api,
    required this._auth,
    required this._products,
    required this._history,
    required this._customers,
    required this._settings,
  }) {
    _auth.addListener(_onAuthChanged);
  }

  static const _pushBatch = 200;
  static const _pullPage = 500;
  static const _interval = Duration(seconds: 60);
  static const _debounce = Duration(seconds: 2);

  final AppDatabase _db;
  final ApiClient _api;
  final AuthProvider _auth;
  final ProductProvider _products;
  final SalesHistoryProvider _history;
  final CustomerProvider _customers;
  final SettingsProvider _settings;

  Timer? _timer;
  Timer? _soonTimer;
  Future<void>? _running;
  bool _wasSignedIn = false;

  DateTime? lastSyncedAt;
  int pendingCount = 0;

  /// Last problem reaching the server, e.g. offline; null after a good sync.
  String? lastError;

  bool get isSyncing => _running != null;

  /// Turns syncing on for the signed-in account. Does not wait for the network.
  Future<void> start() async {
    if (!_auth.isSignedIn) return;
    _wasSignedIn = true;
    _db.syncEnabled = true;
    _db.onLocalWrite = _scheduleSoon;
    lastSyncedAt = await _db.getLastSyncedAt();
    pendingCount = await _db.pendingCount();
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => unawaited(syncNow()));
    notifyListeners();
    unawaited(syncNow());
  }

  /// Stops syncing. Queued changes stay in the outbox.
  void stop() {
    _timer?.cancel();
    _soonTimer?.cancel();
    _timer = null;
    _soonTimer = null;
    _db.syncEnabled = false;
    _db.onLocalWrite = null;
    notifyListeners();
  }

  /// Runs a sync, or joins the one already running.
  Future<void> syncNow() {
    if (!_auth.isSignedIn || !_db.syncEnabled) return Future.value();
    return _running ??= _run().whenComplete(() {
      _running = null;
      notifyListeners();
    });
  }

  void _scheduleSoon() {
    _soonTimer?.cancel();
    _soonTimer = Timer(_debounce, () => unawaited(syncNow()));
    unawaited(_refreshPendingCount());
  }

  Future<void> _refreshPendingCount() async {
    pendingCount = await _db.pendingCount();
    notifyListeners();
  }

  Future<void> _run() async {
    notifyListeners();
    final notes = <String>[];
    try {
      final refused = await _push(notes);
      if (refused) await _db.setCursor(null);
      final page = await _pullAll();
      if (await _db.applyPull(page)) {
        await _db.setCursor(page.cursor);
        await _db.setSyncedShopId(page.shop.id);
        lastSyncedAt = DateTime.now();
        await _db.setLastSyncedAt(lastSyncedAt!);
        if (page.hasChanges) await _reload();
        _settings.applyServerSettings(page.shop);
        _auth.updateShop(page.shop);
      } else {
        // Something was queued while downloading; send it and try again.
        _scheduleSoon();
      }
      lastError = null;
      if (notes.isNotEmpty) {
        reportStorageIssue('Synced with the shop. ${notes.take(3).join(' ')}', 'sync notes');
      }
    } on ApiException catch (e) {
      if (e.isUnauthorized && !_api.hasSession) {
        lastError = 'Signed out';
      } else if (e.isNetwork) {
        lastError = e.message; // offline is normal; no toast
      } else {
        if (lastError != e.message) reportStorageIssue('Could not sync: ${e.message}', e);
        lastError = e.message;
      }
    } catch (e) {
      const message = 'Could not sync. Your changes are kept on this phone and will be sent later.';
      if (lastError != message) reportStorageIssue(message, e);
      lastError = message;
    } finally {
      pendingCount = await _db.pendingCount();
    }
  }

  /// Sends the outbox. Returns true if the server refused any change.
  Future<bool> _push(List<String> notes) async {
    var refused = false;
    final deviceId = await _db.deviceId();
    while (true) {
      final ops = await _db.pendingOps(_pushBatch);
      if (ops.isEmpty) return refused;
      final res = await _api.post('/sync/push', {
        'deviceId': deviceId,
        'ops': [for (final op in ops) op.toJson()],
      });
      final byId = {for (final op in ops) op.opId: op};
      final done = <String>[];
      for (final r in (res['results'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final op = byId[r['opId']];
        if (op == null) continue;
        if (r['status'] == 'rejected') {
          refused = true;
          notes.add('A change was not accepted by the shop and has been undone here: ${r['reason'] ?? 'refused'}.');
        }
        for (final w in (r['warnings'] as List<dynamic>?) ?? const []) {
          notes.add(w as String);
        }
        final mergedInto = r['mergedInto'] as String?;
        if (mergedInto != null) {
          final from = op.type == 'customer.create' ? op.payload['id'] : op.payload['customerId'];
          if (from is String) await _db.remapCustomerId(from, mergedInto);
        }
        done.add(op.opId);
      }
      await _db.removeOps(done);
      // Defensive: never loop on ops the server did not answer.
      if (done.length < ops.length) return refused;
    }
  }

  Future<PullPage> _pullAll() async {
    var cursor = await _db.getCursor();
    PullPage? merged;
    while (true) {
      final j = await _api.get('/sync/pull', query: {'limit': '$_pullPage', 'cursor': ?cursor});
      final page = PullPage.fromJson(j);
      merged = merged == null ? page : merged.merge(page);
      cursor = page.cursor;
      if (!page.hasMore) return merged;
    }
  }

  Future<void> _reload() async {
    final data = await _db.loadAll();
    _products.replaceAll(data.products);
    _history.replaceAll(data.sales);
    _customers.replaceAll(data.customers);
  }

  // ------------------------------------------------------ first sign-in

  /// Decides how to combine this phone's data with the shop it just signed
  /// in to. Needs the network.
  Future<FirstSyncPlan> planFirstSync() async {
    final shopId = _auth.shop?.id;
    if (shopId != null && await _db.getSyncedShopId() == shopId) return FirstSyncPlan.resume;
    final probe = await _api.get('/sync/pull', query: {'limit': '1'});
    final shopIsEmpty =
        (probe['products'] as List<dynamic>).isEmpty &&
        (probe['customers'] as List<dynamic>).isEmpty &&
        (probe['sales'] as List<dynamic>).isEmpty;
    // A new shop starts from what is on the phone, even just the starter
    // products. Only the owner may fill the shop from a phone.
    if (shopIsEmpty && _auth.isOwner) return FirstSyncPlan.upload;
    final data = await _db.loadAll();
    final phoneHasData =
        data.sales.isNotEmpty ||
        data.customers.isNotEmpty ||
        data.products.any((p) => !AppDatabase.starterProductIds.contains(p.id));
    return phoneHasData ? FirstSyncPlan.confirmReplace : FirstSyncPlan.download;
  }

  /// Carries out [plan] and runs the first sync.
  Future<void> begin(FirstSyncPlan plan) async {
    if (plan != FirstSyncPlan.resume) await _db.clearSyncState();
    if (plan == FirstSyncPlan.upload) await _uploadAll(await _db.loadAll(), _settings.settings);
    await _db.setSyncedShopId(_auth.shop?.id);
    await start();
    await syncNow();
  }

  /// Restore while signed in: the shop's data is replaced first, then this
  /// phone downloads it, so every device ends up with the backup.
  Future<void> restoreToShop(Backup backup) async {
    await _uploadAll(backup.data, backup.settings, repair: false);
    await _db.clearSyncState();
    await _db.setSyncedShopId(_auth.shop?.id);
    await syncNow();
  }

  Future<void> _uploadAll(ShopData data, AppSettings settings, {bool repair = true}) async {
    final body = _withUtcDates(jsonDecode(BackupService.encode(data, settings)));
    await _api.post(
      '/backup/restore',
      body,
      // Older on-phone data (e.g. unusual phone formats) is repaired, not refused.
      query: {'sanitize': repair ? 'true' : 'false'},
      timeout: const Duration(minutes: 2),
    );
  }

  /// Backup files store local time without an offset; the server needs UTC.
  static Object? _withUtcDates(Object? v, [String? key]) {
    if (v is Map<String, dynamic>) return {for (final e in v.entries) e.key: _withUtcDates(e.value, e.key)};
    if (v is List<dynamic>) return [for (final x in v) _withUtcDates(x)];
    if (v is String && (key == 'createdAt' || key == 'date' || key == 'exportedAt')) {
      final d = DateTime.tryParse(v);
      return d == null ? v : toServerDate(d);
    }
    return v;
  }

  /// Sign out: syncing stops and the phone keeps its data, working offline
  /// as before. Changes not yet sent are discarded (the UI warns first).
  Future<void> signOut() async {
    stop();
    _wasSignedIn = false;
    await _db.clearSyncState();
    await _auth.signOut();
    lastSyncedAt = null;
    pendingCount = 0;
    lastError = null;
    notifyListeners();
  }

  void _onAuthChanged() {
    if (_auth.isSignedIn || !_wasSignedIn) return;
    // The server ended the login (password changed, account disabled).
    _wasSignedIn = false;
    stop();
    if (_auth.sessionExpired) {
      reportStorageIssue(
        'You have been signed out of the shop. Your changes are kept on this phone; sign in again in Settings to send them.',
        'session expired',
      );
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    stop();
    super.dispose();
  }
}
