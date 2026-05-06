# Makefile — C64 RBCP Kernal Bootloader
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

FLAGS_FILE = build/.flags
CURRENT_FLAGS = PAUSE_BEFORE_RESET=$(if $(PAUSE_BEFORE_RESET),1,0)
AS      = ca65
LD      = ld65
ASFLAGS = --cpu 6502 -I . -D PAUSE_BEFORE_RESET=$(if $(PAUSE_BEFORE_RESET),1,0)
LDFLAGS = -C c64_boot.cfg

BUILD   = build
TARGET  = $(BUILD)/c64_boot.bin

OBJS    = $(BUILD)/rbcp.o \
          $(BUILD)/c64_hw.o \
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

$(BUILD)/rbcp.o: ../rbcp/rbcp.s ../rbcp/rbcp_defs.s rbcp_config.s $(FLAGS_FILE)
	$(AS) $(ASFLAGS) ../rbcp/rbcp.s -o $@

$(BUILD)/c64_hw.o: src/c64_hw.s src/c64_defs.s $(FLAGS_FILE)
	$(AS) $(ASFLAGS) src/c64_hw.s -o $@

$(BUILD)/c64_boot.o: src/c64_boot.s ../rbcp/rbcp_defs.s src/c64_defs.s $(FLAGS_FILE)
	$(AS) $(ASFLAGS) src/c64_boot.s -o $@

$(BUILD)/vectors.o: src/vectors.s $(FLAGS_FILE)
	$(AS) $(ASFLAGS) src/vectors.s -o $@

$(TARGET): $(OBJS) c64_boot.cfg $(FLAGS_FILE)
	$(LD) $(LDFLAGS) $(OBJS) -o $@
	@echo "Output: $@ ($$(wc -c < $@) bytes)"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)