# OMED

OMED est une application Flutter de synthèse MIDI SoundFont et de connexion BLE à
un contrôleur ESP32. Le son est généré localement par FluidSynth : aucun serveur
Python, processus système ou flux audio WebSocket n’est utilisé.

## Plateformes

| Plateforme | Audio | Bluetooth LE |
| --- | --- | --- |
| Android | FluidSynth 2.5.6 via `flutter_midi_pro` et la sortie audio native à faible latence | `universal_ble`; permissions Android et consentement système |
| Linux | FluidSynth partagé via FFI, sortie audio par défaut du système | `universal_ble` via BlueZ/D-Bus |
| Windows | FluidSynth partagé via FFI, sortie audio par défaut du système | `universal_ble` |
| macOS | FluidSynth partagé via FFI, sortie audio par défaut du système | CoreBluetooth, autorisation et entitlement Bluetooth |

La couche Dart expose le même contrat de presets, sélection d’instrument,
`noteOn`, `noteOff` et arrêt de notes. Les commandes MIDI ne transportent que
quelques entiers; aucun tampon PCM n’est envoyé sur un MethodChannel. L’audio est
rendu par le moteur natif hors du thread d’interface. Android utilise le moteur
FluidSynth fourni par `flutter_midi_pro`; les trois cibles desktop chargent la
bibliothèque FluidSynth installée par le système.

## Prérequis

- Flutter et Dart selon `pubspec.yaml`.
- Android : Android SDK et NDK de la version requise par Flutter.
- Linux : FluidSynth 2.4 ou plus récent et un périphérique audio configuré.
- Windows : FluidSynth 2.4 ou plus récent, ainsi que ses DLL runtime accessibles
  depuis le `PATH` au lancement.
- macOS : FluidSynth 2.4 ou plus récent, installé par exemple avec Homebrew.
- BLE : contrôleur Bluetooth LE actif et autorisé par le système.

Exemples d’installation de FluidSynth :

```sh
# Debian / Ubuntu
sudo apt install libfluidsynth3

# macOS
brew install fluid-synth
```

Sous Windows, installer une distribution FluidSynth 2.4+ correspondant à
l’architecture de l’application, puis rendre ses DLL accessibles au processus.
Le moteur desktop recherche la bibliothèque dynamique système; il ne télécharge
ni ne copie de binaire au démarrage.

Pour une application macOS sandboxée distribuée, inclure FluidSynth et toutes
ses bibliothèques dynamiques dépendantes dans
`Runner.app/Contents/Frameworks`, puis les signer avec la même identité que
l’application. Le moteur recherche d’abord `libfluidsynth.3.dylib` et
`libfluidsynth.dylib` dans ce dossier; il ne désactive pas la validation des
bibliothèques de macOS.

## Configuration locale

Créer `lib/.env.local` localement avec les clés attendues par l’application :

```dotenv
supabaseUrl=
supabasePublishableKey=
googleClientId=
googleClientSecret=
```

Ce fichier est ignoré par Git et embarqué comme asset Flutter pour le
fonctionnement actuel de l’authentification. Les valeurs d’un fichier embarqué
dans une application cliente peuvent être extraites : ne jamais y placer une
clé privée ou un secret qui protège une ressource. Fournir également la
configuration Android Google Services requise pour le projet au moment du build.

## Lancer et compiler

Depuis `script/app/omed` :

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d linux
flutter build linux --release
flutter build apk --debug
```

Pour construire Windows et macOS, exécuter Flutter sur le système hôte
correspondant. Les builds doivent être validés sur leurs runners natifs, avec
FluidSynth installé et des pilotes audio disponibles.

### Signature Android release

Les builds debug n’ont besoin d’aucune clé. Un build release échoue si la
signature privée n’est pas explicitement configurée; la clé debug n’est jamais
réutilisée. Fournir les propriétés Gradle privées suivantes via
`~/.gradle/gradle.properties` ou `-P` dans l’environnement CI, sans les committer :

```properties
OMED_RELEASE_STORE_FILE=/chemin/prive/omed-release.jks
OMED_RELEASE_STORE_PASSWORD=...
OMED_RELEASE_KEY_ALIAS=...
OMED_RELEASE_KEY_PASSWORD=...
```

La propriété `OMED_RELEASE_STORE_FILE` est relative au dossier `android` si un
chemin relatif est fourni.

## Bluetooth ESP32

Le firmware de référence est dans [`esp/`](./esp/). Il est destiné à un
ESP32-DevKitC V4 équipé d’un ESP32-WROOM-32 et annonce un service BLE dédié.
L’application filtre les annonces par UUID, laisse l’utilisateur choisir un
appareil puis se connecte sans reconnexion automatique. Le firmware fournit
également une caractéristique en lecture seule contenant la version de protocole;
les commandes musicales ne sont pas encore définies.

L’UUID de service est
`fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a001`. Les anciens appareils BLE 4.x ESP32 sont
inclus dans le scan Android. Sous Linux, le service BlueZ doit être actif et le
compte utilisateur doit pouvoir accéder au Bluetooth. Sur macOS, l’application
déclare une raison d’usage et l’entitlement Bluetooth. Pour une distribution
Windows empaquetée, déclarer les capacités Bluetooth et radios dans le manifeste
du package Windows.

## Tests et limites de validation

`flutter test` couvre les transitions du service BLE au moyen d’un adaptateur
simulé; il n’émule pas un contrôleur radio. Vérifier le scan, la connexion, la
déconnexion et l’émission audio avec un véritable ESP32 et des haut-parleurs sur
chaque système cible avant toute publication.

FluidSynth est distribué sous LGPL-2.1-or-later. Pour distribuer l’application,
respecter les obligations de cette licence et fournir les avis/licences des
bibliothèques natives incluses. Le SoundFont FluidR3_GM livré avec le projet
indique une licence MIT dans ses métadonnées.
