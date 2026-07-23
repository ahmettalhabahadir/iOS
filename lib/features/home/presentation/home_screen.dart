import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/settings_service.dart';
import '../../../services/sip_service.dart';
import '../../call_history/presentation/call_history_screen.dart';
import '../../dialer/presentation/dialer_screen.dart';
import '../../sip_login/presentation/sip_login_screen.dart';
import '../../contacts/presentation/contacts_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _pages = [DialerScreen(), CallHistoryScreen(), ContactsScreen()];
  static const _titles = ['Çevir', 'Arama Geçmişi', 'Rehber'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_titles[_index]),
            const SizedBox(height: 3),
            const _RegistrationStatus(),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: scheme.surfaceContainerHigh,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'SIP Ayarları',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SipLoginScreen()),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dialpad_outlined),
            selectedIcon: Icon(Icons.dialpad),
            label: 'Çevir',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Geçmiş',
          ),
          NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            selectedIcon: Icon(Icons.contacts),
            label: 'Rehber',
          ),
        ],
      ),
    );
  }
}

class _RegistrationStatus extends StatelessWidget {
  const _RegistrationStatus();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SipService>().connectionState;
    final extension = context.watch<SettingsService>().account.extension;
    final (label, color) = switch (state) {
      SipConnectionState.connected => ('Kayıtlı', CallColors.incoming),
      SipConnectionState.connecting => ('Bağlanıyor...', Colors.orange),
      SipConnectionState.registrationFailed => (
        'Kayıt Başarısız',
        CallColors.missed,
      ),
      SipConnectionState.disconnected => ('Bağlı Değil', Colors.grey),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          extension.isEmpty ? label : '$label · Dahili $extension',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
