import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/permissions.dart';
import '../../../services/sip_service.dart';

class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  final _controller = TextEditingController();

  static const _keys = [
    ['1', ''],
    ['2', 'ABC'],
    ['3', 'DEF'],
    ['4', 'GHI'],
    ['5', 'JKL'],
    ['6', 'MNO'],
    ['7', 'PQRS'],
    ['8', 'TUV'],
    ['9', 'WXYZ'],
    ['*', ''],
    ['0', '+'],
    ['#', ''],
  ];

  @override
  void initState() {
    super.initState();
    // Rebuilds the backspace-button fade even when text changes
    // programmatically (keypad taps), not just via direct typing.
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  void _append(String digit) {
    HapticFeedback.selectionClick();
    _controller.text += digit;
  }

  void _backspace() {
    if (_controller.text.isEmpty) return;
    HapticFeedback.selectionClick();
    _controller.text = _controller.text.substring(
      0,
      _controller.text.length - 1,
    );
  }

  Future<void> _call() async {
    final number = _controller.text.trim();
    if (number.isEmpty) return;
    final granted = await ensureMicrophonePermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Arama yapmak için mikrofon izni gerekli'),
        ),
      );
      return;
    }
    if (!mounted) return;
    await context.read<SipService>().makeCall(number, video: false);
  }

  Future<void> _makeVideoCall() async {
    final number = _controller.text.trim();
    if (number.isEmpty) return;
    final micGranted = await ensureMicrophonePermission();
    final camGranted = await ensureCameraPermission();
    if (!micGranted || !camGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Görüntülü arama için mikrofon ve kamera izni gerekli'),
        ),
      );
      return;
    }
    if (!mounted) return;
    await context.read<SipService>().makeCall(number, video: true);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textAlign: TextAlign.center,
                    readOnly: true,
                    showCursor: false,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Dahili no girin',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _controller.text.isEmpty ? 0 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: IconButton(
                    onPressed: _backspace,
                    icon: Icon(
                      Icons.backspace_outlined,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1,
              children: [
                for (final key in _keys)
                  _DialerKey(digit: key[0], letters: key[1], onTap: _append),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Audio Call Button
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: CallColors.incoming.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: FloatingActionButton(
                    heroTag: 'call_audio',
                    backgroundColor: CallColors.incoming,
                    elevation: 0,
                    onPressed: () => _call(),
                    child: const Icon(
                      Icons.call,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                // Video Call Button
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: FloatingActionButton(
                    heroTag: 'call_video',
                    backgroundColor: scheme.primary,
                    elevation: 0,
                    onPressed: () => _makeVideoCall(),
                    child: const Icon(
                      Icons.videocam,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DialerKey extends StatelessWidget {
  const _DialerKey({
    required this.digit,
    required this.letters,
    required this.onTap,
  });

  final String digit;
  final String letters;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => onTap(digit),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                digit,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              if (letters.isNotEmpty)
                Text(
                  letters,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
