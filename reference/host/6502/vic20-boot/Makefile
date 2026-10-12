# Makefile — VIC-20 RBCP Kernal Bootloader
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

AS      = ca65
LD      = ld65
ASFLAGS = --cpu 6502 -I . -I ../common -D PAUSE_BEFORE_RESET=$(if $(PAUSE_BEFORE_RESET),1,0)
LDFLAGS = -C vic20_boot.cfg

BUILD = build
IMAGE = $(BUILD)/vic20_boot.bin

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this bootloader refers to.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)
RBCP_OBJS = $(patsubst $(RBCP_DIR)/%.s,$(BUILD)/rbcp/%.o,$(RBCP_SRCS))
RBCP_LIB  = $(BUILD)/rbcp.lib

FLAGS_FILE    = $(BUILD)/.flags
CURRENT_FLAGS = PAUSE_BEFORE_RESET=$(if $(PAUSE_BEFORE_RESET),1,0)

OBJS = $(BUILD)/vic20_boot.o \
       $(BUILD)/vic20_hw.o \
       $(BUILD)/vic20_tv.o \
       $(BUILD)/vectors.o

.PHONY: all clean test

all: $(IMAGE)

# The flags file is always evaluated but only updated when its content
# changes, preventing spurious rebuilds.
$(FLAGS_FILE): FORCE
	@mkdir -p $(BUILD)
	@echo "$(CURRENT_FLAGS)" | cmp -s - $@ || echo "$(CURRENT_FLAGS)" > $@

FORCE:

$(BUILD)/rbcp/%.o: $(RBCP_DIR)/%.s $(RBCP_DIR)/rbcp_defs.s rbcp_config.s $(FLAGS_FILE)
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) $< -o $@

$(RBCP_LIB): $(RBCP_OBJS)
	@rm -f $@
	ar65 a $@ $(RBCP_OBJS)

$(BUILD)/vic20_hw.o: src/vic20_hw.s src/vic20_defs.s $(FLAGS_FILE)
	$(AS) $(ASFLAGS) src/vic20_hw.s -o $@

$(BUILD)/vic20_boot.o: src/vic20_boot.s ../rbcp/rbcp_defs.s src/vic20_defs.s $(FLAGS_FILE)
	$(AS) $(ASFLAGS) src/vic20_boot.s -o $@

$(BUILD)/vic20_tv.o: ../common/vic20_tv.s $(FLAGS_FILE)
	$(AS) $(ASFLAGS) ../common/vic20_tv.s -o $@

$(BUILD)/vectors.o: ../common/vectors.s $(FLAGS_FILE)
	$(AS) $(ASFLAGS) ../common/vectors.s -o $@

$(IMAGE): $(OBJS) $(RBCP_LIB) vic20_boot.cfg $(FLAGS_FILE)
	$(LD) $(LDFLAGS) $(OBJS) $(RBCP_LIB) -o $@
	@echo "Output: $@ ($$(wc -c < $@) bytes)"

# ROMS is the directory of VIC-20 ROM files, which aren't in this repository.
# TARGET is the machine MAME emulates.
test: all
	@[ -n "$(ROMS)" ] || { echo "usage: make test ROMS=<rom-dir> [TARGET=pal|ntsc]" >&2; exit 1; }
	@RBCP_TARGET=$(if $(TARGET),$(TARGET),pal) test/run.sh "$(ROMS)"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)
