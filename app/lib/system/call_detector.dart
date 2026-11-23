// Détection d'appel : le micro ou la caméra sont utilisés par une application.
// Fonctionne avec Teams, Zoom, Meet, Webex, Slack, WhatsApp, FaceTime... sans intégration propre à chaque outil.
//
// - macOS   : CoreAudio + CoreMediaIO, propriété « IsRunningSomewhere » (code Swift, MainFlutterWindow.swift).
// - Windows : registre CapabilityAccessManager, la source de l'icône micro/caméra de la barre des tâches.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:win32_registry/win32_registry.dart';

const MethodChannel systemChannel = MethodChannel('kwartor/system');

class MediaUse {
  const MediaUse({this.mic = false, this.camera = false, this.apps = const [], this.error});
  final bool mic;
  final bool camera;
  final List<String> apps;
  final String? error;
  bool get any => mic || camera;

  String describe() {
    if (error != null) return 'Détection indisponible ($error)';
    if (!any) return 'Aucun appel détecté';
    final what = [if (mic) 'micro', if (camera) 'caméra'].join(' et ');
    return apps.isEmpty ? '${what[0].toUpperCase()}${what.substring(1)} en cours d\'utilisation' : '${what[0].toUpperCase()}${what.substring(1)} : ${apps.join(', ')}';
  }
}

abstract class MediaProbe {
  Future<MediaUse> probe();

  static MediaProbe forPlatform() {
    if (Platform.isMacOS) return MacMediaProbe();
    if (Platform.isWindows) return WindowsMediaProbe();
    return _UnsupportedProbe();
  }
}

class _UnsupportedProbe implements MediaProbe {
  @override
  Future<MediaUse> probe() async => const MediaUse(error: 'système non pris en charge');
}

class MacMediaProbe implements MediaProbe {
  @override
  Future<MediaUse> probe() async {
    try {
      final r = await systemChannel.invokeMapMethod<String, dynamic>('mediaInUse');
      return MediaUse(mic: r?['mic'] == true, camera: r?['camera'] == true);
    } on PlatformException catch (e) {
      return MediaUse(error: e.message ?? e.code);
    } on MissingPluginException {
      return const MediaUse(error: 'module natif absent');
    }
  }
}

class WindowsMediaProbe implements MediaProbe {
  static const _base = r'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore';

  @override
  Future<MediaUse> probe() async {
    try {
      final mic = _inUse('microphone');
      final cam = _inUse('webcam');
      final apps = {...mic, ...cam}.toList()..sort();
      return MediaUse(mic: mic.isNotEmpty, camera: cam.isNotEmpty, apps: apps);
    } catch (e) {
      return MediaUse(error: e.toString());
    }
  }

  List<String> _inUse(String capability) {
    final found = <String>[];
    RegistryKey root;
    try {
      root = CURRENT_USER.open('$_base\\$capability');
    } catch (_) {
      return found;
    }
    try {
      for (final sub in root.keys) {
        if (sub == 'NonPackaged') {
          final np = root.open(sub);
          try {
            for (final app in np.keys) {
              if (_active(np, app)) found.add(prettyAppName(app));
            }
          } finally {
            np.close();
          }
        } else if (_active(root, sub)) {
          found.add(prettyAppName(sub));
        }
      }
    } finally {
      root.close();
    }
    return found;
  }

  bool _active(RegistryKey parent, String name) {
    try {
      final k = parent.open(name);
      try {
        final start = k.getInt('LastUsedTimeStart') ?? 0;
        final stop = k.getInt('LastUsedTimeStop') ?? 0;
        return start != 0 && stop == 0;
      } finally {
        k.close();
      }
    } catch (_) {
      return false;
    }
  }
}

/// « C:#Users#x#AppData#Local#Zoom#bin#Zoom.exe » -> « Zoom » ; « MSTeams_8wekyb3d8bbwe » -> « MSTeams ».
String prettyAppName(String key) {
  var n = key.split('#').last;
  if (n.toLowerCase().endsWith('.exe')) n = n.substring(0, n.length - 4);
  final us = n.indexOf('_');
  if (us > 0 && !key.contains('#')) n = n.substring(0, us);
  return n;
}

/// Lisse les mesures : un appel commence après [onAfter] mesures positives consécutives
/// et se termine après [offAfter] négatives. Évite qu'une dictée de 1 s allume « En appel ».
class CallDebouncer {
  CallDebouncer({this.onAfter = 2, this.offAfter = 3});
  final int onAfter;
  final int offAfter;
  bool _state = false;
  int _streak = 0;

  bool get inCall => _state;

  /// Renvoie true si l'état a changé.
  bool feed(bool positive) {
    if (positive == _state) {
      _streak = 0;
      return false;
    }
    _streak++;
    if (_streak >= (positive ? onAfter : offAfter)) {
      _state = positive;
      _streak = 0;
      return true;
    }
    return false;
  }

  void reset() {
    _state = false;
    _streak = 0;
  }
}
