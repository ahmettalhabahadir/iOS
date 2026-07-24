import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/permissions.dart';
import '../../../services/local_contacts_service.dart';
import '../../../services/sip_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  
  // Phone contacts state
  List<fc.Contact> _phoneContacts = [];
  List<fc.Contact> _filteredPhoneContacts = [];
  bool _isLoadingPhone = false;
  bool _phonePermissionDenied = false;
  
  // Search controllers
  final _phoneSearchController = TextEditingController();
  final _localSearchController = TextEditingController();
  
  // Local contacts state
  Map<String, String> _filteredLocalContacts = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPhoneContacts();
    
    _phoneSearchController.addListener(_filterPhoneContacts);
    _localSearchController.addListener(_filterLocalContacts);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _phoneSearchController.dispose();
    _localSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadPhoneContacts() async {
    setState(() {
      _isLoadingPhone = true;
      _phonePermissionDenied = false;
    });

    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
      setState(() {
        _isLoadingPhone = false;
      });
      return;
    }

    try {
      final hasPermission = await ensureContactsPermission();
      if (!hasPermission) {
        setState(() {
          _phonePermissionDenied = true;
          _isLoadingPhone = false;
        });
        return;
      }

      // Fetch contacts with phones
      final contacts = await fc.FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      setState(() {
        _phoneContacts = contacts.where((c) => c.phones.isNotEmpty).toList();
        _filteredPhoneContacts = List.from(_phoneContacts);
        _isLoadingPhone = false;
      });
    } catch (e) {
      debugPrint('[Contacts] Failed to load phone contacts: $e');
      setState(() {
        _isLoadingPhone = false;
      });
    }
  }

  void _filterPhoneContacts() {
    final query = _phoneSearchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredPhoneContacts = List.from(_phoneContacts);
      } else {
        _filteredPhoneContacts = _phoneContacts.where((c) {
          final fullName = c.displayName.toLowerCase();
          final hasMatchingPhone = c.phones.any((p) => p.number.contains(query));
          return fullName.contains(query) || hasMatchingPhone;
        }).toList();
      }
    });
  }

  void _filterLocalContacts() {
    final query = _localSearchController.text.toLowerCase().trim();
    final allLocal = context.read<LocalContactsService>().contacts;
    
    setState(() {
      if (query.isEmpty) {
        _filteredLocalContacts = Map.from(allLocal);
      } else {
        _filteredLocalContacts = {};
        allLocal.forEach((number, name) {
          if (name.toLowerCase().contains(query) || number.contains(query)) {
            _filteredLocalContacts[number] = name;
          }
        });
      }
    });
  }

  Future<void> _makeCall(String rawNumber, {bool video = false}) async {
    final cleanNumber = normalizePhoneNumber(rawNumber);
    if (cleanNumber.isEmpty) return;

    final micGranted = await ensureMicrophonePermission();
    if (video) {
      final camGranted = await ensureCameraPermission();
      if (!micGranted || !camGranted) return;
    } else if (!micGranted) {
      return;
    }

    if (!mounted) return;
    await context.read<SipService>().makeCall(cleanNumber, video: video);
  }

  String _initials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final numberController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Yeni Özel Kişi Ekle'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'İsim Soyisim',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: numberController,
                  decoration: const InputDecoration(
                    labelText: 'Dahili veya Telefon No',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.text,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  context.read<LocalContactsService>().addContact(
                    numberController.text.trim(),
                    nameController.text.trim(),
                  );
                  Navigator.pop(context);
                  // Refresh filtered list
                  _filterLocalContacts();
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmDialog(String number, String name) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kişiyi Sil'),
          content: Text('"$name" kişisini özel rehberinizden silmek istiyor musunuz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                context.read<LocalContactsService>().deleteContact(number);
                Navigator.pop(context);
                _filterLocalContacts();
              },
              child: const Text('Sil', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allLocal = context.watch<LocalContactsService>().contacts;
    
    // Sync local search when contacts list changes
    if (_localSearchController.text.isEmpty && _filteredLocalContacts.length != allLocal.length) {
      _filteredLocalContacts = Map.from(allLocal);
    }

    return Column(
      children: [
        Container(
          color: scheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.phone_android), text: 'Cihaz Rehberi'),
              Tab(icon: Icon(Icons.star_outline), text: 'Özel Rehber'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Device Contacts
              _buildPhoneContactsTab(scheme),
              
              // Tab 2: Custom Contacts
              _buildLocalContactsTab(scheme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneContactsTab(ColorScheme scheme) {
    if (_isLoadingPhone) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_phonePermissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.contacts_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Rehberi görüntülemek için izin vermelisiniz.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadPhoneContacts,
                child: const Text('İzin İste'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredPhoneContacts.isEmpty) {
      return Column(
        children: [
          _buildSearchField(_phoneSearchController, 'Cihaz rehberinde ara...'),
          const Expanded(
            child: Center(
              child: Text('Kişi bulunamadı.'),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildSearchField(_phoneSearchController, 'Cihaz rehberinde ara...'),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredPhoneContacts.length,
            itemBuilder: (context, index) {
              final contact = _filteredPhoneContacts[index];
              final phone = contact.phones.first.number;
              final name = contact.displayName;
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      _initials(name),
                      style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(phone),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.call, color: CallColors.incoming),
                        onPressed: () => _makeCall(phone, video: false),
                      ),
                      IconButton(
                        icon: Icon(Icons.videocam, color: scheme.primary),
                        onPressed: () => _makeCall(phone, video: true),
                      ),
                    ],
                  ),
                  onTap: () => _makeCall(phone, video: false),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLocalContactsTab(ColorScheme scheme) {
    final displayed = _localSearchController.text.isEmpty 
        ? context.read<LocalContactsService>().contacts 
        : _filteredLocalContacts;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _buildSearchField(_localSearchController, 'Özel rehberde ara...'),
          Expanded(
            child: displayed.isEmpty
                ? const Center(
                    child: Text('Özel kişi eklenmemiş.'),
                  )
                : ListView.builder(
                    itemCount: displayed.length,
                    itemBuilder: (context, index) {
                      final number = displayed.keys.elementAt(index);
                      final name = displayed[number]!;
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: scheme.outlineVariant),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            child: Text(
                              _initials(name),
                              style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(number),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: () => _showDeleteConfirmDialog(number, name),
                              ),
                              IconButton(
                                icon: Icon(Icons.call, color: CallColors.incoming),
                                onPressed: () => _makeCall(number, video: false),
                              ),
                              IconButton(
                                icon: Icon(Icons.videocam, color: scheme.primary),
                                onPressed: () => _makeCall(number, video: true),
                              ),
                            ],
                          ),
                          onTap: () => _makeCall(number, video: false),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(TextEditingController controller, String hint) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => controller.clear()),
                )
              : null,
          filled: true,
          fillColor: scheme.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
