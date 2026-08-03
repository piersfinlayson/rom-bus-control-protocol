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
# Optional:
#   onerom        used to produce the byte-swapped image.  The 68K is
#                 big-endian and the device stores the slot in its own byte
#                 order, so the natural image must be swapped before it is
#                 written to the device.  Skipped with a warning if absent.
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

ROM_KB    := $(shell sed -n 's/^CONFIG_ROM_KB[[:space:]][[:space:]]*EQU[[:space:]][[:space:]]*\([0-9][0-9]*\).*/\1/p' rbcp_config.s)
ROM_BYTES := $(shell expr $(ROM_KB) \* 1024)

DEPS      = amiga_boot.s        \
            amiga_defs.s        \
            amiga_hw.s          \
            rbcp_config.s       \
            ../rbcp/rbcp_defs.s \
            ../rbcp/rbcp.s      \
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
	@if command -v onerom >/dev/null 2>&1; then \
	     onerom image swap-bytes --input $(TARGET) --output $(SWAPPED) && \
	     echo "Swapped: $(SWAPPED)"; \
	 else \
	     echo "WARNING: onerom not found — $(SWAPPED) not produced."; \
	     echo "         $(TARGET) is in 68K byte order and must be byte-swapped"; \
	     echo "         before it is written to the device."; \
	 fi

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)
