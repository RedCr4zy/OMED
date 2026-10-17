# Firmware BLE OMED

Firmware de référence pour une carte **ESP32-DevKitC V4 avec ESP32-WROOM-32**.
Cette cible est choisie comme référence de départ; le firmware et la liaison
radio n’ont pas été compilés ni testés sur matériel dans cet environnement.

## Ce que fait le firmware

- Démarre un serveur NimBLE et annonce `OMED Controller`.
- Annonce le service `fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a001`.
- Expose `fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a002` en lecture seule avec la version
  de protocole `1`.
- N’accepte pas encore de commandes musicales : le protocole de contrôle reste
  à définir.

## Dépendances

Le fichier [`platformio.ini`](./platformio.ini) épingle PlatformIO
`espressif32` 7.1.3 et `NimBLE-Arduino` 2.5.1. Matériel pris en charge par cet
environnement : `esp32dev`; vérifier le modèle exact de carte avant de flasher.

Installer PlatformIO Core, puis depuis `esp/` :

```sh
pio run -e esp32dev
pio run -e esp32dev -t upload
pio device monitor -b 115200
```

Remplacer au besoin `/dev/ttyUSB0` avec `--upload-port` et `--port` selon le
système. Le nom `OMED Controller` et l’UUID du service apparaissent au moniteur
série au démarrage. L’application Flutter filtre les annonces avec cet UUID et
ne sélectionne pas arbitrairement le premier appareil trouvé.

## Limites

Le firmware n’a pas encore de protocole de notes, de notifications ni de
caractéristique inscriptible. La connexion Bluetooth ne transmet donc pas de
commandes au synthétiseur dans cette première version. La portée, la stabilité
et la consommation doivent être mesurées sur le matériel cible.
