import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/call_log_entry.dart';
import 'call_history_service.dart';
import 'callkit_service.dart';
import 'local_contacts_service.dart';
import 'sip_service.dart';

const activeCallRoute = '/active-call';

/// Glues [SipService] (SIP/WebRTC signaling), [CallKitService] (native
/// incoming-call UI) and [CallHistoryService] (persistence) together, and
/// drives in-app navigation to the active-call screen. Kept as a single
/// coordinator instead of cross-wiring the services directly so each one
/// stays independent and easy to reason about on its own.
class CallCoordinator {
  CallCoordinator({
    required this.sipService,
    required this.callKitService,
    required this.callHistoryService,
    required this.localContactsService,
    required this.navigatorKey,
  });

  final SipService sipService;
  final CallKitService callKitService;
  final CallHistoryService callHistoryService;
  final LocalContactsService localContactsService;
  final GlobalKey<NavigatorState> navigatorKey;

  final _uuid = const Uuid();
  String? _pendingCallKitUuid;
  bool _activeCallScreenOpen = false;
  int _callGeneration = 0;

  void init() {
    callKitService.init();

    sipService.onIncomingCall = _handleIncomingCall;
    sipService.onCallStateUpdated = _handleCallStateUpdated;
    sipService.onCallEnded = _handleCallEnded;

    callKitService.onAccept = (_) => sipService.answerCall();
    callKitService.onDecline = (_) => sipService.hangupCall();
    callKitService.onEnded = (_) => sipService.hangupCall();
    callKitService.onTimeout = (_) {
      // sip_ua independently receives the CANCEL and reports call end;
      // nothing else to do here.
    };
  }

  void _handleIncomingCall(SipCall call) {
    final uuid = _uuid.v4();
    _pendingCallKitUuid = uuid;

    // Extract clean number (strip sip: prefix and @domain part)
    final rawNumber = call.remote_identity ?? call.id;
    final cleanNumber = rawNumber.replaceFirst(RegExp(r'^sip:'), '').split('@').first;

    // Look up in local contacts for a friendly display name
    final localName = localContactsService.getName(cleanNumber);
    final String callerName;
    if (localName != null && localName.isNotEmpty) {
      callerName = '$localName ($cleanNumber)';
    } else if (call.remote_display_name != null && call.remote_display_name!.trim().isNotEmpty) {
      callerName = call.remote_display_name!;
    } else {
      callerName = cleanNumber;
    }

    callKitService.showIncomingCall(
      uuid: uuid,
      number: cleanNumber,
      displayName: callerName,
      isVideo: call.remote_has_video,
    );
  }

  void _handleCallStateUpdated(SipCall call, CallStateEnum state) {
    switch (state) {
      case CallStateEnum.CONNECTING:
        if (call.direction == SipCallDirection.outgoing) {
          _openActiveCallScreen();
        }
        break;
      case CallStateEnum.CONFIRMED:
        if (call.direction == SipCallDirection.incoming &&
            _pendingCallKitUuid != null) {
          callKitService.reportCallConnected(_pendingCallKitUuid!);
        }
        _openActiveCallScreen();
        break;
      default:
        break;
    }
  }

  Future<void> _handleCallEnded({
    required String number,
    required String? displayName,
    required bool wasIncoming,
    required bool wasConnected,
    required bool wasRejected,
    required DateTime startedAt,
    required Duration duration,
  }) async {
    if (_pendingCallKitUuid != null) {
      await callKitService.endCall(_pendingCallKitUuid!);
      _pendingCallKitUuid = null;
    }

    final direction = wasRejected
        ? CallDirection.rejected
        : (!wasIncoming
              ? CallDirection.outgoing
              : (wasConnected ? CallDirection.incoming : CallDirection.missed));

    await callHistoryService.add(
      CallLogEntry(
        id: _uuid.v4(),
        number: number.isEmpty ? 'Bilinmeyen' : number,
        displayName: displayName,
        direction: direction,
        timestamp: startedAt,
        durationSeconds: duration.inSeconds,
      ),
    );

    if (wasRejected) {
      // Give the active-call screen a moment to show "Reddedildi" (driven by
      // SipService.lastCallEnd) before it disappears, instead of just
      // vanishing the instant the call fails.
      final generation = _callGeneration;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (_callGeneration == generation) _closeActiveCallScreen();
      });
    } else {
      _closeActiveCallScreen();
    }
  }

  void _openActiveCallScreen() {
    if (_activeCallScreenOpen) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _activeCallScreenOpen = true;
    _callGeneration++;
    nav.pushNamed(activeCallRoute);
  }

  void _closeActiveCallScreen() {
    if (!_activeCallScreenOpen) return;
    _activeCallScreenOpen = false;
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    }
  }

  /// Called by ActiveCallScreen when it is popped by any means other than
  /// [_closeActiveCallScreen] (e.g. system back), so the open/closed flag
  /// never drifts out of sync.
  void notifyActiveCallScreenClosed() {
    _activeCallScreenOpen = false;
  }
}
