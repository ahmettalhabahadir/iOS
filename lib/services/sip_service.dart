import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/sip_account.dart';

enum SipConnectionState {
  disconnected,
  connecting,
  connected,
  registrationFailed,
}

enum SipCallDirection {
  incoming,
  outgoing,
}

enum CallStateEnum {
  NONE,
  CONNECTING,
  INCOMING,
  CONFIRMED,
  HOLD,
  ENDED,
  
  // Kept for backward compatibility with active_call_screen
  CALL_INITIATION,
  ACCEPTED,
  PROGRESS,
}

class SipCall {
  const SipCall({
    required this.id,
    required this.remote_identity,
    required this.remote_display_name,
    this.remote_has_video = false,
    required this.direction,
    required this.state,
  });

  final String id;
  final String? remote_identity;
  final String? remote_display_name;
  final bool remote_has_video;
  final SipCallDirection direction;
  final CallStateEnum state;

  SipCall copyWith({
    String? id,
    String? remote_identity,
    String? remote_display_name,
    bool? remote_has_video,
    SipCallDirection? direction,
    CallStateEnum? state,
  }) {
    return SipCall(
      id: id ?? this.id,
      remote_identity: remote_identity ?? this.remote_identity,
      remote_display_name: remote_display_name ?? this.remote_display_name,
      remote_has_video: remote_has_video ?? this.remote_has_video,
      direction: direction ?? this.direction,
      state: state ?? this.state,
    );
  }
}

class CallEndInfo {
  const CallEndInfo({
    required this.message,
    required this.displayName,
    required this.number,
  });

  final String message;
  final String? displayName;
  final String number;
}

String normalizePhoneNumber(String raw) {
  String cleaned = raw.trim().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
  if (cleaned.isEmpty) return '';

  if (cleaned.startsWith('+90')) {
    return '0${cleaned.substring(3)}';
  }
  if (cleaned.startsWith('0090')) {
    return '0${cleaned.substring(4)}';
  }
  if (cleaned.startsWith('90') && cleaned.length == 12) {
    return '0${cleaned.substring(2)}';
  }
  if (cleaned.startsWith('+')) {
    return cleaned.substring(1);
  }

  return cleaned;
}

class SipService extends ChangeNotifier {
  SipService() {
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  static const MethodChannel _channel = MethodChannel('com.softphone.call/sip');

  SipAccount? _account;
  SipAccount? get account => _account;

  SipConnectionState _connectionState = SipConnectionState.disconnected;
  SipConnectionState get connectionState => _connectionState;

  SipCall? _currentCall;
  SipCall? get currentCall => _currentCall;

  CallStateEnum _callState = CallStateEnum.NONE;
  CallStateEnum get callState => _callState;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  bool _isOnHold = false;
  bool get isOnHold => _isOnHold;

  bool _isSpeakerOn = true;
  bool get isSpeakerOn => _isSpeakerOn;

  DateTime? _connectedAt;
  DateTime? get connectedAt => _connectedAt;

  bool _isVideoCall = false;
  bool get isVideoCall => _isVideoCall;

  final List<SipCall> _calls = [];
  List<SipCall> get calls => _calls;

  SipCall? _transferCompanionCall;
  SipCall? get transferCompanionCall => _transferCompanionCall;

  bool _isConference = false;
  bool get isConference => _isConference;

  CallEndInfo? _lastCallEnd;
  CallEndInfo? get lastCallEnd => _lastCallEnd;

  bool _wasConnected = false;
  DateTime? _callStartedAt;

  // Callbacks
  void Function(SipCall)? onIncomingCall;
  void Function(SipCall, CallStateEnum)? onCallStateUpdated;
  void Function({
    required String number,
    required String? displayName,
    required bool wasIncoming,
    required bool wasConnected,
    required bool wasRejected,
    required DateTime startedAt,
    required Duration duration,
  })? onCallEnded;

  Future<void> register(SipAccount account) async {
    _account = account;
    _connectionState = SipConnectionState.connecting;
    notifyListeners();

    String host = account.domain;
    if (host.isEmpty && account.wssUrl.isNotEmpty) {
      try {
        final cleanUrl = account.wssUrl.replaceFirst('wss://', 'https://').replaceFirst('ws://', 'http://');
        final uri = Uri.parse(cleanUrl);
        host = uri.host;
      } catch (e) {
        debugPrint('[SIP] Failed parsing WSS url host: $e');
      }
    }
    if (host.isEmpty) {
      host = '192.168.4.235'; // Fallback
    }

    try {
      await _channel.invokeMethod('register', {
        'domain': host,
        'username': account.extension,
        'password': account.password,
        'transport': 'UDP',
      });
      if (defaultTargetPlatform == TargetPlatform.windows) {
        _connectionState = SipConnectionState.connected;
        notifyListeners();
      }
    } catch (e) {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        _connectionState = SipConnectionState.connected;
        notifyListeners();
      } else {
        debugPrint('[SIP] Register failed: $e');
        _connectionState = SipConnectionState.registrationFailed;
        notifyListeners();
      }
    }
  }

  Future<void> unregister() async {
    _account = null;
    _connectionState = SipConnectionState.disconnected;
    notifyListeners();
    try {
      await _channel.invokeMethod('unregister');
    } catch (e) {
      debugPrint('[SIP] Unregister failed: $e');
    }
  }

  Future<void> makeCall(String target, {bool video = false}) async {
    final cleanTarget = normalizePhoneNumber(target);
    if (cleanTarget.isEmpty) return;

    _isVideoCall = video;
    _isCameraOn = video;
    _callStartedAt = DateTime.now();
    _wasConnected = false;
    _lastCallEnd = null;
    notifyListeners();
    try {
      await _channel.invokeMethod('makeCall', {
        'target': cleanTarget,
        'video': video,
      });
    } catch (e) {
      debugPrint('[SIP] Make call failed: $e');
    }
  }

  Future<void> hangupCall() async {
    try {
      await _channel.invokeMethod('hangup');
    } catch (e) {
      debugPrint('[SIP] Hangup failed: $e');
    }
  }

  Future<void> answerCall() async {
    try {
      await _channel.invokeMethod('answer');
    } catch (e) {
      debugPrint('[SIP] Answer failed: $e');
    }
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    notifyListeners();
    try {
      await _channel.invokeMethod('mute', {'enabled': _isMuted});
    } catch (e) {
      debugPrint('[SIP] Toggle mute failed: $e');
    }
  }

  Future<void> toggleHold() async {
    _isOnHold = !_isOnHold;
    notifyListeners();
    try {
      await _channel.invokeMethod('toggleHold');
    } catch (e) {
      debugPrint('[SIP] Toggle hold failed: $e');
    }
  }

  Future<void> setSpeaker(bool enabled) async {
    _isSpeakerOn = enabled;
    notifyListeners();
    try {
      await _channel.invokeMethod('speaker', {'enabled': enabled});
    } catch (e) {
      debugPrint('[SIP] Set speaker failed: $e');
    }
  }

  bool _isCameraOn = false;
  bool get isCameraOn => _isCameraOn;

  bool _isFrontCamera = true;
  bool get isFrontCamera => _isFrontCamera;

  Future<void> toggleCamera() async {
    _isCameraOn = !_isCameraOn;
    notifyListeners();
    try {
      await _channel.invokeMethod('toggleCamera', {'enabled': _isCameraOn});
    } catch (e) {
      debugPrint('[SIP] Toggle camera failed: $e');
    }
  }

  Future<void> switchCamera() async {
    _isFrontCamera = !_isFrontCamera;
    notifyListeners();
    try {
      await _channel.invokeMethod('switchCamera');
    } catch (e) {
      debugPrint('[SIP] Switch camera failed: $e');
    }
  }
  Future<void> sendDTMF(String tone) async {}

  Future<void> transfer(String target) async {
    try {
      await _channel.invokeMethod('transfer', {'target': target});
    } catch (e) {
      debugPrint('[SIP] Transfer failed: $e');
    }
  }

  Future<void> holdCall(SipCall call) async {
    // Note: Since this is a toggle operation in Linphone, toggleHold behaves correctly.
    try {
      await _channel.invokeMethod('toggleHold');
    } catch (e) {
      debugPrint('[SIP] Hold call failed: $e');
    }
  }

  Future<void> unholdCall(SipCall call) async {
    try {
      await _channel.invokeMethod('toggleHold');
    } catch (e) {
      debugPrint('[SIP] Unhold call failed: $e');
    }
  }

  Future<void> startAttendedTransfer(String target) async {
    try {
      await _channel.invokeMethod('startAttendedTransfer', {'target': target});
    } catch (e) {
      debugPrint('[SIP] Start attended transfer failed: $e');
    }
  }

  Future<void> completeAttendedTransfer() async {
    try {
      await _channel.invokeMethod('completeAttendedTransfer');
    } catch (e) {
      debugPrint('[SIP] Complete attended transfer failed: $e');
    }
  }

  Future<void> cancelAttendedTransfer() async {
    try {
      await _channel.invokeMethod('cancelAttendedTransfer');
    } catch (e) {
      debugPrint('[SIP] Cancel attended transfer failed: $e');
    }
  }

  Future<void> addToConference(String target) async {
    _isConference = true;
    notifyListeners();
    try {
      await _channel.invokeMethod('addToConference', {'target': target});
    } catch (e) {
      debugPrint('[SIP] Add to conference failed: $e');
    }
  }

  Future<void> mergeToConference() async {
    try {
      await _channel.invokeMethod('mergeToConference');
    } catch (e) {
      debugPrint('[SIP] Merge to conference failed: $e');
    }
  }

  Future<void> removeFromConference(SipCall call) async {
    try {
      await _channel.invokeMethod('removeFromConference', {'remoteIdentity': call.remote_identity});
    } catch (e) {
      debugPrint('[SIP] Remove from conference failed: $e');
    }
  }

  Future<void> transferConference(String target) async {
    try {
      await _channel.invokeMethod('transferConference', {'target': target});
    } catch (e) {
      debugPrint('[SIP] Transfer conference failed: $e');
    }
  }

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onRegistrationStateChanged':
        final args = Map<String, dynamic>.from(call.arguments);
        final state = args['state'] as String;
        final message = args['message'] as String;
        debugPrint('[SIP] Registration state: $state ($message)');
        
        if (state == 'REGISTERED') {
          _connectionState = SipConnectionState.connected;
        } else if (state == 'REGISTRATION_FAILED') {
          _connectionState = SipConnectionState.registrationFailed;
        } else if (state == 'UNREGISTERED') {
          _connectionState = SipConnectionState.disconnected;
        } else {
          _connectionState = SipConnectionState.connecting;
        }
        notifyListeners();
        break;

      case 'onCallStateChanged':
        final args = Map<String, dynamic>.from(call.arguments);
        final stateStr = args['state'] as String;
        final message = args['message'] as String;
        final remoteIdentity = args['remoteIdentity'] as String?;
        final isVideo = args['isVideo'] as bool? ?? false;
        debugPrint('[SIP] Call state: $stateStr ($message) for $remoteIdentity (video: $isVideo)');

        if (isVideo) {
          _isVideoCall = true;
          _isCameraOn = true;
        }

        final nextState = CallStateEnum.values.firstWhere(
          (e) => e.toString().split('.').last == stateStr,
          orElse: () => CallStateEnum.NONE,
        );

        if (remoteIdentity != null) {
          final cleanIdentity = remoteIdentity.split(';').first;
          final displayName = cleanIdentity.split('@').first.replaceFirst('sip:', '');

          final existingCallIndex = _calls.indexWhere((c) => c.remote_identity == cleanIdentity);

          if (nextState == CallStateEnum.ENDED) {
            if (existingCallIndex != -1) {
              final endedCall = _calls.removeAt(existingCallIndex);
              
              if (_calls.isEmpty) {
                _currentCall = null;
                _callState = CallStateEnum.ENDED;
                
                final duration = _wasConnected && _connectedAt != null
                    ? DateTime.now().difference(_connectedAt!)
                    : Duration.zero;

                onCallEnded?.call(
                  number: endedCall.remote_identity ?? '',
                  displayName: endedCall.remote_display_name,
                  wasIncoming: endedCall.direction == SipCallDirection.incoming,
                  wasConnected: _wasConnected,
                  wasRejected: false,
                  startedAt: _callStartedAt ?? DateTime.now(),
                  duration: duration,
                );
                
                _lastCallEnd = CallEndInfo(
                  message: '',
                  displayName: endedCall.remote_display_name,
                  number: endedCall.remote_identity ?? '',
                );
                
                _isMuted = false;
                _isOnHold = false;
                _isSpeakerOn = true;
                _wasConnected = false;
                _connectedAt = null;
                _isConference = false;
                _transferCompanionCall = null;
              } else {
                _currentCall = _calls.first;
                _callState = _currentCall!.state;
              }
            }
          } else {
            final direction = message.contains('incoming') || stateStr == 'INCOMING'
                ? SipCallDirection.incoming
                : SipCallDirection.outgoing;

            final callObj = SipCall(
              id: cleanIdentity,
              remote_identity: cleanIdentity,
              remote_display_name: displayName,
              direction: direction,
              state: nextState,
            );

            if (existingCallIndex != -1) {
              _calls[existingCallIndex] = callObj;
            } else {
              _calls.add(callObj);
            }

            _currentCall = callObj;
            _callState = nextState;

            if (nextState == CallStateEnum.INCOMING || nextState == CallStateEnum.CONNECTING) {
              _lastCallEnd = null;
            }

            if (nextState == CallStateEnum.INCOMING) {
              onIncomingCall?.call(callObj);
            } else if (nextState == CallStateEnum.CONFIRMED) {
              _wasConnected = true;
              _connectedAt = DateTime.now();
              // Auto merge second call in conference mode
              if (_calls.length >= 2 && _isConference) {
                await mergeToConference();
              }
            }

            if (onCallStateUpdated != null) {
              onCallStateUpdated!.call(callObj, nextState);
            }
          }

          if (_calls.length >= 2) {
            _transferCompanionCall = _calls.last;
          } else {
            _transferCompanionCall = null;
          }
        }
        notifyListeners();
        break;
    }
  }
}
