import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/sip_service.dart';

class DtmfKeypadSheet extends StatefulWidget {
  const DtmfKeypadSheet({super.key});

  @override
  State<DtmfKeypadSheet> createState() => _DtmfKeypadSheetState();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const DtmfKeypadSheet(),
    );
  }
}

class _DtmfKeypadSheetState extends State<DtmfKeypadSheet> {
  final _sent = StringBuffer();

  static const _keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '*',
    '0',
    '#',
  ];

  void _press(String tone) {
    context.read<SipService>().sendDTMF(tone);
    setState(() => _sent.write(tone));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _sent.isEmpty ? 'Tuş Takımı' : _sent.toString(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final key in _keys)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _press(key),
                    child: Center(
                      child: Text(
                        key,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
