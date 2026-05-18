import struct


MAX_FRAME_LEN = 96

ADV_TYPE_FLAGS = 0x01
ADV_TYPE_NAME = 0x09
ADV_TYPE_UUID128_COMPLETE = 0x07

BLE_COMMAND_IGNORE = "ignore"
BLE_COMMAND_ERROR = "error"
BLE_COMMAND_SEND = "send"
BLE_OTA_BEGIN = "ota_begin"
BLE_OTA_DATA = "ota_data"
BLE_OTA_COMMIT = "ota_commit"
BLE_OTA_REBOOT = "ota_reboot"

FRAME_OVERLONG_ERROR = "[ERROR] Dropped overlong frame"


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
        text = value.decode().strip()
    except UnicodeError:
        return BLE_COMMAND_ERROR, "[ERROR] Command must be UTF-8 text"

    if not text:
        return BLE_COMMAND_IGNORE, ""

    parts = text.split(None, 1)
    verb = parts[0].upper()
    arg = parts[1].strip() if len(parts) > 1 else ""

    if verb == "SEND":
        if not is_hex_command(arg):
            return BLE_COMMAND_ERROR, "[ERROR] SEND requires 4 hex digits"
        return BLE_COMMAND_SEND, arg.upper()

    if verb == "OTA":
        parts2 = arg.split(None, 1)
        subcmd = parts2[0].upper() if parts2 else ""
        subarg = parts2[1] if len(parts2) > 1 else ""
        if subcmd == "BEGIN":
            return BLE_OTA_BEGIN, subarg
        if subcmd == "DATA":
            return BLE_OTA_DATA, subarg
        if subcmd == "COMMIT":
            return BLE_OTA_COMMIT, subarg
        if subcmd == "REBOOT":
            return BLE_OTA_REBOOT, ""
        return BLE_COMMAND_ERROR, "[ERROR] Unknown OTA subcommand. Use: BEGIN DATA COMMIT REBOOT"

    return BLE_COMMAND_ERROR, "[ERROR] Unknown command. Supported: SEND XXXX, OTA BEGIN/DATA/COMMIT/REBOOT"


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
