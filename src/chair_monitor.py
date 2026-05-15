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
from textual import events
from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widgets import Header, Footer, Static, RichLog, Input, Label
from textual.binding import Binding
from rich.text import Text

from chair_decode import (
    DisplayMode,
    decode_long_status,
    decode_short_status,
    format_byte,
    format_byte_list,
    format_bytes,
    is_hex_chunk,
    is_hex_code,
    long_known_bit_masks,
    short_known_bit_masks,
    split_bytes,
    unknown_bit_strings,
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


def highlight_unknown_bits(old: str, new: str, label: str, long_status: bool) -> Text:
    old_units = unknown_bit_strings(
        old,
        long_known_bit_masks(old) if long_status else short_known_bit_masks(old),
    )
    new_units = unknown_bit_strings(
        new,
        long_known_bit_masks(new) if long_status else short_known_bit_masks(new),
    )
    result = Text()
    result.append(f"{label}: ", style="bold cyan")

    for unit_index, unit in enumerate(new_units):
        old_unit = old_units[unit_index] if unit_index < len(old_units) else ""
        for char_index, char in enumerate(unit):
            style = "dim" if char == "." else "white"
            if char != "." and (
                char_index >= len(old_unit) or char != old_unit[char_index]
            ):
                style = "bold red"
            result.append(char, style=style)
        if unit_index < len(new_units) - 1:
            result.append(" ", style="white")

    return result


def append_bit_headers(content: Text, label: str, data: str) -> None:
    bytes_ = split_bytes(data)
    if not bytes_:
        return

    prefix = " " * (len(label) + 2)
    byte_labels = " ".join(f"B{index}".center(8) for index in range(len(bytes_)))
    bit_labels = " ".join("76543210" for _ in bytes_)
    content.append(prefix + byte_labels + "\n", style="dim")
    content.append(prefix + bit_labels + "\n", style="dim")


class StatusPanel(Static):
    prev_short: str = ""
    prev_long: str = ""
    curr_short: str = ""
    curr_long: str = ""
    display_mode: DisplayMode = "bin"
    show_full_raw = False

    def set_format(self, display_mode: DisplayMode, show_full_raw: bool) -> None:
        self.display_mode = display_mode
        self.show_full_raw = show_full_raw
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
        mode = "full raw" if self.show_full_raw else "unknown flags"
        content.append(f"Chair Status ({mode})\n", style="bold green")
        if self.curr_short:
            if self.display_mode == "bin":
                append_bit_headers(content, "Short", self.curr_short)
            if self.show_full_raw:
                content.append_text(
                    highlight_diff(
                        self.prev_short,
                        self.curr_short,
                        "Short",
                        self.display_mode,
                    )
                )
            else:
                content.append_text(
                    highlight_unknown_bits(
                        self.prev_short,
                        self.curr_short,
                        "Short",
                        False,
                    )
                )
        content.append("\n")
        if self.curr_long:
            if self.display_mode == "bin":
                append_bit_headers(content, " Long", self.curr_long)
            if self.show_full_raw:
                content.append_text(
                    highlight_diff(
                        self.prev_long,
                        self.curr_long,
                        " Long",
                        self.display_mode,
                    )
                )
            else:
                content.append_text(
                    highlight_unknown_bits(
                        self.prev_long,
                        self.curr_long,
                        " Long",
                        True,
                    )
                )
        elif not self.curr_short:
            content.append("Waiting for data...", style="dim")
        self.update(content)


class DecodedPanel(Static):
    curr_short: str = ""
    curr_long: str = ""
    display_mode: DisplayMode = "bin"

    def set_format(self, display_mode: DisplayMode) -> None:
        self.display_mode = display_mode
        self._render_decoded()

    def update_long(self, data: str) -> None:
        self.curr_long = data
        self._render_decoded()

    def update_short(self, data: str) -> None:
        self.curr_short = data
        self._render_decoded()

    def _render_decoded(self) -> None:
        content = Text()
        if not self.curr_short and not self.curr_long:
            content.append("Decoded\n", style="bold cyan")
            content.append("Waiting for status...", style="dim")
            self.update(content)
            return

        content.append("Decoded\n", style="bold cyan")
        if self.curr_short:
            decoded_short = decode_short_status(self.curr_short)
            area = decoded_short.massage_area
            content.append("Area?: ", style="bold cyan")
            if area.state == "unknown":
                content.append("unknown", style="yellow")
            elif area.state == "reserved":
                content.append("reserved", style="yellow")
            else:
                content.append(area.state, style="bold green")
            content.append(f"  B4[b2:b1]={area.raw}", style="dim")

        if not self.curr_long:
            self.update(content)
            return

        if self.curr_short:
            content.append("\n")
        decoded = decode_long_status(self.curr_long)

        packed_timer = decoded.packed_timer
        content.append("Timer: ", style="bold cyan")
        if packed_timer is None:
            content.append("no candidate", style="yellow")
        else:
            content.append(f"{packed_timer.minutes} min", style="bold green")
            content.append("  B1..B3 ", style="dim")
            content.append(
                f"({format_byte_list(packed_timer.raw.split(), self.display_mode)})",
                style="white",
            )
            content.append(
                f"  seg={packed_timer.tens_segment}/{packed_timer.ones_segment}",
                style="dim",
            )

        heater = decoded.heater
        air = decoded.air
        massage_speed = decoded.massage_speed
        motion = decoded.motion
        width = decoded.width
        foot_roller = decoded.foot_roller
        content.append("\nAir?: ", style="bold cyan")
        if air.state == "on":
            content.append("on", style="bold green")
        elif air.state == "off":
            content.append("off", style="bold yellow")
        else:
            content.append("unknown", style="yellow")
        content.append(f"  strength={air.strength}", style="white")
        content.append(
            f"  B4[b4]={air.raw_enable} B4[b6:b5]={air.raw_strength}",
            style="dim",
        )

        content.append("\nSpeed?: ", style="bold cyan")
        if massage_speed.state == "unknown":
            content.append("unknown", style="yellow")
        elif massage_speed.state == "reserved":
            content.append("reserved", style="yellow")
        else:
            content.append(f"{massage_speed.state}", style="bold green")
        content.append(f"  B5[b3:b2]={massage_speed.raw}", style="dim")

        content.append("\nMotion?: ", style="bold cyan")
        if motion.active == "on":
            content.append("moving", style="bold green")
        elif motion.active == "off":
            content.append("idle", style="bold yellow")
        else:
            content.append("unknown", style="yellow")
        content.append(f"  B6[b4]={motion.raw_active}", style="dim")

        content.append("\nBack?: ", style="bold cyan")
        content.append(
            f"raise={motion.back_raise} recline={motion.back_recline}",
            style="white",
        )
        content.append(
            f"  B6[b2]={motion.raw_back_raise} B6[b3]={motion.raw_back_recline}",
            style="dim",
        )

        content.append("\nLeg?: ", style="bold cyan")
        content.append(
            f"raise={motion.leg_raise} recline={motion.leg_recline}",
            style="white",
        )
        content.append(
            f"  B6[b6]={motion.raw_leg_raise} B6[b5]={motion.raw_leg_recline}",
            style="dim",
        )

        content.append("\nWidth?: ", style="bold cyan")
        if width.state == "unknown":
            content.append("unknown", style="yellow")
        elif width.state == "reserved":
            content.append("reserved", style="yellow")
        else:
            content.append(width.state, style="bold green")
        content.append(f"  B6[b1:b0]={width.raw}", style="dim")

        content.append("\nFoot roller?: ", style="bold cyan")
        if foot_roller.state == "on":
            content.append("on", style="bold green")
        elif foot_roller.state == "off":
            content.append("off", style="bold yellow")
        else:
            content.append("unknown", style="yellow")
        content.append(f"  B6[b7]={foot_roller.raw}", style="dim")

        content.append("\nHeater?: ", style="bold cyan")
        if heater.state == "on":
            content.append("on", style="bold green")
        elif heater.state == "off":
            content.append("off", style="bold yellow")
        else:
            content.append("unknown", style="yellow")
        content.append(f"  last byte={heater.raw}", style="dim")

        self.update(content)


class ResizeHandle(Static):
    def on_mouse_down(self, event: events.MouseDown) -> None:
        self.capture_mouse()
        self.app.start_log_resize()
        event.stop()

    def on_mouse_move(self, event: events.MouseMove) -> None:
        if self.app.is_resizing_logs and event.delta_y:
            self.app.adjust_log_resize(event.delta_y)
            event.stop()

    def on_mouse_up(self, event: events.MouseUp) -> None:
        if self.app.is_resizing_logs:
            self.app.finish_log_resize()
            self.release_mouse()
            event.stop()


class ChairMonitor(App):
    CSS = """
    Screen {
        layout: vertical;
    }
    #status-row {
        height: 12;
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
    #resize-handle {
        height: 1;
        color: gray;
        background: $surface;
        text-align: center;
    }
    #log-row {
        height: 1fr;
    }
    #cmd-panel {
        height: 1fr;
        width: 1fr;
    }
    #raw-panel {
        height: 1fr;
        width: 1fr;
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
        height: 1fr;
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
        Binding("space", "toggle_status_raw", "Raw/Unknown"),
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
        self.show_full_status_raw = False
        self.paused = False
        self.paused_count = 0
        self.status_row_height = 12
        self.is_resizing_logs = False

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(
            "Display: BIN / BYTE | UNKNOWN | LIVE (F2 mode, Space raw, P pause)",
            id="display-mode",
        )
        yield Static("Disconnected", id="connection-status")
        with Horizontal(id="status-row"):
            yield StatusPanel("Chair Status\nWaiting for data...", id="status-box")
            yield DecodedPanel("Decoded\nWaiting for long status...", id="decoded-box")
        yield ResizeHandle(" drag to resize ", id="resize-handle")
        with Horizontal(id="log-row"):
            with Vertical(id="cmd-panel"):
                yield Label(" Commands & Responses", id="cmd-title")
                yield RichLog(highlight=True, markup=True, wrap=True, id="cmd-log")
            with Vertical(id="raw-panel"):
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
        status_mode = "RAW" if self.show_full_status_raw else "UNKNOWN"
        pause = f"PAUSED, skipped={self.paused_count}" if self.paused else "LIVE"
        label = self.query_one("#display-mode", Static)
        style = "bold yellow" if self.paused else "cyan"
        label.update(
            Text(
                f"Display: {mode} / BYTE | {status_mode} | {pause} "
                "(F2 mode, Space raw, P pause)",
                style=style,
            )
        )

    def refresh_status_format(self) -> None:
        self.query_one("#status-box", StatusPanel).set_format(
            self.display_mode,
            self.show_full_status_raw,
        )
        self.query_one("#decoded-box", DecodedPanel).set_format(self.display_mode)

    def start_log_resize(self) -> None:
        self.is_resizing_logs = True

    def adjust_log_resize(self, delta_y: int) -> None:
        status_row = self.query_one("#status-row", Horizontal)
        self.status_row_height = max(7, min(24, self.status_row_height + delta_y))
        status_row.styles.height = self.status_row_height

    def finish_log_resize(self) -> None:
        self.is_resizing_logs = False

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

    def action_toggle_status_raw(self) -> None:
        self.show_full_status_raw = not self.show_full_status_raw
        self.set_display_mode_label()
        self.refresh_status_format()
        raw_log = self.query_one("#raw-log", RichLog)
        mode = "full raw" if self.show_full_status_raw else "unknown flags"
        raw_log.write(Text(f"Chair status changed to {mode}", style="cyan"))

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
                self.query_one("#decoded-box", DecodedPanel).update_short(data)

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
