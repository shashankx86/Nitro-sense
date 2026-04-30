# Nitro Sense (Linux)

Nitro Sense is a split project:

- `driver/`: Nitro Sense kernel module source + DKMS packaging
- `app/`: minimal modern flat curses UI for controlling exposed sysfs nodes

## Arch Linux install

### 1) Install DKMS driver package

```bash
cd driver
makepkg -si
```

This installs DKMS sources under `/usr/src/nitro-sense-<version>`.
It also installs modprobe/modules-load snippets for `nitro_sense`, loads the module after install, and grants the exposed sysfs controls to your current primary group so the UI can run immediately without `sudo`.

### 2) Build/install the curses UI

```bash
cd app
makepkg -si
```

## Run UI

```bash
nitro-sense-tui
```

## Notes

- The app auto-detects `predator_sense` or `nitro_sense` sysfs model paths.
- Some settings are only shown when supported by your model.
- `scripts/nitros-install.sh` accepts `all`, `app`, or `driver` for `install` and `uninstall`. If omitted, it defaults to `all`.
- If you install with `scripts/nitros-install.sh install`, it creates a `nitro_sense` group and applies sysfs permissions so `nitros` can run without `sudo`.
- After first install, log out/in (or run `newgrp nitro_sense`) so your user picks up the new group.
- If you install the packaged driver with `cd driver && makepkg -si`, no extra group refresh is needed. The package grants access to your existing primary group and reapplies it on boot.
