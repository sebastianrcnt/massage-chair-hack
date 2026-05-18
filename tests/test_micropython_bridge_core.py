from bridge_core import (
    BLE_COMMAND_ERROR,
    BLE_COMMAND_IGNORE,
    BLE_COMMAND_SEND,
    FRAME_OVERLONG_ERROR,
    FrameBuffer,
    advertising_payload,
    decode_line,
    is_hex_command,
    parse_ble_write,
)


def test_advertising_payload_contains_flags_and_name() -> None:
    assert advertising_payload("ChairSniffer") == bytearray(
        b"\x02\x01\x06\x0d\x09ChairSniffer"
    )


def test_advertising_payload_fits_legacy_ble_advertising_limit() -> None:
    assert len(advertising_payload("ChairSniffer")) <= 31


def test_is_hex_command_requires_four_hex_digits() -> None:
    assert is_hex_command("0303")
    assert is_hex_command("abCD")
    assert not is_hex_command("303")
    assert not is_hex_command("03030")
    assert not is_hex_command("03G3")


def test_parse_ble_write_ignores_blank_commands() -> None:
    assert parse_ble_write(b" \r\n") == (BLE_COMMAND_IGNORE, "")


def test_parse_ble_write_normalizes_valid_send_commands() -> None:
    assert parse_ble_write(b" SEND 03ab\n") == (BLE_COMMAND_SEND, "03AB")


def test_parse_ble_write_rejects_invalid_utf8() -> None:
    assert parse_ble_write(b"\xff") == (
        BLE_COMMAND_ERROR,
        "[ERROR] Command must be UTF-8 text",
    )


def test_parse_ble_write_rejects_unknown_verbs() -> None:
    assert parse_ble_write(b"PIN 123456") == (
        BLE_COMMAND_ERROR,
        "[ERROR] Unknown command. Supported: SEND XXXX, OTA BEGIN/DATA/COMMIT/REBOOT",
    )


def test_parse_ble_write_rejects_non_hex_send_payload() -> None:
    assert parse_ble_write(b"SEND zzzz") == (
        BLE_COMMAND_ERROR,
        "[ERROR] SEND requires 4 hex digits",
    )


def test_decode_line_replaces_non_text_bytes() -> None:
    assert decode_line(bytearray(b"[Y] \xffA\x00")) == "[Y] ?A?"


def test_frame_buffer_emits_prefixed_frame_between_start_and_carriage_return() -> None:
    frames = FrameBuffer(b"[Y] ")
    output: list[str] = []
    for value in b"~0315\r":
        output.extend(frames.append(value))

    assert output == ["[Y] 0315"]


def test_frame_buffer_flushes_partial_frame_on_new_start_marker() -> None:
    frames = FrameBuffer(b"[W] ")
    output: list[str] = []
    for value in b"~0303~0404\r":
        output.extend(frames.append(value))

    assert output == ["[W] 0303", "[W] 0404"]


def test_frame_buffer_drops_overlong_frame_and_recovers() -> None:
    frames = FrameBuffer(b"[Y] ", max_len=6)
    output: list[str] = []
    for value in b"~1234567~89\r":
        output.extend(frames.append(value))

    assert output == [FRAME_OVERLONG_ERROR, "[Y] 89"]
