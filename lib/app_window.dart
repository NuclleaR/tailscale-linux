import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// The app's single window. It starts hidden (see linux/runner) and closing
/// it only hides it, so the app keeps running in the tray.
class AppWindow {
  Window? _window;

  void show() {
    final window = _window ??=
        WindowManager.instance.getCurrent() ??
        WindowManager.instance.getAll().firstOrNull;
    if (window == null) {
      debugPrint('window: no native window found');
      return;
    }
    window.show();
    window.focus();
  }
}
