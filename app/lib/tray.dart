// Icône dans la barre de menus (Mac) / zone de notification (Windows), avec menu rapide.
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'cube/cube_link.dart';
import 'cube/protocol.dart';

class KwartorTray with TrayListener {
  KwartorTray(this.link, {required this.onQuit});
  final CubeLink link;
  final Future<void> Function() onQuit;
  String? _icon;
  String? _menuSig;

  Future<void> init() async {
    trayManager.addListener(this);
    link.addListener(_refresh);
    await _refresh();
  }

  String _iconName() {
    if (!link.connected) return 'search';
    if (link.autoDetect && link.callDetected) return 'call';
    return switch (link.state?.status) {
      CubeStatus.off => 'off',
      CubeStatus.available => 'available',
      CubeStatus.focus => 'focus',
      CubeStatus.call => 'call',
      CubeStatus.disco => 'disco',
      null => 'search',
    };
  }

  String _tooltip() {
    if (link.phase == LinkPhase.noCubeChosen) return 'Kwartor : aucun cube choisi';
    if (!link.connected) return 'Kwartor : recherche du cube…';
    final s = link.state;
    final parts = ['Kwartor : ${s?.status?.label ?? '…'}'];
    if (s?.source != null) parts.add('(${s!.source!.label})');
    if (s != null) parts.add('- batterie ${s.battery} %');
    return parts.join(' ');
  }

  Future<void> _refresh() async {
    final name = _iconName();
    if (name != _icon) {
      _icon = name;
      await trayManager.setIcon(Platform.isWindows ? 'assets/tray/$name.ico' : 'assets/tray/$name.png', iconSize: 18);
    }
    await trayManager.setToolTip(_tooltip());

    // Le menu n'est reconstruit que s'il change (évite de le refermer sous le pointeur).
    final s = link.state;
    final sig = [link.phase, s?.status, s?.source, s?.session != null, link.autoDetect, link.callDetected].join('|');
    if (sig == _menuSig) return;
    _menuSig = sig;
    final on = link.connected;
    bool sel(CubeStatus st) => s?.status == st && s?.source == StatusSource.remote;
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(label: _tooltip(), disabled: true),
      if (link.autoDetect) MenuItem(label: link.callDetected ? 'Appel détecté' : 'Aucun appel détecté', disabled: true),
      MenuItem.separator(),
      MenuItem.checkbox(key: 'st1', label: 'Disponible', checked: sel(CubeStatus.available), disabled: !on),
      MenuItem.checkbox(key: 'st2', label: 'Concentration', checked: sel(CubeStatus.focus), disabled: !on),
      MenuItem.checkbox(key: 'st3', label: 'En appel', checked: sel(CubeStatus.call), disabled: !on),
      MenuItem.checkbox(key: 'face', label: 'Face du cube', checked: s?.source == StatusSource.face, disabled: !on),
      MenuItem.separator(),
      if (s?.session != null)
        MenuItem(key: 'focusStop', label: 'Arrêter la session focus', disabled: !on)
      else
        MenuItem(key: 'focusStart', label: 'Lancer une session ${link.selectedMethod.name}', disabled: !on),
      MenuItem.checkbox(key: 'auto', label: 'Détection automatique des appels', checked: link.autoDetect),
      MenuItem.separator(),
      MenuItem(key: 'open', label: 'Ouvrir Kwartor'),
      MenuItem(key: 'quit', label: 'Quitter'),
    ]));
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() {
    // Mac : clic = menu (usage de la barre de menus). Windows : clic = fenêtre, clic droit = menu.
    if (Platform.isMacOS) {
      trayManager.popUpContextMenu();
    } else {
      showWindow();
    }
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'st1':
        link.setStatus(CubeStatus.available);
      case 'st2':
        link.setStatus(CubeStatus.focus);
      case 'st3':
        link.setStatus(CubeStatus.call);
      case 'face':
        link.backToFace();
      case 'focusStart':
        link.startFocus();
      case 'focusStop':
        link.stopFocus();
      case 'auto':
        link.setAutoDetect(!link.autoDetect);
      case 'open':
        showWindow();
      case 'quit':
        onQuit();
    }
  }
}
