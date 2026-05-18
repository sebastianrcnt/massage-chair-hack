import CoreBluetooth
import Foundation

struct ChairLogEntry: Identifiable {
    enum Kind {
        case status
        case command
        case sent
        case error
        case system
    }

    let id = UUID()
    let date = Date()
    let kind: Kind
    let text: String
}

enum ChairCommandDirection {
    case remoteToChair
    case chairToRemote
    case appToChair
    case error
}

struct ChairCommandEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let direction: ChairCommandDirection
    let text: String
}

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    var rssi: Int
}

final class ChairBLEManager: NSObject, ObservableObject {
    private enum LogLimit {
        static let raw = 360
        static let command = 180
        static let system = 80
    }

    @Published var connectionState = "Starting Bluetooth"
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var notifyCount = 0
    @Published var latestShort = ""
    @Published var latestLong = ""
    @Published var rawLogs: [ChairLogEntry] = []
    @Published var commandLogs: [ChairCommandEntry] = []
    @Published var systemLogs: [ChairLogEntry] = []
    @Published var droppedRawLogCount = 0

    private let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abc")
    private let dataUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abd")
    private let commandUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abe")
    @Published var discoveredDevices: [DiscoveredDevice] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var decodedStatus: ChairDecodedStatus {
        ChairDecode.decode(short: latestShort, long: latestLong)
    }

    var rawTerminalText: String {
        rawLogs.map(\.text).joined(separator: "\n")
    }

    func scan() {
        guard central.state == .poweredOn else {
            connectionState = bluetoothStateText
            return
        }

        guard !isConnected else {
            connectionState = "Connected"
            return
        }
        commandCharacteristic = nil
        discoveredDevices = []
        isScanning = true
        connectionState = "Scanning..."
        appendSystem(.system, "Scanning for devices")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func disconnect() {
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        central.stopScan()
        isScanning = false
        isConnected = false
        connectionState = "Disconnected"
    }

    func connect(_ device: DiscoveredDevice) {
        central.stopScan()
        isScanning = false
        peripheral = device.peripheral
        device.peripheral.delegate = self
        connectionState = "Connecting to \(device.name)"
        appendSystem(.system, "Connecting to \(device.name)")
        central.connect(device.peripheral)
    }

    func send(command: String) {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard ChairDecode.isFourDigitHex(normalized) else {
            appendCommand(.error, "Invalid command. Use 4 hex digits.")
            return
        }

        guard let peripheral, let commandCharacteristic, isConnected else {
            appendCommand(.error, "Not connected.")
            return
        }

        appendCommand(.appToChair, "App -> Chair  \(ChairDecode.spaced(normalized))")
        peripheral.writeValue(Data(normalized.utf8), for: commandCharacteristic, type: .withResponse)
    }

    private var bluetoothStateText: String {
        switch central.state {
        case .poweredOn:
            return "Bluetooth ready"
        case .poweredOff:
            return "Bluetooth is off"
        case .unauthorized:
            return "Bluetooth permission denied"
        case .unsupported:
            return "Bluetooth unsupported"
        case .resetting:
            return "Bluetooth resetting"
        case .unknown:
            fallthrough
        @unknown default:
            return "Bluetooth unavailable"
        }
    }

    private func appendRaw(_ kind: ChairLogEntry.Kind, _ text: String) {
        rawLogs.append(ChairLogEntry(kind: kind, text: text))
        trim(&rawLogs, limit: LogLimit.raw) { self.droppedRawLogCount += $0 }
    }

    private func appendCommand(_ direction: ChairCommandDirection, _ text: String) {
        commandLogs.append(ChairCommandEntry(direction: direction, text: text))
        trim(&commandLogs, limit: LogLimit.command)
    }

    private func appendSystem(_ kind: ChairLogEntry.Kind, _ text: String) {
        print("[ChairMonitor] \(text)")
        systemLogs.append(ChairLogEntry(kind: kind, text: text))
        trim(&systemLogs, limit: LogLimit.system)
    }

    private func trim<T>(_ entries: inout [T], limit: Int, onDrop: ((Int) -> Void)? = nil) {
        guard entries.count > limit else { return }
        let overflow = entries.count - limit
        entries.removeFirst(overflow)
        onDrop?(overflow)
    }

    private func commandLabel(for prefix: String, payload: String) -> String {
        let spaced = ChairDecode.spaced(payload)
        switch prefix {
        case "[W]":
            return "Remote -> Chair: \(spaced)"
        case "[Y]":
            return "Chair -> Remote: \(spaced)"
        case "[SENT]":
            return "App -> Chair: \(spaced)"
        default:
            return "\(prefix) \(spaced)"
        }
    }

    private func handleNotification(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }

        notifyCount += 1
        appendRaw(.status, text)

        if text.hasPrefix("[Y] ") {
            let payload = String(text.dropFirst(4))
            if payload.count > 12 {
                latestLong = payload
            } else if payload.count > 5 {
                latestShort = payload
            } else {
                appendCommand(.chairToRemote, commandLabel(for: "[Y]", payload: payload))
            }
        } else if text.hasPrefix("[W] ") {
            appendCommand(.remoteToChair, commandLabel(for: "[W]", payload: String(text.dropFirst(4))))
        } else if text.hasPrefix("[SENT] ") {
            appendCommand(.appToChair, commandLabel(for: "[SENT]", payload: String(text.dropFirst(7))))
        } else if text.hasPrefix("[ERR] ") {
            appendCommand(.error, text)
            appendSystem(.error, text)
        }
    }
}

extension ChairBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        connectionState = bluetoothStateText
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let name = advertisedName ?? peripheral.name else { return }

        let device = DiscoveredDevice(id: peripheral.identifier, peripheral: peripheral, name: name, rssi: RSSI.intValue)
        if let idx = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[idx] = device
        } else {
            discoveredDevices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionState = "Connected, discovering services"
        appendSystem(.system, "Connected")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionState = "Connect failed"
        appendSystem(.error, "Connect failed: \(error?.localizedDescription ?? "unknown error")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        commandCharacteristic = nil
        connectionState = "Disconnected"
        appendSystem(.error, "Disconnected: \(error?.localizedDescription ?? "connection closed")")
    }
}

extension ChairBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            appendSystem(.error, "Service discovery failed: \(error.localizedDescription)")
            return
        }

        let services = peripheral.services ?? []
        if services.isEmpty {
            connectionState = "Connected, no services found"
            appendSystem(.error, "No BLE services found")
            return
        }

        for service in services {
            appendSystem(.system, "Service \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            appendSystem(.error, "Characteristic discovery failed: \(error.localizedDescription)")
            return
        }

        let characteristics = service.characteristics ?? []
        for characteristic in characteristics {
            appendSystem(.system, "Char \(characteristic.uuid.uuidString)")
            if characteristic.uuid == dataUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == commandUUID {
                commandCharacteristic = characteristic
            }
        }

        if characteristics.contains(where: { $0.uuid == dataUUID }) {
            connectionState = "Subscribed, waiting for chair data"
            appendSystem(.system, "Subscribed to chair data")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendSystem(.error, "Notify failed: \(error.localizedDescription)")
            return
        }

        if characteristic.uuid == dataUUID, let value = characteristic.value {
            handleNotification(value)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendCommand(.error, "Send failed: \(error.localizedDescription)")
        }
    }
}
