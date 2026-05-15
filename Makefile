.PHONY: build upload monitor devices clean compiledb monitor-app monitor-app-debug check-python test

build:
	uv run pio run

upload:
	uv run pio run --target upload

monitor:
	uv run pio device monitor --baud 115200

devices:
	uv run pio device list

clean:
	uv run pio run --target clean

compiledb:
	uv run pio run -t compiledb

monitor-app:
	uv run src/chair_monitor.py

monitor-app-debug:
	uv run src/chair_monitor.py --debug

check-python:
	uv run python -m py_compile src/chair_decode.py src/chair_monitor.py

test:
	uv run pytest
