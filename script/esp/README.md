# Firmware BLE OMED

Firmware de référence pour une carte **ESP32-DevKitC V4 avec ESP32-WROOM-32**.
Cette cible est choisie comme référence de départ; le firmware et la liaison
radio n’ont pas été compilés ni testés sur matériel dans cet environnement.

## Ce que fait le firmware

- Démarre un serveur NimBLE et annonce `OMED Controller`.
- Annonce le service `fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a001`.
- Expose `fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a002` en lecture seule avec la version
  de protocole `1`.
- Expose `fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a003` en notification pour les mesures
  du capteur analogique.
- Lit le capteur sur GPIO34 (ADC1) et transmet `ANALOG_VALUE:<valeur>` à 10 Hz,
  avec des valeurs brutes de 0 à 4095.

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
ne sélectionne pas arbitrairement le premier appareil trouvé. Relier la sortie
analogique du capteur à GPIO34, sa masse à GND et l’alimenter selon sa
spécification. La tension sur GPIO34 ne doit jamais dépasser 3,3 V.

## Limites

Le firmware envoie uniquement l’événement de bouton documenté ci-dessus; le
protocole de notes et les commandes musicales restent à définir. La portée, la
stabilité et la consommation doivent être mesurées sur le matériel cible.
