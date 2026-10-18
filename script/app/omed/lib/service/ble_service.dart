import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart' hide BleService;

const omedBleServiceUuid = 'fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a001';
const omedSensorValueUuid = 'fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a003';

/// Progression de l'adaptateur BLE etat par etat.
enum BleStatus {
  checking,
  unavailable,
  ready,
  scanning,
  connecting,
  disconnecting,
  connected,
  error,
}

/// Informations d'annonce BLE necessaires a la liste des appareils.
@immutable
class BleDeviceInfo {
  const BleDeviceInfo({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int? rssi;
}

/// Contrat isolant l'application du plugin Bluetooth concret.
///
/// Les tests fournissent une implementation simulee; l'application utilise
/// [UniversalBleAdapter] pour deleguer les operations au systeme.
abstract interface class BleAdapter {
  /// Flux d'appareils trouves pendant une recherche.
  Stream<BleDevice> get scanResults;

  /// Flux signalant les changements d'etat de l'adaptateur Bluetooth.
  Stream<AvailabilityState> get availabilityChanges;

  /// Flux de connexion/deconnexion d'un appareil donne.
  Stream<bool> connectionChanges(String deviceId);

  /// Flux des octets notifies par la caracteristique analogique OMED.
  Stream<List<int>> sensorValueChanges(String deviceId);

  /// Lit l'etat courant du Bluetooth.
  Future<AvailabilityState> getAvailability();

  /// Demande les permissions necessaires au scan et a la connexion.
  Future<void> requestPermissions();

  /// Lance une recherche filtree par UUID de service.
  Future<void> startScan(String serviceUuid);

  /// Termine le scan actif.
  Future<void> stopScan();

  /// Etablit la connexion au controleur choisi.
  Future<void> connect(String deviceId);

  /// Recupere les services et caracteristiques publies par le controleur.
  Future<void> discoverServices(String deviceId);

  /// S'abonne aux mises a jour de valeur du capteur.
  Future<void> subscribeSensorValues(String deviceId);

  /// Ferme la liaison a l'appareil indique.
  Future<void> disconnect(String deviceId);

  /// Libere les flux et les ressources de l'adaptateur.
  Future<void> close();
}

// =========================================
//            Service BLE partage
// =========================================
/// Orchestre le scan, la connexion et la lecture du capteur OMED.
///
/// Les widgets observent ce service avec `AnimatedBuilder` ou un ecouteur
/// `ChangeNotifier`. Les transitions d'etat et les erreurs sont publiees apres
/// chaque operation afin de garder l'interface synchronisee avec le Bluetooth.
class BleService extends ChangeNotifier {
  /// [adapter] peut etre remplace par une simulation dans les tests.
  BleService({BleAdapter? adapter})
    : _adapter = adapter ?? UniversalBleAdapter() {
    _scanSubscription = _adapter.scanResults.listen(
      _onScanResult,
      onError: _onStreamError,
    );
    _availabilitySubscription = _adapter.availabilityChanges.listen(
      _onAvailabilityChanged,
      onError: _onStreamError,
    );
  }

  /// Instance partagee par l'ecran principal et le point d'entree.
  static final BleService instance = BleService();

  // Etat prive des resultats, des ecouteurs et des commandes asynchrones.
  final BleAdapter _adapter;
  final Map<String, BleDeviceInfo> _devices = {};
  final List<String> _deviceOrder = [];
  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<AvailabilityState>? _availabilitySubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<List<int>>? _sensorValueSubscription;
  Timer? _scanTimer;
  Future<void>? _shutdownFuture;
  Future<void>? _availabilityCheck;

  // Etat public observe par les widgets.
  BleStatus status = BleStatus.checking;
  String? connectedDeviceId;
  String? errorMessage;
  int? lastSensorValue;
  List<BleDeviceInfo> get devices =>
      _deviceOrder.map((id) => _devices[id]!).toList(growable: false);

  /// Verifie l'etat du Bluetooth; les appels simultanes partagent le meme controle.
  Future<void> initialize() {
    if (status == BleStatus.scanning ||
        status == BleStatus.connecting ||
        status == BleStatus.disconnecting ||
        status == BleStatus.connected) {
      return Future<void>.value();
    }
    final pending = _availabilityCheck;
    if (pending != null) return pending;

    final future = Future<void>.microtask(_checkAvailability);
    _availabilityCheck = future;
    return future.whenComplete(() {
      if (identical(_availabilityCheck, future)) _availabilityCheck = null;
    });
  }

  /// Met a jour le statut visible a partir de la reponse de l'adaptateur.
  Future<void> _checkAvailability() async {
    status = BleStatus.checking;
    errorMessage = null;
    notifyListeners();
    try {
      _applyAvailability(await _adapter.getAvailability());
    } catch (error) {
      _setError('Vérification du Bluetooth impossible : $error');
    }
  }

  /// Traite les changements asynchrones signales par le systeme.
  void _onAvailabilityChanged(AvailabilityState availability) {
    _applyAvailability(availability);
  }

  /// Convertit chaque etat systeme en disponibilite lisible par l'interface.
  void _applyAvailability(AvailabilityState availability) {
    final wasScanning = status == BleStatus.scanning;
    switch (availability) {
      case AvailabilityState.poweredOn:
        if (status == BleStatus.checking || status == BleStatus.unavailable) {
          status = BleStatus.ready;
        }
        errorMessage = null;
      case AvailabilityState.poweredOff:
        status = BleStatus.unavailable;
        errorMessage = 'Activez le Bluetooth pour rechercher un contrôleur.';
        _stopScanAfterAvailabilityLoss(wasScanning);
      case AvailabilityState.unsupported:
        status = BleStatus.unavailable;
        errorMessage =
            'Le Bluetooth LE n’est pas pris en charge sur cet appareil.';
        _stopScanAfterAvailabilityLoss(wasScanning);
      case AvailabilityState.unauthorized:
        status = BleStatus.unavailable;
        errorMessage = 'L’accès Bluetooth a été refusé par le système.';
        _stopScanAfterAvailabilityLoss(wasScanning);
      case AvailabilityState.unknown:
      case AvailabilityState.resetting:
        status = BleStatus.checking;
        errorMessage = null;
    }
    notifyListeners();
  }

  /// Arrete aussi un scan lorsque le Bluetooth est coupe ou interdit.
  void _stopScanAfterAvailabilityLoss(bool wasScanning) {
    if (wasScanning) {
      _scanTimer?.cancel();
      unawaited(
        _adapter.stopScan().catchError((Object error) {
          _setError('Impossible d’arrêter la recherche Bluetooth : $error');
        }),
      );
    }
  }

  /// Retient uniquement les annonces qui contiennent le service OMED attendu.
  void _onScanResult(BleDevice device) {
    if (!device.services.any(
      (service) => service.toLowerCase() == omedBleServiceUuid,
    )) {
      return;
    }
    if (!_devices.containsKey(device.deviceId)) {
      _deviceOrder.add(device.deviceId);
    }
    _devices[device.deviceId] = BleDeviceInfo(
      id: device.deviceId,
      name: device.name?.trim().isNotEmpty == true
          ? device.name!.trim()
          : 'Contrôleur sans nom',
      rssi: device.rssi,
    );
    notifyListeners();
  }

  /// Publie les erreurs emis par les flux de scan, connexion ou capteur.
  void _onStreamError(Object error, StackTrace stackTrace) {
    _setError('Erreur Bluetooth : $error');
  }

  /// Demande les permissions puis cherche le service OMED pendant 15 secondes.
  ///
  /// Les resultats precedents sont effaces avant un nouveau scan. Cette methode
  /// leve une erreur si le Bluetooth n'est pas allume ou si le systeme refuse
  /// les permissions; les widgets doivent la lancer avec `unawaited` ou `await`.
  Future<void> startScan() async {
    if (status == BleStatus.scanning) return;
    if (connectedDeviceId != null ||
        status == BleStatus.connected ||
        status == BleStatus.connecting ||
        status == BleStatus.disconnecting) {
      throw StateError(
        'Déconnectez le contrôleur avant de lancer une recherche.',
      );
    }

    try {
      final availability = await _adapter.getAvailability();
      _applyAvailability(availability);
      if (availability != AvailabilityState.poweredOn) {
        throw StateError(errorMessage ?? 'Le Bluetooth n’est pas disponible.');
      }
      await _adapter.requestPermissions();
      _devices.clear();
      _deviceOrder.clear();
      status = BleStatus.scanning;
      errorMessage = null;
      notifyListeners();
      await _adapter.startScan(omedBleServiceUuid);
      _scanTimer?.cancel();
      _scanTimer = Timer(const Duration(seconds: 15), () {
        unawaited(
          stopScan().catchError(
            (Object error) =>
                debugPrint('Timed Bluetooth scan stop failed: $error'),
          ),
        );
      });
    } catch (error) {
      _setError('Impossible de rechercher le contrôleur : $error');
      rethrow;
    }
  }

  /// Termine le scan et revient a l'etat pret.
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    try {
      await _adapter.stopScan();
      if (status == BleStatus.scanning) status = BleStatus.ready;
      notifyListeners();
    } catch (error) {
      _setError('Impossible d’arrêter la recherche Bluetooth : $error');
      rethrow;
    }
  }

  /// Connecte l'appareil selectionne, decouvre son service puis ecoute le capteur.
  Future<void> connect(BleDeviceInfo device) async {
    if (status == BleStatus.scanning) await stopScan();
    if (connectedDeviceId != null ||
        status == BleStatus.connected ||
        status == BleStatus.connecting ||
        status == BleStatus.disconnecting) {
      throw StateError(
        'Un contrôleur est déjà connecté ou en cours de connexion.',
      );
    }
    if (!_devices.containsKey(device.id)) {
      throw StateError(
        'Ce contrôleur ne fait plus partie des résultats de recherche.',
      );
    }

    status = BleStatus.connecting;
    errorMessage = null;
    notifyListeners();
    await _connectionSubscription?.cancel();
    _connectionSubscription = _adapter.connectionChanges(device.id).listen((
      isConnected,
    ) {
      if (connectedDeviceId != null && connectedDeviceId != device.id) return;
      if (isConnected) {
        connectedDeviceId = device.id;
        status = BleStatus.connected;
        errorMessage = null;
      } else if (connectedDeviceId == device.id ||
          status == BleStatus.connecting) {
        connectedDeviceId = null;
        status = BleStatus.ready;
        lastSensorValue = null;
        unawaited(_sensorValueSubscription?.cancel());
        _sensorValueSubscription = null;
      }
      notifyListeners();
    }, onError: _onStreamError);
    try {
      await _adapter.connect(device.id);
      await _adapter.discoverServices(device.id);
      _sensorValueSubscription = _adapter
          .sensorValueChanges(device.id)
          .listen(_onSensorValue, onError: _onStreamError);
      await _adapter.subscribeSensorValues(device.id);
      connectedDeviceId = device.id;
      status = BleStatus.connected;
      errorMessage = null;
      notifyListeners();
    } catch (error) {
      await _sensorValueSubscription?.cancel();
      _sensorValueSubscription = null;
      try {
        await _adapter.disconnect(device.id);
      } catch (_) {}
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      connectedDeviceId = null;
      _setError('Connexion à ${device.name} impossible : $error');
      rethrow;
    }
  }

  /// Termine la connexion active et efface la derniere mesure connue.
  Future<void> disconnect() async {
    final deviceId = connectedDeviceId;
    if (deviceId == null) return;
    status = BleStatus.disconnecting;
    notifyListeners();
    try {
      await _sensorValueSubscription?.cancel();
      _sensorValueSubscription = null;
      await _adapter.disconnect(deviceId);
      connectedDeviceId = null;
      status = BleStatus.ready;
      lastSensorValue = null;
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      notifyListeners();
    } catch (error) {
      _setError('Déconnexion Bluetooth impossible : $error');
      rethrow;
    }
  }

  /// Decode les octets UTF-8 au format `ANALOG_VALUE:<0..4095>`.
  void _onSensorValue(List<int> bytes) {
    final message = utf8.decode(bytes, allowMalformed: true).trim();
    const prefix = 'ANALOG_VALUE:';
    if (!message.startsWith(prefix)) return;
    final value = int.tryParse(message.substring(prefix.length));
    if (value == null || value < 0 || value > 4095) return;
    lastSensorValue = value;
    notifyListeners();
  }

  /// Conserve l'erreur courante et notifie immediatement les widgets.
  void _setError(String message) {
    status = BleStatus.error;
    errorMessage = message;
    notifyListeners();
  }

  /// Evite plusieurs fermetures simultanees du meme adaptateur.
  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  /// Arrete scan, abonnements et connexion avant de fermer les flux.
  Future<void> _shutdown() async {
    Object? cleanupError;
    _scanTimer?.cancel();
    if (status == BleStatus.scanning) {
      try {
        await _adapter.stopScan();
      } catch (error) {
        cleanupError = error;
      }
    }
    final deviceId = connectedDeviceId;
    await _sensorValueSubscription?.cancel();
    _sensorValueSubscription = null;
    if (deviceId != null) {
      try {
        await _adapter.disconnect(deviceId);
      } catch (error) {
        cleanupError ??= error;
      }
    }
    try {
      await _scanSubscription?.cancel();
      await _availabilitySubscription?.cancel();
      await _connectionSubscription?.cancel();
      await _adapter.close();
    } catch (error) {
      cleanupError ??= error;
    }
    if (cleanupError != null) {
      throw StateError(
        'Erreur lors de la fermeture du Bluetooth : $cleanupError',
      );
    }
  }

  /// Lance le nettoyage asynchrone quand le service est detruit.
  @override
  void dispose() {
    unawaited(
      shutdown().catchError((Object error) {
        debugPrint('Bluetooth shutdown failed: $error');
      }),
    );
    super.dispose();
  }
}

// =========================================
//       Adaptateur universal_ble natif
// =========================================
/// Relie le contrat [BleAdapter] au plugin `universal_ble`.
///
/// La bibliotheque BLE fournit des callbacks globaux; cet adaptateur les
/// redirige vers des flux Dart que [BleService] peut ecouter et fermer.
class UniversalBleAdapter implements BleAdapter {
  UniversalBleAdapter() {
    UniversalBle.onScanResult = _scanResults.add;
    UniversalBle.onAvailabilityChange = _availabilityChanges.add;
  }

  final StreamController<BleDevice> _scanResults =
      StreamController<BleDevice>.broadcast();
  final StreamController<AvailabilityState> _availabilityChanges =
      StreamController<AvailabilityState>.broadcast();

  // Acces en lecture aux evenements publies par les callbacks globaux.
  @override
  Stream<BleDevice> get scanResults => _scanResults.stream;

  @override
  Stream<AvailabilityState> get availabilityChanges =>
      _availabilityChanges.stream;

  // Delegation des evenements par appareil et des valeurs de caracteristique.
  @override
  Stream<bool> connectionChanges(String deviceId) =>
      UniversalBle.connectionStream(deviceId);

  @override
  Stream<List<int>> sensorValueChanges(String deviceId) =>
      UniversalBle.characteristicValueStream(deviceId, omedSensorValueUuid);

  // Etat et autorisations sont fournis par le plugin pour chaque plateforme.
  @override
  Future<AvailabilityState> getAvailability() =>
      UniversalBle.getBluetoothAvailabilityState();

  @override
  Future<void> requestPermissions() =>
      UniversalBle.requestPermissions(withAndroidFineLocation: false);

  /// Configure le scan BLE 4.x Android utilise par les cartes ESP32 classiques.
  @override
  Future<void> startScan(String serviceUuid) => UniversalBle.startScan(
    scanFilter: ScanFilter(withServices: [serviceUuid]),
    platformConfig: Platform.isAndroid
        ? PlatformConfig(
            android: AndroidOptions(
              legacy: true,
              scanMode: AndroidScanMode.lowLatency,
              requestLocationPermission: false,
            ),
          )
        : null,
    skipDuplicates: true,
  );

  /// Delegue l'arret du scan au plugin.
  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  /// Connexion explicite, sans reconnexion automatique, avec delai de 15 s.
  @override
  Future<void> connect(String deviceId) => UniversalBle.connect(
    deviceId,
    timeout: const Duration(seconds: 15),
    autoConnect: false,
  );

  /// Decouvre le GATT et vide le cache Android pour actualiser les UUID.
  @override
  Future<void> discoverServices(String deviceId) async {
    await UniversalBle.discoverServices(
      deviceId,
      platformConfig: Platform.isAndroid
          ? DiscoverServicesPlatformConfig(
              android: AndroidDiscoverServicesOptions(clearGattCache: true),
            )
          : null,
    );
  }

  /// Active les notifications de la caracteristique analogique OMED.
  @override
  Future<void> subscribeSensorValues(String deviceId) =>
      UniversalBle.subscribeNotifications(
        deviceId,
        omedBleServiceUuid,
        omedSensorValueUuid,
      );

  /// Delegue la deconnexion avec un delai maximal de dix secondes.
  @override
  Future<void> disconnect(String deviceId) =>
      UniversalBle.disconnect(deviceId, timeout: const Duration(seconds: 10));

  /// Detache les callbacks globaux et ferme les flux internes.
  @override
  Future<void> close() async {
    UniversalBle.onScanResult = null;
    UniversalBle.onAvailabilityChange = null;
    await _scanResults.close();
    await _availabilityChanges.close();
  }
}
