import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class DesktopService extends WindowListener with TrayListener {
  static final DesktopService instance = DesktopService._internal();
  DesktopService._internal();

  bool _isInitialized = false;

  Future<void> init() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      if (_isInitialized) return;
      _isInitialized = true;

      try {
        await windowManager.ensureInitialized();

        const windowOptions = WindowOptions(
          size: Size(420, 720),
          minimumSize: Size(360, 600),
          center: true,
          backgroundColor: Colors.transparent,
          skipTaskbar: false,
          titleBarStyle: TitleBarStyle.normal,
          title: 'Softphone Call',
        );

        await windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.show();
          await windowManager.focus();
          await windowManager.setPreventClose(true);
        });

        windowManager.addListener(this);
      } catch (e) {
        debugPrint('[Desktop] WindowManager init error: $e');
      }

      try {
        await trayManager.setIcon('assets/images/logo.png');
        final menu = Menu(
          items: [
            MenuItem(
              key: 'show_window',
              label: 'Uygulamayı Aç',
            ),
            MenuItem.separator(),
            MenuItem(
              key: 'exit_app',
              label: 'Çıkış',
            ),
          ],
        );
        await trayManager.setContextMenu(menu);
        trayManager.addListener(this);
      } catch (e) {
        debugPrint('[Desktop] TrayManager init warning: $e');
      }
    }
  }

  Future<void> showWindow() async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[Desktop] Show window error: $e');
    }
  }

  Future<void> popUpWindowOnIncomingCall() async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(true);
      Future.delayed(const Duration(seconds: 3), () async {
        await windowManager.setAlwaysOnTop(false);
      });
    } catch (e) {
      debugPrint('[Desktop] Pop-up window error: $e');
    }
  }

  @override
  void onWindowClose() async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await windowManager.hide();
    }
  }

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_window') {
      showWindow();
    } else if (menuItem.key == 'exit_app') {
      await windowManager.destroy();
    }
  }
}
