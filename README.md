# Chair

ESP32 BLE sniffer/bridge for a massage chair, running MicroPython firmware.

## Requirements

- Python 3.11+ with [uv](https://docs.astral.sh/uv/)
- [mpremote](https://docs.micropython.org/en/latest/reference/mpremote.html) for initial USB flash

```sh
uv sync
pip install mpremote   # or: brew install mpremote
```

## Initial Firmware Setup (USB, one time)

Connect the ESP32 over USB, then copy the firmware files:

```sh
mpremote cp firmware/micropython/bridge_core.py :bridge_core.py
mpremote cp firmware/micropython/main.py :main.py
mpremote reset
```

Check boot logs:

```sh
mpremote connect auto repl
```

Expected output:

```
BLE ready: ChairSniffer-AFEF
MicroPython firmware is experimental and uses no BLE passkey
```

## OTA Firmware Update (BLE, no USB needed)

After the initial USB setup, use `chair_ota.py` for all future updates:

```sh
# Upload a single file
uv run src/chair_ota.py firmware/micropython/main.py

# Upload multiple files and reboot when done
uv run src/chair_ota.py --reboot firmware/micropython/bridge_core.py firmware/micropython/main.py

# Specify device name if needed
uv run src/chair_ota.py --name ChairSniffer-AFEF --reboot firmware/micropython/main.py
```

The script connects over BLE, uploads in 100-byte chunks with CRC32 verification, and
optionally reboots the device. The device continues sniffing chair data during the upload.

OTA protocol (app → device):
```
OTA BEGIN <filename> <size>   start transfer
OTA DATA <hex_chunk>          send chunk (100 bytes → 200 hex chars)
OTA COMMIT <crc32>            verify and write file
OTA REBOOT                    reboot device
```

## BLE Monitor TUI

```sh
uv run src/chair_monitor.py
uv run src/chair_monitor.py --name ChairSniffer-AFEF
uv run src/chair_monitor.py --debug
```

Keybindings:

| Key | Action |
|-----|--------|
| `F2` | Cycle display: binary → octal → hex |
| `Space` | Toggle status panel: unknown flags ↔ full raw |
| `P` | Pause / resume incoming display updates |
| `Ctrl+Q` | Quit |

Enter 4-digit hex commands in the input bar (e.g. `0303` for power).

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

## iOS App

Open `TodoApp/TodoApp.xcodeproj` in Xcode, select your device, press `Cmd+R`.
Scans for any BLE device whose name starts with `ChairSniffer`.
