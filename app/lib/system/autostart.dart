// Lancement à l'ouverture de session.
// - macOS   : SMAppService.mainApp (macOS 13+), via le canal natif.
// - Windows : clé HKCU\...\Run, avec l'argument --hidden pour démarrer dans la zone de notification.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:win32_registry/win32_registry.dart';

import 'call_detector.dart' show systemChannel;

const _runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';
const _valueName = 'Kwartor';

Future<bool> autostartEnabled() async {
  try {
    if (Platform.isMacOS) {
      return await systemChannel.invokeMethod<bool>('launchAtLogin') ?? false;
    }
    if (Platform.isWindows) {
      final k = CURRENT_USER.open(_runKey);
      try {
        return k.getString(_valueName) != null;
      } finally {
        k.close();
      }
    }
  } catch (_) {}
  return false;
}

Future<bool> setAutostart(bool on) async {
  try {
    if (Platform.isMacOS) {
      return await systemChannel.invokeMethod<bool>('setLaunchAtLogin', on) ?? false;
    }
    if (Platform.isWindows) {
      final k = CURRENT_USER.open(_runKey, config: const RegistryOpenConfig(access: RegistryAccess.readWrite));
      try {
        if (on) {
          k.setValue(_valueName, StringValue('"${Platform.resolvedExecutable}" --hidden'));
        } else if (k.getString(_valueName) != null) {
          k.removeValue(_valueName);
        }
        return true;
      } finally {
        k.close();
      }
    }
  } on PlatformException {
    return false;
  } catch (_) {
    return false;
  }
  return false;
}
