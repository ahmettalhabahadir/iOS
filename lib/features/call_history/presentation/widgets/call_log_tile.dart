import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/duration_formatter.dart';
import '../../../../models/call_log_entry.dart';

class CallLogTile extends StatelessWidget {
  const CallLogTile({super.key, required this.entry, required this.onCall});

  final CallLogEntry entry;
  final VoidCallback onCall;

  IconData get _icon => switch (entry.direction) {
    CallDirection.incoming => Icons.call_received_rounded,
    CallDirection.outgoing => Icons.call_made_rounded,
    CallDirection.missed => Icons.call_missed_rounded,
    CallDirection.rejected => Icons.phone_disabled_rounded,
  };

  Color get _color => switch (entry.direction) {
    CallDirection.incoming => CallColors.incoming,
    CallDirection.outgoing => CallColors.outgoing,
    CallDirection.missed => CallColors.missed,
    CallDirection.rejected => CallColors.missed,
  };

  String get _directionLabel => switch (entry.direction) {
    CallDirection.incoming => 'Gelen',
    CallDirection.outgoing => 'Giden',
    CallDirection.missed => 'Cevapsız',
    CallDirection.rejected => 'Reddedildi',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final timeLabel = DateFormat('HH:mm', 'tr_TR').format(entry.timestamp);
    final subtitle = entry.durationSeconds > 0
        ? '$_directionLabel · $timeLabel · ${formatDuration(Duration(seconds: entry.durationSeconds))}'
        : '$_directionLabel · $timeLabel';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(_icon, color: _color, size: 22),
      ),
      title: Text(
        entry.title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      trailing: Material(
        color: scheme.primary.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onCall,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              Icons.call_rounded,
              color: CallColors.outgoing,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
