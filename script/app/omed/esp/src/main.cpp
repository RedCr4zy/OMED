#include <Arduino.h>
#include <NimBLEDevice.h>

namespace {
constexpr char kDeviceName[] = "OMED Controller";
constexpr char kServiceUuid[] = "fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a001";
constexpr char kProtocolVersionUuid[] = "fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a002";
constexpr char kSensorValueUuid[] = "fd3b6e10-0c0b-4b8e-9f5b-6e8f5d20a003";
constexpr char kProtocolVersion[] = "1";
constexpr uint8_t kSensorPin = 34;
constexpr uint32_t kSampleIntervalMs = 100;
constexpr uint32_t kLogIntervalMs = 1000;

NimBLECharacteristic* gSensorValue = nullptr;
uint32_t gLastSampleMs = 0;
uint32_t gLastLogMs = 0;
int gLatestSensorValue = 0;

class ServerCallbacks final : public NimBLEServerCallbacks {
 public:
  void onConnect(NimBLEServer*, NimBLEConnInfo& connInfo) override {
    Serial.print("BLE client connected: ");
    Serial.println(connInfo.getAddress().toString().c_str());
  }

  void onDisconnect(NimBLEServer*, NimBLEConnInfo& connInfo, int reason) override {
    Serial.print("BLE client disconnected: ");
    Serial.print(connInfo.getAddress().toString().c_str());
    Serial.print(" (reason ");
    Serial.print(reason);
    Serial.println("). Advertising will restart.");
  }
};

ServerCallbacks gServerCallbacks;

void sendSensorValue(int value) {
  if (gSensorValue == nullptr) return;

  char message[24];
  const int messageLength = snprintf(message, sizeof(message), "ANALOG_VALUE:%d", value);
  if (messageLength <= 0 || messageLength >= sizeof(message)) return;

  gSensorValue->setValue(
      reinterpret_cast<const uint8_t*>(message), messageLength);
  gSensorValue->notify();
}
}  // namespace

void setup() {
  Serial.begin(115200);
  pinMode(kSensorPin, INPUT);
  analogReadResolution(12);
  analogSetPinAttenuation(kSensorPin, ADC_11db);

  NimBLEDevice::init(kDeviceName);

  NimBLEServer* server = NimBLEDevice::createServer();
  if (server == nullptr) {
    Serial.println("ERROR: unable to create the BLE server.");
    return;
  }
  server->setCallbacks(&gServerCallbacks, false);
  server->advertiseOnDisconnect(true);

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

  gSensorValue = service->createCharacteristic(
      kSensorValueUuid,
      NIMBLE_PROPERTY::NOTIFY);
  if (gSensorValue == nullptr) {
    Serial.println("ERROR: unable to create the sensor value characteristic.");
    return;
  }

  if (!server->start()) {
    Serial.println("ERROR: unable to start the BLE server.");
    return;
  }

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->enableScanResponse(true);
  if (!advertising->addServiceUUID(kServiceUuid) ||
      !advertising->setName(kDeviceName)) {
    Serial.println("ERROR: unable to configure OMED BLE advertising.");
    return;
  }
  if (!advertising->start()) {
    Serial.println("ERROR: unable to start OMED BLE advertising.");
    return;
  }

  Serial.println("OMED BLE advertising started; it remains available until connected.");
  Serial.print("Service UUID: ");
  Serial.println(kServiceUuid);
  Serial.println("Analog sensor input: GPIO34 (ADC1), range 0-4095.");
}

void loop() {
  const uint32_t now = millis();
  if (now - gLastSampleMs >= kSampleIntervalMs) {
    gLastSampleMs = now;
    gLatestSensorValue = analogRead(kSensorPin);
    sendSensorValue(gLatestSensorValue);
  }

  if (now - gLastLogMs >= kLogIntervalMs) {
    gLastLogMs = now;
    Serial.print("Analog sensor GPIO34: ");
    Serial.print(gLatestSensorValue);
    Serial.println(" / 4095");
  }

  delay(1);
}
