"""
Experimental MicroPython firmware for the ESP32 chair BLE bridge.

This is a first-pass port of src/main.cpp. It intentionally does not implement
BLE pairing/passkey security yet. Keep the BLE text protocol compatible with
src/chair_monitor.py:

    [Y] <hex>      chair -> remote status line
    [W] <hex>      remote -> chair command line
    [SENT] <hex>   command sent by this bridge
    [ERR] <text>   command validation error
"""

from micropython import const
from machine import Pin, UART
import bluetooth
import time

from bridge_core import (
    BLE_COMMAND_ERROR,
    BLE_COMMAND_IGNORE,
    BLE_COMMAND_SEND,
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
BLE_MTU = const(256)


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
        self.pending_command = None

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
        self.ble.gatts_write(self.data_handle, b"")
        self._advertise()

        print("BLE ready: {}".format(DEVICE_NAME))
        print("MicroPython firmware is experimental and uses no BLE passkey")

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
        payload = advertising_payload(DEVICE_NAME)
        self.ble.gap_advertise(100_000, adv_data=payload)

    def _on_ble_irq(self, event, data):
        if event == _IRQ_CENTRAL_CONNECT:
            conn_handle, _, _ = data
            self.connections.add(conn_handle)
            print("Client connected")
        elif event == _IRQ_CENTRAL_DISCONNECT:
            conn_handle, _, _ = data
            self.connections.discard(conn_handle)
            print("Client disconnected")
            self._advertise()
        elif event == _IRQ_GATTS_WRITE:
            conn_handle, value_handle = data
            if value_handle == self.cmd_handle:
                self._handle_ble_write(self.ble.gatts_read(value_handle))

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

    def ble_send(self, message):
        data = message.encode()
        self.ble.gatts_write(self.data_handle, data)
        for conn_handle in list(self.connections):
            try:
                self.ble.gatts_notify(conn_handle, self.data_handle, data)
            except OSError:
                self.connections.discard(conn_handle)
        print(message)

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

    def run(self):
        while True:
            self.poll_uart()
            self._process_pending()
            time.sleep_ms(2)


ChairBleBridge().run()
