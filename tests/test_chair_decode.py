import pytest

from chair_decode import (
    FootRollerDecode,
    HeaterDecode,
    PackedTimerDecode,
    SevenSegmentRun,
    decode_foot_roller,
    decode_heater,
    decode_long_status,
    decode_packed_timer,
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
