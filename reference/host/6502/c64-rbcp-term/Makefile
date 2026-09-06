# Makefile — C64 RBCP terminal
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Three images from one set of sources.  The kernal build is an 8KB 2364 for
# the kernal socket.  The BASIC build is the same size for the other socket.
# The combined build is a 16KB 23128 spanning the two, with the terminal in the
# kernal half and the device's replies in the blank BASIC half.  Only the
# addresses differ, and they come from rbcp_config.s.
#
# make selftest builds a fourth image, for the BASIC socket, which types a
# known script by itself.  It is how the terminal is tested on a machine with
# nobody at the keyboard.

AS       = ca65
LD       = ld65
ASFLAGS  = --cpu 6502 -I . -I src -I ../common -I ../term

BUILD    = build
BUILD_K  = $(BUILD)/kernal
BUILD_B  = $(BUILD)/basic
BUILD_C  = $(BUILD)/combined
BUILD_S  = $(BUILD)/selftest

TARGET_K = $(BUILD)/c64_term_kernal.bin
TARGET_B = $(BUILD)/c64_term_basic.bin
TARGET_C = $(BUILD)/c64_term_combined.bin
TARGET_S = $(BUILD)/c64_term_selftest.bin

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.  One archive per image, since each is
# assembled against a different ROM address.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)

# What every machine's terminal shares, and what this one adds.
TERM_DIR  = ../term
TERM_SRCS = $(TERM_DIR)/term.s $(TERM_DIR)/session.s $(TERM_DIR)/display.s
COMMON_SRCS = ../common/c64_hw.s ../common/rbcp_recover.s
APP_SRCS    = src/plat.s

DEPS = src/plat_defs.s ../common/c64_defs.s ../common/rbcp_stage.s \
       $(TERM_DIR)/term_defs.s $(RBCP_DIR)/rbcp_defs.s rbcp_config.s

.PHONY: all selftest clean

all: $(TARGET_K) $(TARGET_B) $(TARGET_C)

selftest: $(TARGET_S)

# ---------------------------------------------------------------------------
# One rule set per image.  $(1) is the build directory, $(2) the extra ca65
# flags, $(3) the linker configuration, $(4) the image, and $(5) any object
# beyond the ones every image holds.
# ---------------------------------------------------------------------------

define IMAGE

$(1)/rbcp/%.o: $$(RBCP_DIR)/%.s $$(RBCP_DIR)/rbcp_defs.s rbcp_config.s
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/rbcp.lib: $$(patsubst $$(RBCP_DIR)/%.s,$(1)/rbcp/%.o,$$(RBCP_SRCS))
	@rm -f $$@
	ar65 a $$@ $$^

$(1)/term/%.o: $$(TERM_DIR)/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/common/%.o: ../common/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/app/%.o: src/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(4): $$(patsubst src/%.s,$(1)/app/%.o,$$(APP_SRCS)) \
      $$(patsubst $$(TERM_DIR)/%.s,$(1)/term/%.o,$$(TERM_SRCS)) \
      $$(patsubst ../common/%.s,$(1)/common/%.o,$$(COMMON_SRCS)) \
      $(5) $(1)/rbcp.lib $(3)
	@mkdir -p $$(dir $$@)
	$$(LD) -C $(3) $$(filter %.o,$$^) $(1)/rbcp.lib -o $$@ -m $(1)/map.txt
	@echo "Output: $$@ ($$$$(wc -c < $$@) bytes)"

endef

$(eval $(call IMAGE,$(BUILD_K),,c64_term_kernal.cfg,$(TARGET_K),))
$(eval $(call IMAGE,$(BUILD_B),-D BASIC_SOCKET=1,c64_term_basic.cfg,$(TARGET_B),))
$(eval $(call IMAGE,$(BUILD_C),-D COMBINED=1,c64_term_combined.cfg,$(TARGET_C),))
$(eval $(call IMAGE,$(BUILD_S),-D BASIC_SOCKET=1 -D SELFTEST=1,c64_term_basic.cfg,$(TARGET_S),$(BUILD_S)/term/selftest.o))

clean:
	rm -rf $(BUILD)
