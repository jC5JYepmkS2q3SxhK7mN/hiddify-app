import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hiddify/utils/platform_utils.dart';

/// Dock / taskbar status mark for desktop.
///
/// macOS: green corner badge on the Dock icon when connected; cleared otherwise.
/// Windows: green overlay on the taskbar button when connected; cleared otherwise.
/// Linux: no-op (no standard taskbar badge API).
class DesktopStatusBadge {
  DesktopStatusBadge._();

  static const _channel = MethodChannel('com.hiddify.app/desktop_status');

  static Future<void> setConnected(bool connected) async {
    if (!PlatformUtils.isDesktop || Platform.isLinux) return;
    try {
      await _channel.invokeMethod<void>('setConnected', {'connected': connected});
    } on MissingPluginException {
      // Hot-restart / older builds without the native handler.
    } catch (_) {
      // Best-effort UI hint; never fail tray updates on badge errors.
    }
  }
}
