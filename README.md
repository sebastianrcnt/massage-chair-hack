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

## Build

Compile the firmware:

```sh
uv run pio run
```

## Upload

Connect the ESP32 over USB and upload:

```sh
uv run pio run --target upload
```

If PlatformIO does not auto-detect the port, pass it explicitly:

```sh
uv run pio run --target upload --upload-port /dev/cu.usbserial-0001
```

## Monitor

Open the serial monitor:

```sh
uv run pio device monitor
```

Use a specific port:

```sh
uv run pio device monitor --port /dev/cu.usbserial-0001
```

The firmware logs at `115200` baud.

## Common Commands

```sh
uv run pio run                         # build
uv run pio run --target upload          # upload firmware
uv run pio device monitor               # serial monitor
uv run pio run --target clean           # clean build artifacts
uv run pio device list                  # list serial devices
```

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
uv run pio run -t compiledb
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
