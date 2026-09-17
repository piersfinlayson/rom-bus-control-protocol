# Makefile — Amiga RBCP Kickstart Bootloader
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Requires:
#   vasmm68k_mot  Motorola 68K assembler from http://sun.hasenbraten.de/vasm/
#                 (no official git repo; the tarball is upstream)
#                   make CPU=m68k SYNTAX=mot
#   font_8x8.bin  2048-byte CP437/ASCII 8x8 bitmap font (256 glyphs * 8 bytes,
#                 no header)
#
# The device stores a slot in its own byte order, so the build also writes a
# swapped image.  That is the one to program.
#
# Build:   make
# Clean:   make clean
#
# The ROM size comes from CONFIG_ROM_KB in rbcp_config.s — change it there,
# not here, so the assembler and this size check cannot disagree.

AS        = vasmm68k_mot
ASFLAGS   = -m68000 -Fbin -I . -I ../rbcp

BUILD     = build
TARGET    = $(BUILD)/amiga_boot.bin
SWAPPED   = $(BUILD)/amiga_boot_swapped.bin
FONT      = font_8x8.bin

# ROM size in KB, 256 or 512.  Defaults to the value in rbcp_config.s; override
# on the command line for a 512 KB (27C400) socket:  make ROM_KB=512
ROM_KB    ?= $(shell sed -n 's/^CONFIG_ROM_KB[[:space:]][[:space:]]*EQU[[:space:]][[:space:]]*\([0-9][0-9]*\).*/\1/p' rbcp_config.s)
ROM_BYTES := $(shell expr $(ROM_KB) \* 1024)
ASFLAGS  += -DCONFIG_ROM_KB=$(ROM_KB)

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

DEPS      = amiga_boot.s        \
            amiga_config.s      \
            amiga_defs.s        \
            amiga_hw.s          \
            rbcp_config.s       \
            ../rbcp/rbcp_defs.s \
            ../rbcp/rbcp.s      \
            $(ASSETS)           \
            $(FONT)

.PHONY: all clean

all: $(TARGET)

$(BUILD):
	mkdir -p $(BUILD)

$(TARGET): $(DEPS) | $(BUILD)
	$(AS) $(ASFLAGS) amiga_boot.s -o $@
	@SIZE=$$(wc -c < $@ | tr -d ' '); \
	 echo "Output: $@ ($$SIZE bytes, expected $(ROM_BYTES) for $(ROM_KB) KB)"; \
	 if [ "$$SIZE" != "$(ROM_BYTES)" ]; then \
	     echo "ERROR: wrong image size — check ORG directives and CONFIG_ROM_KB"; \
	     exit 1; \
	 fi
	@dd if=$(TARGET) of=$(SWAPPED) conv=swab status=none
	@echo "Swapped: $(SWAPPED)"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)
