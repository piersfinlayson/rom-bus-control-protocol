# Makefile — VIC-20 RBCP reliability meter
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Two images from one set of sources, PAL and NTSC, which differ only in where
# the picture sits.  There is no demo build.  Everything this program reports
# comes from a device, and a build that made the answers up would report
# nothing worth looking at.

AS       = ca65
LD       = ld65
ASFLAGS  = --cpu 6502 -I . -I src -I ../common -I ../stress

BUILD    = build
BUILD_P  = $(BUILD)/pal
BUILD_N  = $(BUILD)/ntsc

TARGET_P = $(BUILD)/vic20_meter_pal.bin
TARGET_N = $(BUILD)/vic20_meter_ntsc.bin

RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)

STRESS_DIR  = ../stress
STRESS_SRCS = $(STRESS_DIR)/stress.s $(STRESS_DIR)/display.s \
              $(STRESS_DIR)/report.s $(STRESS_DIR)/ratio.s \
              $(STRESS_DIR)/session.s
COMMON_SRCS = ../common/rbcp_recover.s
APP_SRCS    = src/plat.s

DEPS = src/plat_defs.s ../common/rbcp_stage.s $(STRESS_DIR)/stress_defs.s \
       $(RBCP_DIR)/rbcp_defs.s rbcp_config.s

.PHONY: all clean

all: $(TARGET_P) $(TARGET_N)

define IMAGE_RULES

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

$(3): $$(patsubst src/%.s,$(1)/app/%.o,$$(APP_SRCS)) \
      $$(patsubst $$(STRESS_DIR)/%.s,$(1)/stress/%.o,$$(STRESS_SRCS)) \
      $$(patsubst ../common/%.s,$(1)/common/%.o,$$(COMMON_SRCS)) \
      $(1)/rbcp.lib vic20_meter.cfg
	@mkdir -p $$(dir $$@)
	$$(LD) -C vic20_meter.cfg $$(filter %.o,$$^) $(1)/rbcp.lib -o $$@ \
	       -m $(1)/map.txt
	@echo "Output: $$@ ($$$$(wc -c < $$@) bytes)"

endef

$(eval $(call IMAGE_RULES,$(BUILD_P),-D PAL=1,$(TARGET_P)))
$(eval $(call IMAGE_RULES,$(BUILD_N),-D NTSC=1,$(TARGET_N)))

clean:
	rm -rf $(BUILD)
