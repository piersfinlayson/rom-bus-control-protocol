# Makefile — Apple IIe auxiliary I/O tester
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# One 8KB image for the IIe's EF socket.
#
# make demo builds a second image which answers its own questions, so that
# every screen can be looked at under an emulator with no device fitted.
# BOARD picks which imaginary board it describes.

AS       = ca65
LD       = ld65
ASFLAGS  = --cpu 6502 -I . -I src -I ../aux-io

BUILD    = build
BUILD_M  = $(BUILD)/main
BUILD_D  = $(BUILD)/demo

TARGET   = $(BUILD)/apple2_auxio.bin
TARGET_D = $(BUILD)/apple2_auxio_demo.bin

# BOARD only reaches the sources through the command line, so make cannot see
# a change to it.  The demo build is deleted on a change, before any rule runs.
BOARD   ?= 0
$(shell [ "`cat $(BUILD_D)/.flags 2>/dev/null`" = "$(BOARD)" ] || \
    { rm -rf $(BUILD_D) $(TARGET_D) && mkdir -p $(BUILD_D) && \
      echo "$(BOARD)" > $(BUILD_D)/.flags; })

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.
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

.PHONY: all demo clean test

all: $(TARGET)
demo: $(TARGET_D)

# ---------------------------------------------------------------------------
# One rule set per image.  The name has to differ from any variable this
# Makefile reads, because $(NAME) of a define expands to the whole block.
#
# One rule set per image.  $(1) is the build directory, $(2) the extra ca65
# flags, $(3) the image and $(4) the sources that differ between them.
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
      $(1)/rbcp.lib apple2_auxio.cfg
	$$(LD) -C apple2_auxio.cfg $$(filter %.o,$$^) $(1)/rbcp.lib -o $$@
	@echo "Output: $$@ ($$$$(wc -c < $$@) bytes)"

endef

$(eval $(call IMAGE_RULES,$(BUILD_M),,$(TARGET),$(DEV_SRCS)))
$(eval $(call IMAGE_RULES,$(BUILD_D),-D BOARD=$(BOARD),$(TARGET_D),$(FAKE_SRCS)))

test: $(TARGET)
	test/run.sh $(ROMS) $(TARGET)

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)
