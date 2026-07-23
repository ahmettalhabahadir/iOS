import 'package:flutter/material.dart';

class CallControlButton extends StatelessWidget {
  const CallControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.light = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool light;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = color ??
        (active
            ? (light ? Colors.white : scheme.primary)
            : (light ? Colors.white24 : scheme.surfaceContainerHigh));
    final fg = color != null
        ? Colors.white
        : (active
            ? (light ? Colors.black87 : scheme.onPrimary)
            : (light ? Colors.white : scheme.onSurfaceVariant));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: bg.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: bg,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 68,
                height: 68,
                child: Icon(icon, color: fg, size: 28),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active
                ? (light ? Colors.white : scheme.primary)
                : (light ? Colors.white70 : scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
