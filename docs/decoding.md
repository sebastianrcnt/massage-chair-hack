# Chair Status Decoding

This document tracks the current reverse-engineered mapping for chair status frames.
Anything marked as tentative is based on observed samples and may need correction as more
captures are collected.

## Frame Sources

The ESP32 bridge forwards two serial lines over BLE:

| Prefix | Source | Meaning |
| --- | --- | --- |
| `[Y]` | Chair status line, yellow wire | Chair-to-remote status broadcast |
| `[W]` | Remote command line, white wire | Remote-to-chair command sniffing |
| `[SENT]` | BLE monitor app | Command sent by this tool to the chair |

The monitor currently classifies `[Y]` payloads by hex string length:

| Payload length | Monitor treatment |
| --- | --- |
| `<= 5` hex chars | Command ACK / short response |
| `6..12` hex chars | Short status |
| `> 12` hex chars | Long status |

Commands are still entered as 4 hex chars. Status display can be toggled between binary,
octal, and hex in the TUI.

## 7-Segment Table

The timer display uses the standard 7-segment byte mapping below.

| Digit | Segment byte |
| --- | --- |
| `0` | `3F` |
| `1` | `06` |
| `2` | `5B` |
| `3` | `4F` |
| `4` | `66` |
| `5` | `6D` |
| `6` | `7D` |
| `7` | `07` |
| `8` | `7F` |
| `9` | `6F` |

## Long Status

Long status is decoded byte-by-byte. Byte positions below are 1-based.

| Field | Bytes / bits | Decode rule | Status |
| --- | --- | --- | --- |
| Timer tens digit | Byte 2 | Direct 7-segment byte | Confirmed by samples |
| Timer ones digit | Byte 3 high nibble + byte 4 low nibble | `ones_segment = ((B4 & 0x0F) << 4) \| ((B3 & 0xF0) >> 4)` | Confirmed by samples |
| Foot roller | Byte 7 high nibble | `on` when the first hex digit of byte 7 is `1`; otherwise `off` | Tentative |
| Heater | Last byte bit 1 | `on` when `(last_byte & 0x02) != 0`; otherwise `off` | Tentative |

Timer example:

```text
28: 23 5B F0 D7 0B 06 81 80 E0
       ^^ ^^ ^^
       B2 B3 B4
```

`B2 = 5B` decodes to digit `2`.

The ones digit is packed across `B3` and `B4`:

```text
((D7 & 0F) << 4) | ((F0 & F0) >> 4) = 7F
```

`7F` decodes to digit `8`, so the timer is `28` minutes.

### Observed Timer Samples

These samples are covered by `tests/test_chair_decode.py`.

| Timer | Long status sample |
| --- | --- |
| `28` | `23 5B F0 D7 0B 06 81 80 E0` |
| `05` | `27 3F D0 D6 0F 06 81 80 E0` |
| `10` | `27 06 F0 D3 0B 06 81 80 A0` |
| `15` | `23 06 D0 D6 0B 06 81 80 E0` |
| `20` | `27 5B F0 D3 0B 06 81 80 A0` |
| `19` | `27 06 F0 D6 0B 06 81 80 60` |
| `19` | `27 06 F0 D6 0F 06 81 80 E0` |
| `23` | `23 5B F0 D4 0B 06 81 80 E0` |
| `23` | `27 5B F0 D4 0F 06 81 80 E0` |
| `28` | `27 5B F0 D7 0B 06 81 80 A0` |
| `27` | `27 5B 70 D0 0F 06 81 80 E0` |
| `27` | `26 5B 70 D0 0B 06 81 80 E0` |

## Short Status

Short status frames are displayed and diffed by the TUI, but their field-level mapping is
not known yet. The monitor currently treats any `[Y]` payload of `6..12` hex chars as short
status.

Known examples from live debugging:

| Short status | Notes |
| --- | --- |
| `03 15 13` | Previously observed while timer showed `05`; exact field meaning unknown |
| `03 15 06` | Previously observed while timer showed `04`; exact field meaning unknown |
| `03 15 15` | Previously observed while timer showed `09`; exact field meaning unknown |
| `00 06 15` | Previously observed while timer showed `10`; exact field meaning unknown |

These short-status timer guesses were superseded by the packed long-status timer mapping.

## Unknowns

- Most long-status bytes and bit flags are still unmapped.
- Short status has no confirmed field-level mapping yet.
- Foot roller and heater rules should be validated against more captures.
- Some bits in the timer sample bytes vary while the displayed timer stays the same; those
  bits are likely unrelated flags, but their meanings are unknown.
