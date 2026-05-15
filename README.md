# Chair

ESP32 chair BLE bridge/sniffer firmware built with Arduino on PlatformIO.

## Requirements

- uv
- ESP32 Dev Module compatible board

Install project dependencies:

```sh
uv sync
```

PlatformIO is provided by the uv environment. Run it as `uv run pio`.
Common project commands are wrapped by `make`.

## Build

Compile the firmware:

```sh
make build
```

## Deploy

Connect the ESP32 over USB, then list available serial devices:

```sh
make devices
```

Upload the firmware:

```sh
make upload
```

If PlatformIO does not auto-detect the port, pass it explicitly:

```sh
uv run pio run --target upload --upload-port /dev/cu.usbserial-0001
```

After upload, open the serial monitor:

```sh
make monitor
```

Expected boot logs include:

```text
Loaded PIN: 000000
BLE ready: ChairSniffer
```

The device advertises over BLE as `ChairSniffer`.

On first BLE pairing, enter the 6-digit passkey shown by the firmware. The default is
`000000`. After connecting with the monitor app, change it with a command such as
`PIN:123456`.

## Common Commands

```sh
make build                 # build firmware
make upload                # upload firmware
make monitor               # serial monitor at 115200 baud
make devices               # list serial devices
make clean                 # clean build artifacts
make compiledb             # generate compile_commands.json for clangd
make monitor-app           # run BLE TUI
make monitor-app-debug     # run BLE TUI with diagnostics
make check-python          # syntax-check Python monitor
make test                  # run Python unit tests
```

The BLE TUI displays status bytes as binary by default. Press `F2` to cycle byte display
between binary, octal, and hex. Press `P` to pause or resume incoming display updates.
Commands are still entered as 4-digit hex codes.

The TUI shows `Chair Status` and `Decoded` side by side. The `Decoded` panel shows
tentative long-status fields, including byte-aligned 7-segment timer candidates and a
heater candidate decoded from the last long-status hex digit.

## Formatting

Format C/C++ code with `clang-format`. The shared rules live in `.clang-format`.

On macOS, Xcode may provide `clang-format` through `xcrun`:

```sh
xcrun clang-format -i src/main.cpp
```

If `clang-format` is not installed, install it with Homebrew:

```sh
brew install clang-format
```

Check formatting manually:

```sh
clang-format --dry-run --Werror src/main.cpp
```

Apply formatting:

```sh
clang-format -i src/main.cpp
```

## Editor Setup

Editor-specific files are intentionally not committed. VS Code users can regenerate local
IntelliSense settings with:

```sh
uv run pio project init --ide vscode
```

clangd users should generate a local compilation database:

```sh
make compiledb
```

The repository includes `.clangd` to remove ESP32 GCC flags that clangd cannot parse.
VS Code clangd users also need to allow clangd to query the ESP32 cross compiler. Add this
to local VS Code settings:

```json
{
  "clangd.arguments": [
    "--query-driver=/Users/*/.platformio/packages/toolchain-xtensa-esp32/bin/xtensa-esp32-elf-*,/home/*/.platformio/packages/toolchain-xtensa-esp32/bin/xtensa-esp32-elf-*"
  ]
}
```

Restart clangd after changing settings or generating `compile_commands.json`.
