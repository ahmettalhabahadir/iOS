import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

Future<bool> ensureMicrophonePermission() async {
  final status = await Permission.microphone.status;
  if (status.isGranted) return true;
  final result = await Permission.microphone.request();
  return result.isGranted || result.isLimited;
}

Future<bool> ensureCameraPermission() async {
  final status = await Permission.camera.status;
  if (status.isGranted) return true;
  final result = await Permission.camera.request();
  // On iOS Simulators without hardware camera, status may return restricted
  if (defaultTargetPlatform == TargetPlatform.iOS && result.isRestricted) {
    return true;
  }
  return result.isGranted;
}

Future<void> ensureNotificationPermission() async {
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
}

Future<bool> ensureContactsPermission() async {
  final status = await Permission.contacts.status;
  if (status.isGranted) return true;
  final result = await Permission.contacts.request();
  return result.isGranted || result.isLimited;
}
