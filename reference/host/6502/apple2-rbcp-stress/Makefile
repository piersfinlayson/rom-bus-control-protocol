# Makefile — Apple IIe RBCP reliability meter
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# One image: 8KB for the IIe's EF socket.  There is no demo build.  Everything
# this program reports comes from a device, and a build that made the answers
# up would report nothing worth looking at.

AS       = ca65
LD       = ld65
ASFLAGS  = --cpu 6502 -I . -I src -I ../common -I ../stress

BUILD    = build
TARGET   = $(BUILD)/apple2_meter.bin

RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)
RBCP_OBJS = $(patsubst $(RBCP_DIR)/%.s,$(BUILD)/rbcp/%.o,$(RBCP_SRCS))
RBCP_LIB  = $(BUILD)/rbcp.lib

STRESS_DIR  = ../stress
STRESS_SRCS = $(STRESS_DIR)/stress.s $(STRESS_DIR)/display.s \
              $(STRESS_DIR)/report.s $(STRESS_DIR)/ratio.s \
              $(STRESS_DIR)/session.s
STRESS_OBJS = $(patsubst $(STRESS_DIR)/%.s,$(BUILD)/stress/%.o,$(STRESS_SRCS))

COMMON_SRCS = ../common/rbcp_recover.s
COMMON_OBJS = $(patsubst ../common/%.s,$(BUILD)/common/%.o,$(COMMON_SRCS))

APP_OBJS = $(BUILD)/app/plat.o

DEPS = src/plat_defs.s ../common/rbcp_stage.s $(STRESS_DIR)/stress_defs.s \
       $(RBCP_DIR)/rbcp_defs.s rbcp_config.s

.PHONY: all clean test

all: $(TARGET)

$(BUILD)/rbcp/%.o: $(RBCP_DIR)/%.s $(RBCP_DIR)/rbcp_defs.s rbcp_config.s
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) $< -o $@

$(RBCP_LIB): $(RBCP_OBJS)
	@rm -f $@
	ar65 a $@ $(RBCP_OBJS)

$(BUILD)/stress/%.o: $(STRESS_DIR)/%.s $(DEPS)
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD)/common/%.o: ../common/%.s $(DEPS)
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD)/app/%.o: src/%.s $(DEPS)
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) $< -o $@

$(TARGET): $(APP_OBJS) $(STRESS_OBJS) $(COMMON_OBJS) $(RBCP_LIB) apple2_meter.cfg
	@mkdir -p $(dir $@)
	$(LD) -C apple2_meter.cfg $(APP_OBJS) $(STRESS_OBJS) $(COMMON_OBJS) \
	      $(RBCP_LIB) -o $@ -m $(BUILD)/map.txt
	@echo "Output: $@ ($$(wc -c < $@) bytes)"

clean:
	rm -rf $(BUILD)

# Needs the machine's ROM files, which are not in the repository.
test: all
	@[ -n "$(ROMS)" ] || { echo "usage: make test ROMS=<rom-dir>" >&2; exit 1; }
	@test/run.sh "$(ROMS)"
