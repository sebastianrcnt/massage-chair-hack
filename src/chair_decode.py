from dataclasses import dataclass
from typing import Literal

DisplayMode = Literal["bin", "oct", "hex"]
HeaterState = Literal["on", "off", "unknown"]
MassageSpeedState = Literal["1", "3", "5", "reserved", "unknown"]
WidthState = Literal["wide", "medium", "narrow", "reserved", "unknown"]
AirStrengthState = Literal["1", "3", "5", "reserved", "unknown"]

SEVEN_SEG_DIGITS = {
    "3F": "0",
    "06": "1",
    "5B": "2",
    "4F": "3",
    "66": "4",
    "6D": "5",
    "7D": "6",
    "07": "7",
    "7F": "8",
    "6F": "9",
}


@dataclass(frozen=True)
class SevenSegmentRun:
    start_byte: int
    end_byte: int
    digits: str
    raw: str


@dataclass(frozen=True)
class HeaterDecode:
    state: HeaterState
    raw: str


@dataclass(frozen=True)
class FootRollerDecode:
    state: HeaterState
    raw: str


@dataclass(frozen=True)
class MassageSpeedDecode:
    state: MassageSpeedState
    raw: str


@dataclass(frozen=True)
class WidthDecode:
    state: WidthState
    raw: str


@dataclass(frozen=True)
class AirDecode:
    state: HeaterState
    strength: AirStrengthState
    raw_enable: str
    raw_strength: str


@dataclass(frozen=True)
class PackedTimerDecode:
    minutes: str
    tens_segment: str
    ones_segment: str
    raw: str


@dataclass(frozen=True)
class LongStatusDecode:
    last_bytes: str
    seven_segment_runs: list[SevenSegmentRun]
    packed_timer: PackedTimerDecode | None
    air: AirDecode
    massage_speed: MassageSpeedDecode
    width: WidthDecode
    foot_roller: FootRollerDecode
    heater: HeaterDecode


def split_bytes(data: str) -> list[str]:
    return [data[i:i + 2] for i in range(0, len(data), 2)]


def is_hex_code(value: str, length: int) -> bool:
    return len(value) == length and all(c in "0123456789ABCDEF" for c in value)


def is_hex_chunk(value: str) -> bool:
    return 0 < len(value) <= 2 and all(c in "0123456789ABCDEF" for c in value)


def format_byte(byte: str, display_mode: DisplayMode) -> str:
    if not is_hex_chunk(byte):
        return byte

    value = int(byte, 16)
    if display_mode == "hex":
        return f"{value:02X}"
    if display_mode == "oct":
        return f"0o{value:03o}"
    return f"{value:08b}"


def format_bytes(data: str, display_mode: DisplayMode) -> str:
    return " ".join(format_byte(byte, display_mode) for byte in split_bytes(data))


def format_byte_list(bytes_: list[str], display_mode: DisplayMode) -> str:
    return " ".join(format_byte(byte, display_mode) for byte in bytes_)


def long_known_bit_masks(data: str) -> list[int]:
    bytes_ = split_bytes(data)
    masks = [0] * len(bytes_)

    if len(bytes_) > 1:
        masks[1] |= 0xFF  # Timer tens segment.
    if len(bytes_) > 2:
        masks[2] |= 0xF0  # Timer ones low nibble.
    if len(bytes_) > 3:
        masks[3] |= 0x0F  # Timer ones high nibble.
    if len(bytes_) > 4:
        masks[4] |= 0x70  # Air strength + on/off.
    if len(bytes_) > 5:
        masks[5] |= 0x30  # Massage speed.
    if len(bytes_) > 6:
        masks[6] |= 0xF3  # Foot roller high nibble + width low bits.
    if masks:
        masks[-1] |= 0x02  # Heater.

    return masks


def unknown_bit_strings(data: str, known_masks: list[int]) -> list[str]:
    result: list[str] = []
    for index, byte in enumerate(split_bytes(data)):
        if not is_hex_chunk(byte):
            result.append(byte)
            continue

        mask = known_masks[index] if index < len(known_masks) else 0
        value = int(byte, 16)
        result.append(
            "".join(
                "." if mask & (1 << bit_index) else str((value >> bit_index) & 1)
                for bit_index in range(7, -1, -1)
            )
        )
    return result


def decode_seven_segment_runs(data: str) -> list[SevenSegmentRun]:
    runs: list[SevenSegmentRun] = []
    bytes_ = split_bytes(data)
    for start in range(0, max(0, len(bytes_) - 1)):
        digits = ""
        raw: list[str] = []
        for byte in bytes_[start:]:
            digit = SEVEN_SEG_DIGITS.get(byte)
            if digit is None:
                break

            digits += digit
            raw.append(byte)

        if len(digits) >= 2:
            runs.append(
                SevenSegmentRun(
                    start_byte=start + 1,
                    end_byte=start + len(raw),
                    digits=digits,
                    raw=" ".join(raw),
                )
            )

    return runs


def decode_heater(data: str) -> HeaterDecode:
    bytes_ = split_bytes(data)
    if not bytes_:
        return HeaterDecode(state="unknown", raw="-")

    last_byte = bytes_[-1]
    if not is_hex_code(last_byte, 2):
        return HeaterDecode(state="unknown", raw=last_byte)

    value = int(last_byte, 16)
    state: HeaterState = "on" if value & 0x02 else "off"
    return HeaterDecode(state=state, raw=f"{value:08b}")


def decode_packed_timer(data: str) -> PackedTimerDecode | None:
    bytes_ = split_bytes(data)
    if len(bytes_) < 4:
        return None

    tens_segment = bytes_[1]
    if not is_hex_code(tens_segment, 2):
        return None

    byte_2 = bytes_[2]
    byte_3 = bytes_[3]
    if not is_hex_code(byte_2, 2) or not is_hex_code(byte_3, 2):
        return None

    ones_segment_value = ((int(byte_3, 16) & 0x0F) << 4) | (
        (int(byte_2, 16) & 0xF0) >> 4
    )
    ones_segment = f"{ones_segment_value:02X}"

    tens = SEVEN_SEG_DIGITS.get(tens_segment)
    ones = SEVEN_SEG_DIGITS.get(ones_segment)
    if tens is None or ones is None:
        return None

    return PackedTimerDecode(
        minutes=f"{tens}{ones}",
        tens_segment=tens_segment,
        ones_segment=ones_segment,
        raw=" ".join(bytes_[1:4]),
    )


def decode_foot_roller(data: str) -> FootRollerDecode:
    bytes_ = split_bytes(data)
    if len(bytes_) < 7:
        return FootRollerDecode(state="unknown", raw="-")

    byte_7 = bytes_[6]
    if not is_hex_code(byte_7, 2):
        return FootRollerDecode(state="unknown", raw=byte_7)

    high_nibble = byte_7[0]
    if high_nibble == "1":
        return FootRollerDecode(state="on", raw=high_nibble)
    return FootRollerDecode(state="off", raw=high_nibble)


def decode_massage_speed(data: str) -> MassageSpeedDecode:
    bytes_ = split_bytes(data)
    if len(bytes_) < 6:
        return MassageSpeedDecode(state="unknown", raw="-")

    byte_6 = bytes_[5]
    if not is_hex_code(byte_6, 2):
        return MassageSpeedDecode(state="unknown", raw=byte_6)

    speed_bits = (int(byte_6, 16) & 0x30) >> 4
    speed = {
        0b00: "1",
        0b01: "3",
        0b11: "5",
    }.get(speed_bits, "reserved")

    return MassageSpeedDecode(state=speed, raw=f"{speed_bits:02b}")


def decode_air(data: str) -> AirDecode:
    bytes_ = split_bytes(data)
    if len(bytes_) < 5:
        return AirDecode(
            state="unknown",
            strength="unknown",
            raw_enable="-",
            raw_strength="-",
        )

    byte_5 = bytes_[4]
    if not is_hex_code(byte_5, 2):
        return AirDecode(
            state="unknown",
            strength="unknown",
            raw_enable=byte_5,
            raw_strength=byte_5,
        )

    value = int(byte_5, 16)
    enabled = "on" if value & 0x10 else "off"
    strength_bits = (value & 0x60) >> 5
    strength = {
        0b00: "1",
        0b01: "3",
        0b11: "5",
    }.get(strength_bits, "reserved")

    return AirDecode(
        state=enabled,
        strength=strength,
        raw_enable=str((value & 0x10) >> 4),
        raw_strength=f"{strength_bits:02b}",
    )


def decode_width(data: str) -> WidthDecode:
    bytes_ = split_bytes(data)
    if len(bytes_) < 7:
        return WidthDecode(state="unknown", raw="-")

    byte_7 = bytes_[6]
    if not is_hex_code(byte_7, 2):
        return WidthDecode(state="unknown", raw=byte_7)

    width_bits = int(byte_7, 16) & 0x03
    width = {
        0b00: "wide",
        0b01: "medium",
        0b10: "narrow",
    }.get(width_bits, "reserved")

    return WidthDecode(state=width, raw=f"{width_bits:02b}")


def decode_long_status(data: str) -> LongStatusDecode:
    bytes_ = split_bytes(data)
    last_bytes = " ".join(bytes_[-4:]) if bytes_ else "-"
    return LongStatusDecode(
        last_bytes=last_bytes,
        seven_segment_runs=decode_seven_segment_runs(data),
        packed_timer=decode_packed_timer(data),
        air=decode_air(data),
        massage_speed=decode_massage_speed(data),
        width=decode_width(data),
        foot_roller=decode_foot_roller(data),
        heater=decode_heater(data),
    )
