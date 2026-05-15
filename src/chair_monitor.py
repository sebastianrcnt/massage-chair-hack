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
from time import monotonic

from bleak import BleakClient, BleakScanner
from textual.app import App, ComposeResult
from textual.containers import Horizontal
from textual.widgets import Header, Footer, Static, RichLog, Input, Label
from textual.binding import Binding
from rich.text import Text

from chair_decode import (
    DisplayMode,
    decode_long_status,
    format_byte,
    format_byte_list,
    format_bytes,
    is_hex_chunk,
    is_hex_code,
    split_bytes,
)

# Must match ESP32 code
SERVICE_UUID = "12345678-1234-1234-1234-123456789abc"
CHAR_DATA_UUID = "12345678-1234-1234-1234-123456789abd"  # Notify
CHAR_CMD_UUID = "12345678-1234-1234-1234-123456789abe"   # Write


def highlight_diff(old: str, new: str, label: str, display_mode: DisplayMode) -> Text:
    old_pairs = split_bytes(old)
    new_pairs = split_bytes(new)
    result = Text()
    result.append(f"{label}: ", style="bold cyan")
    for i, pair in enumerate(new_pairs):
        old_pair = old_pairs[i] if i < len(old_pairs) else ""
        if display_mode == "bin" and is_hex_chunk(pair):
            new_bits = format_byte(pair, "bin")
            old_bits = format_byte(old_pair, "bin") if is_hex_chunk(old_pair) else ""
            for bit_index, bit in enumerate(new_bits):
                style = (
                    "bold red"
                    if bit_index >= len(old_bits) or bit != old_bits[bit_index]
                    else "white"
                )
                result.append(bit, style=style)
        elif pair != old_pair:
            result.append(format_byte(pair, display_mode), style="bold red")
        else:
            result.append(format_byte(pair, display_mode), style="white")
        if i < len(new_pairs) - 1:
            result.append(" ", style="white")
    return result


class StatusPanel(Static):
    prev_short: str = ""
    prev_long: str = ""
    curr_short: str = ""
    curr_long: str = ""
    display_mode: DisplayMode = "bin"

    def set_format(self, display_mode: DisplayMode) -> None:
        self.display_mode = display_mode
        self._render_status()

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
        content.append("Chair Status\n", style="bold green")
        if self.curr_short:
            content.append_text(
                highlight_diff(
                    self.prev_short,
                    self.curr_short,
                    "Short",
                    self.display_mode,
                )
            )
        content.append("\n")
        if self.curr_long:
            content.append_text(
                highlight_diff(
                    self.prev_long,
                    self.curr_long,
                    " Long",
                    self.display_mode,
                )
            )
        elif not self.curr_short:
            content.append("Waiting for data...", style="dim")
        self.update(content)


class DecodedPanel(Static):
    curr_long: str = ""
    display_mode: DisplayMode = "bin"

    def set_format(self, display_mode: DisplayMode) -> None:
        self.display_mode = display_mode
        self._render_decoded()

    def update_long(self, data: str) -> None:
        self.curr_long = data
        self._render_decoded()

    def _render_decoded(self) -> None:
        content = Text()
        if not self.curr_long:
            content.append("Decoded\n", style="bold cyan")
            content.append("Waiting for long status...", style="dim")
            self.update(content)
            return

        content.append("Decoded\n", style="bold cyan")
        decoded = decode_long_status(self.curr_long)
        bytes_ = split_bytes(self.curr_long)
        content.append("Last bytes: ", style="bold cyan")
        content.append(format_byte_list(bytes_[-4:], self.display_mode), style="white")

        runs = decoded.seven_segment_runs
        content.append("\n")
        if not runs:
            content.append("7seg timer?: ", style="bold cyan")
            content.append("no candidate", style="yellow")
        else:
            run = runs[0]
            content.append("7seg timer?: ", style="bold cyan")
            content.append(f"{run.digits[-2:]} min", style="bold green")
            content.append(f"  b{run.start_byte}-b{run.end_byte} ", style="dim")
            content.append(
                f"({format_byte_list(run.raw.split(), self.display_mode)})",
                style="white",
            )

            if len(runs) > 1:
                content.append("\nOther 7seg: ", style="bold cyan")
                content.append(
                    "; ".join(
                        (
                            f"b{run.start_byte}-b{run.end_byte}:"
                            f"{run.digits}("
                            f"{format_byte_list(run.raw.split(), self.display_mode)})"
                        )
                        for run in runs[1:4]
                    ),
                    style="dim",
                )

        heater = decoded.heater
        content.append("\nHeater?: ", style="bold cyan")
        if heater.state == "on":
            content.append("on", style="bold green")
        elif heater.state == "off":
            content.append("off", style="bold yellow")
        else:
            content.append("unknown", style="yellow")
        content.append(f"  last hex={heater.raw}", style="dim")

        self.update(content)


class ChairMonitor(App):
    CSS = """
    Screen {
        layout: vertical;
    }
    #status-row {
        height: 7;
    }
    #status-box {
        height: 1fr;
        width: 1fr;
        border: solid green;
        padding: 0 1;
    }
    #connection-status {
        height: 1;
        padding: 0 1;
    }
    #decoded-box {
        height: 1fr;
        width: 1fr;
        border: solid cyan;
        padding: 0 1;
    }
    #display-mode {
        height: 1;
        padding: 0 1;
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
        Binding("p", "toggle_pause", "Pause"),
        Binding("f2", "toggle_display_mode", "Display"),
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
        self.last_notify_at: float | None = None
        self.subscribed_at: float | None = None
        self.warned_no_notify = False
        self.display_mode = "bin"
        self.paused = False
        self.paused_count = 0

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(
            "Display: BIN / BYTE | LIVE (F2 mode, P pause)",
            id="display-mode",
        )
        yield Static("Disconnected", id="connection-status")
        with Horizontal(id="status-row"):
            yield StatusPanel("Chair Status\nWaiting for data...", id="status-box")
            yield DecodedPanel("Decoded\nWaiting for long status...", id="decoded-box")
        yield Label(" Commands & Responses", id="cmd-title")
        yield RichLog(highlight=True, markup=True, wrap=True, id="cmd-log")
        yield Label(" Raw Feed", id="raw-title")
        yield RichLog(highlight=True, markup=True, wrap=True, id="raw-log")
        yield Input(placeholder="Command: 4-digit hex (e.g. 0303) or PIN:XXXXXX - Enter to send")
        yield Footer()

    async def on_mount(self) -> None:
        self.ui_thread_id = threading.get_ident()
        self.run_worker(self.ble_connect(), exclusive=True)

    def set_connection_status(self, message: str, style: str = "white") -> None:
        status = self.query_one("#connection-status", Static)
        status.update(Text(message, style=style))

    def set_display_mode_label(self) -> None:
        mode = self.display_mode.upper()
        pause = f"PAUSED, skipped={self.paused_count}" if self.paused else "LIVE"
        label = self.query_one("#display-mode", Static)
        style = "bold yellow" if self.paused else "cyan"
        label.update(
            Text(f"Display: {mode} / BYTE | {pause} (F2 mode, P pause)", style=style)
        )

    def refresh_status_format(self) -> None:
        self.query_one("#status-box", StatusPanel).set_format(self.display_mode)
        self.query_one("#decoded-box", DecodedPanel).set_format(self.display_mode)

    def action_toggle_display_mode(self) -> None:
        modes: list[DisplayMode] = ["bin", "oct", "hex"]
        self.display_mode = modes[(modes.index(self.display_mode) + 1) % len(modes)]
        self.set_display_mode_label()
        self.refresh_status_format()
        raw_log = self.query_one("#raw-log", RichLog)
        mode = {
            "bin": "binary",
            "oct": "octal",
            "hex": "hex",
        }[self.display_mode]
        raw_log.write(Text(f"Display mode changed to {mode}", style="cyan"))

    def action_toggle_pause(self) -> None:
        self.paused = not self.paused
        if self.paused:
            self.paused_count = 0
        self.set_display_mode_label()
        raw_log = self.query_one("#raw-log", RichLog)
        message = (
            "Paused incoming display updates"
            if self.paused
            else "Resumed incoming display updates"
        )
        style = "bold yellow" if self.paused else "bold green"
        raw_log.write(Text(message, style=style))

    def debug_log(self, message: str) -> None:
        if not self.debug_enabled:
            return
        raw_log = self.query_one("#raw-log", RichLog)
        now = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        raw_log.write(Text(f"{now}  [debug] {message}", style="blue"))

    def process_line(self, text: str) -> None:
        if self.paused:
            self.paused_count += 1
            self.set_display_mode_label()
            return

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
                entry.append(
                    format_bytes(data, self.display_mode),
                    style="bold white",
                )
                cmd_log.write(entry)

            elif data_len <= 12:
                status.update_short(data)

            else:
                status.update_long(data)
                self.query_one("#decoded-box", DecodedPanel).update_long(data)

        elif text.startswith("[W] "):
            data = text[4:]
            entry = Text()
            entry.append(f"{now}  ", style="dim")
            entry.append("→ ", style="green")
            entry.append("[W] ", style="bold green")
            entry.append(
                format_bytes(data, self.display_mode),
                style="bold white",
            )
            cmd_log.write(entry)

        elif text.startswith("[SENT] "):
            data = text[7:]
            entry = Text()
            entry.append(f"{now}  ", style="dim")
            entry.append("⚡ ", style="magenta")
            entry.append("[SENT] ", style="bold magenta")
            entry.append(
                format_bytes(data, self.display_mode),
                style="bold white",
            )
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
        self.last_notify_at = monotonic()
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
                self.set_connection_status("Scanning", "cyan")
                raw_log.write(
                    Text(f"Scanning for '{self.device_name}'...", style="cyan")
                )

                device = await BleakScanner.find_device_by_name(
                    self.device_name, timeout=10.0
                )
                if not device:
                    self.set_connection_status("Device not found; retrying", "yellow")
                    raw_log.write(Text("Device not found. Retrying...", style="yellow"))
                    await asyncio.sleep(3)
                    continue

                raw_log.write(
                    Text(f"Found {device.name} ({device.address})", style="cyan")
                )

                self.ble_client = BleakClient(device, timeout=15.0)
                self.set_connection_status("Connecting", "cyan")
                await self.ble_client.connect()

                if not self.ble_client.is_connected:
                    self.set_connection_status("Connection failed", "red")
                    raw_log.write(Text("Connection failed", style="red"))
                    await asyncio.sleep(3)
                    continue

                self.set_connection_status("Connected; subscribing", "green")
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
                self.subscribed_at = monotonic()
                self.last_notify_at = None
                self.warned_no_notify = False
                self.notify_count = 0
                self.set_connection_status("Subscribed; waiting for chair data", "green")
                raw_log.write(Text("Subscribed to chair data notifications", style="bold green"))

                try:
                    value = await self.ble_client.read_gatt_char(CHAR_DATA_UUID)
                    raw_log.write(Text(f"[debug] initial read: {value!r}", style="blue"))
                except Exception as e:
                    raw_log.write(Text(f"[debug] initial read failed: {e}", style="blue"))

                # Stay alive while connected
                while self.ble_client.is_connected:
                    now = monotonic()
                    if self.last_notify_at is None:
                        elapsed = now - (self.subscribed_at or now)
                        self.set_connection_status(
                            f"Subscribed; no notifications yet ({elapsed:.0f}s)",
                            "yellow" if elapsed >= 5 else "green",
                        )
                        if elapsed >= 5 and not self.warned_no_notify:
                            raw_log.write(
                                Text(
                                    "Subscribed, but no BLE notifications received yet",
                                    style="bold yellow",
                                )
                            )
                            self.warned_no_notify = True
                    else:
                        age = now - self.last_notify_at
                        self.set_connection_status(
                            f"Receiving; notifications={self.notify_count}, last={age:.0f}s ago",
                            "green" if age < 5 else "yellow",
                        )
                    self.debug_log(f"connected; notifications received={self.notify_count}")
                    await asyncio.sleep(1)

                self.set_connection_status("Disconnected; retrying", "yellow")
                raw_log.write(Text("Disconnected", style="yellow"))

            except Exception as e:
                self.set_connection_status("BLE error; retrying", "red")
                raw_log.write(Text(f"BLE error: {e}", style="red"))
                await asyncio.sleep(3)

    async def on_input_submitted(self, event: Input.Submitted) -> None:
        cmd = event.value.strip().upper()
        cmd_log = self.query_one("#cmd-log", RichLog)

        if not cmd:
            return

        if not self.ble_client or not self.ble_client.is_connected:
            cmd_log.write(Text("Not connected!", style="bold red"))
            event.input.clear()
            return

        # Validate
        is_pin_cmd = cmd.startswith("PIN:") and len(cmd) == 10 and cmd[4:].isdigit()
        is_chair_cmd = is_hex_code(cmd, 4)

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
