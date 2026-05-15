import pytest

from chair_decode import (
    HeaterDecode,
    SevenSegmentRun,
    decode_heater,
    decode_long_status,
    decode_seven_segment_runs,
    format_byte,
    format_byte_list,
    format_bytes,
    is_hex_code,
    is_hex_chunk,
    split_bytes,
)


def test_split_bytes_keeps_trailing_nibble() -> None:
    assert split_bytes("0315D") == ["03", "15", "D"]


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("03", "00000011"),
        ("15", "00010101"),
        ("D", "00001101"),
    ],
)
def test_format_byte_binary(value: str, expected: str) -> None:
    assert format_byte(value, "bin") == expected


def test_format_bytes_octal() -> None:
    assert format_bytes("0315D", "oct") == "0o003 0o025 0o015"


def test_format_bytes_hex() -> None:
    assert format_bytes("0315D", "hex") == "03 15 0D"


def test_format_byte_list_octal() -> None:
    assert format_byte_list(["AA", "3F", "6D", "02"], "oct") == (
        "0o252 0o077 0o155 0o002"
    )


def test_format_byte_leaves_non_hex_chunks_unchanged() -> None:
    assert format_byte("GG", "bin") == "GG"
    assert format_byte("123", "oct") == "123"


def test_hex_validation_helpers() -> None:
    assert is_hex_code("03AF", 4)
    assert not is_hex_code("03A", 4)
    assert not is_hex_code("03AG", 4)

    assert is_hex_chunk("F")
    assert is_hex_chunk("0F")
    assert not is_hex_chunk("")
    assert not is_hex_chunk("100")
    assert not is_hex_chunk("0G")


def test_decode_seven_segment_runs_requires_two_consecutive_bytes() -> None:
    assert decode_seven_segment_runs("3F") == []
    assert decode_seven_segment_runs("3F6D") == [
        SevenSegmentRun(start_byte=1, end_byte=2, digits="05", raw="3F 6D")
    ]


def test_decode_seven_segment_runs_scans_later_candidates() -> None:
    assert decode_seven_segment_runs("AA3F6D00") == [
        SevenSegmentRun(start_byte=2, end_byte=3, digits="05", raw="3F 6D")
    ]


@pytest.mark.parametrize(
    ("data", "expected"),
    [
        ("AA0", HeaterDecode(state="off", raw="0")),
        ("AA2", HeaterDecode(state="on", raw="2")),
        ("AAF", HeaterDecode(state="unknown", raw="F")),
        ("", HeaterDecode(state="unknown", raw="-")),
    ],
)
def test_decode_heater_uses_last_hex_digit(data: str, expected: HeaterDecode) -> None:
    assert decode_heater(data) == expected


def test_decode_long_status_combines_known_fields() -> None:
    decoded = decode_long_status("AA3F6D02")

    assert decoded.last_bytes == "AA 3F 6D 02"
    assert decoded.seven_segment_runs == [
        SevenSegmentRun(start_byte=2, end_byte=3, digits="05", raw="3F 6D")
    ]
    assert decoded.heater == HeaterDecode(state="on", raw="2")
