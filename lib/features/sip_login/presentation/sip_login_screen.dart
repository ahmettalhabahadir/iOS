import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/settings_service.dart';
import '../../../services/sip_service.dart';
import '../../home/presentation/home_screen.dart';
import '../../../models/sip_account.dart';

class SipLoginScreen extends StatefulWidget {
  const SipLoginScreen({super.key});

  @override
  State<SipLoginScreen> createState() => _SipLoginScreenState();
}

class _SipLoginScreenState extends State<SipLoginScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _extensionController;
  late final TextEditingController _passwordController;
  late final TextEditingController _domainController;
  late final TextEditingController _displayNameController;

  bool _obscurePassword = true;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    final account = context.read<SettingsService>().account;
    _extensionController = TextEditingController(text: account.extension);
    _passwordController = TextEditingController(text: account.password);
    _domainController = TextEditingController(text: account.domain);
    _displayNameController = TextEditingController(text: account.displayName);
  }

  @override
  void dispose() {
    _extensionController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final account = SipAccount(
      wssUrl: _domainController.text.trim(), // Map to domain directly
      extension: _extensionController.text.trim(),
      password: _passwordController.text,
      domain: _domainController.text.trim(),
      displayName: _displayNameController.text.trim(),
      allowSelfSignedCertificate: false,
    );

    final settingsService = context.read<SettingsService>();
    final sipService = context.read<SipService>();

    setState(() => _connecting = true);
    try {
      await settingsService.save(account);
      await sipService.register(account);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SIP Ayarları')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Santral hesabınıza bağlanın',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Devam etmek için SIP bilgilerinizi girin',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _domainController,
                  decoration: const InputDecoration(
                    labelText: 'SIP Sunucu Adresi (Domain / IP)',
                    hintText: '192.168.4.235',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _extensionController,
                  decoration: const InputDecoration(
                    labelText: 'Dahili No (Extension)',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.text,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Şifre',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Zorunlu alan' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Görünen Ad (opsiyonel)',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _connecting ? null : _submit,
                  icon: _connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(
                    _connecting ? 'Bağlanıyor...' : 'Kaydol (REGISTER)',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
