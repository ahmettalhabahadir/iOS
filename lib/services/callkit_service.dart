import 'dart:async';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Wraps flutter_callkit_incoming so the rest of the app never touches the
/// plugin directly. Only handles the incoming-call alert (lock screen /
/// full-screen native UI) - once a call is answered, the custom Flutter
/// ActiveCallScreen takes over.
class CallKitService {
  StreamSubscription<CallEvent?>? _sub;

  void Function(String callId)? onAccept;
  void Function(String callId)? onDecline;
  void Function(String callId)? onEnded;
  void Function(String callId)? onTimeout;

  void init() {
    _sub = FlutterCallkitIncoming.onEvent.listen((event) {
      switch (event) {
        case CallEventActionCallAccept():
          onAccept?.call(event.callKitParams.id);
        case CallEventActionCallDecline():
          onDecline?.call(event.callKitParams.id);
        case CallEventActionCallEnded():
          onEnded?.call(event.callKitParams.id);
        case CallEventActionCallTimeout():
          onTimeout?.call(event.id);
        default:
          break;
      }
    });
  }

  Future<void> showIncomingCall({
    required String uuid,
    required String number,
    String? displayName,
    bool isVideo = false,
  }) {
    final params = CallKitParams(
      id: uuid,
      nameCaller: (displayName != null && displayName.trim().isNotEmpty)
          ? displayName
          : number,
      appName: 'Softphone',
      handle: number,
      // 0 = audio, 1 = video - controls the icon/label on the native
      // incoming-call UI.
      type: isVideo ? 1 : 0,
      duration: 45000,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Cevapsız arama',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0A84FF',
        actionColor: '#4CAF50',
        incomingCallNotificationChannelName: 'Gelen Aramalar',
        isShowFullLockedScreen: true,
        textAccept: 'Kabul Et',
        textDecline: 'Reddet',
      ),
      ios: IOSParams(handleType: 'generic', supportsVideo: isVideo),
    );
    return FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> reportCallConnected(String uuid) {
    return FlutterCallkitIncoming.setCallConnected(uuid);
  }

  Future<void> endCall(String uuid) {
    return FlutterCallkitIncoming.endCall(uuid);
  }

  Future<void> endAllCalls() {
    return FlutterCallkitIncoming.endAllCalls();
  }

  void dispose() {
    _sub?.cancel();
  }
}
