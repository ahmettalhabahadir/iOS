import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sip_account.dart';

class SettingsService extends ChangeNotifier {
  static const _prefsKey = 'sip_account';

  SipAccount _account = SipAccount.empty;
  SipAccount get account => _account;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      _account = SipAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      notifyListeners();
    }
  }

  Future<void> save(SipAccount account) async {
    _account = account;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(account.toJson()));
  }
}
