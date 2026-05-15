#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <HardwareSerial.h>
#include <Preferences.h>

// === Pin Configuration ===
#define RXD_STATUS 16 // Yellow wire: chair -> remote (status broadcast)
#define TXD_STATUS 17
#define RXD_CMD 13 // White wire RX: remote -> chair (sniff remote commands)
#define TXD_CMD 14 // White wire TX: ESP32 -> chair (send commands)

// === BLE UUIDs ===
#define SERVICE_UUID "12345678-1234-1234-1234-123456789abc"
#define CHAR_DATA_UUID "12345678-1234-1234-1234-123456789abd" // Notify: chair data -> client
#define CHAR_CMD_UUID "12345678-1234-1234-1234-123456789abe"  // Write: client -> chair command

// === Hardware Serial ===
HardwareSerial chairStatus(2);
HardwareSerial chairCommand(1);

// === BLE ===
BLEServer *pServer = nullptr;
BLECharacteristic *pDataChar = nullptr;
BLECharacteristic *pCmdChar = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// === Preferences (NVS) ===
Preferences prefs;
uint32_t blePin = 0;

// === Line Buffers ===
String lineY = "";
String lineW = "";

void bleSend(const String &s);
void sendToChair(const String &cmd);
void sendLine(const String &s);

// ============================================================
// BLE Security Callback
// ============================================================
class MySecurity : public BLESecurityCallbacks {
public:
    uint32_t onPassKeyRequest() override
    {
        Serial.printf("PassKey requested, returning: %06d\n", blePin);
        return blePin;
    }

    void onPassKeyNotify(uint32_t passKey) override
    {
        Serial.printf("PassKey notify: %06d\n", passKey);
    }

    bool onConfirmPIN(uint32_t pin) override
    {
        Serial.printf("Confirm PIN: %06d\n", pin);
        return true;
    }

    bool onSecurityRequest() override
    {
        return true;
    }

    void onAuthenticationComplete(esp_ble_auth_cmpl_t authCmpl) override
    {
        if (authCmpl.success) {
            Serial.println("Auth OK");
        } else {
            Serial.printf("Auth FAIL reason=0x%x\n", authCmpl.fail_reason);
        }
    }
};

// ============================================================
// BLE Server Callbacks
// ============================================================
class MyServerCallbacks : public BLEServerCallbacks {
public:
    void onConnect(BLEServer *server) override
    {
        (void)server;
        deviceConnected = true;
        Serial.println("Client connected");
    }

    void onDisconnect(BLEServer *server) override
    {
        (void)server;
        deviceConnected = false;
        Serial.println("Client disconnected");
    }
};

// ============================================================
// BLE Command Characteristic Callback
// ============================================================
class MyCmdCallback : public BLECharacteristicCallbacks {
public:
    void onWrite(BLECharacteristic *characteristic) override
    {
        String val = characteristic->getValue().c_str();
        val.trim();
        if (val.length() == 0) {
            return;
        }

        Serial.printf("BLE received: %s\n", val.c_str());

        // PIN change command: "PIN:XXXX"
        if (val.startsWith("PIN:") && val.length() >= 8) {
            String newPin = val.substring(4);
            newPin.trim();
            uint32_t pin = newPin.toInt();
            if (newPin.length() == 4 && pin <= 9999) {
                blePin = pin;
                prefs.begin("chair", false);
                prefs.putUInt("pin", blePin);
                prefs.end();

                String msg = "[PIN] Changed to " + newPin;
                Serial.println(msg);
                bleSend(msg);

                // Update BLE security
                esp_ble_gap_set_security_param(
                    ESP_BLE_SM_SET_STATIC_PASSKEY, &blePin, sizeof(uint32_t));
            } else {
                bleSend("[PIN] Invalid. Use PIN:XXXX (0000-9999)");
            }
            return;
        }

        // Chair command: 4-char hex code
        if (val.length() == 4) {
            sendToChair(val);
            return;
        }

        bleSend("[ERR] Unknown command: " + val);
    }
};

// ============================================================
// Functions
// ============================================================
void bleSend(const String &s)
{
    if (deviceConnected && pDataChar) {
        pDataChar->setValue(s.c_str());
        pDataChar->notify();
    }
    Serial.println(s);
}

void sendToChair(const String &cmd)
{
    // Temporarily enable TX.
    chairCommand.end();
    chairCommand.begin(9600, SERIAL_8N1, RXD_CMD, TXD_CMD);

    chairCommand.print('~');
    chairCommand.print(cmd);
    chairCommand.print('\r');
    chairCommand.flush();

    // Return to RX only.
    chairCommand.end();
    chairCommand.begin(9600, SERIAL_8N1, RXD_CMD, -1);

    bleSend("[SENT] " + cmd);
}

void sendLine(const String &s)
{
    digitalWrite(2, HIGH);
    bleSend(s);
    digitalWrite(2, LOW);
}

// ============================================================
// Setup
// ============================================================
void setup()
{
    Serial.begin(115200);
    chairStatus.begin(9600, SERIAL_8N1, RXD_STATUS, TXD_STATUS);
    chairCommand.begin(9600, SERIAL_8N1, RXD_CMD, -1); // RX only
    pinMode(2, OUTPUT);

    // Load PIN from NVS.
    prefs.begin("chair", true);       // read-only
    blePin = prefs.getUInt("pin", 0); // default 0000
    prefs.end();
    Serial.printf("Loaded PIN: %04d\n", blePin);

    // Init BLE.
    BLEDevice::init("ChairSniffer");
    BLEDevice::setEncryptionLevel(ESP_BLE_SEC_ENCRYPT_MITM);
    BLEDevice::setSecurityCallbacks(new MySecurity());

    // Set static passkey.
    esp_ble_gap_set_security_param(
        ESP_BLE_SM_SET_STATIC_PASSKEY, &blePin, sizeof(uint32_t));

    // Auth mode: passkey entry.
    esp_ble_auth_req_t authReq = ESP_LE_AUTH_REQ_SC_MITM_BOND;
    esp_ble_gap_set_security_param(ESP_BLE_SM_AUTHEN_REQ_MODE, &authReq, sizeof(authReq));

    esp_ble_io_cap_t ioCap = ESP_IO_CAP_OUT;
    esp_ble_gap_set_security_param(ESP_BLE_SM_IOCAP_MODE, &ioCap, sizeof(ioCap));

    uint8_t keySize = 16;
    esp_ble_gap_set_security_param(ESP_BLE_SM_MAX_KEY_SIZE, &keySize, sizeof(keySize));

    uint8_t initKey = ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK;
    esp_ble_gap_set_security_param(ESP_BLE_SM_SET_INIT_KEY, &initKey, sizeof(initKey));

    uint8_t rspKey = ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK;
    esp_ble_gap_set_security_param(ESP_BLE_SM_SET_RSP_KEY, &rspKey, sizeof(rspKey));

    // Create BLE server.
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    // Create BLE service.
    BLEService *service = pServer->createService(SERVICE_UUID);

    // Data characteristic (Notify).
    pDataChar = service->createCharacteristic(
        CHAR_DATA_UUID,
        BLECharacteristic::PROPERTY_NOTIFY |
            BLECharacteristic::PROPERTY_READ);
    pDataChar->addDescriptor(new BLE2902());

    // Command characteristic (Write).
    pCmdChar = service->createCharacteristic(
        CHAR_CMD_UUID,
        BLECharacteristic::PROPERTY_WRITE);
    pCmdChar->setCallbacks(new MyCmdCallback());

    // Start.
    service->start();

    // Advertising.
    BLEAdvertising *advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(SERVICE_UUID);
    advertising->setScanResponse(true);
    advertising->setMinPreferred(0x06);
    advertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("BLE ready: ChairSniffer");
}

// ============================================================
// Loop
// ============================================================
void loop()
{
    // Handle reconnection advertising.
    if (!deviceConnected && oldDeviceConnected) {
        delay(500);
        BLEDevice::startAdvertising();
        Serial.println("Advertising restarted");
        oldDeviceConnected = deviceConnected;
    }
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }

    // Read chair status (Yellow line).
    while (chairStatus.available()) {
        char c = chairStatus.read();
        if (c == '~') {
            if (lineY.length() > 0) {
                String tmp = lineY;
                sendLine(tmp);
            }
            lineY = "[Y] ";
        } else if (c == '\r') {
            String tmp = lineY;
            sendLine(tmp);
            lineY = "";
        } else {
            lineY += c;
        }
    }

    // Read remote commands (White line).
    while (chairCommand.available()) {
        char c = chairCommand.read();
        if (c == '~') {
            if (lineW.length() > 0) {
                String tmp = lineW;
                sendLine(tmp);
            }
            lineW = "[W] ";
        } else if (c == '\r') {
            String tmp = lineW;
            sendLine(tmp);
            lineW = "";
        } else {
            lineW += c;
        }
    }
}
