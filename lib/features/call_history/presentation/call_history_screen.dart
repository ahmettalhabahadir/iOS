import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/permissions.dart';
import '../../../models/call_log_entry.dart';
import '../../../services/call_history_service.dart';
import '../../../services/sip_service.dart';
import 'widgets/call_log_tile.dart';

class CallHistoryScreen extends StatelessWidget {
  const CallHistoryScreen({super.key});

  Future<void> _redial(BuildContext context, String number) async {
    final granted = await ensureMicrophonePermission();
    if (!granted) return;
    if (!context.mounted) return;
    await context.read<SipService>().makeCall(number);
  }

  String _dateGroupLabel(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Dün';
    const months = [
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];
    return '${timestamp.day} ${months[timestamp.month - 1]} ${timestamp.year}';
  }

  @override
  Widget build(BuildContext context) {
    context.read<CallHistoryService>().importPendingFromNative();
    final logs = context.watch<CallHistoryService>().logs;
    final scheme = Theme.of(context).colorScheme;

    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_rounded,
                size: 40,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Henüz arama geçmişi yok',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Yaptığınız ve aldığınız aramalar burada görünecek',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          ],
        ),
      );
    }

    final groups = <String, List<CallLogEntry>>{};
    for (final entry in logs) {
      groups.putIfAbsent(_dateGroupLabel(entry.timestamp), () => []).add(entry);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final group in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Text(
              group.key,
              style: TextStyle(
                fontSize: 15,
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                for (var i = 0; i < group.value.length; i++) ...[
                  CallLogTile(
                    entry: group.value[i],
                    onCall: () => _redial(context, group.value[i].number),
                  ),
                  if (i != group.value.length - 1)
                    Divider(
                      height: 1,
                      indent: 72,
                      color: scheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
