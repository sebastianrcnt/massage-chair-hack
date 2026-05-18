# Chair Status Decoding

This document tracks the current reverse-engineered status model. Byte positions
are 0-based. Byte labels use uppercase `B`; bit labels use lowercase `b`. For
example, `B4[b6:b5]` means bits 6 through 5 of byte 4, where `b7` is the most
significant bit.

## Source Of Truth

`spec/chair.yml` is the source of truth for command codes, status bit maps,
known-bit masks, blink indicators, and decode constants. Generated files are
produced from it:

- [Generated command table](generated/commands.md)
- [Generated long status map](generated/long_status_map.md)
- [Generated short status map](generated/short_status_map.md)
- [Generated blink indicators](generated/blink_indicators.md)
- [Generated known masks](generated/masks.md)
- `ChairSniffer/ChairSniffer/Generated/ChairSpec.generated.swift`

Regenerate after changing the YAML:

```sh
uv run tools/generate_chair_spec.py
```

Check that generated files are current:

```sh
uv run tools/generate_chair_spec.py --check
```

## Frame Sources

| Prefix | Source | Meaning |
| --- | --- | --- |
| `[CHAIR]` | Chair status line, yellow wire | Chair-to-remote status broadcast |
| `[REMOTE]` | Remote command line, white wire | Remote-to-chair command sniffing |
| `[TRANSMITTED]` | BLE monitor app | Command transmitted by this tool to the chair |
| `[ERROR]` | Bridge firmware | Error message |

**App -> ESP32 write format:** `SEND XXXX` where `XXXX` is a 4-digit hex command.

## Commands And ACKs

Use the generated command table:

- [Commands](generated/commands.md)

Release `0355` appears to be shared across multiple buttons, but speed,
stretching auto mode, manual mode, and foot roller have their own release codes.

## Frame Classification

The monitor currently classifies `[Y]` payloads by hex string length.

| Payload length | Monitor treatment |
| --- | --- |
| `<= 5` hex chars | Command ACK / short response |
| `6..12` hex chars | Short status |
| `> 12` hex chars | Long status |

## Long Status

Known long-status samples are currently 9 bytes, but decoding code treats the
heater as the last byte so it can tolerate length changes.

Use the generated long-status map and masks:

- [Long status map](generated/long_status_map.md)
- [Known masks](generated/masks.md)

## Blink Indicators

Several status fields are blink indicators rather than stable state bits. UI
should debounce them by treating any bit observed in its active blink phase
within a recent window as active/current.

Use the generated blink table:

- [Blink indicators](generated/blink_indicators.md)

Roller position is spread across `B0[b2:b0]` and `B8[b7:b5]`. The bits are
normally `1`; when the roller passes a position, that bit blinks `0`/`1` about
every 0.5 s. Unlike B7 air-area bits, roller position should generally be
interpreted as a single current/passing position.

`B7` contains air-area blink indicators. These bits are normally `0`; when an
area is active, the corresponding bit blinks high about every 0.5 s. Multiple
air-area bits can blink at the same time.

## Manual Mode

`B4[b4]` indicates the broad mode: `0` is manual mode and `1` is auto /
non-manual mode. Six bits across `B3[b7:b6]` and `B4[b3:b0]` each correspond to
one manual massage technique. Each bit defaults to `1`; while the matching
technique is active, the bit blinks `0`/`1`.

The original remote/manual-mode names appear to be misleading, so the app uses
observed-motion names instead. The exact names and bit assignments live in:

- [Blink indicators](generated/blink_indicators.md)

Overlaps to validate:

- No known long-status bit currently has two intentional meanings. Re-check the
  generated maps when adding or changing bit mappings.

## Packed Timer Detail

The timer display is packed as two 7-segment bytes.

| Timer digit | Source |
| --- | --- |
| Tens | `B1[b7:b0]` |
| Ones high nibble | `B3[b3:b0]` |
| Ones low nibble | `B2[b7:b4]` |

Formula:

```text
tens_segment = B1
ones_segment = ((B3 & 0x0F) << 4) | ((B2 & 0xF0) >> 4)
timer = seven_segment[tens_segment] + seven_segment[ones_segment]
```

Example:

```text
28: 23 5B F0 D7 0B 06 81 80 E0
       ^^ ^^ ^^
       B1 B2 B3

tens_segment = 5B -> 2
ones_segment = ((D7 & 0F) << 4) | ((F0 & F0) >> 4) = 7F -> 8
timer = 28
```

## Observed Long Timer Samples

These samples should be kept aligned with `spec/chair.yml` and the generated
Swift decoder constants.

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

Short status frames are displayed and diffed by the iOS debug status screen.
Some captures are 3 bytes, but massage area requires at least 5 bytes; the app
keeps the most recent decodable area when shorter short-status frames arrive.

Use the generated short-status map and masks:

- [Short status map](generated/short_status_map.md)
- [Known masks](generated/masks.md)

## Observed Short Samples

These were observed while the remote showed a timer value, but the timer mapping
is now believed to belong to long status instead.

| Remote timer | Short status sample | Notes |
| --- | --- | --- |
| `05` | `03 15 13` | Exact field meaning unknown |
| `04` | `03 15 06` | Exact field meaning unknown |
| `09` | `03 15 15` | Exact field meaning unknown |
| `10` | `00 06 15` | Exact field meaning unknown |

## Unknowns

- Most long-status bytes and bit flags are still unmapped.
- Short status has only one tentative field-level mapping so far.
- Air, massage speed, massage width, foot roller, and heater rules should be
  validated against more captures.
- Some bits in the timer sample bytes vary while the displayed timer stays the
  same; those bits are likely unrelated flags, but their meanings are unknown.
- `B7[b7]` is consistently observed with values such as `80`, `A0`, and `60`,
  but the function is still unmapped; it could be an always-on flag.
- Heater lives on the last byte of long status, not a fixed index. The decoder
  uses the last byte; if future captures show a different long-status length,
  masks should be regenerated from the YAML rule rather than patched by hand.
