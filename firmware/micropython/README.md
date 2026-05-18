# Experimental MicroPython Firmware

ESP32 MicroPython firmware acting as a UART sniffer + BLE bridge for the chair.

Scope:

- UART status sniffing on the yellow line
- UART command sniffing on the white line
- BLE GATT notify/write
- OTA firmware update over BLE (see `src/chair_ota.py`)

Not implemented yet:

- BLE pairing/passkey security
- Long-running stability validation

## Install

See the top-level [README](../../README.md) for the full setup (USB flash,
firmware copy, OTA workflow). Quick reference:

```sh
make flash             # flash MicroPython to the ESP32 over USB
make upload            # copy bridge_core.py and main.py to the board
make repl              # open a REPL to verify boot logs
```

## Protocol

BLE notifications use a text format with readable prefixes:

```text
[CHAIR] <hex>          chair -> remote status / ACK
[REMOTE] <hex>         remote -> chair command (sniffed)
[TRANSMITTED] <hex>    command transmitted by this bridge
[ERROR] <text>         validation / runtime error
```

BLE writes accept verbs:

```text
SEND XXXX              send a 4-digit hex command
OTA BEGIN/DATA/COMMIT/REBOOT   firmware update
```
