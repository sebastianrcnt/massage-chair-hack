# Chair

ESP32 BLE sniffer/bridge for a massage chair, running MicroPython firmware.

## Requirements

- Python 3.11+ with [uv](https://docs.astral.sh/uv/)

```sh
uv sync
```

`esptool` and `mpremote` are project dependencies and are available via `uv run` after syncing.

## Initial Firmware Setup (USB, one time)

### 1. Flash MicroPython to the ESP32

Connect over USB, then erase and write the MicroPython binary:

```sh
uv run esptool --port /dev/cu.usbserial-1110 erase-flash
uv run esptool --port /dev/cu.usbserial-1110 --baud 460800 write-flash -z 0x1000 \
  .cache/firmware/ESP32_GENERIC-20260406-v1.28.0.bin
```

Or with `make` (uses `PORT ?= /dev/cu.usbserial-1110`):

```sh
make flash
make flash PORT=/dev/cu.usbserial-XXXX   # override if port differs
```

List connected devices: `ls /dev/cu.*`

### 2. Copy the bridge firmware

```sh
uv run mpremote connect /dev/cu.usbserial-1110 \
  cp firmware/micropython/bridge_core.py :bridge_core.py + \
  cp firmware/micropython/main.py :main.py + \
  reset
```

Or: `make upload`

Check boot logs:

```sh
uv run mpremote connect /dev/cu.usbserial-1110 repl
```

Or: `make repl`

Expected output:

```
BLE ready: ChairSniffer-AFEF
MicroPython firmware is experimental and uses no BLE passkey
```

## OTA Firmware Update (BLE, no USB needed)

After the initial USB setup, use `chair_ota.py` for all future updates:

```sh
# Upload both files and reboot
uv run src/chair_ota.py --name ChairSniffer-AFEF --reboot \
  firmware/micropython/bridge_core.py firmware/micropython/main.py
```

Or: `make ota`

The script connects over BLE, uploads in 100-byte chunks with CRC32 verification, and
optionally reboots the device. The device continues sniffing chair data during the upload.

OTA protocol (app → device):
```
OTA BEGIN <filename> <size>   start transfer
OTA DATA <hex_chunk>          send chunk (100 bytes → 200 hex chars)
OTA COMMIT <crc32>            verify and write file
OTA REBOOT                    reboot device
```

## BLE Protocol

**Device → app (notify):**

| Prefix | Source |
|--------|--------|
| `[CHAIR] <hex>` | Chair status line (yellow wire) |
| `[REMOTE] <hex>` | Remote command line (white wire, sniffed) |
| `[TRANSMITTED] <hex>` | Command sent by this app to the chair |
| `[ERROR] <text>` | Error from bridge firmware |

**App → device (write):**

| Command | Effect |
|---------|--------|
| `SEND XXXX` | Send 4-digit hex command to chair |
| `OTA BEGIN/DATA/COMMIT/REBOOT` | Firmware update (see above) |

## Tests

```sh
uv run pytest
```

## Reverse Engineering Notes

- Known remote button codes: [docs/decoding.md](docs/decoding.md)
- Raw samples and scratch notes: [reverse.md](reverse.md)

## iOS / macOS App

Open `ChairSniffer/ChairSniffer.xcodeproj` in Xcode, select your device or **My Mac (Mac Catalyst)**, press `Cmd+R`.
Scans for any BLE device whose name starts with `ChairSniffer`.

Features: decoded status panel, hex keypad for sending commands, raw BLE feed with pause, display mode toggle (HEX / BIN / OCT) with diff highlighting for changed bytes.
