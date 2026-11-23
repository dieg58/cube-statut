import 'package:flutter_test/flutter_test.dart';
import 'package:kwartor/cube/protocol.dart';
import 'package:kwartor/system/call_detector.dart';

void main() {
  group('STATUT', () {
    test('ancien firmware : 4 octets', () {
      final s = CubeState.parse([2, 0, 87, 0x01])!;
      expect(s.status, CubeStatus.focus);
      expect(s.source, StatusSource.face);
      expect(s.battery, 87);
      expect(s.charging, isTrue);
      expect(s.session, isNull);
    });

    test('session focus : 10 octets, secondes petit-boutiste', () {
      final t0 = DateTime(2026, 11, 23, 10);
      // travail, bloc 2 sur 4, phase de 25 min, 1 300 s restantes (0x0514)
      final s = CubeState.parse([2, 3, 60, 0x08, 1, 2, 4, 25, 0x14, 0x05], now: t0)!;
      expect(s.source, StatusSource.focusSession);
      final f = s.session!;
      expect(f.phase, FocusPhase.work);
      expect(f.block, 2);
      expect(f.blocksBeforeLong, 4);
      expect(f.secondsLeft, 1300);
      expect(f.remainingAt(t0.add(const Duration(seconds: 100))), 1200);
      expect(f.remainingAt(t0.add(const Duration(hours: 2))), 0);
      expect(f.progressAt(t0), closeTo(1 - 1300 / 1500, 1e-9));
    });

    test('appel détecté et trame trop courte', () {
      expect(CubeState.parse([3, 2, 50, 0x02])!.callActive, isTrue);
      expect(CubeState.parse([1, 0]), isNull);
    });
  });

  group('COMMANDE', () {
    test('trames', () {
      expect(Cmd.setStatus(CubeStatus.disco), [0x01, 4]);
      expect(Cmd.backToFace(), [0x01, 0]);
      expect(Cmd.callDetected(true), [0x02, 1]);
      expect(Cmd.brightness(80), [0x03, 40]);
      expect(Cmd.brightness(1), [0x03, 5]);
      expect(Cmd.focusDuration(500), [0x04, 240]);
      expect(Cmd.learnFace(CubeStatus.call), [0x05, 3]);
      expect(Cmd.startFocus(kFocusMethods.first), [0x07, 25, 5, 15, 4]);
      expect(Cmd.stopFocus(), [0x07, 0]);
    });

    test('reconnaissance du cube', () {
      expect(looksLikeCube('Kwartor-4F2A', const []), isTrue);
      expect(looksLikeCube('Cube-Statut-11AB', const []), isTrue);
      expect(looksLikeCube(null, const [kServiceUuid]), isTrue);
      expect(looksLikeCube('AirPods', const []), isFalse);
    });
  });

  group('Détection', () {
    test('lissage : 2 mesures pour entrer, 3 pour sortir', () {
      final d = CallDebouncer();
      expect(d.feed(true), isFalse);
      expect(d.feed(true), isTrue);
      expect(d.inCall, isTrue);
      expect(d.feed(false), isFalse);
      expect(d.feed(true), isFalse); // un trou d'une mesure ne coupe pas l'appel
      expect(d.feed(false), isFalse);
      expect(d.feed(false), isFalse);
      expect(d.feed(false), isTrue);
      expect(d.inCall, isFalse);
    });

    test('noms des applications Windows', () {
      expect(prettyAppName(r'C:#Users#d#AppData#Local#Zoom#bin#Zoom.exe'), 'Zoom');
      expect(prettyAppName('MSTeams_8wekyb3d8bbwe'), 'MSTeams');
      expect(prettyAppName(r'C:#Program Files#my_app#App.exe'), 'App');
    });

    test('libellés', () {
      expect(const MediaUse(mic: true, apps: ['Zoom']).describe(), 'Micro : Zoom');
      expect(const MediaUse(mic: true, camera: true).describe(), "Micro et caméra en cours d'utilisation");
      expect(const MediaUse().describe(), 'Aucun appel détecté');
    });
  });
}
