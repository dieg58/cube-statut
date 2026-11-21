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

## STATUT - 4 octets

| Octet | Contenu |
|---|---|
| 0 | Statut affiché : 0 éteint, 1 disponible, 2 concentré, 3 en appel, 4 disco |
| 1 | Origine : 0 face posée, 1 choix manuel à distance, 2 détection automatique d'appel |
| 2 | Batterie en % (0-100) |
| 3 | Drapeaux : bit0 en charge, bit1 appel détecté actif, bit2 concentré expiré |

## COMMANDE - 2 octets `[commande, valeur]`

| Commande | Valeur | Effet |
|---|---|---|
| `0x01` | 0-4 | Statut manuel à distance. 0 = annuler et revenir à la face posée. 4 = mode disco (à distance uniquement, aucune face ne peut l'afficher) |
| `0x02` | 0/1 | Appel détecté par l'ordinateur. À renvoyer toutes les 10 s : sans rafraîchissement pendant 30 s, le cube l'oublie |
| `0x03` | 5-40 | Luminosité maximale en % |
| `0x04` | 1-240 | Durée du mode concentré en minutes (défaut 60) |
| `0x05` | 0-3 | Apprentissage : la face actuellement posée affichera ce statut (enregistré) |
| `0x06` | 0 | Remettre les réglages d'usine |

## Priorités

1. Face LED contre la table : **éteint**, toujours.
2. Appel détecté par l'ordinateur : **en appel**.
3. Choix manuel à distance (ordinateur ou iPhone) : jusqu'au prochain retournement du cube.
4. Face posée.

Le mode concentré repasse en disponible après la durée réglée, jusqu'au prochain retournement.
