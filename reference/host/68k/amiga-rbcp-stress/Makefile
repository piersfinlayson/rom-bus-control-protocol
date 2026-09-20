# Makefile — Amiga RBCP Reliability Meter
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Requires:
#   vasmm68k_mot  Motorola 68K assembler from http://sun.hasenbraten.de/vasm/
#                 (no official git repo — the tarball is upstream)
#                   make CPU=m68k SYNTAX=mot
#   font_8x8.bin  2048-byte CP437/ASCII 8x8 bitmap font in ../amiga-common
#                 (256 glyphs * 8 bytes, no header)
#
# The device stores a slot in its own byte order, so the build also writes a
# swapped image.  That is the one to program.
#
# Build:   make
# Images:  make images
# Clean:   make clean
#
# make images builds both ROM sizes, each under its own name.  That is what
# the workflows ask for.
#
# The ROM size comes from CONFIG_ROM_KB in rbcp_config.s — change it there,
# not here, so the assembler and this size check cannot disagree.

AS        = vasmm68k_mot
ASFLAGS   = -m68000 -Fbin -I . -I ../rbcp -I ../amiga-common

BUILD     = build
NAME      = amiga_meter
SRC       = amiga_stress.s
TARGET    = $(BUILD)/$(NAME).bin
SWAPPED   = $(BUILD)/$(NAME)_swapped.bin
COMMON    = ../amiga-common
FONT      = $(COMMON)/font_8x8.bin

# ROM size in KB, 256 or 512.  Defaults to the value in rbcp_config.s.
# Override on the command line for a 512 KB (27C400) socket:  make ROM_KB=512
ROM_KB    ?= $(shell sed -n 's/^CONFIG_ROM_KB[[:space:]][[:space:]]*EQU[[:space:]][[:space:]]*\([0-9][0-9]*\).*/\1/p' rbcp_config.s)
ROM_BYTES := $(shell expr $(ROM_KB) \* 1024)

# make writes the same file names whichever size it built, so a size change
# alone leaves make with nothing out of date.  The size that built the image
# is recorded beside it, and a build for a different size picks up FORCE,
# which make never considers up to date.  make images needs none of this
# because its two images have different names.
ROM_KB_FILE = $(BUILD)/rom_kb
LAST_ROM_KB := $(shell cat $(ROM_KB_FILE) 2>/dev/null)
ifneq ($(LAST_ROM_KB),$(ROM_KB))
ROM_KB_DEP = FORCE
endif

COMMON_SRC = $(COMMON)/amiga_defs.s        $(COMMON)/amiga_hw.s           \
             $(COMMON)/amiga_screen.s      $(COMMON)/amiga_screen_data.s  \
             $(COMMON)/amiga_input.s       $(COMMON)/amiga_input_data.s   \
             $(COMMON)/amiga_log.s         $(COMMON)/amiga_log_data.s     \
             $(COMMON)/amiga_error.s       $(COMMON)/amiga_error_data.s   \
             $(COMMON)/amiga_diag_data.s   $(COMMON)/amiga_time.s

DEPS      = amiga_stress.s      \
            amiga_defs.s        \
            rbcp_config.s       \
            ../rbcp/rbcp_defs.s \
            ../rbcp/rbcp.s      \
            $(COMMON_SRC)       \
            $(FONT)

.PHONY: all images clean FORCE

all: $(TARGET)

# Both ROM sizes, under the names a release carries.
images: $(BUILD)/$(NAME)_256k.bin $(BUILD)/$(NAME)_512k.bin

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

clean:
	@echo "Cleaning build artefacts"
	@rm -rf $(BUILD)
