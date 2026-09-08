# Makefile — C64 auxiliary I/O tester
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Three images from one set of sources.  The kernal build is an 8KB 2364 for
# the kernal socket.  The BASIC build is the same size for the other socket.
# The combined build is a 16KB 23128 spanning the two, with the tester in the
# kernal half and the device's replies in the blank BASIC half.  Only the
# addresses and the ROM type differ, and they come from rbcp_config.s.
#
# make demo builds a fourth image, for the kernal socket, which answers its own
# questions, so that every screen can be looked at under an emulator with no
# device fitted.  BOARD picks which imaginary board it describes.

AS       = ca65
LD       = ld65
ASFLAGS  = --cpu 6502 -I . -I src -I ../common -I ../aux-io

BUILD    = build
BUILD_K  = $(BUILD)/kernal
BUILD_B  = $(BUILD)/basic
BUILD_C  = $(BUILD)/combined
BUILD_D  = $(BUILD)/demo

TARGET_K = $(BUILD)/c64_auxio_kernal.bin
TARGET_B = $(BUILD)/c64_auxio_basic.bin
TARGET_C = $(BUILD)/c64_auxio_combined.bin
TARGET_D = $(BUILD)/c64_auxio_demo.bin

BOARD   ?= 0

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.  One archive per image, since each is
# assembled against a different ROM address.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)

# What every machine's tester shares, and what this one adds.
AUX_DIR     = ../aux-io
AUX_SRCS    = $(AUX_DIR)/auxio.s $(AUX_DIR)/display.s $(AUX_DIR)/pins.s
COMMON_SRCS = ../common/c64_hw.s
APP_SRCS    = src/plat.s

DEV_SRCS  = $(AUX_DIR)/pins_dev.s $(AUX_DIR)/session.s
FAKE_SRCS = $(AUX_DIR)/pins_fake.s $(AUX_DIR)/session_fake.s

DEPS = src/plat_defs.s ../common/c64_defs.s $(AUX_DIR)/auxio_defs.s \
       $(RBCP_DIR)/rbcp_defs.s rbcp_config.s

.PHONY: all demo clean

all: $(TARGET_K) $(TARGET_B) $(TARGET_C)
demo: $(TARGET_D)

# ---------------------------------------------------------------------------
# One rule set per image.  The name has to differ from any variable this
# Makefile reads, because $(NAME) of a define expands to the whole block.
#
# One rule set per image.  $(1) is the build directory, $(2) the extra ca65
# flags, $(3) the linker configuration, $(4) the image, and $(5) the sources
# that differ between a device build and the demo.
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

$(4): $$(patsubst src/%.s,$(1)/app/%.o,$$(APP_SRCS)) \
      $$(patsubst $$(AUX_DIR)/%.s,$(1)/aux/%.o,$$(AUX_SRCS) $(5)) \
      $$(patsubst ../common/%.s,$(1)/common/%.o,$$(COMMON_SRCS)) \
      $(1)/rbcp.lib $(3)
	@mkdir -p $$(dir $$@)
	$$(LD) -C $(3) $$(filter %.o,$$^) $(1)/rbcp.lib -o $$@ -m $(1)/map.txt
	@echo "Output: $$@ ($$$$(wc -c < $$@) bytes)"

endef

$(eval $(call IMAGE_RULES,$(BUILD_K),,c64_auxio_kernal.cfg,$(TARGET_K),$(DEV_SRCS)))
$(eval $(call IMAGE_RULES,$(BUILD_B),-D BASIC_SOCKET=1,c64_auxio_basic.cfg,$(TARGET_B),$(DEV_SRCS)))
$(eval $(call IMAGE_RULES,$(BUILD_C),-D COMBINED=1,c64_auxio_combined.cfg,$(TARGET_C),$(DEV_SRCS)))
$(eval $(call IMAGE_RULES,$(BUILD_D),-D BOARD=$(BOARD),c64_auxio_kernal.cfg,$(TARGET_D),$(FAKE_SRCS)))

clean:
	rm -rf $(BUILD)
