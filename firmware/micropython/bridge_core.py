import struct


MAX_FRAME_LEN = 96

ADV_TYPE_FLAGS = 0x01
ADV_TYPE_NAME = 0x09
ADV_TYPE_UUID128_COMPLETE = 0x07

BLE_COMMAND_IGNORE = "ignore"
BLE_COMMAND_ERROR = "error"
BLE_COMMAND_SEND = "send"

FRAME_OVERLONG_ERROR = "[ERR] Dropped overlong frame"


def advertising_payload(name):
    payload = bytearray()

    def append(adv_type, value):
        payload.extend(struct.pack("BB", len(value) + 1, adv_type))
        payload.extend(value)

    append(ADV_TYPE_FLAGS, b"\x06")
    append(ADV_TYPE_NAME, name.encode())
    return payload


def advertising_payload_with_service(uuid):
    payload = bytearray()

    def append(adv_type, value):
        payload.extend(struct.pack("BB", len(value) + 1, adv_type))
        payload.extend(value)

    append(ADV_TYPE_FLAGS, b"\x06")
    append(ADV_TYPE_UUID128_COMPLETE, bytes(reversed(bytes.fromhex(uuid.replace("-", "")))))
    return payload


def scan_response_payload(name):
    payload = bytearray()
    value = name.encode()
    payload.extend(struct.pack("BB", len(value) + 1, ADV_TYPE_NAME))
    payload.extend(value)
    return payload


def is_hex_command(value):
    if len(value) != 4:
        return False
    return all(char in "0123456789ABCDEFabcdef" for char in value)


def parse_ble_write(value):
    try:
        command = value.decode().strip()
    except UnicodeError:
        return BLE_COMMAND_ERROR, "[ERR] Command must be UTF-8 text"

    if not command:
        return BLE_COMMAND_IGNORE, ""
    if command.startswith("PIN:"):
        return BLE_COMMAND_ERROR, "[ERR] PIN is not supported by MicroPython firmware"
    if not is_hex_command(command):
        return BLE_COMMAND_ERROR, "[ERR] Invalid command. Use 4 hex digits"
    return BLE_COMMAND_SEND, command.upper()


def decode_line(line):
    try:
        return line.decode()
    except UnicodeError:
        return "".join(chr(value) if 32 <= value <= 126 else "?" for value in line)


class FrameBuffer:
    def __init__(self, prefix, max_len=MAX_FRAME_LEN):
        self.prefix = prefix
        self.max_len = max_len
        self.line = bytearray()
        self.dropping = False

    def append(self, value):
        if value == ord("~"):
            self.dropping = False
            messages = self.flush()
            self.line[:] = self.prefix
            return messages

        if value == ord("\r"):
            self.dropping = False
            messages = self.flush()
            self.line = bytearray()
            return messages

        if self.dropping:
            return []

        if len(self.line) < self.max_len:
            self.line.append(value)
            return []

        self.line = bytearray()
        self.dropping = True
        return [FRAME_OVERLONG_ERROR]

    def flush(self):
        if not self.line:
            return []
        return [decode_line(self.line)]
