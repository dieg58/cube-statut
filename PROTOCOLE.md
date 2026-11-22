# Cube de statut - protocole Bluetooth (BLE)

Le cube est un périphérique BLE. Il accepte **2 connexions simultanées**
(par exemple l'ordinateur + l'iPhone).

Nom diffusé : `Cube-Statut-XXXX` (XXXX = fin de l'adresse Bluetooth).

## Service

| Élément | UUID |
|---|---|
| Service cube | `7c0be000-5a7e-4b1d-9c3a-2f6d8e1b4a00` |
| Caractéristique STATUT (lecture, notification) | `7c0be001-5a7e-4b1d-9c3a-2f6d8e1b4a00` |
| Caractéristique COMMANDE (écriture) | `7c0be002-5a7e-4b1d-9c3a-2f6d8e1b4a00` |
| Service batterie standard | `0x180F` (niveau en %) |

## STATUT - 10 octets

Les 4 premiers octets sont inchangés : un client qui ne lit que 4 octets continue de fonctionner.

| Octet | Contenu |
|---|---|
| 0 | Statut affiché : 0 éteint, 1 disponible, 2 concentré, 3 en appel, 4 disco |
| 1 | Origine : 0 face posée, 1 choix manuel à distance, 2 détection automatique d'appel, 3 session focus |
| 2 | Batterie en % (0-100) |
| 3 | Drapeaux : bit0 en charge, bit1 appel détecté actif, bit2 concentré expiré, bit3 session focus en cours |
| 4 | Phase de la session : 0 aucune, 1 travail, 2 pause, 3 longue pause |
| 5 | Numéro du bloc de travail en cours (1, 2, ...) |
| 6 | Blocs de travail avant la longue pause (0 = pas de longue pause, la session boucle) |
| 7 | Durée de la phase en cours, en minutes |
| 8-9 | Secondes restantes dans la phase, entier 16 bits petit-boutiste, valeur au moment de l'envoi |

Le cube n'envoie une notification qu'aux changements (statut, origine, phase). Entre deux, l'app décompte elle-même à partir des octets 8-9.

## COMMANDE - 2 octets `[commande, valeur]`

| Commande | Valeur | Effet |
|---|---|---|
| `0x01` | 0-4 | Statut manuel à distance. 0 = annuler et revenir à la face posée. 4 = mode disco (à distance uniquement, aucune face ne peut l'afficher) |
| `0x02` | 0/1 | Appel détecté par l'ordinateur. À renvoyer toutes les 10 s : sans rafraîchissement pendant 30 s, le cube l'oublie |
| `0x03` | 5-40 | Luminosité maximale en % |
| `0x04` | 1-240 | Durée du mode concentré en minutes (défaut 60) |
| `0x05` | 0-3 | Apprentissage : la face actuellement posée affichera ce statut (enregistré) |
| `0x06` | 0 | Remettre les réglages d'usine |
| `0x07` | 4 octets | Session focus : `[0x07, travail, pause, longue pause, blocs]`, durées en minutes (travail 1-240, pauses 0-60, blocs 1-12). Longue pause à 0 : la session boucle travail/pause jusqu'à l'arrêt. `[0x07, 0]` arrête la session |

## Priorités

1. Face LED contre la table : **éteint**, toujours.
2. Appel détecté par l'ordinateur : **en appel**.
3. Choix manuel à distance (ordinateur ou iPhone) : jusqu'au prochain retournement du cube.
4. Face posée.

Le mode concentré repasse en disponible après la durée réglée, jusqu'au prochain retournement.

## Session focus

- La session prend la place du choix manuel (rang 3). Le minuteur tourne dans le cube : l'iPhone peut se verrouiller ou se déconnecter.
- Travail = statut concentré ; pauses = statut disponible. Pendant la session, l'anneau sert de cadran : les LED allumées représentent le temps restant de la phase.
- Chaque changement de phase est signalé par 3 impulsions blanches lentes (2,4 s).
- Un appel détecté s'affiche par-dessus sans arrêter le minuteur.
- Retourner le cube, choisir un statut à distance (`0x01`) ou envoyer `[0x07, 0]` arrête la session. Après la longue pause, la session se termine et le cube revient à la face posée.
