# Nitro Sense Driver Base

This directory contains a vendor base of the Linuwu Sense kernel module source,
used as the hardware control backend for Nitro Sense.

Source base:
- https://github.com/0x7375646F/Linuwu-Sense

Build locally:

```bash
make
```

Clean build artifacts:

```bash
make clean
```

Build Arch Linux DKMS package:

```bash
makepkg -si
```

The package also installs:

- `/usr/lib/modprobe.d/linuwu_sense.conf` to blacklist `acer_wmi`
- `/usr/lib/modules-load.d/linuwu_sense.conf` to auto-load `linuwu_sense`
