"""
BLE OTA firmware uploader for ChairSniffer (MicroPython).

Usage:
    uv run src/chair_ota.py firmware/micropython/main.py
    uv run src/chair_ota.py firmware/micropython/main.py firmware/micropython/bridge_core.py
    uv run src/chair_ota.py --reboot firmware/micropython/main.py
    uv run src/chair_ota.py --name ChairSniffer-AFEF firmware/micropython/main.py
"""

import asyncio
import argparse
import binascii
import sys
from pathlib import Path

from bleak import BleakClient, BleakScanner

SERVICE_UUID = "12345678-1234-1234-1234-123456789abc"
CHAR_DATA_UUID = "12345678-1234-1234-1234-123456789abd"
CHAR_CMD_UUID = "12345678-1234-1234-1234-123456789abe"

CHUNK_SIZE = 100  # raw bytes per OTA DATA chunk


async def upload_file(client: BleakClient, filepath: Path, queue: asyncio.Queue) -> None:
    data = filepath.read_bytes()
    filename = filepath.name
    size = len(data)
    crc = binascii.crc32(data) & 0xFFFFFFFF

    print(f"  Uploading {filename} ({size} bytes, crc32={crc})")

    async def write(cmd: str) -> None:
        await client.write_gatt_char(CHAR_CMD_UUID, cmd.encode(), response=True)

    async def expect(prefix: str, timeout: float = 10.0) -> str:
        while True:
            msg = await asyncio.wait_for(queue.get(), timeout=timeout)
            if msg.startswith(prefix):
                return msg
            if msg.startswith("[ERROR]"):
                raise RuntimeError(f"Device error: {msg}")

    await write(f"OTA BEGIN {filename} {size}")
    await expect("[CHAIR] OTA READY")

    for offset in range(0, size, CHUNK_SIZE):
        chunk = data[offset:offset + CHUNK_SIZE]
        await write(f"OTA DATA {chunk.hex()}")
        ack = await expect("[CHAIR] OTA ACK")
        received = int(ack.split()[-1])
        pct = received / size * 100
        print(f"    {pct:5.1f}%  ({received}/{size} bytes)", end="\r")

    print()

    await write(f"OTA COMMIT {crc}")
    await expect("[CHAIR] OTA DONE")
    print(f"  {filename} written successfully.")


async def run(device_name: str, files: list[Path], reboot: bool) -> None:
    print(f"Scanning for '{device_name}'...")
    device = await BleakScanner.find_device_by_name(device_name, timeout=10.0)
    if not device:
        print(f"Device '{device_name}' not found.", file=sys.stderr)
        sys.exit(1)

    print(f"Found {device.name} ({device.address}). Connecting...")

    queue: asyncio.Queue = asyncio.Queue()

    def on_notify(sender, data: bytearray) -> None:
        text = data.decode("utf-8", errors="replace").strip()
        if text:
            queue.put_nowait(text)

    async with BleakClient(device, timeout=15.0) as client:
        await client.start_notify(CHAR_DATA_UUID, on_notify)
        print("Connected.\n")

        for filepath in files:
            await upload_file(client, filepath, queue)

        if reboot:
            print("\nRebooting device...")
            await client.write_gatt_char(CHAR_CMD_UUID, b"OTA REBOOT", response=True)

    print("\nDone.")


def main() -> None:
    parser = argparse.ArgumentParser(description="ChairSniffer BLE OTA updater")
    parser.add_argument("files", nargs="+", type=Path, help=".py files to upload")
    parser.add_argument("--name", default="ChairSniffer", help="BLE device name prefix")
    parser.add_argument("--reboot", action="store_true", help="reboot device after upload")
    args = parser.parse_args()

    for f in args.files:
        if not f.exists():
            print(f"File not found: {f}", file=sys.stderr)
            sys.exit(1)
        if f.suffix != ".py":
            print(f"Only .py files are supported: {f}", file=sys.stderr)
            sys.exit(1)

    asyncio.run(run(args.name, args.files, args.reboot))


if __name__ == "__main__":
    main()
