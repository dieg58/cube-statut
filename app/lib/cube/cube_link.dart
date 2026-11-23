// Liaison avec le cube : recherche, appairage logiciel (on retient UN cube), connexion,
// reconnexion automatique, notifications de statut et relais de la détection d'appel.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

import '../system/call_detector.dart';
import 'protocol.dart';

enum LinkPhase { bluetoothOff, noCubeChosen, searching, connecting, connected }

class FoundCube {
  FoundCube(this.id, this.name, this.rssi);
  final String id;
  final String name;
  int? rssi;
}

class CubeLink extends ChangeNotifier {
  CubeLink({MediaProbe? probe}) : _probe = probe ?? MediaProbe.forPlatform();

  // ---------------------------------------------------------------- réglages persistants
  late SharedPreferences _prefs;
  String? cubeId;
  String? cubeName;
  bool autoDetect = true;
  int brightness = 25;
  int focusDuration = 60;
  String focusMethodId = 'pomodoro';
  FocusMethod customMethod = const FocusMethod('custom', 'Personnalisé', 45, 10, 0, 4, 'Vos propres durées');

  // ---------------------------------------------------------------- état
  LinkPhase phase = LinkPhase.noCubeChosen;
  CubeState? state;
  String? firmware;
  String? lastError;
  final Map<String, FoundCube> discovered = {};
  bool scanningForChoice = false;

  final MediaProbe _probe;
  final CallDebouncer _debouncer = CallDebouncer();
  MediaUse media = const MediaUse();
  bool get callDetected => _debouncer.inCall;

  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<Uint8List>? _valueSub;
  StreamSubscription<AvailabilityState>? _availSub;
  Timer? _pollTimer;
  Timer? _retryTimer;
  DateTime _lastCallSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;
  bool _disposed = false;

  bool get connected => phase == LinkPhase.connected;

  FocusMethod get selectedMethod =>
      focusMethodId == 'custom' ? customMethod : kFocusMethods.firstWhere((m) => m.id == focusMethodId, orElse: () => kFocusMethods.first);

  /// Réglages enregistrés : rapide, à faire avant d'afficher quoi que ce soit.
  Future<void> loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    cubeId = _prefs.getString('cubeId');
    cubeName = _prefs.getString('cubeName');
    autoDetect = _prefs.getBool('autoDetect') ?? true;
    brightness = _prefs.getInt('brightness') ?? 25;
    focusDuration = _prefs.getInt('focusDuration') ?? 60;
    focusMethodId = _prefs.getString('focusMethod') ?? 'pomodoro';
    final c = _prefs.getStringList('customMethod');
    if (c != null && c.length == 4) {
      customMethod = customMethod.copyWith(
          work: int.tryParse(c[0]), shortBreak: int.tryParse(c[1]), longBreak: int.tryParse(c[2]), blocks: int.tryParse(c[3]));
    }

  }

  /// Bluetooth et détection d'appel. Ne bloque jamais l'interface : l'autorisation Bluetooth
  /// de macOS peut faire attendre la réponse du système.
  Future<void> startBackground() async {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollMedia());
    try {
      UniversalBle.timeout = const Duration(seconds: 12);
      _availSub = UniversalBle.availabilityStream.listen(_onAvailability);
      final s = await UniversalBle.getBluetoothAvailabilityState().timeout(const Duration(seconds: 8));
      _onAvailability(s);
    } on TimeoutException {
      // L'état arrivera par availabilityStream (par exemple après la réponse à la demande d'autorisation).
    } catch (e) {
      lastError = 'Bluetooth indisponible : $e';
      _notify();
    }
  }

  // ---------------------------------------------------------------- Bluetooth
  void _onAvailability(AvailabilityState s) {
    if (s == AvailabilityState.poweredOn) {
      if (phase == LinkPhase.bluetoothOff) phase = cubeId == null ? LinkPhase.noCubeChosen : LinkPhase.searching;
      if (cubeId != null && !connected) _connectSaved();
    } else if (s == AvailabilityState.poweredOff || s == AvailabilityState.unauthorized || s == AvailabilityState.unsupported) {
      phase = LinkPhase.bluetoothOff;
      lastError = switch (s) {
        AvailabilityState.unauthorized => "Kwartor n'a pas l'autorisation d'utiliser le Bluetooth.",
        AvailabilityState.unsupported => "Cet ordinateur n'a pas de Bluetooth Low Energy.",
        _ => 'Le Bluetooth est désactivé.',
      };
    }
    _notify();
  }

  /// Recherche les cubes à portée pour que l'utilisateur choisisse le sien
  /// (dans un bureau, plusieurs cubes peuvent être visibles : on ne prend jamais celui d'un collègue d'office).
  Future<void> scanForChoice() async {
    discovered.clear();
    scanningForChoice = true;
    _notify();
    await _startScan((d) {
      discovered.putIfAbsent(d.deviceId, () => FoundCube(d.deviceId, d.name ?? 'Cube', d.rssi)).rssi = d.rssi;
      _notify();
    });
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 15), () async {
      await _stopScan();
      scanningForChoice = false;
      _notify();
    });
  }

  Future<void> choose(FoundCube cube) async {
    await _stopScan();
    scanningForChoice = false;
    cubeId = cube.id;
    cubeName = cube.name;
    await _prefs.setString('cubeId', cube.id);
    await _prefs.setString('cubeName', cube.name);
    await _connect(cube.id);
  }

  Future<void> forget() async {
    final id = cubeId;
    cubeId = null;
    cubeName = null;
    await _prefs.remove('cubeId');
    await _prefs.remove('cubeName');
    _retryTimer?.cancel();
    await _stopScan();
    if (id != null) {
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
    }
    _teardown();
    phase = LinkPhase.noCubeChosen;
    _notify();
  }

  Future<void> _connectSaved() async {
    if (_busy || cubeId == null || connected) return;
    phase = LinkPhase.searching;
    _notify();
    // Le système doit avoir vu le cube récemment (macOS en particulier) : on scanne jusqu'à le trouver.
    await _startScan((d) async {
      if (d.deviceId == cubeId) {
        await _stopScan();
        if (d.name != null && d.name != cubeName) {
          cubeName = d.name;
          await _prefs.setString('cubeName', d.name!);
        }
        await _connect(d.deviceId);
      }
    });
  }

  Future<void> _startScan(void Function(BleDevice) onCube) async {
    await _stopScan();
    _scanSub = UniversalBle.scanStream.listen((d) {
      if (looksLikeCube(d.name, d.services)) onCube(d);
    });
    try {
      await UniversalBle.startScan(scanFilter: ScanFilter(withServices: [kServiceUuid], withNamePrefix: kNamePrefixes));
    } catch (e) {
      lastError = 'Recherche Bluetooth impossible : $e';
      _scheduleRetry();
      _notify();
    }
  }

  Future<void> _stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      if (await UniversalBle.isScanning()) await UniversalBle.stopScan();
    } catch (_) {}
  }

  Future<void> _connect(String id) async {
    if (_busy) return;
    _busy = true;
    phase = LinkPhase.connecting;
    lastError = null;
    _notify();
    try {
      await _connSub?.cancel();
      _connSub = UniversalBle.connectionStream(id).listen((up) {
        if (!up && connected) _onDisconnected();
      });
      await UniversalBle.connect(id, timeout: const Duration(seconds: 15));
      await UniversalBle.discoverServices(id);

      await _valueSub?.cancel();
      _valueSub = UniversalBle.characteristicValueStream(id, kStatusUuid).listen(_onStatus);
      await UniversalBle.subscribeNotifications(id, kServiceUuid, kStatusUuid);
      _onStatus(await UniversalBle.read(id, kServiceUuid, kStatusUuid));
      firmware = await _readFirmware(id);

      phase = LinkPhase.connected;
      _notify();
      await send(Cmd.brightness(brightness));
      await send(Cmd.focusDuration(focusDuration));
      if (autoDetect && callDetected) await _sendCall(true);
    } catch (e) {
      lastError = 'Connexion au cube impossible. Il se reconnectera dès qu\'il est à portée.';
      debugPrint('connect: $e');
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
      _teardown();
      phase = LinkPhase.searching;
      _scheduleRetry();
      _notify();
    } finally {
      _busy = false;
    }
  }

  Future<String?> _readFirmware(String id) async {
    try {
      final v = await UniversalBle.read(id, '180a', '2a26');
      return String.fromCharCodes(v).trim();
    } catch (_) {
      return null;
    }
  }

  void _onDisconnected() {
    _teardown();
    phase = cubeId == null ? LinkPhase.noCubeChosen : LinkPhase.searching;
    _notify();
    _scheduleRetry(const Duration(seconds: 2));
  }

  void _teardown() {
    _valueSub?.cancel();
    _valueSub = null;
    _connSub?.cancel();
    _connSub = null;
    state = null;
  }

  void _scheduleRetry([Duration delay = const Duration(seconds: 8)]) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!connected && cubeId != null && phase != LinkPhase.bluetoothOff) _connectSaved();
    });
  }

  void _onStatus(Uint8List data) {
    final s = CubeState.parse(data);
    if (s != null) {
      state = s;
      _notify();
    }
  }

  Future<bool> send(Uint8List frame) async {
    final id = cubeId;
    if (id == null || !connected) return false;
    try {
      await UniversalBle.write(id, kServiceUuid, kCommandUuid, frame);
      return true;
    } catch (e) {
      debugPrint('write: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------- détection d'appel
  Future<void> _pollMedia() async {
    if (!autoDetect) return;
    media = await _probe.probe();
    final changed = _debouncer.feed(media.any);
    final due = callDetected && DateTime.now().difference(_lastCallSent) >= kCallKeepalive;
    if (changed || due) await _sendCall(callDetected);
    if (changed) _notify();
  }

  Future<void> _sendCall(bool on) async {
    _lastCallSent = DateTime.now();
    await send(Cmd.callDetected(on));
  }

  // ---------------------------------------------------------------- actions de l'interface
  Future<void> setStatus(CubeStatus s) => send(Cmd.setStatus(s));
  Future<void> backToFace() => send(Cmd.backToFace());
  Future<void> learnFace(CubeStatus s) => send(Cmd.learnFace(s));

  Future<void> setAutoDetect(bool on) async {
    autoDetect = on;
    await _prefs.setBool('autoDetect', on);
    if (!on) {
      _debouncer.reset();
      media = const MediaUse();
      await _sendCall(false);
    }
    _notify();
  }

  Future<void> setBrightness(int pct, {bool persist = true}) async {
    brightness = pct;
    if (persist) await _prefs.setInt('brightness', pct);
    _notify();
    await send(Cmd.brightness(pct));
  }

  Future<void> setFocusDuration(int min) async {
    focusDuration = min;
    await _prefs.setInt('focusDuration', min);
    _notify();
    await send(Cmd.focusDuration(min));
  }

  Future<void> selectMethod(String id) async {
    focusMethodId = id;
    await _prefs.setString('focusMethod', id);
    _notify();
  }

  Future<void> setCustom(FocusMethod m) async {
    customMethod = m;
    await _prefs.setStringList('customMethod', ['${m.work}', '${m.shortBreak}', '${m.longBreak}', '${m.blocks}']);
    _notify();
  }

  Future<void> startFocus() => send(Cmd.startFocus(selectedMethod));
  Future<void> stopFocus() => send(Cmd.stopFocus());

  /// À appeler en quittant : le cube ne doit pas rester bloqué en « En appel ».
  Future<void> shutdown() async {
    _pollTimer?.cancel();
    _retryTimer?.cancel();
    if (connected) await _sendCall(false);
    final id = cubeId;
    if (id != null) {
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _retryTimer?.cancel();
    _scanSub?.cancel();
    _connSub?.cancel();
    _valueSub?.cancel();
    _availSub?.cancel();
    super.dispose();
  }
}
