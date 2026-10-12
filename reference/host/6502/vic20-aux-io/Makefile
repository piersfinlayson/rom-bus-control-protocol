# Makefile — VIC-20 auxiliary I/O tester
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# One image runs on PAL and NTSC.
#
# make demo builds a second image, which answers its own questions, so that
# every screen can be looked at under an emulator with no device fitted.
# BOARD picks which imaginary board it describes.

AS       = ca65
LD       = ld65
ASFLAGS  = --cpu 6502 -I . -I src -I ../aux-io

BUILD    = build
BUILD_I  = $(BUILD)/image
BUILD_D  = $(BUILD)/demo

TARGET_I = $(BUILD)/vic20_auxio.bin
TARGET_D = $(BUILD)/vic20_auxio_demo.bin

# BOARD only reaches the sources through the command line, so make cannot see
# a change to it.  The demo build is deleted on a change, before any rule runs.
BOARD   ?= 0
$(shell [ "`cat $(BUILD_D)/.flags 2>/dev/null`" = "$(BOARD)" ] || \
    { rm -rf $(BUILD_D) $(TARGET_D) && mkdir -p $(BUILD_D) && \
      echo "$(BOARD)" > $(BUILD_D)/.flags; })

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.  One archive per image, since each is
# assembled with its own flags.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)

# What every machine's tester shares, and what this one adds.
AUX_DIR   = ../aux-io
AUX_SRCS  = $(AUX_DIR)/auxio.s $(AUX_DIR)/display.s $(AUX_DIR)/pins.s
COMMON_SRCS = ../common/vic20_tv.s
APP_SRCS  = src/plat.s

DEV_SRCS  = $(AUX_DIR)/pins_dev.s $(AUX_DIR)/session.s
FAKE_SRCS = $(AUX_DIR)/pins_fake.s $(AUX_DIR)/session_fake.s

DEPS = src/plat_defs.s $(AUX_DIR)/auxio_defs.s $(RBCP_DIR)/rbcp_defs.s \
       rbcp_config.s

.PHONY: all demo clean test

all: $(TARGET_I)
demo: $(TARGET_D)

# ---------------------------------------------------------------------------
# One rule set per image.  $(1) is the build directory, $(2) the extra ca65
# flags, $(3) the image, and $(4) the sources that differ between them.  The
# define's name has to differ from any variable this Makefile reads, because
# $(NAME) of a define expands to the whole block.
# ---------------------------------------------------------------------------

define IMAGE_RULES

$(1)/rbcp/%.o: $$(RBCP_DIR)/%.s $$(RBCP_DIR)/rbcp_defs.s rbcp_config.s
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/rbcp.lib: $$(patsubst $$(RBCP_DIR)/%.s,$(1)/rbcp/%.o,$$(RBCP_SRCS))
	@rm -f $$@
	ar65 a $$@ $$^

$(1)/aux/%.o: $$(AUX_DIR)/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/common/%.o: ../common/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/app/%.o: src/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(3): $$(patsubst src/%.s,$(1)/app/%.o,$$(APP_SRCS)) \
      $$(patsubst $$(AUX_DIR)/%.s,$(1)/aux/%.o,$$(AUX_SRCS) $(4)) \
      $$(patsubst ../common/%.s,$(1)/common/%.o,$$(COMMON_SRCS)) \
      $(1)/rbcp.lib vic20_auxio.cfg
	@mkdir -p $$(dir $$@)
	$$(LD) -C vic20_auxio.cfg $$(filter %.o,$$^) $(1)/rbcp.lib -o $$@ -m $(1)/map.txt
	@echo "Output: $$@ ($$$$(wc -c < $$@) bytes)"

endef

$(eval $(call IMAGE_RULES,$(BUILD_I),,$(TARGET_I),$(DEV_SRCS)))
$(eval $(call IMAGE_RULES,$(BUILD_D),-D BOARD=$(BOARD),$(TARGET_D),$(FAKE_SRCS)))

# ROMS is the directory of VIC-20 ROM files, which aren't in this repository.
test: all
	@[ -n "$(ROMS)" ] || { echo "usage: make test ROMS=<rom-dir> [TARGET=pal|ntsc]" >&2; exit 1; }
	@RBCP_TARGET=$(if $(TARGET),$(TARGET),pal) test/run.sh "$(ROMS)"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)
