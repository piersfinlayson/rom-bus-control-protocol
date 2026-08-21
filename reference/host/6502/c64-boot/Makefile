# Makefile — C64 RBCP Kernal Bootloader
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

FLAGS_FILE = build/.flags
CURRENT_FLAGS = PAUSE_BEFORE_RESET=$(if $(PAUSE_BEFORE_RESET),1,0)
AS      = ca65
LD      = ld65
ASFLAGS = --cpu 6502 -I . -I ../common -D PAUSE_BEFORE_RESET=$(if $(PAUSE_BEFORE_RESET),1,0)
LDFLAGS = -C c64_boot.cfg

BUILD   = build
TARGET  = $(BUILD)/c64_boot.bin

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)
RBCP_OBJS = $(patsubst $(RBCP_DIR)/%.s,$(BUILD)/rbcp/%.o,$(RBCP_SRCS))
RBCP_LIB  = $(BUILD)/rbcp.lib

OBJS    = $(BUILD)/c64_hw.o \
          $(BUILD)/c64_boot.o \
          $(BUILD)/vectors.o

.PHONY: all clean

all: $(BUILD) $(TARGET)
$(FLAGS_FILE): FORCE
	@mkdir -p build
	@echo "$(CURRENT_FLAGS)" | cmp -s - $@ || echo "$(CURRENT_FLAGS)" > $@

FORCE:

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/rbcp/%.o: $(RBCP_DIR)/%.s $(RBCP_DIR)/rbcp_defs.s rbcp_config.s $(FLAGS_FILE) | $(BUILD)
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) $< -o $@

$(RBCP_LIB): $(RBCP_OBJS)
	@rm -f $@
	ar65 a $@ $(RBCP_OBJS)

$(BUILD)/c64_hw.o: ../common/c64_hw.s ../common/c64_defs.s $(FLAGS_FILE)
	$(AS) $(ASFLAGS) ../common/c64_hw.s -o $@

$(BUILD)/c64_boot.o: src/c64_boot.s ../rbcp/rbcp_defs.s ../common/c64_defs.s $(FLAGS_FILE)
	$(AS) $(ASFLAGS) src/c64_boot.s -o $@

$(BUILD)/vectors.o: ../common/vectors.s $(FLAGS_FILE)
	$(AS) $(ASFLAGS) ../common/vectors.s -o $@

$(TARGET): $(OBJS) $(RBCP_LIB) c64_boot.cfg $(FLAGS_FILE)
	$(LD) $(LDFLAGS) $(OBJS) $(RBCP_LIB) -o $@
	@echo "Output: $@ ($$(wc -c < $@) bytes)"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)