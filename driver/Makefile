obj-m := src/nitro_sense.o

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
PWD := $(shell pwd)
KBUILD_TOOLCHAIN :=

MODULE_NAME := nitro_sense

ifeq ($(wildcard $(KDIR)/.config),$(KDIR)/.config)
ifeq ($(shell grep -Eq '^CONFIG_CC_IS_CLANG=y' "$(KDIR)/.config" && echo y),y)
KBUILD_TOOLCHAIN := LLVM=1
endif
endif

all:
	$(MAKE) -C $(KDIR) M=$(PWD) $(KBUILD_TOOLCHAIN) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

install: all
	$(MAKE) -C $(KDIR) M=$(PWD) $(KBUILD_TOOLCHAIN) modules_install
	install -D -m 644 nitro_sense.conf /etc/modprobe.d/nitro_sense.conf
	install -D -m 644 nitro_sense.modules-load /etc/modules-load.d/nitro_sense.conf
	depmod -a $(KVER)
	@echo "Module installed for kernel $(KVER)"
	@echo "Load with: sudo modprobe $(MODULE_NAME)"

uninstall:
	rm -f /lib/modules/$(KVER)/extra/$(MODULE_NAME).ko*
	rm -f /lib/modules/$(KVER)/updates/dkms/$(MODULE_NAME).ko*
	rm -f /etc/modprobe.d/nitro_sense.conf
	rm -f /etc/modules-load.d/nitro_sense.conf
	depmod -a $(KVER)
	@echo "Module uninstalled for kernel $(KVER)"
