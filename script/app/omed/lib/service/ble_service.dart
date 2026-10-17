import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart' hide BleService;

const omedBleServiceUuid = 'fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a001';

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

abstract interface class BleAdapter {
  Stream<BleDevice> get scanResults;
  Stream<AvailabilityState> get availabilityChanges;
  Stream<bool> connectionChanges(String deviceId);
  Future<AvailabilityState> getAvailability();
  Future<void> requestPermissions();
  Future<void> startScan(String serviceUuid);
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect(String deviceId);
  Future<void> close();
}

class BleService extends ChangeNotifier {
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

  static final BleService instance = BleService();

  final BleAdapter _adapter;
  final Map<String, BleDeviceInfo> _devices = {};
  final List<String> _deviceOrder = [];
  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<AvailabilityState>? _availabilitySubscription;
  StreamSubscription<bool>? _connectionSubscription;
  Timer? _scanTimer;
  Future<void>? _shutdownFuture;
  Future<void>? _availabilityCheck;

  BleStatus status = BleStatus.checking;
  String? connectedDeviceId;
  String? errorMessage;
  List<BleDeviceInfo> get devices =>
      _deviceOrder.map((id) => _devices[id]!).toList(growable: false);

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

  void _onAvailabilityChanged(AvailabilityState availability) {
    _applyAvailability(availability);
  }

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

  void _onStreamError(Object error, StackTrace stackTrace) {
    _setError('Erreur Bluetooth : $error');
  }

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
      }
      notifyListeners();
    }, onError: _onStreamError);
    try {
      await _adapter.connect(device.id);
      connectedDeviceId = device.id;
      status = BleStatus.connected;
      errorMessage = null;
      notifyListeners();
    } catch (error) {
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      connectedDeviceId = null;
      _setError('Connexion à ${device.name} impossible : $error');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final deviceId = connectedDeviceId;
    if (deviceId == null) return;
    status = BleStatus.disconnecting;
    notifyListeners();
    try {
      await _adapter.disconnect(deviceId);
      connectedDeviceId = null;
      status = BleStatus.ready;
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      notifyListeners();
    } catch (error) {
      _setError('Déconnexion Bluetooth impossible : $error');
      rethrow;
    }
  }

  void _setError(String message) {
    status = BleStatus.error;
    errorMessage = message;
    notifyListeners();
  }

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

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

class UniversalBleAdapter implements BleAdapter {
  UniversalBleAdapter() {
    UniversalBle.onScanResult = _scanResults.add;
    UniversalBle.onAvailabilityChange = _availabilityChanges.add;
  }

  final StreamController<BleDevice> _scanResults =
      StreamController<BleDevice>.broadcast();
  final StreamController<AvailabilityState> _availabilityChanges =
      StreamController<AvailabilityState>.broadcast();

  @override
  Stream<BleDevice> get scanResults => _scanResults.stream;

  @override
  Stream<AvailabilityState> get availabilityChanges =>
      _availabilityChanges.stream;

  @override
  Stream<bool> connectionChanges(String deviceId) =>
      UniversalBle.connectionStream(deviceId);

  @override
  Future<AvailabilityState> getAvailability() =>
      UniversalBle.getBluetoothAvailabilityState();

  @override
  Future<void> requestPermissions() =>
      UniversalBle.requestPermissions(withAndroidFineLocation: false);

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

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(String deviceId) => UniversalBle.connect(
    deviceId,
    timeout: const Duration(seconds: 15),
    autoConnect: false,
  );

  @override
  Future<void> disconnect(String deviceId) =>
      UniversalBle.disconnect(deviceId, timeout: const Duration(seconds: 10));

  @override
  Future<void> close() async {
    UniversalBle.onScanResult = null;
    UniversalBle.onAvailabilityChange = null;
    await _scanResults.close();
    await _availabilityChanges.close();
  }
}
