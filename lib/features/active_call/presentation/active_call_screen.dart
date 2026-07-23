import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../services/call_coordinator.dart';
import '../../../services/sip_service.dart';
import '../../../services/local_contacts_service.dart';
import 'widgets/call_control_button.dart';
import 'widgets/transfer_sheet.dart';
import 'widgets/add_to_conference_sheet.dart';

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late final SipService _sip;
  late final CallCoordinator _coordinator;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _sip = context.read<SipService>();
    _coordinator = context.read<CallCoordinator>();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    // Safe no-op if the call has already ended.
    _sip.hangupCall();
    _coordinator.notifyActiveCallScreenClosed();
    super.dispose();
  }

  bool _isRinging(CallStateEnum state) => switch (state) {
    CallStateEnum.CALL_INITIATION ||
    CallStateEnum.CONNECTING ||
    CallStateEnum.PROGRESS ||
    CallStateEnum.ACCEPTED => true,
    _ => false,
  };

  String _statusLabel(SipService sip) {
    // Once a call ends without ever connecting, SipService resets its call
    // state immediately - lastCallEnd is what survives that reset so a
    // final status (e.g. "Reddedildi") can still be shown for a moment.
    final endInfo = sip.lastCallEnd;
    if (endInfo != null && endInfo.message.isNotEmpty) return endInfo.message;
    // Once the call has actually connected, keep showing the running timer
    // no matter which transient CallStateEnum value fires next (sip_ua
    // emits things like STREAM/MUTED/UNMUTED mid-call that aren't call
    // lifecycle states) - only an explicit HOLD should override it.
    if (sip.callState == CallStateEnum.HOLD) return 'Beklemede';
    final connectedAt = sip.connectedAt;
    if (connectedAt != null) {
      return formatDuration(DateTime.now().difference(connectedAt));
    }
    switch (sip.callState) {
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.CONNECTING:
      case CallStateEnum.ACCEPTED:
        return 'Bağlanıyor...';
      case CallStateEnum.PROGRESS:
        return 'Çalıyor...';
      default:
        return '';
    }
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return p.substring(0, p.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  Widget _buildPlatformView(String viewType) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(viewType: viewType);
    }
    return AndroidView(viewType: viewType);
  }

  @override
  Widget build(BuildContext context) {
    final sip = context.watch<SipService>();
    final localContacts = context.watch<LocalContactsService>();
    final call = sip.currentCall;
    final endInfo = sip.lastCallEnd;
    final rawName = call?.remote_display_name ?? endInfo?.displayName;
    final number = call?.remote_identity ?? endInfo?.number ?? '';

    // Extract just the numeric/sip part from sip:XXXX@domain
    final cleanNumber = number.replaceFirst(RegExp(r'^sip:'), '').split('@').first;

    // Look up in local contacts book first
    final localName = localContacts.getName(cleanNumber);
    final displayName = localName ?? (rawName?.trim().isNotEmpty == true ? rawName : null);

    // Format: if local name found → "Ahmet (6614)", else just name or number
    final String title;
    final bool showNumberLine;
    if (localName != null && localName.isNotEmpty) {
      title = '$localName ($cleanNumber)';
      showNumberLine = false;
    } else if (displayName != null && displayName.isNotEmpty && displayName != cleanNumber) {
      title = displayName;
      showNumberLine = cleanNumber.isNotEmpty;
    } else {
      title = cleanNumber.isNotEmpty ? cleanNumber : 'Bilinmeyen';
      showNumberLine = false;
    }
    final ringing = _isRinging(sip.callState);
    final onHold = sip.callState == CallStateEnum.HOLD;
    
    final companion = sip.transferCompanionCall;
    final SipCall? call1 = sip.calls.isNotEmpty
        ? sip.calls.firstWhere((c) => c.id != companion?.id, orElse: () => sip.calls.first)
        : null;

    final scheme = Theme.of(context).colorScheme;
    final isVideo = sip.isVideoCall;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote Video or Audio Gradient Background
          if (isVideo)
            Positioned.fill(
              child: ClipRect(
                child: Transform.scale(
                  scale: 1.45,
                  alignment: const Alignment(0, -0.4),
                  child: _buildPlatformView('com.softphone.call/remote_video_view'),
                ),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.primary.withValues(alpha: 0.85),
                      scheme.primary.withValues(alpha: 0.55),
                      scheme.surface,
                    ],
                    stops: const [0.0, 0.32, 0.62],
                  ),
                ),
              ),
            ),

          // Local Camera Preview (Picture-in-Picture)
          if (isVideo && sip.isCameraOn)
            Positioned(
              top: 48,
              right: 16,
              child: Container(
                width: 110,
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 12),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildPlatformView('com.softphone.call/local_preview_view'),
              ),
            ),

          // Call UI Overlay
          SafeArea(
            child: Column(
              children: [
                if (sip.isConference) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Konferans Görüşmesi',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isVideo ? Colors.white : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      itemCount: sip.calls.length,
                      itemBuilder: (context, index) {
                        final c = sip.calls[index];
                        final cRawName = c.remote_display_name ?? '';
                        final cNumber = c.remote_identity ?? '';
                        final cClean = cNumber.replaceFirst(RegExp(r'^sip:'), '').split('@').first;
                        final cLocalName = localContacts.getName(cClean);
                        final String cTitle;
                        if (cLocalName != null && cLocalName.isNotEmpty) {
                          cTitle = '$cLocalName ($cClean)';
                        } else {
                          cTitle = cRawName.isNotEmpty ? cRawName : cClean;
                        }
                        final isCallHeld = c.state == CallStateEnum.HOLD;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: scheme.primaryContainer,
                              child: Text(
                                _initials(cTitle),
                                style: TextStyle(color: scheme.onPrimaryContainer),
                              ),
                            ),
                            title: Text(
                              cTitle,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              isCallHeld ? 'Beklemede' : (c.state == CallStateEnum.CONFIRMED ? 'Bağlı' : 'Çalıyor...'),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(isCallHeld ? Icons.play_arrow : Icons.pause),
                                  onPressed: () {
                                    if (isCallHeld) {
                                      sip.unholdCall(c);
                                    } else {
                                      sip.holdCall(c);
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.call_end, color: Colors.red),
                                  onPressed: () => sip.removeFromConference(c),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 28),
                  if (!isVideo)
                    _PulsingAvatar(
                      initials: _initials(title),
                      animate: ringing,
                      controller: _pulseController,
                    ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isVideo ? Colors.white : scheme.onSurface,
                      shadows: isVideo ? const [Shadow(color: Colors.black, blurRadius: 8)] : null,
                    ),
                  ),
                  if (showNumberLine) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: (isVideo ? Colors.black54 : scheme.surfaceContainerHighest).withValues(
                          alpha: 0.7,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        number,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isVideo ? Colors.white : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _StatusBadge(
                    label: _statusLabel(sip),
                    ringing: ringing,
                    onHold: onHold,
                    light: isVideo,
                  ),
                  if (companion != null && call1 != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.swap_calls, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${call1.remote_display_name ?? call1.remote_identity ?? ""} ➜ ${companion.remote_display_name ?? companion.remote_identity ?? ""}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                ],
                if (endInfo == null)
                  _ControlPanel(sip: sip)
                else
                  const SizedBox(width: double.infinity, height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingAvatar extends StatelessWidget {
  const _PulsingAvatar({
    required this.initials,
    required this.animate,
    required this.controller,
  });

  final String initials;
  final bool animate;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (animate)
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final t = controller.value;
                return Opacity(
                  opacity: (1 - t) * 0.35,
                  child: Transform.scale(
                    scale: 0.82 + t * 0.5,
                    child: Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                );
              },
            ),
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.95),
                  Colors.white.withValues(alpha: 0.75),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}



class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.ringing,
    required this.onHold,
    this.light = false,
  });

  final String label;
  final bool ringing;
  final bool onHold;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final baseColor = light
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!ringing && !onHold)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: CallColors.incoming,
                shape: BoxShape.circle,
              ),
            ),
          ),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: baseColor.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.sip,
  });

  final SipService sip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final companion = sip.transferCompanionCall;

    final isVideo = sip.isVideoCall;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, isVideo ? 16 : 28, 24, isVideo ? 20 : 32),
      decoration: BoxDecoration(
        color: isVideo ? Colors.black.withValues(alpha: 0.6) : scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: EdgeInsets.only(bottom: isVideo ? 16 : 24),
            decoration: BoxDecoration(
              color: isVideo ? Colors.white38 : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (sip.callState == CallStateEnum.INCOMING) ...[
            // Incoming Call Control Mode
            Text(
              'Gelen Arama...',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isVideo ? Colors.white : scheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CallControlButton(
                  icon: Icons.call,
                  label: 'Cevapla',
                  color: CallColors.incoming,
                  onTap: sip.answerCall,
                ),
                CallControlButton(
                  icon: Icons.call_end,
                  label: 'Reddet',
                  color: CallColors.hangup,
                  onTap: sip.hangupCall,
                ),
              ],
            ),
          ] else if (isVideo) ...[
            // Dedicated Video Call Control Mode (No transfer, no conference)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CallControlButton(
                  icon: sip.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                  label: 'Hoparlör',
                  active: sip.isSpeakerOn,
                  light: true,
                  onTap: () => sip.setSpeaker(!sip.isSpeakerOn),
                ),
                CallControlButton(
                  icon: sip.isMuted ? Icons.mic_off : Icons.mic,
                  label: 'Sessiz',
                  active: sip.isMuted,
                  light: true,
                  onTap: sip.toggleMute,
                ),
                CallControlButton(
                  icon: sip.isCameraOn ? Icons.videocam : Icons.videocam_off,
                  label: 'Kamera',
                  active: sip.isCameraOn,
                  light: true,
                  onTap: sip.toggleCamera,
                ),
                CallControlButton(
                  icon: Icons.flip_camera_ios,
                  label: 'Çevir',
                  light: true,
                  onTap: sip.switchCamera,
                ),
                CallControlButton(
                  icon: Icons.call_end,
                  label: 'Kapat',
                  color: CallColors.hangup,
                  onTap: sip.hangupCall,
                ),
              ],
            ),
          ] else if (sip.isConference) ...[
            // Conference control mode
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CallControlButton(
                  icon: sip.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                  label: 'Hoparlör',
                  active: sip.isSpeakerOn,
                  onTap: () => sip.setSpeaker(!sip.isSpeakerOn),
                ),
                CallControlButton(
                  icon: sip.isMuted ? Icons.mic_off : Icons.mic,
                  label: 'Sessiz',
                  active: sip.isMuted,
                  onTap: sip.toggleMute,
                ),
                CallControlButton(
                  icon: sip.isOnHold ? Icons.play_arrow : Icons.pause,
                  label: sip.isOnHold ? 'Devam' : 'Beklet',
                  active: sip.isOnHold,
                  onTap: sip.toggleHold,
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CallControlButton(
                  icon: Icons.add_call,
                  label: 'Ekle',
                  onTap: () => AddToConferenceSheet.show(context),
                ),
                CallControlButton(
                  icon: Icons.call_end,
                  label: 'Kapat',
                  color: CallColors.hangup,
                  onTap: sip.hangupCall,
                ),
              ],
            ),
          ] else if (companion != null) ...[
            // Attended Transfer control mode
            Text(
              'Kontrollü Aktarma',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CallControlButton(
                  icon: Icons.check_circle,
                  label: 'Aktar',
                  color: CallColors.incoming,
                  onTap: sip.completeAttendedTransfer,
                ),
                CallControlButton(
                  icon: Icons.cancel,
                  label: 'Vazgeç',
                  color: CallColors.hangup,
                  onTap: sip.cancelAttendedTransfer,
                ),
              ],
            ),
          ] else ...[
            // Standard audio control mode
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CallControlButton(
                  icon: sip.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                  label: 'Hoparlör',
                  active: sip.isSpeakerOn,
                  onTap: () => sip.setSpeaker(!sip.isSpeakerOn),
                ),
                CallControlButton(
                  icon: sip.isMuted ? Icons.mic_off : Icons.mic,
                  label: 'Sessiz',
                  active: sip.isMuted,
                  onTap: sip.toggleMute,
                ),
                CallControlButton(
                  icon: sip.isOnHold ? Icons.play_arrow : Icons.pause,
                  label: sip.isOnHold ? 'Devam' : 'Beklet',
                  active: sip.isOnHold,
                  onTap: sip.toggleHold,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CallControlButton(
                  icon: Icons.people,
                  label: 'Konferans',
                  onTap: () => AddToConferenceSheet.show(context),
                ),
                CallControlButton(
                  icon: Icons.call_split,
                  label: 'Aktar',
                  onTap: () => TransferSheet.show(context),
                ),
                CallControlButton(
                  icon: Icons.call_end,
                  label: 'Kapat',
                  color: CallColors.hangup,
                  onTap: sip.hangupCall,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
