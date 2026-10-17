#include <Arduino.h>
#include <NimBLEDevice.h>

namespace {
constexpr char kDeviceName[] = "OMED Controller";
constexpr char kServiceUuid[] = "fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a001";
constexpr char kProtocolVersionUuid[] = "fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a002";
constexpr char kProtocolVersion[] = "1";
}  // namespace

void setup() {
  Serial.begin(115200);
  NimBLEDevice::init(kDeviceName);

  NimBLEServer* server = NimBLEDevice::createServer();
  if (server == nullptr) {
    Serial.println("ERROR: unable to create the BLE server.");
    return;
  }
  NimBLEService* service = server->createService(kServiceUuid);
  if (service == nullptr) {
    Serial.println("ERROR: unable to create the OMED BLE service.");
    return;
  }
  NimBLECharacteristic* protocolVersion = service->createCharacteristic(
      kProtocolVersionUuid,
      NIMBLE_PROPERTY::READ);
  if (protocolVersion == nullptr) {
    Serial.println("ERROR: unable to create the protocol version characteristic.");
    return;
  }
  protocolVersion->setValue(kProtocolVersion);
  service->start();

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  if (!advertising->addServiceUUID(kServiceUuid) ||
      !advertising->setName(kDeviceName)) {
    Serial.println("ERROR: unable to configure OMED BLE advertising.");
    return;
  }
  advertising->enableScanResponse(true);
  if (!advertising->start()) {
    Serial.println("ERROR: unable to start OMED BLE advertising.");
    return;
  }

  Serial.println("OMED BLE controller advertising.");
  Serial.println(kServiceUuid);
}

void loop() {
  delay(1000);
}
