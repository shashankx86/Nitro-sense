# Nitro Sense TUI

Minimal flat curses UI for controlling supported `linuwu_sense` sysfs nodes.

## Run

```bash
python3 app/nitro_sense_tui.py
```

Arch package build:

```bash
cd app
makepkg -si
```

## Controls

- `Up/Down`: select setting
- `Enter`: apply or edit selected setting
- `r`: refresh detected feature list
- `q`: quit

## Notes

- You need read/write permissions for relevant sysfs nodes.
- Works with both `predator_sense` and `nitro_sense` model paths when present.
