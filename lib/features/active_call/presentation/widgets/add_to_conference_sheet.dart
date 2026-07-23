import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../services/sip_service.dart';
import '../../../contacts/presentation/widgets/contact_select_dialog.dart';

class AddToConferenceSheet extends StatefulWidget {
  const AddToConferenceSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const AddToConferenceSheet(),
    );
  }

  @override
  State<AddToConferenceSheet> createState() => _AddToConferenceSheetState();
}

class _AddToConferenceSheetState extends State<AddToConferenceSheet> {
  final _controller = TextEditingController();

  final List<String> _keys = const [
    '1', '2', '3',
    '4', '5', '6',
    '7', '8', '9',
    '*', '0', '#',
  ];

  void _append(String char) {
    setState(() {
      _controller.text += char;
    });
  }

  void _backspace() {
    if (_controller.text.isNotEmpty) {
      setState(() {
        _controller.text = _controller.text.substring(0, _controller.text.length - 1);
      });
    }
  }

  Future<void> _selectFromContacts() async {
    final selectedNumber = await ContactSelectDialog.show(context);
    if (selectedNumber != null) {
      setState(() {
        _controller.text = selectedNumber.replaceAll(RegExp(r'[^\d+*#]'), '');
      });
    }
  }

  void _add() {
    final target = _controller.text.trim();
    if (target.isEmpty) return;
    final sip = context.read<SipService>();
    sip.addToConference(target);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Konferansa Katılımcı Ekle',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            // Number Display with Backspace
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    readOnly: true,
                    showCursor: false,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Dahili No Girin',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _selectFromContacts,
                  icon: const Icon(Icons.contact_phone_outlined),
                ),
                IconButton(
                  onPressed: _backspace,
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),
            // Keypad Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 16,
                childAspectRatio: 1.4,
              ),
              itemCount: _keys.length,
              itemBuilder: (context, index) {
                final key = _keys[index];
                return Material(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _append(key),
                    child: Center(
                      child: Text(
                        key,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_call),
              label: const Text('Konferansa Ekle'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
