import pytest

from chair_decode import (
    AirDecode,
    FootRollerDecode,
    HeaterDecode,
    MassageSpeedDecode,
    PackedTimerDecode,
    SevenSegmentRun,
    WidthDecode,
    decode_air,
    decode_foot_roller,
    decode_heater,
    decode_long_status,
    decode_massage_speed,
    decode_packed_timer,
    decode_seven_segment_runs,
    decode_width,
    format_byte,
    format_byte_list,
    format_bytes,
    is_hex_code,
    is_hex_chunk,
    long_known_bit_masks,
    split_bytes,
    unknown_bit_strings,
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
        ("AA00", HeaterDecode(state="off", raw="00000000")),
        ("AA02", HeaterDecode(state="on", raw="00000010")),
        ("AA03", HeaterDecode(state="on", raw="00000011")),
        ("AA04", HeaterDecode(state="off", raw="00000100")),
        ("AAF", HeaterDecode(state="unknown", raw="F")),
        ("", HeaterDecode(state="unknown", raw="-")),
    ],
)
def test_decode_heater_uses_bit_1_of_last_byte(
    data: str, expected: HeaterDecode
) -> None:
    assert decode_heater(data) == expected


def test_decode_long_status_combines_known_fields() -> None:
    decoded = decode_long_status("AA3F6D02")

    assert decoded.last_bytes == "AA 3F 6D 02"
    assert decoded.seven_segment_runs == [
        SevenSegmentRun(start_byte=2, end_byte=3, digits="05", raw="3F 6D")
    ]
    assert decoded.air == AirDecode(
        state="unknown",
        strength="unknown",
        raw_enable="-",
        raw_strength="-",
    )
    assert decoded.massage_speed == MassageSpeedDecode(state="unknown", raw="-")
    assert decoded.width == WidthDecode(state="unknown", raw="-")
    assert decoded.foot_roller == FootRollerDecode(state="unknown", raw="-")
    assert decoded.heater == HeaterDecode(state="on", raw="00000010")


@pytest.mark.parametrize(
    ("minutes", "data", "segments"),
    [
        ("28", "235BF0D70B068180E0", ("5B", "7F")),
        ("05", "273FD0D60F068180E0", ("3F", "6D")),
        ("10", "2706F0D30B068180A0", ("06", "3F")),
        ("15", "2306D0D60B068180E0", ("06", "6D")),
        ("20", "275BF0D30B068180A0", ("5B", "3F")),
        ("19", "2706F0D60B06818060", ("06", "6F")),
        ("19", "2706F0D60F068180E0", ("06", "6F")),
        ("23", "235BF0D40B068180E0", ("5B", "4F")),
        ("23", "275BF0D40F068180E0", ("5B", "4F")),
        ("28", "275BF0D70B068180A0", ("5B", "7F")),
        ("27", "275B70D00F068180E0", ("5B", "07")),
        ("27", "265B70D00B068180E0", ("5B", "07")),
    ],
)
def test_decode_packed_timer_matches_reverse_notes(
    minutes: str, data: str, segments: tuple[str, str]
) -> None:
    assert decode_packed_timer(data) == PackedTimerDecode(
        minutes=minutes,
        tens_segment=segments[0],
        ones_segment=segments[1],
        raw=" ".join(split_bytes(data)[1:4]),
    )


def test_decode_packed_timer_rejects_missing_or_unknown_segments() -> None:
    assert decode_packed_timer("235B") is None
    assert decode_packed_timer("23FFF0D70B068180E0") is None


@pytest.mark.parametrize(
    ("data", "expected"),
    [
        ("235BF0D70B061180E0", FootRollerDecode(state="on", raw="1")),
        ("235BF0D70B068180E0", FootRollerDecode(state="off", raw="8")),
        ("235BF0D70B060180E0", FootRollerDecode(state="off", raw="0")),
        ("235BF0D70B06", FootRollerDecode(state="unknown", raw="-")),
        ("235BF0D70B06G180E0", FootRollerDecode(state="unknown", raw="G1")),
    ],
)
def test_decode_foot_roller_uses_seventh_byte_high_nibble(
    data: str, expected: FootRollerDecode
) -> None:
    assert decode_foot_roller(data) == expected


@pytest.mark.parametrize(
    ("data", "expected"),
    [
        ("235BF0D70B001180E0", MassageSpeedDecode(state="1", raw="00")),
        ("235BF0D70B101180E0", MassageSpeedDecode(state="3", raw="01")),
        ("235BF0D70B301180E0", MassageSpeedDecode(state="5", raw="11")),
        ("235BF0D70B201180E0", MassageSpeedDecode(state="reserved", raw="10")),
        ("235BF0D70B", MassageSpeedDecode(state="unknown", raw="-")),
        ("235BF0D70BG01180E0", MassageSpeedDecode(state="unknown", raw="G0")),
    ],
)
def test_decode_massage_speed_uses_sixth_byte_bits_5_to_4(
    data: str, expected: MassageSpeedDecode
) -> None:
    assert decode_massage_speed(data) == expected


@pytest.mark.parametrize(
    ("data", "expected"),
    [
        (
            "235BF0D700068180E0",
            AirDecode(state="off", strength="1", raw_enable="0", raw_strength="00"),
        ),
        (
            "235BF0D70A068180E0",
            AirDecode(state="on", strength="3", raw_enable="1", raw_strength="01"),
        ),
        (
            "235BF0D70E068180E0",
            AirDecode(state="on", strength="5", raw_enable="1", raw_strength="11"),
        ),
        (
            "235BF0D70C068180E0",
            AirDecode(
                state="on",
                strength="reserved",
                raw_enable="1",
                raw_strength="10",
            ),
        ),
        (
            "235BF0D7",
            AirDecode(
                state="unknown",
                strength="unknown",
                raw_enable="-",
                raw_strength="-",
            ),
        ),
        (
            "235BF0D7GG068180E0",
            AirDecode(
                state="unknown",
                strength="unknown",
                raw_enable="GG",
                raw_strength="GG",
            ),
        ),
    ],
)
def test_decode_air_uses_fifth_byte_bits_3_to_1(
    data: str, expected: AirDecode
) -> None:
    assert decode_air(data) == expected


@pytest.mark.parametrize(
    ("data", "expected"),
    [
        ("235BF0D70B068080E0", WidthDecode(state="wide", raw="00")),
        ("235BF0D70B068180E0", WidthDecode(state="medium", raw="01")),
        ("235BF0D70B068280E0", WidthDecode(state="narrow", raw="10")),
        ("235BF0D70B068380E0", WidthDecode(state="reserved", raw="11")),
        ("235BF0D70B06", WidthDecode(state="unknown", raw="-")),
        ("235BF0D70B06G180E0", WidthDecode(state="unknown", raw="G1")),
    ],
)
def test_decode_width_uses_seventh_byte_low_bits(
    data: str, expected: WidthDecode
) -> None:
    assert decode_width(data) == expected


def test_long_known_bit_masks_include_decoded_fields() -> None:
    assert long_known_bit_masks("235BF0D70B068180E0") == [
        0x00,
        0xFF,
        0xF0,
        0x0F,
        0x0E,
        0x30,
        0xF3,
        0x00,
        0x02,
    ]


def test_unknown_bit_strings_masks_known_bits() -> None:
    masks = long_known_bit_masks("235BF0D70B068180E0")
    assert unknown_bit_strings("235BF0D70B068180E0", masks) == [
        "00100011",
        "........",
        "....0000",
        "1101....",
        "0000...1",
        "00..0110",
        "....00..",
        "10000000",
        "111000.0",
    ]
