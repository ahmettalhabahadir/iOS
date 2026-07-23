import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:provider/provider.dart';

import '../../../../core/utils/permissions.dart';
import '../../../../services/local_contacts_service.dart';

class ContactSelectDialog extends StatefulWidget {
  const ContactSelectDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const ContactSelectDialog(),
    );
  }

  @override
  State<ContactSelectDialog> createState() => _ContactSelectDialogState();
}

class _ContactSelectDialogState extends State<ContactSelectDialog> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  
  // Phone contacts
  List<fc.Contact> _phoneContacts = [];
  List<fc.Contact> _filteredPhoneContacts = [];
  bool _isLoadingPhone = false;
  bool _phonePermissionDenied = false;
  
  // Local contacts
  Map<String, String> _filteredLocalContacts = {};
  
  // Search controllers
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPhoneContacts();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPhoneContacts() async {
    setState(() {
      _isLoadingPhone = true;
      _phonePermissionDenied = false;
    });

    try {
      final hasPermission = await ensureContactsPermission();
      if (!hasPermission) {
        setState(() {
          _phonePermissionDenied = true;
          _isLoadingPhone = false;
        });
        return;
      }

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

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    
    // Filter phone contacts
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

    // Filter local contacts
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

  String _initials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allLocal = context.watch<LocalContactsService>().contacts;
    
    if (_searchController.text.isEmpty && _filteredLocalContacts.length != allLocal.length) {
      _filteredLocalContacts = Map.from(allLocal);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 500),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Rehberden Seç',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'İsim veya numara ara...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: scheme.surfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // TabBar
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Özel Rehber'),
                Tab(text: 'Cihaz Rehberi'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Local Contacts
                  _buildLocalTab(scheme),
                  // Phone Contacts
                  _buildPhoneTab(scheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalTab(ColorScheme scheme) {
    final displayed = _searchController.text.isEmpty 
        ? context.read<LocalContactsService>().contacts 
        : _filteredLocalContacts;

    if (displayed.isEmpty) {
      return const Center(child: Text('Kişi bulunamadı.'));
    }

    return ListView.builder(
      itemCount: displayed.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final number = displayed.keys.elementAt(index);
        final name = displayed[number]!;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            child: Text(
              _initials(name),
              style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(number),
          onTap: () => Navigator.pop(context, number),
        );
      },
    );
  }

  Widget _buildPhoneTab(ColorScheme scheme) {
    if (_isLoadingPhone) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_phonePermissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Rehber izni verilmedi.'),
              const SizedBox(height: 8),
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
      return const Center(child: Text('Kişi bulunamadı.'));
    }

    return ListView.builder(
      itemCount: _filteredPhoneContacts.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final contact = _filteredPhoneContacts[index];
        final phone = contact.phones.first.number;
        final name = contact.displayName;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            child: Text(
              _initials(name),
              style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(phone),
          onTap: () => Navigator.pop(context, phone),
        );
      },
    );
  }
}
