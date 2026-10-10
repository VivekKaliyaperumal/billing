import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Problems found while loading or saving data, shown to the user as toasts.
/// Holds the latest message; listeners are notified for each new one.
final storageIssues = ValueNotifier<String?>(null);

/// Logs [error] and shows [message] to the user.
void reportStorageIssue(String message, Object error) {
  debugPrint('storage: $message: $error');
  // Reset first so a repeat of the same message still notifies listeners.
  storageIssues.value = null;
  storageIssues.value = message;
}

/// Reads a JSON list stored under [key]. Records that fail to parse are
/// skipped rather than crashing the app on launch; the original text is kept
/// under a backup key so nothing is destroyed. Returns null if nothing is stored.
List<T>? readJsonList<T>(SharedPreferences prefs, String key, T Function(Map<String, dynamic>) fromJson) {
  final raw = prefs.getString(key);
  if (raw == null) return null;
  List<dynamic> list;
  try {
    list = jsonDecode(raw) as List<dynamic>;
  } catch (e) {
    _backup(prefs, key, raw, e);
    return [];
  }
  final result = <T>[];
  Object? firstError;
  for (final item in list) {
    try {
      result.add(fromJson(item as Map<String, dynamic>));
    } catch (e) {
      firstError ??= e;
    }
  }
  if (firstError != null) _backup(prefs, key, raw, firstError);
  return result;
}

/// Like [readJsonList] for a single JSON object.
T? readJsonObject<T>(SharedPreferences prefs, String key, T Function(Map<String, dynamic>) fromJson) {
  final raw = prefs.getString(key);
  if (raw == null) return null;
  try {
    return fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (e) {
    _backup(prefs, key, raw, e);
    return null;
  }
}

void _backup(SharedPreferences prefs, String key, String raw, Object error) {
  final backupKey = '${key}_corrupt_${DateTime.now().millisecondsSinceEpoch}';
  unawaited(_write(prefs, backupKey, raw));
  reportStorageIssue('Some saved data could not be read and was skipped. A backup was kept.', error);
}

/// Encodes and saves [value]. Encoding happens synchronously so a bad value
/// is caught here; a failed platform write is reported instead of being lost.
void writeJson(SharedPreferences prefs, String key, Object value) {
  final String encoded;
  try {
    encoded = jsonEncode(value);
  } catch (e) {
    reportStorageIssue('Could not save your changes.', e);
    return;
  }
  unawaited(_write(prefs, key, encoded));
}

/// Saves a plain string preference in the background, reporting failures.
void writeString(SharedPreferences prefs, String key, String value) => unawaited(_write(prefs, key, value));

Future<void> _write(SharedPreferences prefs, String key, String value) async {
  try {
    if (!await prefs.setString(key, value)) {
      reportStorageIssue('Could not save your changes.', 'setString returned false');
    }
  } catch (e) {
    reportStorageIssue('Could not save your changes.', e);
  }
}
