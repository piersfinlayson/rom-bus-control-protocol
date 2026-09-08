# Makefile — VIC-20 auxiliary I/O tester
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Two images from one set of sources, PAL and NTSC, which differ in where the
# picture sits and in nothing else.
#
# make demo builds a third image, PAL, which answers its own questions, so that
# every screen can be looked at under an emulator with no device fitted.
# BOARD picks which imaginary board it describes.

AS       = ca65
LD       = ld65
ASFLAGS  = --cpu 6502 -I . -I src -I ../aux-io

BUILD    = build
BUILD_P  = $(BUILD)/pal
BUILD_N  = $(BUILD)/ntsc
BUILD_D  = $(BUILD)/demo

TARGET_P = $(BUILD)/vic20_auxio_pal.bin
TARGET_N = $(BUILD)/vic20_auxio_ntsc.bin
TARGET_D = $(BUILD)/vic20_auxio_demo.bin

BOARD   ?= 0

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.  One archive per image, since each is
# assembled against a different picture.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)

# What every machine's tester shares, and what this one adds.
AUX_DIR   = ../aux-io
AUX_SRCS  = $(AUX_DIR)/auxio.s $(AUX_DIR)/display.s $(AUX_DIR)/pins.s
APP_SRCS  = src/plat.s

DEV_SRCS  = $(AUX_DIR)/pins_dev.s $(AUX_DIR)/session.s
FAKE_SRCS = $(AUX_DIR)/pins_fake.s $(AUX_DIR)/session_fake.s

DEPS = src/plat_defs.s $(AUX_DIR)/auxio_defs.s $(RBCP_DIR)/rbcp_defs.s \
       rbcp_config.s

.PHONY: all demo clean

all: $(TARGET_P) $(TARGET_N)
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

$(1)/app/%.o: src/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(3): $$(patsubst src/%.s,$(1)/app/%.o,$$(APP_SRCS)) \
      $$(patsubst $$(AUX_DIR)/%.s,$(1)/aux/%.o,$$(AUX_SRCS) $(4)) \
      $(1)/rbcp.lib vic20_auxio.cfg
	@mkdir -p $$(dir $$@)
	$$(LD) -C vic20_auxio.cfg $$(filter %.o,$$^) $(1)/rbcp.lib -o $$@ -m $(1)/map.txt
	@echo "Output: $$@ ($$$$(wc -c < $$@) bytes)"

endef

$(eval $(call IMAGE_RULES,$(BUILD_P),-D PAL=1,$(TARGET_P),$(DEV_SRCS)))
$(eval $(call IMAGE_RULES,$(BUILD_N),-D NTSC=1,$(TARGET_N),$(DEV_SRCS)))
$(eval $(call IMAGE_RULES,$(BUILD_D),-D PAL=1 -D BOARD=$(BOARD),$(TARGET_D),$(FAKE_SRCS)))

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)
