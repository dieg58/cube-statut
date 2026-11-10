# Cube de statut - logiciels

Trois éléments qui parlent au cube en Bluetooth :

| Dossier | Rôle |
|---|---|
| `firmware/` | Programme du cube (XIAO nRF52840 Sense). Fichier prêt à copier : `cube_statut.uf2` |
| `agent/` | Programme pour Mac et Windows : passe le cube en « en appel » quand le micro ou la caméra sont utilisés, et icône pour choisir un statut |
| `telecommande/` | Page de contrôle pour iPhone (dans l'app Bluefy) |
| `hardware/` | Fichiers 3D du boîtier (STL) et script paramétrique |
| `PROTOCOLE.md` | Détail des échanges Bluetooth |

Le cube accepte 2 connexions en même temps : l'ordinateur et l'iPhone.

---

## 1. Installer le programme sur le cube

1. Brancher la carte XIAO en USB-C sur l'ordinateur.
2. Appuyer **deux fois rapidement** sur le petit bouton reset de la carte. Un disque nommé `XIAO-SENSE` apparaît.
3. Copier `firmware/cube_statut.uf2` sur ce disque. La carte redémarre seule avec le nouveau programme.

À refaire sur chacune des 3 cartes. Pour modifier le code : Arduino IDE, ajouter l'URL
`https://files.seeedstudio.com/arduino/package_seeeduino_boards_index.json`, installer **Seeed nRF52 Boards**
(pas la version « mbed »), carte **Seeed XIAO nRF52840 Sense**, bibliothèques **Adafruit NeoPixel** et **Seeed Arduino LSM6DS3**.

## 2. Premier réglage des faces

Le sens de montage de la carte dans le boîtier détermine quelle face donne quel statut. Réglage par défaut :
LED contre la table = éteint, une face = concentré, une face = en appel, les autres = disponible.
Pour le changer, depuis l'iPhone : « Programmer les faces du cube », poser le cube sur une face, toucher le statut voulu.
C'est enregistré dans le cube. Coller ensuite une petite pastille ou un pictogramme sur chaque face.

## 3. Programme Mac / Windows

Prérequis : Python 3.10 ou plus récent ([python.org](https://www.python.org/downloads/)).

```
cd agent
pip install -r requirements.txt
python cube_agent.py
```

- Une icône apparaît dans la barre de menus (Mac) ou près de l'horloge (Windows). Sa forme indique le statut :
  coche = disponible, anneau = concentré, micro = en appel, tiret = éteint.
- Menu « Lancer au démarrage » pour qu'il démarre seul à chaque session.
- Pour tester la détection seule : `python cube_agent.py --test-detection`, puis lancer un appel Teams ou Zoom.

**Mac** : au premier lancement, macOS demande l'accès au Bluetooth pour le Terminal (ou Python). Accepter.
**Windows** : Bluetooth activé. Sur un PC d'entreprise, l'installation de Python ou l'accès Bluetooth peuvent être bloqués par l'IT.

Version sans Python (optionnel) : `pip install pyinstaller` puis
`pyinstaller --noconsole --onefile --name CubeStatut cube_agent.py` sur la machine cible.

## 4. Télécommande iPhone

Safari ne gère pas le Bluetooth web. Il faut l'app gratuite **Bluefy - Web BLE Browser** (App Store).

Adresse : https://dieg58.github.io/cube-statut/telecommande/
Ouvrir son adresse dans Bluefy, toucher « Connecter le cube », choisir `Cube-Statut-XXXX`.

## Limites connues

- L'iPhone ne peut pas détecter tout seul un appel téléphonique pour le cube : sur le téléphone, le statut se choisit à la main.
- La détection de l'ordinateur repose sur l'usage du micro ou de la caméra : une app qui garde le micro ouvert hors appel
  (certains logiciels de dictée) fera passer le cube en « en appel ». Le menu permet de couper la détection automatique.
- Autonomie à mesurer sur le premier prototype.
