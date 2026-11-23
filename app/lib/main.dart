// Kwartor - app de bureau (Mac et Windows) du cube de statut.
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'cube/cube_link.dart';
import 'tray.dart';
import 'ui/home.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final link = CubeLink();
  await link.start();

  late final KwartorTray tray;
  Future<void> quit() async {
    await link.shutdown();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  tray = KwartorTray(link, onQuit: quit);
  await tray.init();

  // Démarrage discret (ouverture de session) : seulement l'icône, sauf si aucun cube n'est encore choisi.
  final hidden = args.contains('--hidden') || (Platform.isMacOS && link.cubeId != null);
  const options = WindowOptions(
    size: Size(440, 780),
    minimumSize: Size(380, 520),
    center: true,
    title: 'Kwartor',
    backgroundColor: K.paper,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setPreventClose(true);
    if (!hidden) await tray.showWindow();
  });

  runApp(KwartorApp(link: link));
}

class KwartorApp extends StatefulWidget {
  const KwartorApp({super.key, required this.link});
  final CubeLink link;
  @override
  State<KwartorApp> createState() => _KwartorAppState();
}

class _KwartorAppState extends State<KwartorApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// Fermer la fenêtre ne quitte pas : Kwartor continue de détecter les appels depuis la barre de menus.
  @override
  void onWindowClose() => windowManager.hide();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Kwartor',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: HomePage(link: widget.link),
      );
}
