obj-m := src/linuwu_sense.o

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
PWD := $(shell pwd)
KBUILD_TOOLCHAIN :=

ifeq ($(wildcard $(KDIR)/.config),$(KDIR)/.config)
ifeq ($(shell grep -Eq '^CONFIG_CC_IS_CLANG=y' "$(KDIR)/.config" && echo y),y)
KBUILD_TOOLCHAIN := LLVM=1
endif
endif

ifneq ($(KERNELRELEASE),)
obj-m := src/linuwu_sense.o
else

all:
	$(MAKE) -C $(KDIR) M=$(PWD) $(KBUILD_TOOLCHAIN) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
endif
