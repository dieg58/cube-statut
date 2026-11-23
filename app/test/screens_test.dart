// Rend la fenêtre dans plusieurs états et enregistre des captures dans build/screens/ (contrôle visuel).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwartor/cube/cube_link.dart';
import 'package:kwartor/cube/protocol.dart';
import 'package:kwartor/system/call_detector.dart';
import 'package:kwartor/ui/home.dart';
import 'package:kwartor/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _loadFonts() async {
  for (final f in ['Inter', 'Newsreader']) {
    final loader = FontLoader(f)..addFont(rootBundle.load('assets/fonts/$f.ttf'));
    await loader.load();
  }
}

class _Fake extends CubeLink {
  _Fake() : super(probe: _NoProbe());
}

class _NoProbe implements MediaProbe {
  @override
  Future<MediaUse> probe() async => const MediaUse();
}

Future<void> _shot(WidgetTester t, CubeLink link, String name, {double height = 1900}) async {
  t.view.physicalSize = Size(440 * 2, height * 2);
  t.view.devicePixelRatio = 2;
  final key = GlobalKey();
  await t.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: HomePage(link: link)),
  ));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
  await t.runAsync(() async {
    await precacheImage(const AssetImage('assets/brand/kwartor-wordmark.png'), key.currentContext!);
  });
  await t.pump();
  await t.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/screens')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('premier lancement', (t) async {
    final l = _Fake()..phase = LinkPhase.noCubeChosen;
    l.discovered['a'] = FoundCube('a', 'Kwartor-4F2A', -52);
    l.discovered['b'] = FoundCube('b', 'Kwartor-91C0', -80);
    await _shot(t, l, '1_premier_lancement', height: 900);
  });

  testWidgets('connecté, en appel détecté', (t) async {
    final l = _Fake()
      ..phase = LinkPhase.connected
      ..cubeId = 'a'
      ..cubeName = 'Kwartor-4F2A'
      ..firmware = 'kw01 1.0.0'
      ..media = const MediaUse(mic: true, camera: true, apps: ['Teams'])
      ..state = CubeState.parse([3, 2, 82, 0x02]);
    await _shot(t, l, '2_en_appel');
  });

  testWidgets('session focus', (t) async {
    final l = _Fake()
      ..phase = LinkPhase.connected
      ..cubeId = 'a'
      ..cubeName = 'Kwartor-4F2A'
      ..state = CubeState.parse([2, 3, 64, 0x08, 1, 2, 4, 25, 0x14, 0x05]);
    await _shot(t, l, '3_focus', height: 1300);
  });

  testWidgets('disco', (t) async {
    final l = _Fake()
      ..phase = LinkPhase.connected
      ..cubeId = 'a'
      ..cubeName = 'Kwartor-4F2A'
      ..state = CubeState.parse([4, 1, 64, 0x00]);
    await _shot(t, l, '4_disco', height: 1100);
  });
}
