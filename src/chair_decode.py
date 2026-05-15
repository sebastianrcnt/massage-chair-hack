from dataclasses import dataclass
from typing import Literal

DisplayMode = Literal["bin", "oct", "hex"]
HeaterState = Literal["on", "off", "unknown"]

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
class LongStatusDecode:
    last_bytes: str
    seven_segment_runs: list[SevenSegmentRun]
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
    if not data:
        return HeaterDecode(state="unknown", raw="-")

    value = data[-1]
    if value == "0":
        return HeaterDecode(state="off", raw=value)
    if value == "2":
        return HeaterDecode(state="on", raw=value)
    return HeaterDecode(state="unknown", raw=value)


def decode_long_status(data: str) -> LongStatusDecode:
    bytes_ = split_bytes(data)
    last_bytes = " ".join(bytes_[-4:]) if bytes_ else "-"
    return LongStatusDecode(
        last_bytes=last_bytes,
        seven_segment_runs=decode_seven_segment_runs(data),
        heater=decode_heater(data),
    )
