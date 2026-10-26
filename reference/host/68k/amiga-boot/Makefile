# Makefile — Amiga RBCP Kickstart Bootloader
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Requires:
#   vasmm68k_mot  Motorola 68K assembler from http://sun.hasenbraten.de/vasm/
#                 (no official git repo — the tarball is upstream)
#                   make CPU=m68k SYNTAX=mot
#   font_8x8.bin  2048-byte CP437/ASCII 8x8 bitmap font in ../amiga-common
#                 (256 glyphs * 8 bytes, no header)
#
# The device serves a slot in its own byte order, so the build also writes a
# byte-swapped image.  That is the one to program.
#
# BUS=32 builds for a 32-bit Amiga, the A1200 for example, where a pair of
# devices serve the high and low words of a 512 KB Kickstart.  ROM_KB is then
# each device's size, and the build writes one image per device in the
# device's byte order.  A 512 KB image holds its 256 KB half twice.
#
# Build:   make
# 32-bit:  make BUS=32 [ROM_KB=512]
# Images:  make images
# Clean:   make clean
#
# The ROM size comes from CONFIG_ROM_KB in rbcp_config.s — change it there,
# not here, so the assembler and this size check cannot disagree.

AS        = vasmm68k_mot
ASFLAGS   = -m68000 -Fbin -I . -I ../rbcp -I ../amiga-common

BUILD     = build
NAME      = amiga_boot
SRC       = amiga_boot.s
TARGET    = $(BUILD)/$(NAME).bin
SWAPPED   = $(BUILD)/$(NAME)_swapped.bin
COMMON    = ../amiga-common
FONT      = $(COMMON)/font_8x8.bin

# ROM size in KB, 256 or 512.  Defaults to the value in rbcp_config.s.  Override
# it on the command line for a 512 KB (27C400) socket:  make ROM_KB=512
ROM_KB    ?= $(shell sed -n 's/^CONFIG_ROM_KB[[:space:]][[:space:]]*EQU[[:space:]][[:space:]]*\([0-9][0-9]*\).*/\1/p' rbcp_config.s)
ROM_BYTES := $(shell expr $(ROM_KB) \* 1024)

# make writes the same file names whichever size it built, so a size change
# alone leaves make with nothing out of date.  The size that built the image
# is recorded beside it, and a build for a different size depends on FORCE,
# which is never up to date.  make images needs none of this because its two
# images have different names.
ROM_KB_FILE = $(BUILD)/rom_kb
LAST_ROM_KB := $(shell cat $(ROM_KB_FILE) 2>/dev/null)
ifneq ($(LAST_ROM_KB),$(ROM_KB))
ROM_KB_DEP = FORCE
endif

# The CPU image is the whole 512 KB Kickstart as the CPU reads it, under
# build/32bit/.  The 32-bit build splits it into one image per device.
BUS       ?= 16
ifneq ($(BUS),16)
ifneq ($(BUS),32)
$(error BUS must be 16 or 32)
endif
endif
WIDE      = $(BUILD)/$(NAME)_32bit
WIDE_CPU  = $(BUILD)/32bit/$(NAME)
WIDE_ALL  = $(WIDE)_256k_hi.bin $(WIDE)_256k_lo.bin \
            $(WIDE)_512k_hi.bin $(WIDE)_512k_lo.bin

# split — $(1) the CPU image, $(2) 0 for the high word or 2 for the low,
# $(3) the output, $(4) how many copies of the half it holds.  The half is
# written in the device's byte order.
split = python3 -c 'import sys; d = open(sys.argv[1], "rb").read(); o = int(sys.argv[2]); open(sys.argv[3], "wb").write(b"".join(d[i+o+1:i+o+2] + d[i+o:i+o+1] for i in range(0, len(d), 4)) * int(sys.argv[4]))' $(1) $(2) $(3) $(4)

# DEV=1 builds a bench copy whose menu always appears, however the mouse
# buttons read.  See CONFIG_DEV_ALWAYS_MENU in amiga_config.s.
DEV       ?= 0
ASFLAGS  += -DCONFIG_DEV_ALWAYS_MENU=$(DEV)

# Build switches, each one covering its own code and artwork.  See
# amiga_config.s.
#   ART=0     no tagline heading and no logo
#   BALL=0    no bouncing ball, and so no shadow either
#   SHADOW=1  adds a drop shadow under the ball
#   CHIME=0   no chime as the menu comes up
ART       ?= 1
BALL      ?= 1
SHADOW    ?= 0
CHIME     ?= 1
ASFLAGS  += -DCONFIG_BANNER_ART=$(ART)       \
            -DCONFIG_BANNER_BALL=$(BALL)     \
            -DCONFIG_BANNER_SHADOW=$(SHADOW) \
            -DCONFIG_BOOT_CHIME=$(CHIME)

# The artwork is checked in, so a build never regenerates it — but a
# regenerated asset has to force a re-assemble.
ASSETS    = assets/logo.s            assets/logo.bin            \
            assets/logo_mask.bin                                \
            assets/tagline_wide.s    assets/tagline_wide.bin    \
            assets/ball.s            assets/ball.bin            \
            assets/ball_mask.bin                                \
            assets/chime.s           assets/chime.bin

COMMON_SRC = $(COMMON)/amiga_defs.s        $(COMMON)/amiga_hw.s           \
             $(COMMON)/amiga_screen.s      $(COMMON)/amiga_screen_data.s  \
             $(COMMON)/amiga_input.s       $(COMMON)/amiga_input_data.s   \
             $(COMMON)/amiga_device.s      $(COMMON)/amiga_device_data.s  \
             $(COMMON)/amiga_log.s         $(COMMON)/amiga_log_data.s     \
             $(COMMON)/amiga_error.s       $(COMMON)/amiga_error_data.s   \
             $(COMMON)/amiga_diag_data.s   $(COMMON)/amiga_time.s         \
             $(COMMON)/amiga_blit.s

DEPS      = amiga_boot.s        \
            amiga_config.s      \
            amiga_defs.s        \
            rbcp_config.s       \
            ../rbcp/rbcp_defs.s \
            ../rbcp/rbcp.s      \
            $(COMMON_SRC)       \
            $(ASSETS)           \
            $(FONT)

.PHONY: all images clean FORCE

ifeq ($(BUS),32)
all: $(WIDE)_$(ROM_KB)k_hi.bin $(WIDE)_$(ROM_KB)k_lo.bin
else
all: $(TARGET)
endif

# Both ROM sizes and both 32-bit pairs, under the names a release uses.
images: $(BUILD)/$(NAME)_256k.bin $(BUILD)/$(NAME)_512k.bin $(WIDE_ALL)

FORCE:

$(BUILD):
	mkdir -p $(BUILD)

$(TARGET): $(DEPS) $(ROM_KB_DEP) | $(BUILD)
	$(AS) $(ASFLAGS) -DCONFIG_ROM_KB=$(ROM_KB) $(SRC) -o $@
	@SIZE=$$(wc -c < $@ | tr -d ' '); \
	 echo "Output: $@ ($$SIZE bytes, expected $(ROM_BYTES) for $(ROM_KB) KB)"; \
	 if [ "$$SIZE" != "$(ROM_BYTES)" ]; then \
	     echo "ERROR: wrong image size — check ORG directives and CONFIG_ROM_KB"; \
	     exit 1; \
	 fi
	@dd if=$(TARGET) of=$(SWAPPED) conv=swab status=none
	@echo "Swapped: $(SWAPPED)"
	@echo $(ROM_KB) > $(ROM_KB_FILE)

# One ROM size, named for it.  The device is programmed with the swapped
# image, so the unswapped one goes as soon as it has been swapped.
$(BUILD)/$(NAME)_%k.bin: $(DEPS) | $(BUILD)
	$(AS) $(ASFLAGS) -DCONFIG_ROM_KB=$* $(SRC) -o $(BUILD)/$(NAME)_$*k_unswapped.bin
	@SIZE=$$(wc -c < $(BUILD)/$(NAME)_$*k_unswapped.bin | tr -d ' '); \
	 BYTES=$$(($* * 1024)); \
	 echo "Output: $@ ($$SIZE bytes, expected $$BYTES for $* KB)"; \
	 if [ "$$SIZE" != "$$BYTES" ]; then \
	     echo "ERROR: wrong image size — check ORG directives and CONFIG_ROM_KB"; \
	     exit 1; \
	 fi
	@dd if=$(BUILD)/$(NAME)_$*k_unswapped.bin of=$@ conv=swab status=none
	@rm -f $(BUILD)/$(NAME)_$*k_unswapped.bin

$(WIDE_CPU)_%k.bin: $(DEPS)
	@mkdir -p $(BUILD)/32bit
	$(AS) $(ASFLAGS) -DCONFIG_BUS_WIDTH=32 -DCONFIG_ROM_KB=512 -DCONFIG_DEV_KB=$* $(SRC) -o $@
	@SIZE=$$(wc -c < $@ | tr -d ' '); \
	 echo "Output: $@ ($$SIZE bytes, expected 524288 for 512 KB)"; \
	 if [ "$$SIZE" != "524288" ]; then \
	     echo "ERROR: wrong image size — check ORG directives and CONFIG_ROM_KB"; \
	     exit 1; \
	 fi

# The CPU image is kept for use under a debugger.
.PRECIOUS: $(WIDE_CPU)_%k.bin

$(WIDE)_%k_hi.bin: $(WIDE_CPU)_%k.bin
	@$(call split,$<,0,$@,$(if $(filter 512,$*),2,1))

$(WIDE)_%k_lo.bin: $(WIDE_CPU)_%k.bin
	@$(call split,$<,2,$@,$(if $(filter 512,$*),2,1))

clean:
	@echo "Cleaning build artefacts"
	@rm -rf $(BUILD)
