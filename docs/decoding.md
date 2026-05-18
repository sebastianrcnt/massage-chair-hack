# Chair Status Decoding

This document tracks the current reverse-engineered status map. Byte positions are
0-based. Byte labels use uppercase `B`; bit labels use lowercase `b`. For example,
`B4[b6:b5]` means bits 6 through 5 of byte 4, where `b7` is the most significant bit.

## Frame Sources

| Prefix | Source | Meaning |
| --- | --- | --- |
| `[CHAIR]` | Chair status line, yellow wire | Chair-to-remote status broadcast |
| `[REMOTE]` | Remote command line, white wire | Remote-to-chair command sniffing |
| `[TRANSMITTED]` | BLE monitor app | Command transmitted by this tool to the chair |
| `[ERROR]` | Bridge firmware | Error message |

**App → ESP32 write format:** `SEND XXXX` where `XXXX` is a 4-digit hex command.

## Remote Commands (`[REMOTE]`)

| Button | Press | Release | Notes |
| --- | --- | --- | --- |
| Power | `0303` | `0355` | |
| Timer | `032D` | `0355` | Cycles +5 min steps; max 30 min, then wraps to 5 min |
| Pause / Resume | `0322` | `0355` | |
| Speed | `0327` | `0336` | 3-step cycle; manual mode only — no ACK outside manual mode |
| Manual mode | `0363` | `0339` | |
| Back recline | `0304` | `0355` | Hold to move; stops at end of travel |
| Back raise | `0302` | `0355` | Hold to move; stops at end of travel |
| Leg lower | `0301` | `0355` | Hold to move; stops at end of travel |
| Leg raise | `0307` | `0355` | Hold to move; stops at end of travel |
| Air mode cycle | `0375` | `0355` | Cycles through air massage modes |
| Air strength | `0315` | `0355` | No ACK observed |
| Foot roller | `0331` | `0339` | |
| Massage position up | `032C` | `0355` | ACK `1103` (beep); chair sends `[Y] 1100` after release |
| Massage position down | `032F` | `0355` | ACK `1103` (beep); chair sends `[Y] 1100` after release |
| Position reset | `0384` | `0355` | ACK `1103` (beep); no `1100` |
| Zero gravity | `0306` | `0355` | ACK `1103` (beep) |
| Auto: Charging (충전) | `031F` | `0355` | ACK `1103`; resets timer to 15 min |
| Auto: Digestion (소화) | `0391` | `0355` | ACK `1103`; resets timer to 15 min |
| Auto: Classic (클래식) | `0305` | `0355` | ACK `1103`; resets timer to 15 min |
| Auto: Sleep (숙면) | `0321` | `0355` | ACK `1103`; resets timer to 15 min |
| Auto: Stretching (스트레칭) | `031E` | `0336` | ACK `1103`; resets timer to 15 min; unique release code |
| Auto: Healing (힐링) | `0320` | `0355` | ACK `1103`; resets timer to 15 min |
| Width cycle | `0364` | `0355` | No ACK observed |
| Heater toggle | `0330` | `0355` | ACK `1103` (beep) |

Release `0355` appears to be shared across multiple buttons, but speed and manual mode have their own release codes.

## Chair ACK (`[Y]`)

| Code | Hypothesis | Confidence |
| --- | --- | --- |
| `1103` | Single beep on remote | Tentative — observed on most button presses |
| `1104` | Double beep on remote — cycle complete | Sent when any cycle button wraps back to first step (confirmed: speed, air strength; likely: timer, others) |
| `1100` | Unknown — observed after massage position up/down release only | Tentative — not seen after position reset; may signal head-unit reached target position |

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
| `B4[b7]` | Manual: 지압 blink | Default `1`; blinks `0`/`1` when 지압 is the active manual technique | Tentative |
| `B4[b6]` | Manual: 주무름 blink / Air strength high bit | Manual mode: blinks `0`/`1` when 주무름 active. Otherwise: high bit of strength (with `B4[b5]`) | Tentative — mode-dependent |
| `B4[b5]` | Air strength low bit | With `B4[b6]`: `00` -> lv 1, `01` -> lv 3, `11` -> lv 5, `10` reserved | Tentative |
| `B4[b4]` | Air | `1` -> on, `0` -> off | Tentative |
| `B4[b3:b0]` | Unknown flags | Not mapped | Unknown |
| `B5[b7:b6]` | Unknown flags | Not mapped | Unknown |
| `B5[b5:b4]` | Manual mode indicator | `00` -> chair is in manual mode | Tentative |
| `B5[b3]` | Manual: 복합 blink / Massage speed high bit | Manual mode: blinks `0`/`1` when 복합 active. Otherwise: high bit of speed (with `B5[b2]`) | Tentative — mode-dependent |
| `B5[b2]` | Manual: 손날 두드림 blink / Massage speed low bit | Manual mode: blinks `0`/`1` when 손날 active. With `B5[b3]`: `00` -> lv 1, `01` -> lv 3, `11` -> lv 5, `10` reserved | Tentative — mode-dependent |
| `B5[b1]` | Manual: 두드림 blink | Default `1`; blinks `0`/`1` when 두드림 active | Tentative |
| `B5[b0]` | Manual: 시아추 blink | Default `1`; blinks `0`/`1` when 시아추 active | Tentative |
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

### Manual Mode

When `B5[b5:b4] == 00` the chair is in manual mode. Six bits across B4 and B5
each correspond to one manual massage technique. Each bit defaults to `1`; while
the matching technique is the active one, the bit blinks `0`/`1` (~1 Hz, same
behavior as the back/leg motion bits).

| Slot | Technique (Korean) | English | Blink bit |
| --- | --- | --- | --- |
| 1 | 주무름 | Knead | `B4[b6]` |
| 2 | 두드림 | Tap | `B5[b1]` |
| 3 | 지압 | Acupressure | `B4[b7]` |
| 4 | 손날 두드림 | Edge tap / Chop | `B5[b2]` |
| 5 | 시아추 | Shiatsu | `B5[b0]` |
| 6 | 복합 | Combination | `B5[b3]` |

Overlaps to validate:

- `B4[b6:b5]` was tentatively mapped to Air strength. `B4[b6]` is also the
  Knead blink bit in manual mode. The two may be mode-dependent; needs
  cross-mode capture.
- `B5[b3:b2]` was tentatively mapped to Massage speed. `B5[b3]` is the
  Combination blink and `B5[b2]` is the Edge-tap blink in manual mode. Same
  caveat.

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
| `B4[b7:b0]` | Massage area | `09` -> point, `0D` -> full, `0B` -> local, other values reserved | Tentative |

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
- `B7` is consistently observed with `b7 == 1` (samples show `80`, `A0`, `60`) but the
  function is still unmapped; could be an always-on flag rather than a true unknown.
- Heater lives on the *last* byte of long status, not a fixed index. The decoder
  uses `bytes.last`, which is length-tolerant. The dev "mask known bits" toggle in
  `Dev/DecodedStatusScreen.swift` currently hard-codes index 8; if future captures
  show a different long-status length, that mask needs to follow the last-byte rule.
