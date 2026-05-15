"""
Massage Chair Monitor TUI (BLE)

Usage:
    pip install textual bleak
    python chair_monitor.py [--name ChairSniffer]

On first run, your OS will prompt for the BLE passkey (default: 000000).
"""

import asyncio
import argparse
import threading
from datetime import datetime

from bleak import BleakClient, BleakScanner
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, Static, RichLog, Input, Label
from textual.binding import Binding
from rich.text import Text

# Must match ESP32 code
SERVICE_UUID = "12345678-1234-1234-1234-123456789abc"
CHAR_DATA_UUID = "12345678-1234-1234-1234-123456789abd"  # Notify
CHAR_CMD_UUID = "12345678-1234-1234-1234-123456789abe"   # Write


def split_pairs(data: str) -> list[str]:
    return [data[i:i+2] for i in range(0, len(data), 2)]


def highlight_diff(old: str, new: str, label: str) -> Text:
    old_pairs = split_pairs(old)
    new_pairs = split_pairs(new)
    result = Text()
    result.append(f"{label}: ", style="bold cyan")
    for i, pair in enumerate(new_pairs):
        if i >= len(old_pairs) or pair != old_pairs[i]:
            result.append(pair, style="bold red")
        else:
            result.append(pair, style="white")
        if i < len(new_pairs) - 1:
            result.append(" ", style="white")
    return result


class StatusPanel(Static):
    prev_short: str = ""
    prev_long: str = ""
    curr_short: str = ""
    curr_long: str = ""

    def update_short(self, data: str) -> bool:
        if data == self.curr_short:
            return False
        self.prev_short = self.curr_short
        self.curr_short = data
        self._render_status()
        return True

    def update_long(self, data: str) -> bool:
        if data == self.curr_long:
            return False
        self.prev_long = self.curr_long
        self.curr_long = data
        self._render_status()
        return True

    def _render_status(self):
        content = Text()
        if self.curr_short:
            content.append_text(
                highlight_diff(self.prev_short, self.curr_short, "Short")
            )
        content.append("\n")
        if self.curr_long:
            content.append_text(
                highlight_diff(self.prev_long, self.curr_long, " Long")
            )
        self.update(content)


class ChairMonitor(App):
    CSS = """
    Screen {
        layout: vertical;
    }
    #status-box {
        height: 5;
        border: solid green;
        padding: 0 1;
    }
    #status-title {
        color: green;
        text-style: bold;
    }
    #cmd-log {
        height: 1fr;
        border: solid yellow;
    }
    #cmd-title {
        color: yellow;
        text-style: bold;
    }
    #raw-log {
        height: 8;
        border: solid gray;
    }
    #raw-title {
        color: gray;
        text-style: bold;
    }
    Input {
        dock: bottom;
        margin: 0 1;
    }
    """

    TITLE = "Massage Chair Monitor"
    BINDINGS = [
        Binding("ctrl+q", "quit", "Quit"),
        Binding("ctrl+c", "quit", "Quit"),
    ]

    def __init__(self, device_name: str, debug_enabled: bool = False, **kwargs):
        super().__init__(**kwargs)
        self.device_name = device_name
        self.debug_enabled = debug_enabled
        self.ble_client: BleakClient | None = None
        self.ui_thread_id = threading.get_ident()
        self.notify_count = 0

    def compose(self) -> ComposeResult:
        yield Header()
        yield Label(" Chair Status (live)", id="status-title")
        yield StatusPanel("Waiting for data...", id="status-box")
        yield Label(" Commands & Responses", id="cmd-title")
        yield RichLog(highlight=True, markup=True, wrap=True, id="cmd-log")
        yield Label(" Raw Feed", id="raw-title")
        yield RichLog(highlight=True, markup=True, wrap=True, id="raw-log")
        yield Input(placeholder="Command: 4-digit hex (e.g. 0303) or PIN:XXXXXX - Enter to send")
        yield Footer()

    async def on_mount(self) -> None:
        self.ui_thread_id = threading.get_ident()
        self.run_worker(self.ble_connect(), exclusive=True)

    def debug_log(self, message: str) -> None:
        if not self.debug_enabled:
            return
        raw_log = self.query_one("#raw-log", RichLog)
        now = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        raw_log.write(Text(f"{now}  [debug] {message}", style="blue"))

    def process_line(self, text: str) -> None:
        raw_log = self.query_one("#raw-log", RichLog)
        cmd_log = self.query_one("#cmd-log", RichLog)
        status = self.query_one("#status-box", StatusPanel)

        now = datetime.now().strftime("%H:%M:%S.%f")[:-3]

        # Raw log
        raw_log.write(Text(f"{now}  {text}", style="dim"))

        # Parse
        if text.startswith("[Y] "):
            data = text[4:]
            data_len = len(data)

            if data_len <= 5:
                # Command ACK
                entry = Text()
                entry.append(f"{now}  ", style="dim")
                entry.append("← ", style="yellow")
                entry.append("[Y] ", style="bold yellow")
                entry.append(" ".join(split_pairs(data)), style="bold white")
                cmd_log.write(entry)

            elif data_len <= 12:
                status.update_short(data)

            else:
                status.update_long(data)

        elif text.startswith("[W] "):
            data = text[4:]
            entry = Text()
            entry.append(f"{now}  ", style="dim")
            entry.append("→ ", style="green")
            entry.append("[W] ", style="bold green")
            entry.append(" ".join(split_pairs(data)), style="bold white")
            cmd_log.write(entry)

        elif text.startswith("[SENT] "):
            data = text[7:]
            entry = Text()
            entry.append(f"{now}  ", style="dim")
            entry.append("⚡ ", style="magenta")
            entry.append("[SENT] ", style="bold magenta")
            entry.append(" ".join(split_pairs(data)), style="bold white")
            cmd_log.write(entry)

        elif text.startswith("[PIN] ") or text.startswith("[ERR] "):
            style = "bold green" if text.startswith("[PIN]") else "bold red"
            entry = Text()
            entry.append(f"{now}  ", style="dim")
            entry.append(text, style=style)
            cmd_log.write(entry)

    def notification_handler(self, sender, data: bytearray) -> None:
        """Called by bleak when ESP32 sends a notification."""
        self.notify_count += 1
        text = data.decode("utf-8", errors="replace").strip()
        if text:
            try:
                if threading.get_ident() == self.ui_thread_id:
                    self.process_line(text)
                else:
                    self.call_from_thread(self.process_line, text)
            except Exception as e:
                print(f"notification handler failed: {e!r}; text={text!r}")

    async def ble_connect(self) -> None:
        raw_log = self.query_one("#raw-log", RichLog)

        while True:
            try:
                raw_log.write(
                    Text(f"Scanning for '{self.device_name}'...", style="cyan")
                )

                device = await BleakScanner.find_device_by_name(
                    self.device_name, timeout=10.0
                )
                if not device:
                    raw_log.write(Text("Device not found. Retrying...", style="yellow"))
                    await asyncio.sleep(3)
                    continue

                raw_log.write(
                    Text(f"Found {device.name} ({device.address})", style="cyan")
                )

                self.ble_client = BleakClient(device, timeout=15.0)
                await self.ble_client.connect()

                if not self.ble_client.is_connected:
                    raw_log.write(Text("Connection failed", style="red"))
                    await asyncio.sleep(3)
                    continue

                raw_log.write(Text("Connected!", style="bold green"))

                if self.debug_enabled:
                    services = self.ble_client.services
                    for service in services:
                        raw_log.write(Text(f"[debug] service {service.uuid}", style="blue"))
                        for char in service.characteristics:
                            raw_log.write(
                                Text(
                                    f"[debug] char {char.uuid} props={','.join(char.properties)}",
                                    style="blue",
                                )
                            )

                # Subscribe to notifications
                raw_log.write(Text(f"Subscribing to {CHAR_DATA_UUID}...", style="cyan"))
                await self.ble_client.start_notify(
                    CHAR_DATA_UUID, self.notification_handler
                )
                raw_log.write(Text("Subscribed to chair data notifications", style="bold green"))

                try:
                    value = await self.ble_client.read_gatt_char(CHAR_DATA_UUID)
                    raw_log.write(Text(f"[debug] initial read: {value!r}", style="blue"))
                except Exception as e:
                    raw_log.write(Text(f"[debug] initial read failed: {e}", style="blue"))

                # Stay alive while connected
                while self.ble_client.is_connected:
                    self.debug_log(f"connected; notifications received={self.notify_count}")
                    await asyncio.sleep(1)

                raw_log.write(Text("Disconnected", style="yellow"))

            except Exception as e:
                raw_log.write(Text(f"BLE error: {e}", style="red"))
                await asyncio.sleep(3)

    async def on_input_submitted(self, event: Input.Submitted) -> None:
        cmd = event.value.strip()
        cmd_log = self.query_one("#cmd-log", RichLog)

        if not cmd:
            return

        if not self.ble_client or not self.ble_client.is_connected:
            cmd_log.write(Text("Not connected!", style="bold red"))
            event.input.clear()
            return

        # Validate
        is_pin_cmd = cmd.startswith("PIN:") and len(cmd) == 10 and cmd[4:].isdigit()
        is_chair_cmd = len(cmd) == 4 and not cmd.startswith("PIN")

        if not is_pin_cmd and not is_chair_cmd:
            cmd_log.write(
                Text(
                    f"Invalid: '{cmd}'. Use 4-digit hex or PIN:XXXXXX",
                    style="bold red",
                )
            )
            event.input.clear()
            return

        now = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        if is_pin_cmd:
            label = f"PIN change: {cmd}"
        else:
            label = f"Sending: ~{cmd}\\r"

        entry = Text()
        entry.append(f"{now}  ", style="dim")
        entry.append("📤 ", style="magenta")
        entry.append(label, style="bold magenta")
        cmd_log.write(entry)

        try:
            await self.ble_client.write_gatt_char(
                CHAR_CMD_UUID, cmd.encode("utf-8"), response=True
            )
        except Exception as e:
            cmd_log.write(Text(f"Send failed: {e}", style="bold red"))

        event.input.clear()


def main():
    parser = argparse.ArgumentParser(description="Massage Chair Monitor (BLE)")
    parser.add_argument(
        "--name", default="ChairSniffer", help="BLE device name to scan for"
    )
    parser.add_argument("--debug", action="store_true", help="show BLE diagnostic logs")
    args = parser.parse_args()

    app = ChairMonitor(device_name=args.name, debug_enabled=args.debug)
    app.run()


if __name__ == "__main__":
    main()
