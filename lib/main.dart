import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/utils/permissions.dart';
import 'services/call_coordinator.dart';
import 'services/call_history_service.dart';
import 'services/callkit_service.dart';
import 'services/settings_service.dart';
import 'services/sip_service.dart';
import 'services/desktop_service.dart';
import 'services/local_contacts_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopService.instance.init();
  await Hive.initFlutter();
  await initializeDateFormatting('tr_TR', null);
  unawaited(ensureNotificationPermission());
  unawaited(ensureMicrophonePermission());

  final settingsService = SettingsService();
  await settingsService.init();

  final callHistoryService = CallHistoryService();
  await callHistoryService.init();

  final localContactsService = LocalContactsService();
  await localContactsService.init();

  final sipService = SipService();
  final callKitService = CallKitService();
  final navigatorKey = GlobalKey<NavigatorState>();

  final callCoordinator = CallCoordinator(
    sipService: sipService,
    callKitService: callKitService,
    callHistoryService: callHistoryService,
    localContactsService: localContactsService,
    navigatorKey: navigatorKey,
  )..init();

  if (settingsService.account.isComplete) {
    unawaited(sipService.register(settingsService.account));
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsService),
        ChangeNotifierProvider.value(value: callHistoryService),
        ChangeNotifierProvider.value(value: localContactsService),
        ChangeNotifierProvider.value(value: sipService),
        Provider.value(value: callKitService),
        Provider.value(value: callCoordinator),
      ],
      child: SoftphoneApp(navigatorKey: navigatorKey),
    ),
  );
}
