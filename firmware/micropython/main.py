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
import struct
import time


# Pin configuration.
RXD_STATUS = const(16)  # Yellow wire: chair -> remote status broadcast.
TXD_STATUS = const(17)
RXD_CMD = const(13)  # White wire RX: remote -> chair command sniffing.
TXD_CMD = const(14)  # White wire TX: ESP32 -> chair command injection.
LED_PIN = const(2)

BAUD_RATE = const(9600)
MAX_FRAME_LEN = const(96)

DEVICE_NAME = "ChairSniffer"
SERVICE_UUID = bluetooth.UUID("12345678-1234-1234-1234-123456789abc")
CHAR_DATA_UUID = bluetooth.UUID("12345678-1234-1234-1234-123456789abd")
CHAR_CMD_UUID = bluetooth.UUID("12345678-1234-1234-1234-123456789abe")

_IRQ_CENTRAL_CONNECT = const(1)
_IRQ_CENTRAL_DISCONNECT = const(2)
_IRQ_GATTS_WRITE = const(3)

_FLAG_READ = const(0x0002)
_FLAG_WRITE = const(0x0008)
_FLAG_NOTIFY = const(0x0010)

_ADV_TYPE_FLAGS = const(0x01)
_ADV_TYPE_NAME = const(0x09)
_ADV_TYPE_UUID128_COMPLETE = const(0x07)


def advertising_payload(name, services):
    payload = bytearray()

    def append(adv_type, value):
        payload.extend(struct.pack("BB", len(value) + 1, adv_type))
        payload.extend(value)

    append(_ADV_TYPE_FLAGS, b"\x06")
    append(_ADV_TYPE_NAME, name.encode())
    for uuid in services:
        append(_ADV_TYPE_UUID128_COMPLETE, bytes(uuid))
    return payload


def is_hex_command(value):
    if len(value) != 4:
        return False
    return all(char in "0123456789ABCDEFabcdef" for char in value)


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

        self.status_line = bytearray()
        self.command_line = bytearray()
        self.connections = set()

        self.ble = bluetooth.BLE()
        self.ble.active(True)
        self.ble.irq(self._on_ble_irq)

        data_char = (CHAR_DATA_UUID, _FLAG_READ | _FLAG_NOTIFY)
        cmd_char = (CHAR_CMD_UUID, _FLAG_WRITE)
        service = (SERVICE_UUID, (data_char, cmd_char))
        ((self.data_handle, self.cmd_handle),) = self.ble.gatts_register_services(
            (service,)
        )
        self.ble.gatts_write(self.data_handle, b"")
        self._advertise()

        print("BLE ready: {}".format(DEVICE_NAME))
        print("MicroPython firmware is experimental and uses no BLE passkey")

    def _open_command_rx(self):
        Pin(TXD_CMD, Pin.IN)
        return UART(
            1,
            baudrate=BAUD_RATE,
            bits=8,
            parity=None,
            stop=1,
            rx=Pin(RXD_CMD),
            tx=None,
        )

    def _advertise(self):
        payload = advertising_payload(DEVICE_NAME, [SERVICE_UUID])
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
        try:
            command = value.decode().strip()
        except UnicodeError:
            self.ble_send("[ERR] Command must be UTF-8 text")
            return

        if not command:
            return

        print("BLE received: {}".format(command))
        if command.startswith("PIN:"):
            self.ble_send("[ERR] PIN is not supported by MicroPython firmware")
            return
        if not is_hex_command(command):
            self.ble_send("[ERR] Invalid command. Use 4 hex digits")
            return

        self.send_to_chair(command.upper())

    def ble_send(self, message):
        data = message.encode()
        self.ble.gatts_write(self.data_handle, data)
        for conn_handle in self.connections:
            self.ble.gatts_notify(conn_handle, self.data_handle, data)
        print(message)

    def send_to_chair(self, command):
        self.command_uart.deinit()
        tx_pin = Pin(TXD_CMD, Pin.OUT)
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
        self.ble_send("[SENT] " + command)

    def _send_line(self, line):
        if not line:
            return
        self.led.on()
        try:
            message = line.decode()
        except UnicodeError:
            message = "".join(chr(value) if 32 <= value <= 126 else "?" for value in line)
        self.ble_send(message)
        self.led.off()

    def _append_frame_byte(self, line, prefix, value):
        if value == ord("~"):
            self._send_line(line)
            line[:] = prefix
            return
        if value == ord("\r"):
            self._send_line(line)
            line.clear()
            return
        if len(line) < MAX_FRAME_LEN:
            line.append(value)
        else:
            self.ble_send("[ERR] Dropped overlong frame")
            line.clear()

    def poll_uart(self):
        while self.status_uart.any():
            value = self.status_uart.read(1)[0]
            self._append_frame_byte(self.status_line, b"[Y] ", value)

        while self.command_uart.any():
            value = self.command_uart.read(1)[0]
            self._append_frame_byte(self.command_line, b"[W] ", value)

    def run(self):
        while True:
            self.poll_uart()
            time.sleep_ms(2)


ChairBleBridge().run()
