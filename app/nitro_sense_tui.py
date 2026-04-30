#!/usr/bin/env python3
import curses
import os
import re
from dataclasses import dataclass
from typing import Callable, List, Optional, Tuple


SYSFS_ROOT = "/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi"
PROFILE_PATH = "/sys/firmware/acpi/platform_profile"
PROFILE_CHOICES_PATH = "/sys/firmware/acpi/platform_profile_choices"


def first_existing(paths: List[str]) -> Optional[str]:
    for path in paths:
        if os.path.exists(path):
            return path
    return None


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read().strip()


def write_text(path: str, value: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write(value)


def safe_read(path: str) -> str:
    try:
        return read_text(path)
    except Exception as exc:
        return f"err: {exc}"


def parse_profile_choices(text: str) -> List[str]:
    text = text.strip()
    if not text:
        return []
    return text.split()


def normalize_bool_text(text: str) -> Optional[str]:
    value = text.strip().lower()
    if value in {"1", "on", "enabled", "enable", "true", "yes"}:
        return "1"
    if value in {"0", "off", "disabled", "disable", "false", "no"}:
        return "0"
    return None


def validate_fan_input(raw: str) -> str:
    text = raw.strip().lower()
    if text == "auto":
        return "0,0"
    if not re.fullmatch(r"\d{1,3},\d{1,3}", text):
        raise ValueError("expected cpu,gpu (0-100)")
    cpu_s, gpu_s = text.split(",", 1)
    cpu = int(cpu_s)
    gpu = int(gpu_s)
    if not (0 <= cpu <= 100 and 0 <= gpu <= 100):
        raise ValueError("fan values must be 0-100")
    return f"{cpu},{gpu}"


def validate_per_zone_input(raw: str) -> str:
    text = raw.strip().lower()
    if not re.fullmatch(
        r"[0-9a-f]{6},[0-9a-f]{6},[0-9a-f]{6},[0-9a-f]{6},\d{1,3}", text
    ):
        raise ValueError("expected z1,z2,z3,z4,brightness")
    parts = text.split(",")
    brightness = int(parts[-1])
    if not (0 <= brightness <= 100):
        raise ValueError("brightness must be 0-100")
    return text


@dataclass
class Setting:
    label: str
    read_cb: Callable[[], str]
    apply_cb: Callable[["ScreenUI"], None]
    hint: str


class ScreenUI:
    def __init__(self, stdscr: "curses._CursesWindow"):
        self.stdscr = stdscr
        self.status = "Ready"
        self.cursor = 0

        model_base = first_existing(
            [
                os.path.join(SYSFS_ROOT, "predator_sense"),
                os.path.join(SYSFS_ROOT, "nitro_sense"),
            ]
        )
        self.model_name = os.path.basename(model_base) if model_base else "not-detected"
        self.model_base = model_base
        self.kb_base = os.path.join(SYSFS_ROOT, "four_zoned_kb")
        self.settings = self.build_settings()

    def path(self, name: str) -> Optional[str]:
        if not self.model_base:
            return None
        candidate = os.path.join(self.model_base, name)
        return candidate if os.path.exists(candidate) else None

    def kb_path(self, name: str) -> Optional[str]:
        candidate = os.path.join(self.kb_base, name)
        return candidate if os.path.exists(candidate) else None

    def set_status(self, message: str) -> None:
        self.status = message

    def read_path(self, path: Optional[str]) -> str:
        if not path:
            return "n/a"
        return safe_read(path)

    def ask(self, prompt: str) -> Optional[str]:
        curses.echo()
        curses.curs_set(1)
        max_y, max_x = self.stdscr.getmaxyx()
        self.stdscr.attron(curses.color_pair(3))
        self.stdscr.addstr(max_y - 2, 0, " " * (max_x - 1))
        self.stdscr.addstr(max_y - 2, 0, prompt[: max_x - 2])
        self.stdscr.attroff(curses.color_pair(3))
        self.stdscr.refresh()
        try:
            value = self.stdscr.getstr(max_y - 2, min(len(prompt), max_x - 2), max_x - len(prompt) - 2)
        except Exception:
            value = b""
        curses.noecho()
        curses.curs_set(0)
        text = value.decode("utf-8", errors="ignore").strip()
        return text or None

    def write_bool(self, path: Optional[str]) -> None:
        if not path:
            self.set_status("Setting unavailable on this model")
            return
        current = self.read_path(path)
        current_norm = normalize_bool_text(current)
        if current_norm is None:
            self.set_status(f"Cannot toggle invalid value: {current}")
            return
        next_value = "0" if current_norm == "1" else "1"
        try:
            write_text(path, next_value)
            self.set_status(f"Updated -> {next_value}")
        except Exception as exc:
            self.set_status(f"Write failed: {exc}")

    def cycle_profile(self) -> None:
        if not os.path.exists(PROFILE_PATH) or not os.path.exists(PROFILE_CHOICES_PATH):
            self.set_status("platform_profile is not available")
            return
        try:
            current = read_text(PROFILE_PATH)
            choices = parse_profile_choices(read_text(PROFILE_CHOICES_PATH))
            if not choices:
                self.set_status("No platform_profile choices")
                return
            if current not in choices:
                target = choices[0]
            else:
                target = choices[(choices.index(current) + 1) % len(choices)]
            write_text(PROFILE_PATH, target)
            self.set_status(f"platform_profile -> {target}")
        except Exception as exc:
            self.set_status(f"Profile switch failed: {exc}")

    def set_fan(self) -> None:
        path = self.path("fan_speed")
        if not path:
            self.set_status("fan_speed unavailable")
            return
        typed = self.ask("fan cpu,gpu or auto: ")
        if typed is None:
            self.set_status("Cancelled")
            return
        try:
            value = validate_fan_input(typed)
            write_text(path, value)
            self.set_status(f"fan_speed -> {value}")
        except Exception as exc:
            self.set_status(f"Invalid fan value: {exc}")

    def cycle_usb(self) -> None:
        path = self.path("usb_charging")
        if not path:
            self.set_status("usb_charging unavailable")
            return
        try:
            current = read_text(path)
            options = ["0", "10", "20", "30"]
            target = options[0]
            if current in options:
                target = options[(options.index(current) + 1) % len(options)]
            write_text(path, target)
            self.set_status(f"usb_charging -> {target}")
        except Exception as exc:
            self.set_status(f"USB toggle failed: {exc}")

    def set_per_zone(self) -> None:
        path = self.kb_path("per_zone_mode")
        if not path:
            self.set_status("per_zone_mode unavailable")
            return
        typed = self.ask("z1,z2,z3,z4,brightness: ")
        if typed is None:
            self.set_status("Cancelled")
            return
        try:
            value = validate_per_zone_input(typed)
            write_text(path, value)
            self.set_status("Applied per-zone RGB")
        except Exception as exc:
            self.set_status(f"Invalid per-zone value: {exc}")

    def bool_setting(self, name: str, label: str, hint: str) -> Optional[Setting]:
        path = self.path(name)
        if not path:
            return None
        return Setting(
            label=label,
            read_cb=lambda p=path: self.read_path(p),
            apply_cb=lambda _ui, p=path: self.write_bool(p),
            hint=hint,
        )

    def build_settings(self) -> List[Setting]:
        settings: List[Setting] = []

        settings.append(
            Setting(
                label="Platform Profile",
                read_cb=lambda: self.read_path(PROFILE_PATH if os.path.exists(PROFILE_PATH) else None),
                apply_cb=lambda _ui: self.cycle_profile(),
                hint="Cycle available ACPI profile",
            )
        )

        if self.path("fan_speed"):
            settings.append(
                Setting(
                    label="Fan Speed",
                    read_cb=lambda: self.read_path(self.path("fan_speed")),
                    apply_cb=lambda _ui: self.set_fan(),
                    hint="Set cpu,gpu in range 0-100",
                )
            )

        limiter = self.bool_setting("battery_limiter", "Battery Limiter", "Toggle 80% charge limiter")
        if limiter:
            settings.append(limiter)

        calibration = self.bool_setting(
            "battery_calibration", "Battery Calibration", "Start or stop calibration"
        )
        if calibration:
            settings.append(calibration)

        if self.path("usb_charging"):
            settings.append(
                Setting(
                    label="USB Charging",
                    read_cb=lambda: self.read_path(self.path("usb_charging")),
                    apply_cb=lambda _ui: self.cycle_usb(),
                    hint="Cycle 0 -> 10 -> 20 -> 30",
                )
            )

        for sys_name, ui_name, hint in [
            ("backlight_timeout", "Backlight Timeout", "Toggle keyboard timeout"),
            ("boot_animation_sound", "Boot Animation Sound", "Toggle boot sound"),
            ("lcd_override", "LCD Override", "Toggle LCD override"),
        ]:
            setting = self.bool_setting(sys_name, ui_name, hint)
            if setting:
                settings.append(setting)

        if self.kb_path("per_zone_mode"):
            settings.append(
                Setting(
                    label="Per-Zone RGB",
                    read_cb=lambda: self.read_path(self.kb_path("per_zone_mode")),
                    apply_cb=lambda _ui: self.set_per_zone(),
                    hint="Set z1,z2,z3,z4,brightness",
                )
            )

        return settings

    def draw(self) -> None:
        self.stdscr.erase()
        max_y, max_x = self.stdscr.getmaxyx()

        title = "Nitro Sense - Flat TUI"
        subtitle = f"Model: {self.model_name}"
        self.stdscr.attron(curses.color_pair(2))
        self.stdscr.addstr(0, 0, title[: max_x - 1])
        self.stdscr.attroff(curses.color_pair(2))
        self.stdscr.addstr(1, 0, subtitle[: max_x - 1])

        list_top = 3
        view_height = max(1, max_y - 7)
        start = 0
        if self.cursor >= view_height:
            start = self.cursor - view_height + 1

        for i in range(start, min(len(self.settings), start + view_height)):
            row = list_top + (i - start)
            setting = self.settings[i]
            value = setting.read_cb()
            line = f"{setting.label:<22} {value}"
            if i == self.cursor:
                self.stdscr.attron(curses.color_pair(1))
                self.stdscr.addstr(row, 0, line[: max_x - 1])
                self.stdscr.attroff(curses.color_pair(1))
            else:
                self.stdscr.addstr(row, 0, line[: max_x - 1])

        hint = self.settings[self.cursor].hint if self.settings else "No settings detected"
        self.stdscr.attron(curses.color_pair(3))
        self.stdscr.addstr(max_y - 3, 0, (hint + " " * max_x)[: max_x - 1])
        self.stdscr.addstr(max_y - 2, 0, (self.status + " " * max_x)[: max_x - 1])
        self.stdscr.attroff(curses.color_pair(3))
        self.stdscr.addstr(max_y - 1, 0, "Up/Down: move  Enter: apply/edit  r: refresh  q: quit"[: max_x - 1])

        self.stdscr.refresh()

    def run(self) -> None:
        curses.curs_set(0)
        self.stdscr.nodelay(False)
        self.stdscr.keypad(True)
        curses.use_default_colors()
        curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_CYAN)
        curses.init_pair(2, curses.COLOR_CYAN, -1)
        curses.init_pair(3, curses.COLOR_BLACK, curses.COLOR_WHITE)

        if not self.settings:
            self.set_status("No supported sysfs nodes found. Is linuwu_sense loaded?")

        while True:
            self.draw()
            key = self.stdscr.getch()
            if key in (ord("q"), ord("Q")):
                break
            if key in (ord("r"), ord("R")):
                self.settings = self.build_settings()
                self.cursor = min(self.cursor, max(0, len(self.settings) - 1))
                self.set_status("Refreshed")
                continue
            if key == curses.KEY_UP and self.settings:
                self.cursor = (self.cursor - 1) % len(self.settings)
                continue
            if key == curses.KEY_DOWN and self.settings:
                self.cursor = (self.cursor + 1) % len(self.settings)
                continue
            if key in (curses.KEY_ENTER, 10, 13) and self.settings:
                self.settings[self.cursor].apply_cb(self)


def main(stdscr: "curses._CursesWindow") -> None:
    ScreenUI(stdscr).run()


if __name__ == "__main__":
    curses.wrapper(main)
