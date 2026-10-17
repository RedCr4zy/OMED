import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omed/service/ble_service.dart';
import 'package:universal_ble/universal_ble.dart' hide BleService;

void main() {
  group('BleService', () {
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

        await service.disconnect();
        expect(adapter.connectedDeviceId, isNull);
        expect(service.status, BleStatus.ready);
      },
    );

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

class _FakeBleAdapter implements BleAdapter {
  final StreamController<BleDevice> scanController =
      StreamController<BleDevice>.broadcast();
  final StreamController<AvailabilityState> availabilityController =
      StreamController<AvailabilityState>.broadcast();
  final Map<String, StreamController<bool>> connectionControllers = {};

  AvailabilityState availability = AvailabilityState.poweredOn;
  String? connectedDeviceId;
  bool scanStarted = false;

  @override
  Stream<BleDevice> get scanResults => scanController.stream;

  @override
  Stream<AvailabilityState> get availabilityChanges =>
      availabilityController.stream;

  @override
  Stream<bool> connectionChanges(String deviceId) => connectionControllers
      .putIfAbsent(deviceId, () => StreamController<bool>.broadcast())
      .stream;

  @override
  Future<AvailabilityState> getAvailability() async => availability;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> startScan(String serviceUuid) async {
    scanStarted = true;
  }

  @override
  Future<void> stopScan() async {
    scanStarted = false;
  }

  @override
  Future<void> connect(String deviceId) async {
    connectedDeviceId = deviceId;
    connectionControllers[deviceId]!.add(true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    connectedDeviceId = null;
    connectionControllers[deviceId]!.add(false);
  }

  @override
  Future<void> close() async {
    await scanController.close();
    await availabilityController.close();
    for (final controller in connectionControllers.values) {
      await controller.close();
    }
  }
}
