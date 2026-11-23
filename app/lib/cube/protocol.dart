// Protocole BLE du cube Kwartor. Référence : PROTOCOLE.md à la racine du dépôt.
import 'dart:typed_data';

const String kServiceUuid = '7c0be000-5a7e-4b1d-9c3a-2f6d8e1b4a00';
const String kStatusUuid = '7c0be001-5a7e-4b1d-9c3a-2f6d8e1b4a00';
const String kCommandUuid = '7c0be002-5a7e-4b1d-9c3a-2f6d8e1b4a00';

/// Préfixes de nom diffusés : carte KW-01 (série) et prototype XIAO.
const List<String> kNamePrefixes = ['Kwartor', 'Cube-Statut'];

/// Le cube oublie un appel après 30 s sans rafraîchissement : on renvoie toutes les 10 s.
const Duration kCallKeepalive = Duration(seconds: 10);

enum CubeStatus {
  off(0, 'Éteint'),
  available(1, 'Disponible'),
  focus(2, 'Concentration'),
  call(3, 'En appel'),
  disco(4, 'Disco');

  const CubeStatus(this.code, this.label);
  final int code;
  final String label;

  static CubeStatus? fromCode(int c) {
    for (final s in values) {
      if (s.code == c) return s;
    }
    return null;
  }
}

enum StatusSource {
  face(0, 'face posée'),
  remote(1, 'choix manuel'),
  callDetected(2, "appel détecté par l'ordinateur"),
  focusSession(3, 'session focus');

  const StatusSource(this.code, this.label);
  final int code;
  final String label;

  static StatusSource? fromCode(int c) {
    for (final s in values) {
      if (s.code == c) return s;
    }
    return null;
  }
}

enum FocusPhase { none, work, shortBreak, longBreak }

class FocusSession {
  const FocusSession({
    required this.phase,
    required this.block,
    required this.blocksBeforeLong,
    required this.phaseMinutes,
    required this.secondsLeft,
    required this.receivedAt,
  });

  final FocusPhase phase;
  final int block;
  final int blocksBeforeLong;
  final int phaseMinutes;
  final int secondsLeft;
  final DateTime receivedAt;

  /// Secondes restantes à l'instant [now] : l'app décompte elle-même entre deux notifications.
  int remainingAt(DateTime now) {
    final r = secondsLeft - now.difference(receivedAt).inSeconds;
    return r < 0 ? 0 : r;
  }

  double progressAt(DateTime now) {
    final total = phaseMinutes * 60;
    if (total <= 0) return 0;
    return 1 - remainingAt(now) / total;
  }
}

class CubeState {
  const CubeState({
    required this.status,
    required this.source,
    required this.battery,
    required this.charging,
    required this.callActive,
    required this.focusExpired,
    this.session,
  });

  final CubeStatus? status;
  final StatusSource? source;
  final int battery;
  final bool charging;
  final bool callActive;
  final bool focusExpired;
  final FocusSession? session;

  /// Décode la caractéristique STATUT (4 octets sur les anciens firmwares, 10 sur les récents).
  static CubeState? parse(List<int> data, {DateTime? now}) {
    if (data.length < 4) return null;
    final flags = data[3];
    FocusSession? session;
    if (data.length >= 10 && (flags & 0x08) != 0) {
      final phase = data[4] < FocusPhase.values.length ? FocusPhase.values[data[4]] : FocusPhase.none;
      session = FocusSession(
        phase: phase,
        block: data[5],
        blocksBeforeLong: data[6],
        phaseMinutes: data[7],
        secondsLeft: data[8] | (data[9] << 8),
        receivedAt: now ?? DateTime.now(),
      );
    }
    return CubeState(
      status: CubeStatus.fromCode(data[0]),
      source: StatusSource.fromCode(data[1]),
      battery: data[2].clamp(0, 100),
      charging: (flags & 0x01) != 0,
      callActive: (flags & 0x02) != 0,
      focusExpired: (flags & 0x04) != 0,
      session: session,
    );
  }
}

class FocusMethod {
  const FocusMethod(this.id, this.name, this.work, this.shortBreak, this.longBreak, this.blocks, this.description);
  final String id;
  final String name;
  final int work;
  final int shortBreak;
  final int longBreak;
  final int blocks;
  final String description;

  FocusMethod copyWith({int? work, int? shortBreak, int? longBreak, int? blocks}) => FocusMethod(
        id,
        name,
        work ?? this.work,
        shortBreak ?? this.shortBreak,
        longBreak ?? this.longBreak,
        blocks ?? this.blocks,
        description,
      );
}

const List<FocusMethod> kFocusMethods = [
  FocusMethod('pomodoro', 'Pomodoro', 25, 5, 15, 4, '25 min de travail, 5 min de pause, 15 min après 4 blocs'),
  FocusMethod('5217', '52 / 17', 52, 17, 0, 1, '52 min de travail, 17 min de pause, en boucle'),
  FocusMethod('9020', 'Cycle long', 90, 20, 0, 1, '90 min de travail, 20 min de pause, en boucle'),
];

/// Constructeurs des trames COMMANDE.
abstract final class Cmd {
  static Uint8List setStatus(CubeStatus? s) => Uint8List.fromList([0x01, s?.code ?? 0]);
  static Uint8List backToFace() => Uint8List.fromList([0x01, 0]);
  static Uint8List callDetected(bool on) => Uint8List.fromList([0x02, on ? 1 : 0]);
  static Uint8List brightness(int pct) => Uint8List.fromList([0x03, pct.clamp(5, 40)]);
  static Uint8List focusDuration(int min) => Uint8List.fromList([0x04, min.clamp(1, 240)]);
  static Uint8List learnFace(CubeStatus s) => Uint8List.fromList([0x05, s.code.clamp(0, 3)]);
  static Uint8List factoryReset() => Uint8List.fromList([0x06, 0]);
  static Uint8List startFocus(FocusMethod m) => Uint8List.fromList([
        0x07,
        m.work.clamp(1, 240),
        m.shortBreak.clamp(0, 60),
        m.longBreak.clamp(0, 60),
        m.blocks.clamp(1, 12),
      ]);
  static Uint8List stopFocus() => Uint8List.fromList([0x07, 0]);
}

bool looksLikeCube(String? name, List<String> services) {
  if (services.map((s) => s.toLowerCase()).contains(kServiceUuid)) return true;
  if (name == null) return false;
  return kNamePrefixes.any(name.startsWith);
}
