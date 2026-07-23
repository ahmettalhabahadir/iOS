import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LocalContactsService extends ChangeNotifier {
  late final Box<String> _box;
  bool _initialized = false;
  bool get initialized => _initialized;

  Future<void> init() async {
    _box = await Hive.openBox<String>('local_contacts');
    _initialized = true;
    notifyListeners();
  }

  Map<String, String> get contacts {
    if (!_initialized) return {};
    final map = _box.toMap().cast<String, String>();
    final sortedKeys = map.keys.toList()..sort((a, b) => map[a]!.compareTo(map[b]!));
    return {for (final k in sortedKeys) k: map[k]!};
  }

  String? getName(String number) {
    if (!_initialized) return null;
    return _box.get(number);
  }

  Future<void> addContact(String number, String name) async {
    await _box.put(number, name);
    notifyListeners();
  }

  Future<void> deleteContact(String number) async {
    await _box.delete(number);
    notifyListeners();
  }
}
