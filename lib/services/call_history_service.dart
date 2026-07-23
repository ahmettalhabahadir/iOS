import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/call_log_entry.dart';

class CallHistoryService extends ChangeNotifier {
  static const _boxName = 'call_logs';
  late Box<CallLogEntry> _box;

  Future<void> init() async {
    Hive.registerAdapter(CallLogEntryAdapter());
    _box = await Hive.openBox<CallLogEntry>(_boxName);
    await importPendingFromNative();
  }

  /// Reads any call log entries saved by SipForegroundService while Flutter
  /// was not running, adds them to Hive, then clears the native queue.
  Future<void> importPendingFromNative() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pending_call_logs') ?? '[]';
      final list = jsonDecode(raw) as List<dynamic>;
      if (list.isEmpty) return;

      for (final item in list) {
        final dir = switch (item['direction'] as String? ?? 'missed') {
          'incoming' => CallDirection.incoming,
          'outgoing' => CallDirection.outgoing,
          'rejected'  => CallDirection.rejected,
          _           => CallDirection.missed,
        };
        final entry = CallLogEntry(
          id: item['id'] as String,
          number: (item['number'] as String?)?.isNotEmpty == true
              ? item['number'] as String
              : 'Bilinmeyen',
          displayName: item['displayName'] as String?,
          direction: dir,
          timestamp: DateTime.fromMillisecondsSinceEpoch(item['timestamp'] as int),
          durationSeconds: (item['durationSeconds'] as int?) ?? 0,
        );
        // Avoid duplicates (same id already in Hive)
        if (!_box.containsKey(entry.id)) {
          await _box.put(entry.id, entry);
        }
      }

      // Clear the native queue
      await prefs.remove('pending_call_logs');
      notifyListeners();
    } catch (e) {
      debugPrint('importPendingFromNative error: $e');
    }
  }

  List<CallLogEntry> get logs =>
      _box.values.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  Future<void> add(CallLogEntry entry) async {
    await _box.put(entry.id, entry);
    notifyListeners();
  }

  Future<void> clear() async {
    await _box.clear();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
    notifyListeners();
  }
}
