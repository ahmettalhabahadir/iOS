import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/active_call/presentation/active_call_screen.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/sip_login/presentation/sip_login_screen.dart';
import 'services/call_coordinator.dart';
import 'services/settings_service.dart';

class SoftphoneApp extends StatelessWidget {
  const SoftphoneApp({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Softphone',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      themeMode: ThemeMode.light,
      home: const _StartupGate(),
      onGenerateRoute: (settings) {
        if (settings.name == activeCallRoute) {
          return MaterialPageRoute(builder: (_) => const ActiveCallScreen());
        }
        return null;
      },
    );
  }
}

/// Skips the login form on subsequent launches once a SIP account has
/// already been saved; [main] kicks off the actual REGISTER in that case.
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    final account = context.watch<SettingsService>().account;
    return account.isComplete ? const HomeScreen() : const SipLoginScreen();
  }
}
