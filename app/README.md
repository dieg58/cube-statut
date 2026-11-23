# Kwartor - app de bureau (Mac et Windows)

App Flutter qui remplace l'agent Python (`agent/`). Le même code servira ensuite aux apps iPhone et Android.

## Ce qu'elle fait

- **Détection des appels** : dès que le micro ou la caméra sont utilisés par une application (Teams, Zoom, Meet, Webex, Slack, WhatsApp, FaceTime...), le cube passe en « En appel ». Lissage : 2 mesures positives (environ 4 s) pour entrer, 3 négatives (environ 6 s) pour sortir. Rafraîchissement toutes les 10 s, comme l'exige le protocole.
  - macOS : CoreAudio + CoreMediaIO (`macos/Runner/MainFlutterWindow.swift`). Lit l'état des périphériques, ne demande pas l'accès au micro.
  - Windows : registre `CapabilityAccessManager` (`lib/system/call_detector.dart`), la même source que l'icône micro de la barre des tâches. Affiche le nom de l'application.
- **Barre de menus / zone de notification** : icône par statut (forme + couleur, lisible en cas de daltonisme), menu rapide : statut, face du cube, session focus, détection.
- **Fenêtre** : statut actuel, choix du statut, mode focus (Pomodoro, 52/17, 90/20, personnalisé) avec décompte, luminosité, durée de la concentration, programmation des faces, mode disco (la boule descend et tourne), infos du cube.
- **Choix du cube** : au premier lancement, l'utilisateur choisit SON cube dans la liste (le plus proche en tête). L'app ne se connecte jamais d'office au cube d'un collègue.
- **Reconnexion automatique**, démarrage discret à l'ouverture de session (`SMAppService` sur Mac, clé `Run` sur Windows).
- Fermer la fenêtre ne quitte pas l'app : « Quitter » est dans le menu de l'icône. En quittant, l'app retire l'appel au cube.

## Structure

| Fichier | Rôle |
|---|---|
| `lib/cube/protocol.dart` | UUID, décodage STATUT (4 ou 10 octets), trames COMMANDE |
| `lib/cube/cube_link.dart` | Bluetooth (`universal_ble`), connexion, reconnexion, relais de la détection |
| `lib/system/call_detector.dart` | Détection micro / caméra, lissage |
| `lib/system/autostart.dart` | Lancement à l'ouverture de session |
| `lib/tray.dart` | Icône et menu |
| `lib/ui/` | Charte Kwartor, signes, écrans, mode disco |
| `test/` | Tests du protocole et captures d'écran (`build/screens/`) |

## Développer

```bash
cd app
flutter pub get
flutter test          # tests + captures dans build/screens/
flutter run -d macos  # sur un Mac (Xcode requis)
flutter run -d windows  # sur un PC (Visual Studio 2022, charge « Développement Desktop C++ »)
```

Les builds de diffusion sont produits par GitHub Actions (`.github/workflows/app-bureau.yml`) : onglet Actions > dernière exécution > Artifacts.

## Avant la diffusion publique

- **Mac** : signer avec un certificat Developer ID et notariser (compte Apple Developer), sinon Gatekeeper bloque l'ouverture.
- **Windows** : signer l'exécutable (certificat de signature de code) et livrer un installateur (MSIX ou Inno Setup), sinon SmartScreen avertit.
- Traductions NL, EN, DE, ES (les textes sont en français pour l'instant).
- Mise à jour du cube depuis l'app (DFU) : prévue, pas encore faite.
