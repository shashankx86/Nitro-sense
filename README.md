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
It also installs modprobe/modules-load snippets for `nitro_sense`.

### 2) Build/install the curses UI

```bash
cd app
makepkg -si
```

### 3) Load module

```bash
sudo modprobe nitro_sense
```

## Run UI

```bash
nitro-sense-tui
```

## Notes

- The app auto-detects `predator_sense` or `nitro_sense` sysfs model paths.
- Some settings are only shown when supported by your model.
- You need sufficient permissions to write the sysfs control nodes.
