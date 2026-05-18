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
    let code: String
    let title: String
    let subtitle: String?
    let note: String?
}

enum ChairAirArea: String, CaseIterable, Identifiable {
    case wrist = "팔목"
    case shoulder = "어깨"
    case foot = "발"
    case calf = "종아리"

    var id: Self { self }
}

enum ChairRollerPosition: Int, CaseIterable, Identifiable {
    case bottom = 1
    case lower
    case lowerMiddle
    case upperMiddle
    case upper
    case top

    var id: Self { self }
    var label: String { "\(rawValue)/6" }
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

    private enum DefaultsKey {
        static let autoReconnectEnabled = "ChairBLEManager.autoReconnectEnabled"
        static let lastDeviceId = "ChairBLEManager.lastDeviceId"
        static let lastDeviceName = "ChairBLEManager.lastDeviceName"
    }

    @Published var connectionState = "Starting Bluetooth"
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var isBluetoothReady = false
    @Published var bluetoothStatusMessage = "Initializing Bluetooth…"
    @Published var notifyCount = 0
    @Published var sentCount = 0
    @Published var latestShort = ""
    @Published var latestLong = ""
    @Published var rawLogs: [ChairLogEntry] = []
    @Published var commandLogs: [ChairCommandEntry] = []
    @Published var systemLogs: [ChairLogEntry] = []
    @Published var droppedRawLogCount = 0
    @Published var currentAutoMode: String?
    @Published var isWidthAutoCycling = false
    /// The peripheral currently being connected to (spinner state) or already connected (idle/active).
    /// Cleared on failure, intentional disconnect, or unintentional drop.
    @Published var activeDeviceId: UUID?
    @Published var autoReconnectEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoReconnectEnabled, forKey: DefaultsKey.autoReconnectEnabled)
            if autoReconnectEnabled {
                intentionalDisconnect = false
                attemptAutoReconnect(reason: "Auto reconnect enabled")
            }
        }
    }

    /// `true` while the chair's short status reports manual mode (B3[b5] == 0).
    @Published var isManualMode: Bool = false
    /// Most-recently observed blinking manual technique (e.g. "롤링 두드림"), or nil when none active.
    @Published var manualTechnique: String?
    @Published var stableAirStrength: String?
    @Published var stableArea: String?
    @Published var activeAirAreas: [ChairAirArea] = []
    @Published var rollerPosition: ChairRollerPosition?

    private static let autoModeCodes = ChairSpec.autoModeCodes

    /// (name, byte index, bit mask). Each bit defaults to 1 and blinks 0/1 while its technique is active.
    private static let manualTechniqueBits = ChairSpec.manualTechniqueBits

    /// How long after observing a `0` on a manual-blink bit we consider that technique active.
    /// Chair pushes long status ~2x/sec; a 1.5 s window catches at least one blink low.
    private static let manualBlinkWindow: TimeInterval = 1.5

    private var manualBitLastZero: [String: Date] = [:]
    private var manualBitLastOne: [String: Date] = [:]

    /// B7 air-area bits default to 0 and blink high while selected. Multiple areas may blink together.
    private static let airAreaBits = ChairSpec.airAreaBits

    /// Roller-position bits default to 1 and blink low as the roller passes the position.
    private static let rollerPositionBits = ChairSpec.rollerPositionBits

    private static let airAreaBlinkWindow: TimeInterval = 1.3
    private static let rollerPositionBlinkWindow: TimeInterval = 1.3

    private var airAreaLastHigh: [ChairAirArea: Date] = [:]
    private var rollerPositionLastLow: [ChairRollerPosition: Date] = [:]

    private let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abc")
    private let dataUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abd")
    private let commandUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abe")
    private var discoveredDevices: [DiscoveredDevice] = []
    @Published var displayedDevices: [DiscoveredDevice] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var hasReceivedFirstNotification = false
    private var connectedDeviceName: String?
    private var intentionalDisconnect = false
    private var autoReconnectTargetId: UUID?
    private var recentWidthSamples: [(value: String, date: Date)] = []

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    override init() {
        if UserDefaults.standard.object(forKey: DefaultsKey.autoReconnectEnabled) == nil {
            autoReconnectEnabled = true
        } else {
            autoReconnectEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.autoReconnectEnabled)
        }
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var isConnectionBusy: Bool {
        isScanning || (activeDeviceId != nil && !isConnected)
    }

    var decodedStatus: ChairDecodedStatus {
        var status = ChairDecode.decode(short: latestShort, long: latestLong)
        if status.area == "-", let stableArea {
            status.area = stableArea
        }
        return status
    }

    var rawTerminalText: String {
        rawLogs.map { entry in
            "\(Self.timeFormatter.string(from: entry.date))  \(entry.text)"
        }.joined(separator: "\n")
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
        displayedDevices = []
        isScanning = true
        connectionState = "Scanning..."
        appendSystem(.system, "Scanning for nearby chair bridges…")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func refreshDeviceList() {
        displayedDevices = discoveredDevices.sorted { a, b in
            let aChair = a.name.localizedCaseInsensitiveContains("ChairSniffer")
            let bChair = b.name.localizedCaseInsensitiveContains("ChairSniffer")
            if aChair != bChair { return aChair }
            if a.rssi != b.rssi { return a.rssi > b.rssi }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    func disconnect() {
        intentionalDisconnect = true
        autoReconnectTargetId = nil
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        central.stopScan()
        isScanning = false
        isConnected = false
        activeDeviceId = nil
        connectionState = "Disconnected"
        resetSession()
    }

    func connect(_ device: DiscoveredDevice) {
        intentionalDisconnect = false
        autoReconnectTargetId = nil
        central.stopScan()
        isScanning = false
        peripheral = device.peripheral
        connectedDeviceName = device.name
        remember(device)
        device.peripheral.delegate = self
        connectionState = "Connecting to \(device.name)"
        appendSystem(.system, "Connecting to \(device.name) (\(device.rssi) dBm)")
        resetSession()
        activeDeviceId = device.id
        central.connect(device.peripheral)
    }

    func send(command: String) {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard ChairDecode.isFourDigitHex(normalized) else {
            appendCommand(.error, code: "", title: "Invalid command", subtitle: nil, note: "use 4 hex digits")
            return
        }

        guard let peripheral, let commandCharacteristic, isConnected else {
            appendCommand(.error, code: normalized, title: "Not connected", subtitle: nil, note: nil)
            return
        }

        let info = CommandCatalog.describe(normalized)
        appendCommand(
            .appToChair,
            code: normalized,
            title: info?.name ?? "Send",
            subtitle: info?.role.rawValue,
            note: info?.note
        )
        peripheral.writeValue(Data("SEND \(normalized)".utf8), for: commandCharacteristic, type: .withResponse)
        sentCount += 1
        updateAutoMode(forCode: normalized)
    }

    private var rememberedDeviceId: UUID? {
        guard let raw = UserDefaults.standard.string(forKey: DefaultsKey.lastDeviceId) else { return nil }
        return UUID(uuidString: raw)
    }

    private var rememberedDeviceName: String? {
        UserDefaults.standard.string(forKey: DefaultsKey.lastDeviceName)
    }

    private func remember(_ device: DiscoveredDevice) {
        UserDefaults.standard.set(device.id.uuidString, forKey: DefaultsKey.lastDeviceId)
        UserDefaults.standard.set(device.name, forKey: DefaultsKey.lastDeviceName)
    }

    private func attemptAutoReconnect(reason: String) {
        guard autoReconnectEnabled,
              !intentionalDisconnect,
              central?.state == .poweredOn,
              !isConnected,
              !isConnectionBusy,
              let id = rememberedDeviceId else { return }

        let known = central.retrievePeripherals(withIdentifiers: [id])
        if let device = known.first {
            let name = rememberedDeviceName ?? device.name ?? "chair"
            peripheral = device
            connectedDeviceName = name
            device.delegate = self
            activeDeviceId = id
            connectionState = "Reconnecting to \(name)"
            appendSystem(.system, "\(reason): reconnecting to \(name)")
            central.connect(device)
        } else {
            autoReconnectTargetId = id
            isScanning = true
            connectionState = "Scanning for remembered chair..."
            appendSystem(.system, "\(reason): scanning for remembered chair")
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    private func scheduleAutoReconnect(reason: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.attemptAutoReconnect(reason: reason)
        }
    }

    private func updateAutoMode(forCode code: String) {
        let upper = code.uppercased()
        if let name = Self.autoModeCodes[upper] {
            currentAutoMode = name
        } else if upper == "0303" || upper == "0363" {
            // Power toggle or Manual mode clears any active auto preset.
            currentAutoMode = nil
        }
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

    private func resetSession() {
        notifyCount = 0
        sentCount = 0
        currentAutoMode = nil
        hasReceivedFirstNotification = false
        manualBitLastZero.removeAll()
        manualBitLastOne.removeAll()
        isManualMode = false
        manualTechnique = nil
        stableAirStrength = nil
        stableArea = nil
        recentWidthSamples.removeAll()
        isWidthAutoCycling = false
        airAreaLastHigh.removeAll()
        activeAirAreas = []
        rollerPositionLastLow.removeAll()
        rollerPosition = nil
    }

    private func updateManualModeState(from shortHex: String) {
        let bytes = ChairDecode.bytes(from: shortHex)
        guard bytes.indices.contains(ChairSpec.manualIndicatorByteIndex),
              let manualByte = UInt8(bytes[ChairSpec.manualIndicatorByteIndex], radix: 16) else { return }

        let inManual = (manualByte & ChairSpec.manualIndicatorMask) == 0
        isManualMode = inManual
        if inManual { return }

        manualBitLastZero.removeAll()
        manualBitLastOne.removeAll()
        manualTechnique = nil
    }

    /// Inspects a long-status hex string and updates `manualTechnique` from the
    /// technique-blink bits (B3[b7], B3[b6], B4[b0..b3]).
    private func updateManualTechniqueState(from longHex: String) {
        guard isManualMode else { return }

        let bytes = ChairDecode.bytes(from: longHex)

        let now = Date()
        for entry in Self.manualTechniqueBits {
            guard bytes.indices.contains(entry.byteIndex),
                  let value = UInt8(bytes[entry.byteIndex], radix: 16) else { continue }
            if value & entry.mask == 0 {
                manualBitLastZero[entry.name] = now
            } else {
                manualBitLastOne[entry.name] = now
            }
        }

        let cutoff = now.addingTimeInterval(-Self.manualBlinkWindow)
        manualBitLastZero = manualBitLastZero.filter { $0.value > cutoff }
        manualBitLastOne = manualBitLastOne.filter { $0.value > cutoff }

        let blinkCandidates = manualBitLastZero.compactMap { name, zeroDate -> (name: String, date: Date)? in
            guard let oneDate = manualBitLastOne[name], oneDate > cutoff else { return nil }
            return (name, max(zeroDate, oneDate))
        }
        let mostRecent = blinkCandidates
            .max { $0.date < $1.date }
        manualTechnique = mostRecent?.name
    }

    private func updateWidthAutoState(from longHex: String) {
        let width = ChairDecode.decode(short: "", long: longHex).width
        guard ["wide", "medium", "narrow"].contains(width) else { return }

        let now = Date()
        recentWidthSamples.append((width, now))
        recentWidthSamples.removeAll { now.timeIntervalSince($0.date) > 1.6 }

        let distinct = Set(recentWidthSamples.map(\.value))
        isWidthAutoCycling = distinct.count >= 3
    }

    private func updateStableAirStrength(from longHex: String) {
        guard !isManualMode else { return }
        let strength = ChairDecode.decode(short: "", long: longHex).airStrength
        if ["1", "3", "5"].contains(strength) {
            stableAirStrength = strength
        }
    }

    private func updateStableArea(from shortHex: String) {
        let area = ChairDecode.decode(short: shortHex, long: "").area
        if area != "-" {
            stableArea = area
        }
    }

    private func updateAirAreaState(from longHex: String) {
        let bytes = ChairDecode.bytes(from: longHex)
        let now = Date()

        for entry in Self.airAreaBits {
            guard bytes.indices.contains(entry.byteIndex),
                  let value = UInt8(bytes[entry.byteIndex], radix: 16) else { continue }
            if value & entry.mask != 0 {
                airAreaLastHigh[entry.area] = now
            }
        }

        let cutoff = now.addingTimeInterval(-Self.airAreaBlinkWindow)
        airAreaLastHigh = airAreaLastHigh.filter { $0.value > cutoff }
        activeAirAreas = ChairAirArea.allCases.filter { area in
            airAreaLastHigh[area] != nil
        }
    }

    private func updateRollerPositionState(from longHex: String) {
        let bytes = ChairDecode.bytes(from: longHex)
        let now = Date()

        for entry in Self.rollerPositionBits {
            guard bytes.indices.contains(entry.byteIndex),
                  let value = UInt8(bytes[entry.byteIndex], radix: 16) else { continue }
            if value & entry.mask == 0 {
                rollerPositionLastLow[entry.position] = now
            }
        }

        let cutoff = now.addingTimeInterval(-Self.rollerPositionBlinkWindow)
        rollerPositionLastLow = rollerPositionLastLow.filter { $0.value > cutoff }
        rollerPosition = rollerPositionLastLow.max { $0.value < $1.value }?.key
    }

    private func appendRaw(_ kind: ChairLogEntry.Kind, _ text: String) {
        rawLogs.append(ChairLogEntry(kind: kind, text: text))
        trim(&rawLogs, limit: LogLimit.raw) { self.droppedRawLogCount += $0 }
    }

    private func appendCommand(_ direction: ChairCommandDirection,
                               code: String,
                               title: String,
                               subtitle: String?,
                               note: String?) {
        commandLogs.append(ChairCommandEntry(
            direction: direction,
            code: code,
            title: title,
            subtitle: subtitle,
            note: note
        ))
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

    private func handleNotification(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }

        notifyCount += 1
        appendRaw(.status, text)

        if !hasReceivedFirstNotification {
            hasReceivedFirstNotification = true
            let name = connectedDeviceName ?? "chair"
            connectionState = "Connected to \(name)"
            appendSystem(.system, "Receiving chair data")
        }

        if text.hasPrefix("[CHAIR] ") {
            let payload = String(text.dropFirst(8))
            if payload.count > 12 {
                latestLong = payload
                updateManualTechniqueState(from: payload)
                updateStableAirStrength(from: payload)
                updateWidthAutoState(from: payload)
                updateAirAreaState(from: payload)
                updateRollerPositionState(from: payload)
            } else if payload.count > 5 {
                latestShort = payload
                updateManualModeState(from: payload)
                updateStableArea(from: payload)
            } else {
                if payload == "1104" {
                    ChairHaptics.doubleHeavy()
                }
                let info = CommandCatalog.describe(payload)
                appendCommand(
                    .chairToRemote,
                    code: payload,
                    title: info?.name ?? "Unknown",
                    subtitle: info?.role.rawValue,
                    note: info?.note
                )
            }
        } else if text.hasPrefix("[REMOTE] ") {
            let payload = String(text.dropFirst(9))
            let info = CommandCatalog.describe(payload)
            updateAutoMode(forCode: payload)
            appendCommand(
                .remoteToChair,
                code: payload,
                title: info?.name ?? "Unknown",
                subtitle: info?.role.rawValue,
                note: info?.note
            )
        } else if text.hasPrefix("[TRANSMITTED] ") {
            // Echo of our own send. Already shown locally — skip the chat duplicate.
        } else if text.hasPrefix("[ERROR] ") {
            let body = String(text.dropFirst(8))
            appendCommand(.error, code: "", title: body, subtitle: nil, note: nil)
            appendSystem(.error, body)
        }
    }
}

extension ChairBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothReady = central.state == .poweredOn
        let text = bluetoothStateText
        bluetoothStatusMessage = text
        connectionState = text
        if central.state != .unknown {
            appendSystem(.system, text)
        }
        if central.state == .poweredOn {
            attemptAutoReconnect(reason: "Bluetooth ready")
        } else {
            autoReconnectTargetId = nil
            isScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let name = advertisedName ?? peripheral.name else { return }

        let device = DiscoveredDevice(id: peripheral.identifier, peripheral: peripheral, name: name, rssi: RSSI.intValue)
        if let idx = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[idx] = device
        } else {
            discoveredDevices.append(device)
            // Insert into displayed list only when discovered for the first time;
            // keep its position stable until the next snapshot.
            if !displayedDevices.contains(where: { $0.id == device.id }) {
                displayedDevices.append(device)
            }
        }

        if autoReconnectTargetId == device.id, !isConnected, activeDeviceId == nil {
            connect(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        let name = connectedDeviceName ?? peripheral.name ?? "device"
        connectionState = "Connected to \(name), discovering…"
        appendSystem(.system, "Connected to \(name)")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        activeDeviceId = nil
        connectionState = "Connect failed"
        appendSystem(.error, "Couldn't connect: \(error?.localizedDescription ?? "unknown error")")
        scheduleAutoReconnect(reason: "Connect failed")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        activeDeviceId = nil
        commandCharacteristic = nil
        connectionState = "Disconnected"
        if let error {
            appendSystem(.error, "Disconnected (\(error.localizedDescription))")
        } else {
            appendSystem(.system, "Disconnected")
        }
        resetSession()
        scheduleAutoReconnect(reason: "Connection dropped")
    }
}

extension ChairBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            appendSystem(.error, "Couldn't read chair services: \(error.localizedDescription)")
            return
        }

        let services = peripheral.services ?? []
        if services.isEmpty {
            connectionState = "Connected, no services found"
            appendSystem(.error, "Chair advertises no BLE services — wrong device?")
            return
        }

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            appendSystem(.error, "Couldn't read characteristics: \(error.localizedDescription)")
            return
        }

        let characteristics = service.characteristics ?? []
        var hasData = false
        var hasCommand = false
        for characteristic in characteristics {
            if characteristic.uuid == dataUUID {
                peripheral.setNotifyValue(true, for: characteristic)
                hasData = true
            } else if characteristic.uuid == commandUUID {
                commandCharacteristic = characteristic
                hasCommand = true
            }
        }

        if hasData {
            connectionState = "Subscribed, waiting for chair data"
            if hasCommand {
                appendSystem(.system, "Subscribed; chair can both receive and send")
            } else {
                appendSystem(.system, "Subscribed; receive only (no command channel)")
            }
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
            appendCommand(.error, code: "", title: "Send failed", subtitle: nil, note: error.localizedDescription)
        }
    }
}
