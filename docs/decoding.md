# Chair Status Decoding

This document tracks the current reverse-engineered status map. Byte positions are
0-based. Byte labels use uppercase `B`; bit labels use lowercase `b`. For example,
`B4[b6:b5]` means bits 6 through 5 of byte 4, where `b7` is the most significant bit.

## Frame Sources

| Prefix | Source | Meaning |
| --- | --- | --- |
| `[Y]` | Chair status line, yellow wire | Chair-to-remote status broadcast |
| `[W]` | Remote command line, white wire | Remote-to-chair command sniffing |
| `[SENT]` | BLE monitor app | Command sent by this tool to the chair |

## Frame Classification

The monitor currently classifies `[Y]` payloads by hex string length.

| Payload length | Monitor treatment |
| --- | --- |
| `<= 5` hex chars | Command ACK / short response |
| `6..12` hex chars | Short status |
| `> 12` hex chars | Long status |

## Long Status Map

Known long-status samples are currently 9 bytes, but decoding code treats the heater as
the last byte so it can tolerate length changes.

| Range | Name | Values / rule | Confidence |
| --- | --- | --- | --- |
| `B0[b7:b0]` | Unknown flags | Varies across samples | Unknown |
| `B1[b7:b0]` | Timer tens 7-segment byte | Direct lookup in the 7-segment table | Confirmed |
| `B2[b7:b4]` | Timer ones segment low nibble | Becomes `ones_segment[b3:b0]` | Confirmed |
| `B2[b3:b0]` | Unknown flags | Varies across samples | Unknown |
| `B3[b7:b4]` | Unknown flags | Varies across samples | Unknown |
| `B3[b3:b0]` | Timer ones segment high nibble | Becomes `ones_segment[b7:b4]` | Confirmed |
| `B4[b7]` | Unknown flags | Not mapped | Unknown |
| `B4[b6:b5]` | Air strength | `00` -> level 1, `01` -> level 3, `11` -> level 5, `10` reserved | Tentative |
| `B4[b4]` | Air | `1` -> on, `0` -> off | Tentative |
| `B4[b3:b0]` | Unknown flags | Not mapped | Unknown |
| `B5[b7:b6]` | Unknown flags | Not mapped | Unknown |
| `B5[b5:b4]` | Unknown flags | Not mapped | Unknown |
| `B5[b3:b2]` | Massage speed | `00` -> level 1, `01` -> level 3, `11` -> level 5, `10` reserved | Tentative |
| `B5[b1:b0]` | Unknown flags | Not mapped | Unknown |
| `B6[b7]` | Foot roller | `1` -> on, `0` -> off | Tentative |
| `B6[b6]` | Leg raise movement | Blinks `0`/`1` about once per second while the leg rest is raising | Tentative |
| `B6[b5]` | Leg recline movement | Blinks `0`/`1` about once per second while the leg rest is reclining | Tentative |
| `B6[b4]` | Chair movement active | `1` while either back or leg movement is physically active; delayed until motion starts; `0` at rest or out of travel range | Tentative |
| `B6[b3]` | Back recline movement | Blinks `0`/`1` about once per second while the back is reclining | Tentative |
| `B6[b2]` | Back raise movement | Blinks `0`/`1` about once per second while the back is raising | Tentative |
| `B6[b1:b0]` | Massage width | `00` -> wide, `01` -> medium, `10` -> narrow, `11` reserved | Tentative |
| `B7[b7:b0]` | Unknown flags | Usually observed as `80` in current samples | Unknown |
| `last[b1]` | Heater | `on` when `(last_byte & 0x02) != 0`; otherwise `off` | Tentative |
| `last[b7:b2], last[b0]` | Unknown flags | Not mapped | Unknown |

### Packed Timer Detail

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

### 7-Segment Table

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

### Observed Long Timer Samples

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

## Short Status Map

Short status frames are displayed and diffed by the TUI. Some captures are 3 bytes, but
newer observations include at least 5 bytes.

| Range | Name | Values / rule | Confidence |
| --- | --- | --- | --- |
| `B0[b7:b0]` | Unknown | Observed `03`, `00` | Unknown |
| `B1[b7:b0]` | Unknown | Observed `15`, `06` | Unknown |
| `B2[b7:b0]` | Unknown | Observed `13`, `06`, `15` | Unknown |
| `B3[b7:b0]` | Unknown | Not mapped | Unknown |
| `B4[b7:b3]` | Unknown | Not mapped | Unknown |
| `B4[b2:b1]` | Massage area | `00` -> point, `10` -> full, `01` -> local, `11` reserved | Tentative |
| `B4[b0]` | Unknown | Not mapped | Unknown |

### Observed Short Samples

These were observed while the remote showed a timer value, but the timer mapping is now
believed to belong to long status instead.

| Remote timer | Short status sample | Notes |
| --- | --- | --- |
| `05` | `03 15 13` | Exact field meaning unknown |
| `04` | `03 15 06` | Exact field meaning unknown |
| `09` | `03 15 15` | Exact field meaning unknown |
| `10` | `00 06 15` | Exact field meaning unknown |

## Unknowns

- Most long-status bytes and bit flags are still unmapped.
- Short status has only one tentative field-level mapping so far.
- Air, massage speed, massage width, foot roller, and heater rules should be validated
  against more captures.
- Some bits in the timer sample bytes vary while the displayed timer stays the same; those
  bits are likely unrelated flags, but their meanings are unknown.
