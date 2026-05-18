.PHONY: flash upload repl ota monitor test

PORT     ?= /dev/cu.usbserial-1110
BLE_NAME ?= ChairSniffer-AFEF
FIRMWARE ?= .cache/firmware/ESP32_GENERIC-20260406-v1.28.0.bin
PY_FILES  = firmware/micropython/bridge_core.py firmware/micropython/main.py

flash:
	uv run esptool --port $(PORT) erase-flash
	uv run esptool --port $(PORT) --baud 460800 write-flash -z 0x1000 $(FIRMWARE)

upload:
	uv run mpremote connect $(PORT) \
	  cp firmware/micropython/bridge_core.py :bridge_core.py + \
	  cp firmware/micropython/main.py :main.py + \
	  reset

repl:
	uv run mpremote connect $(PORT) repl

ota:
	uv run src/chair_ota.py --name $(BLE_NAME) --reboot $(PY_FILES)

monitor:
	uv run src/chair_monitor.py --name $(BLE_NAME)

test:
	uv run pytest
