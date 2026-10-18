import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omed/service/ble_service.dart';
import 'package:universal_ble/universal_ble.dart' hide BleService;

// =========================================
//          Tests unitaires du service BLE
// =========================================
/// Verifie les transitions et les donnees BLE avec un adaptateur simule.
void main() {
  // Le faux adaptateur permet de piloter les annonces et notifications en Dart.
  group('BleService', () {
    // Un appareil sans UUID OMED doit etre ignore; un appareil compatible peut
    // ensuite etre choisi, connecte et utilise pour lire une mesure analogique.
    test(
      'filters service results and connects only to a selected device',
      () async {
        final adapter = _FakeBleAdapter();
        final service = BleService(adapter: adapter);
        addTearDown(service.dispose);

        await service.initialize();
        expect(service.status, BleStatus.ready);

        await service.startScan();
        adapter.scanController.add(
          BleDevice(
            deviceId: 'unrelated',
            name: 'Unrelated',
            services: const ['0000180d-0000-1000-8000-00805f9b34fb'],
          ),
        );
        adapter.scanController.add(
          BleDevice(
            deviceId: 'omed-device',
            name: 'OMED Controller',
            rssi: -52,
            services: const [omedBleServiceUuid],
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(service.devices, hasLength(1));
        expect(service.devices.single.id, 'omed-device');

        await service.stopScan();
        await service.connect(service.devices.single);
        expect(adapter.connectedDeviceId, 'omed-device');
        expect(service.status, BleStatus.connected);
        expect(adapter.servicesDiscovered, isTrue);
        expect(adapter.sensorValuesSubscribed, isTrue);

        adapter.sensorValueController.add('ANALOG_VALUE:1732'.codeUnits);
        await Future<void>.delayed(Duration.zero);
        expect(service.lastSensorValue, 1732);

        await service.disconnect();
        expect(adapter.connectedDeviceId, isNull);
        expect(service.status, BleStatus.ready);
      },
    );

    // Aucun scan ne doit demarrer si le systeme signale Bluetooth eteint.
    test('does not scan when Bluetooth is powered off', () async {
      final adapter = _FakeBleAdapter()
        ..availability = AvailabilityState.poweredOff;
      final service = BleService(adapter: adapter);
      addTearDown(service.dispose);

      await service.initialize();

      expect(service.status, BleStatus.unavailable);
      await expectLater(service.startScan(), throwsStateError);
      expect(adapter.scanStarted, isFalse);
      expect(service.status, BleStatus.error);
    });
  });
}

/// Adaptateur BLE en memoire pour simuler scan, connexion et valeurs du capteur.
class _FakeBleAdapter implements BleAdapter {
  final StreamController<BleDevice> scanController =
      StreamController<BleDevice>.broadcast();
  final StreamController<AvailabilityState> availabilityController =
      StreamController<AvailabilityState>.broadcast();
  final Map<String, StreamController<bool>> connectionControllers = {};
  final StreamController<List<int>> sensorValueController =
      StreamController<List<int>>.broadcast();

  AvailabilityState availability = AvailabilityState.poweredOn;
  String? connectedDeviceId;
  bool scanStarted = false;
  bool servicesDiscovered = false;
  bool sensorValuesSubscribed = false;

  /// Flux d'annonces et d'etats dont les tests injectent les evenements.
  @override
  Stream<BleDevice> get scanResults => scanController.stream;

  @override
  Stream<AvailabilityState> get availabilityChanges =>
      availabilityController.stream;

  /// Cree un flux de connexion distinct pour chaque identifiant d'appareil.
  @override
  Stream<bool> connectionChanges(String deviceId) => connectionControllers
      .putIfAbsent(deviceId, () => StreamController<bool>.broadcast())
      .stream;

  /// Flux partage utilise pour emettre les mesures simulees.
  @override
  Stream<List<int>> sensorValueChanges(String deviceId) =>
      sensorValueController.stream;

  /// Renvoie l'etat Bluetooth configure par le test.
  @override
  Future<AvailabilityState> getAvailability() async => availability;

  /// Les permissions sont considerees deja accordees dans les tests.
  @override
  Future<void> requestPermissions() async {}

  /// Memorise que le scan a commence.
  @override
  Future<void> startScan(String serviceUuid) async {
    scanStarted = true;
  }

  /// Memorise l'arret du scan.
  @override
  Future<void> stopScan() async {
    scanStarted = false;
  }

  /// Simule la connexion et emet l'evenement correspondant.
  @override
  Future<void> connect(String deviceId) async {
    connectedDeviceId = deviceId;
    connectionControllers[deviceId]!.add(true);
  }

  /// Marque la decouverte des services comme effectuee.
  @override
  Future<void> discoverServices(String deviceId) async {
    servicesDiscovered = true;
  }

  /// Simule la deconnexion et notifie l'abonne.
  @override
  Future<void> disconnect(String deviceId) async {
    connectedDeviceId = null;
    connectionControllers[deviceId]!.add(false);
  }

  /// Memorise l'abonnement aux notifications du capteur.
  @override
  Future<void> subscribeSensorValues(String deviceId) async {
    sensorValuesSubscribed = true;
  }

  /// Ferme tous les flux pour terminer proprement le test.
  @override
  Future<void> close() async {
    await scanController.close();
    await availabilityController.close();
    await sensorValueController.close();
    for (final controller in connectionControllers.values) {
      await controller.close();
    }
  }
}
