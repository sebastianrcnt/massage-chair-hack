"""
Experimental MicroPython firmware for the ESP32 chair BLE bridge.

BLE text protocol (notify):

    [CHAIR] <hex>         chair -> remote status / ACK
    [REMOTE] <hex>        remote -> chair command (sniffed)
    [TRANSMITTED] <hex>   command sent by this bridge
    [ERROR] <text>        validation / runtime error

BLE writes (verbs):

    SEND XXXX                       send a 4-digit hex chair command
    OTA BEGIN/DATA/COMMIT/REBOOT    firmware update

BLE pairing/passkey security is intentionally not implemented yet.
"""

from micropython import const
from machine import Pin, UART, WDT, reset, reset_cause
import binascii
import bluetooth
import gc
import micropython
import os
import time

from bridge_core import (
    BLE_COMMAND_ERROR,
    BLE_COMMAND_IGNORE,
    BLE_COMMAND_SEND,
    BLE_OTA_BEGIN,
    BLE_OTA_DATA,
    BLE_OTA_COMMIT,
    BLE_OTA_REBOOT,
    FrameBuffer,
    advertising_payload,
    parse_ble_write,
)


# Pin configuration.
RXD_STATUS = const(16)  # Yellow wire: chair -> remote status broadcast.
TXD_STATUS = const(17)
RXD_CMD = const(13)  # White wire RX: remote -> chair command sniffing.
TXD_CMD = const(14)  # White wire TX: ESP32 -> chair command injection.
LED_PIN = const(2)

BAUD_RATE = const(9600)

DEVICE_NAME = "ChairSniffer-AFEF"
SERVICE_UUID_TEXT = "12345678-1234-1234-1234-123456789abc"
SERVICE_UUID = bluetooth.UUID(SERVICE_UUID_TEXT)
CHAR_DATA_UUID = bluetooth.UUID("12345678-1234-1234-1234-123456789abd")
CHAR_CMD_UUID = bluetooth.UUID("12345678-1234-1234-1234-123456789abe")

_IRQ_CENTRAL_CONNECT = const(1)
_IRQ_CENTRAL_DISCONNECT = const(2)
_IRQ_GATTS_WRITE = const(3)

_FLAG_READ = const(0x0002)
_FLAG_WRITE = const(0x0008)
_FLAG_NOTIFY = const(0x0010)

# Long enough for the largest [ERR ...] string and a full MAX_FRAME_LEN frame.
GATT_BUFFER_LEN = const(128)
GATT_COMMAND_BUFFER_LEN = const(256)
BLE_MTU = const(256)
BLE_ADVERTISE_INTERVAL_US = const(100_000)
BLE_ADVERTISE_RETRY_MS = const(10_000)
GC_INTERVAL_MS = const(60_000)
WDT_TIMEOUT_MS = const(30_000)

micropython.alloc_emergency_exception_buf(100)


class ChairBleBridge:
    def __init__(self):
        self.led = Pin(LED_PIN, Pin.OUT)
        self.status_uart = UART(
            2,
            baudrate=BAUD_RATE,
            bits=8,
            parity=None,
            stop=1,
            rx=Pin(RXD_STATUS),
            tx=Pin(TXD_STATUS),
        )
        self.command_uart = self._open_command_rx()

        self.status_frames = FrameBuffer(b"[CHAIR] ")
        self.command_frames = FrameBuffer(b"[REMOTE] ")
        self.connections = set()
        # Hand send_to_chair off to main loop; don't deinit/reinit UART in BLE IRQ.
        self.pending_write = None
        self.dropped_ble_writes = 0
        self.pending_command = None
        self.pending_ota = None
        self.ota_active = False
        self.ota_filename = None
        self.ota_size = 0
        self.ota_received = 0
        self.ota_file = None
        self.adv_payload = advertising_payload(DEVICE_NAME)
        self.need_advertise = False
        self.last_advertise_ms = time.ticks_ms()
        self.last_gc_ms = time.ticks_ms()

        self.ble = bluetooth.BLE()
        self.ble.active(True)
        self.ble.config(mtu=BLE_MTU)
        self.ble.irq(self._on_ble_irq)

        data_char = (CHAR_DATA_UUID, _FLAG_READ | _FLAG_NOTIFY)
        cmd_char = (CHAR_CMD_UUID, _FLAG_WRITE)
        service = (SERVICE_UUID, (data_char, cmd_char))
        ((self.data_handle, self.cmd_handle),) = self.ble.gatts_register_services(
            (service,)
        )
        # Default value buffer is 20B; bump so long error strings survive read_gatt_char.
        self.ble.gatts_set_buffer(self.data_handle, GATT_BUFFER_LEN)
        self.ble.gatts_set_buffer(self.cmd_handle, GATT_COMMAND_BUFFER_LEN)
        self.ble.gatts_write(self.data_handle, b"")
        self._advertise()

        print("BLE ready: {}".format(DEVICE_NAME))
        print("Reset cause: {}".format(reset_cause()))
        print("MicroPython firmware is experimental and uses no BLE passkey")
        self.wdt = WDT(timeout=WDT_TIMEOUT_MS)

    def _open_command_rx(self):
        # Omit tx= so UART(1) leaves TXD_CMD high-Z; mirrors src/main.cpp's tx=-1
        # and lets the real remote drive the shared white line.
        Pin(TXD_CMD, Pin.IN)
        return UART(
            1,
            baudrate=BAUD_RATE,
            bits=8,
            parity=None,
            stop=1,
            rx=Pin(RXD_CMD),
        )

    def _advertise(self):
        try:
            self.ble.gap_advertise(BLE_ADVERTISE_INTERVAL_US, adv_data=self.adv_payload)
            self.last_advertise_ms = time.ticks_ms()
            self.need_advertise = False
        except OSError as exc:
            print("BLE advertise failed: {}".format(exc))
            self.need_advertise = True

    def _on_ble_irq(self, event, data):
        if event == _IRQ_CENTRAL_CONNECT:
            conn_handle, _, _ = data
            self.connections.add(conn_handle)
            print("Client connected")
        elif event == _IRQ_CENTRAL_DISCONNECT:
            conn_handle, _, _ = data
            self.connections.discard(conn_handle)
            print("Client disconnected")
            self.need_advertise = True
        elif event == _IRQ_GATTS_WRITE:
            conn_handle, value_handle = data
            if value_handle == self.cmd_handle:
                if self.pending_write is None:
                    self.pending_write = bytes(self.ble.gatts_read(value_handle))
                else:
                    self.dropped_ble_writes += 1

    def _handle_ble_write(self, value):
        action, payload = parse_ble_write(value)
        if action == BLE_COMMAND_IGNORE:
            return
        if action == BLE_COMMAND_ERROR:
            self.ble_send(payload)
            return
        if action == BLE_COMMAND_SEND:
            # Drop instead of queueing so a write flood can't unbound IRQ work.
            if self.pending_command is None:
                self.pending_command = payload
            else:
                self.ble_send("[ERROR] Busy; previous command pending")
        elif action in (BLE_OTA_BEGIN, BLE_OTA_DATA, BLE_OTA_COMMIT, BLE_OTA_REBOOT):
            if self.pending_ota is None:
                self.pending_ota = (action, payload)
            else:
                self.ble_send("[ERROR] OTA busy; wait for ACK")

    def ble_send(self, message):
        data = message.encode()
        self.ble.gatts_write(self.data_handle, data)
        for conn_handle in list(self.connections):
            try:
                self.ble.gatts_notify(conn_handle, self.data_handle, data)
            except OSError:
                self.connections.discard(conn_handle)
        print(message)
        if not self.connections:
            self.need_advertise = True

    def send_to_chair(self, command):
        self.command_uart.deinit()
        # Pre-drive high (UART idle) before UART takes over to avoid a glitch.
        tx_pin = Pin(TXD_CMD, Pin.OUT, value=1)
        self.command_uart = UART(
            1,
            baudrate=BAUD_RATE,
            bits=8,
            parity=None,
            stop=1,
            rx=Pin(RXD_CMD),
            tx=tx_pin,
        )
        self.command_uart.write(b"~" + command.encode() + b"\r")
        try:
            self.command_uart.flush()
        except AttributeError:
            time.sleep_ms(20)

        self.command_uart.deinit()
        self.command_uart = self._open_command_rx()
        self.ble_send("[TRANSMITTED] " + command)

    def _send_line(self, message):
        self.led.on()
        self.ble_send(message)
        self.led.off()

    def _emit_frame_messages(self, messages):
        for message in messages:
            if message.startswith("[ERR] "):
                self.ble_send(message)
            else:
                self._send_line(message)

    def poll_uart(self):
        while self.status_uart.any():
            value = self.status_uart.read(1)[0]
            self._emit_frame_messages(self.status_frames.append(value))

        while self.command_uart.any():
            value = self.command_uart.read(1)[0]
            self._emit_frame_messages(self.command_frames.append(value))

    def _process_pending(self):
        command = self.pending_command
        if command is None:
            return
        self.pending_command = None
        print("BLE received: {}".format(command))
        self.send_to_chair(command)

    def _process_pending_write(self):
        value = self.pending_write
        if value is None:
            return
        self.pending_write = None
        self._handle_ble_write(value)

        dropped = self.dropped_ble_writes
        if dropped:
            self.dropped_ble_writes = 0
            self.ble_send("[ERROR] Dropped {} BLE write(s)".format(dropped))

    def _process_pending_ota(self):
        item = self.pending_ota
        if item is None:
            return
        self.pending_ota = None
        action, payload = item
        if action == BLE_OTA_BEGIN:
            self._ota_begin(payload)
        elif action == BLE_OTA_DATA:
            self._ota_data(payload)
        elif action == BLE_OTA_COMMIT:
            self._ota_commit(payload)
        elif action == BLE_OTA_REBOOT:
            time.sleep_ms(200)
            reset()

    def _ota_begin(self, payload):
        parts = payload.split()
        if len(parts) != 2:
            self.ble_send("[ERROR] OTA BEGIN requires: filename size")
            return
        filename, size_str = parts[0], parts[1]
        if not filename.endswith(".py") or "/" in filename or ".." in filename:
            self.ble_send("[ERROR] OTA filename must be a .py file with no path")
            return
        try:
            size = int(size_str)
        except ValueError:
            self.ble_send("[ERROR] OTA BEGIN invalid size")
            return
        if self.ota_file is not None:
            try:
                self.ota_file.close()
            except Exception:
                pass
        self.ota_filename = filename
        self.ota_size = size
        self.ota_received = 0
        self.ota_file = open(filename + ".tmp", "wb")
        self.ota_active = True
        print("OTA begin: {} ({} bytes)".format(filename, size))
        self.ble_send("[CHAIR] OTA READY")

    def _ota_data(self, hex_chunk):
        if not self.ota_active or self.ota_file is None:
            self.ble_send("[ERROR] OTA not started")
            return
        try:
            data = bytes.fromhex(hex_chunk)
        except ValueError:
            self.ble_send("[ERROR] OTA DATA invalid hex")
            return
        self.ota_file.write(data)
        self.ota_received += len(data)
        self.ble_send("[CHAIR] OTA ACK {}".format(self.ota_received))

    def _ota_commit(self, expected_crc):
        if not self.ota_active or self.ota_file is None:
            self.ble_send("[ERROR] OTA not started")
            return
        self.ota_file.close()
        self.ota_file = None
        tmp = self.ota_filename + ".tmp"
        try:
            with open(tmp, "rb") as f:
                content = f.read()
            actual_crc = binascii.crc32(content) & 0xFFFFFFFF
            if str(actual_crc) != expected_crc:
                os.remove(tmp)
                self.ble_send("[ERROR] OTA checksum mismatch: got {} expected {}".format(actual_crc, expected_crc))
                self.ota_active = False
                return
            if len(content) != self.ota_size:
                os.remove(tmp)
                self.ble_send("[ERROR] OTA size mismatch: got {} expected {}".format(len(content), self.ota_size))
                self.ota_active = False
                return
            os.rename(tmp, self.ota_filename)
        except Exception as e:
            self.ble_send("[ERROR] OTA commit failed: {}".format(e))
            self.ota_active = False
            return
        self.ota_active = False
        print("OTA done: {}".format(self.ota_filename))
        self.ble_send("[CHAIR] OTA DONE {}".format(self.ota_filename))

    def _process_ble_health(self):
        now = time.ticks_ms()
        if not self.connections and (
            self.need_advertise
            or time.ticks_diff(now, self.last_advertise_ms) >= BLE_ADVERTISE_RETRY_MS
        ):
            self._advertise()

        if time.ticks_diff(now, self.last_gc_ms) >= GC_INTERVAL_MS:
            gc.collect()
            self.last_gc_ms = now

    def run(self):
        while True:
            self.poll_uart()
            self._process_pending_write()
            self._process_pending()
            self._process_pending_ota()
            self._process_ble_health()
            self.wdt.feed()
            time.sleep_ms(2)


ChairBleBridge().run()
