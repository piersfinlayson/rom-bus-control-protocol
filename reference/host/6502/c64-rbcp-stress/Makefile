# Makefile — C64 RBCP reliability meter
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Three images from one set of sources.  The kernal build is an 8KB 2364 for
# the kernal socket.  The BASIC build is the same size for the other socket, so
# that one program measures both.  The combined build is a 16KB 23128 spanning
# the two, with the meter in the kernal half and the device's replies in the
# blank BASIC half.  Only the addresses differ, and they come from
# rbcp_config.s.
#
# There is no demo build.  Everything this program reports comes from a device,
# and a build that made the answers up would report nothing worth looking at.

AS       = ca65
LD       = ld65
ASFLAGS  = --cpu 6502 -I . -I src -I ../common -I ../stress

BUILD    = build
BUILD_K  = $(BUILD)/kernal
BUILD_B  = $(BUILD)/basic
BUILD_C  = $(BUILD)/combined

TARGET_K = $(BUILD)/c64_meter_kernal.bin
TARGET_B = $(BUILD)/c64_meter_basic.bin
TARGET_C = $(BUILD)/c64_meter_combined.bin

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.  One archive per image, since the two are
# assembled against different ROM addresses.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)

# What every machine's meter shares, and what this one adds.
STRESS_DIR  = ../stress
STRESS_SRCS = $(STRESS_DIR)/stress.s $(STRESS_DIR)/display.s \
              $(STRESS_DIR)/report.s $(STRESS_DIR)/ratio.s \
              $(STRESS_DIR)/session.s
COMMON_SRCS = ../common/c64_hw.s ../common/vectors.s \
              ../common/rbcp_recover.s
APP_SRCS    = src/plat.s

DEPS = src/plat_defs.s ../common/c64_defs.s ../common/rbcp_stage.s \
       $(STRESS_DIR)/stress_defs.s $(RBCP_DIR)/rbcp_defs.s rbcp_config.s

.PHONY: all clean

all: $(TARGET_K) $(TARGET_B) $(TARGET_C)

# ---------------------------------------------------------------------------
# One rule set per image.  $(1) is the build directory, $(2) the extra ca65
# flags, $(3) the linker configuration, $(4) the image.
# ---------------------------------------------------------------------------

define IMAGE

$(1)/rbcp/%.o: $$(RBCP_DIR)/%.s $$(RBCP_DIR)/rbcp_defs.s rbcp_config.s
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/rbcp.lib: $$(patsubst $$(RBCP_DIR)/%.s,$(1)/rbcp/%.o,$$(RBCP_SRCS))
	@rm -f $$@
	ar65 a $$@ $$^

$(1)/stress/%.o: $$(STRESS_DIR)/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/common/%.o: ../common/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/app/%.o: src/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(4): $$(patsubst src/%.s,$(1)/app/%.o,$$(APP_SRCS)) \
      $$(patsubst $$(STRESS_DIR)/%.s,$(1)/stress/%.o,$$(STRESS_SRCS)) \
      $$(patsubst ../common/%.s,$(1)/common/%.o,$$(COMMON_SRCS)) \
      $(1)/rbcp.lib $(3)
	@mkdir -p $$(dir $$@)
	$$(LD) -C $(3) $$(filter %.o,$$^) $(1)/rbcp.lib -o $$@ -m $(1)/map.txt
	@echo "Output: $$@ ($$$$(wc -c < $$@) bytes)"

endef

$(eval $(call IMAGE,$(BUILD_K),,c64_meter_kernal.cfg,$(TARGET_K)))
$(eval $(call IMAGE,$(BUILD_B),-D BASIC_SOCKET=1,c64_meter_basic.cfg,$(TARGET_B)))
$(eval $(call IMAGE,$(BUILD_C),-D COMBINED=1,c64_meter_combined.cfg,$(TARGET_C)))

clean:
	rm -rf $(BUILD)
