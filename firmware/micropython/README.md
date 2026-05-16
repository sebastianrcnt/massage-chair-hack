# Experimental MicroPython Firmware

This is a first-pass ESP32 MicroPython port of the Arduino/PlatformIO firmware
in `src/main.cpp`.

Scope:

- UART status sniffing on the yellow line
- UART command sniffing on the white line
- BLE GATT notify/write using the same UUIDs as the C++ firmware
- Text protocol compatible with `src/chair_monitor.py`

Not implemented yet:

- BLE pairing/passkey security
- Runtime PIN changes
- Long-running stability validation

## Install

Flash MicroPython to the ESP32, then copy `main.py` to the board.

Example using `mpremote`:

```sh
uv tool run mpremote connect /dev/cu.usbserial-0001 fs cp firmware/micropython/main.py :main.py
uv tool run mpremote connect /dev/cu.usbserial-0001 reset
```

If the serial port differs, list devices first:

```sh
ls /dev/cu.*
```

## Monitor

The device advertises as `ChairSniffer`, just like the C++ firmware. Because this
experimental firmware does not require BLE pairing, the existing TUI should connect
without a passkey prompt:

```sh
uv run src/chair_monitor.py
```

Expected boot output:

```text
BLE ready: ChairSniffer
MicroPython firmware is experimental and uses no BLE passkey
```

## Protocol

BLE notifications keep the same text format as the C++ firmware:

```text
[Y] <hex>      chair -> remote status
[W] <hex>      remote -> chair command
[SENT] <hex>   command sent by the bridge
[ERR] <text>   validation/runtime error
```

BLE writes accept only 4-digit hex chair commands in this version. `PIN:XXXXXX`
returns an error because BLE passkey support is intentionally out of scope for
this first port.
