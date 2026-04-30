# Nitro Sense Driver

This directory contains a kernel module source for Nitro Sense based Acer Nitro/Predator laptops,
used as the hardware control backend.

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

Install driver:

```bash
sudo make install
```

Build Arch Linux DKMS package:

```bash
makepkg -si
```

The package also installs:

- `/usr/lib/modprobe.d/nitro_sense.conf` to blacklist `acer_wmi`
- `/usr/lib/modules-load.d/nitro_sense.conf` to auto-load `nitro_sense`
- a post-transaction pacman hook that loads `nitro_sense` after install/upgrade
- a boot-time service that reapplies sysfs permissions to the installing user's primary group
