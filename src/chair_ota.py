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
LEGACY_CHUNK_SIZE = 5  # keep "OTA DATA <hex>" within a 20-byte GATT buffer
LEGACY_MAX_DECIMAL = 1_000_000_000
LEGACY_BOOT = (
    b"import os\n"
    b"os.rename('m.py','main.py');os.rename('b.py','bridge_core.py');os.remove('boot.py')\n\t"
)


def crc32(data: bytes) -> int:
    return binascii.crc32(data) & 0xFFFFFFFF


def pad_legacy_crc(data: bytes) -> bytes:
    """Keep OTA COMMIT below 20 bytes for old firmware with a 20B write buffer."""
    if crc32(data) < LEGACY_MAX_DECIMAL:
        return data

    for i in range(10000):
        candidate = data + f"\n# ota-pad {i}\n".encode()
        if crc32(candidate) < LEGACY_MAX_DECIMAL:
            return candidate

    raise RuntimeError("Unable to find legacy OTA CRC padding")


async def upload_blob(
    client: BleakClient,
    filename: str,
    data: bytes,
    queue: asyncio.Queue,
    chunk_size: int = CHUNK_SIZE,
) -> None:
    size = len(data)
    crc = crc32(data)

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

    for offset in range(0, size, chunk_size):
        chunk = data[offset:offset + chunk_size]
        await write(f"OTA DATA {chunk.hex()}")
        ack = await expect("[CHAIR] OTA ACK")
        received = int(ack.split()[-1])
        pct = received / size * 100
        print(f"    {pct:5.1f}%  ({received}/{size} bytes)", end="\r")

    print()

    await write(f"OTA COMMIT {crc}")
    await expect("[CHAIR] OTA DONE")
    print(f"  {filename} written successfully.")


async def upload_file(client: BleakClient, filepath: Path, queue: asyncio.Queue) -> None:
    await upload_blob(client, filepath.name, filepath.read_bytes(), queue)


async def upload_legacy_20_byte(
    client: BleakClient,
    files: list[Path],
    queue: asyncio.Queue,
    reboot: bool,
) -> bool:
    by_name = {filepath.name: filepath for filepath in files}
    if "bridge_core.py" not in by_name or "main.py" not in by_name:
        return False

    print("\nRetrying with legacy 20-byte OTA bootstrap...")

    uploads = [
        ("b.py", pad_legacy_crc(by_name["bridge_core.py"].read_bytes())),
        ("m.py", pad_legacy_crc(by_name["main.py"].read_bytes())),
        ("boot.py", LEGACY_BOOT),
    ]

    for filename, data in uploads:
        await upload_blob(client, filename, data, queue, chunk_size=LEGACY_CHUNK_SIZE)

    if reboot:
        print("\nRebooting device...")
        await client.write_gatt_char(CHAR_CMD_UUID, b"OTA REBOOT", response=True)

    return True


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

        legacy_used = False
        try:
            for filepath in files:
                await upload_file(client, filepath, queue)
        except RuntimeError as exc:
            if "OTA BEGIN requires: filename size" not in str(exc):
                raise
            if not await upload_legacy_20_byte(client, files, queue, reboot):
                raise
            legacy_used = True

        if reboot and not legacy_used:
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
