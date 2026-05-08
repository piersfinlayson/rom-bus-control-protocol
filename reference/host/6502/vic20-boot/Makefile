# Makefile — VIC-20 RBCP Kernal Bootloader
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

AS           = ca65
LD           = ld65
ASFLAGS_BASE = --cpu 6502 -I . -D PAUSE_BEFORE_RESET=$(if $(PAUSE_BEFORE_RESET),1,0)
LDFLAGS      = -C vic20_boot.cfg

BUILD       = build
BUILD_PAL   = $(BUILD)/pal
BUILD_NTSC  = $(BUILD)/ntsc
TARGET_PAL  = $(BUILD)/vic20_boot_pal.bin
TARGET_NTSC = $(BUILD)/vic20_boot_ntsc.bin

FLAGS_PAL           = $(BUILD_PAL)/.flags
FLAGS_NTSC          = $(BUILD_NTSC)/.flags
FLAGS_PAL_CURRENT   = VARIANT=PAL PAUSE=$(if $(PAUSE_BEFORE_RESET),1,0)
FLAGS_NTSC_CURRENT  = VARIANT=NTSC PAUSE=$(if $(PAUSE_BEFORE_RESET),1,0)

OBJS_PAL  = $(BUILD_PAL)/rbcp.o \
            $(BUILD_PAL)/vic20_boot.o \
            $(BUILD_PAL)/vic20_hw.o \
            $(BUILD_PAL)/vectors.o

OBJS_NTSC = $(BUILD_NTSC)/rbcp.o \
            $(BUILD_NTSC)/vic20_boot.o \
            $(BUILD_NTSC)/vic20_hw.o \
            $(BUILD_NTSC)/vectors.o

.PHONY: all clean

all: $(TARGET_PAL) $(TARGET_NTSC)

$(BUILD_PAL) $(BUILD_NTSC):
	mkdir -p $@

# Flags files — always evaluated but only updated when content changes,
# preventing spurious rebuilds.  Variant name is embedded so PAL and NTSC
# flags files are never identical even when PAUSE_BEFORE_RESET is the same.

$(FLAGS_PAL): FORCE | $(BUILD_PAL)
	@echo "$(FLAGS_PAL_CURRENT)" | cmp -s - $@ || echo "$(FLAGS_PAL_CURRENT)" > $@

$(FLAGS_NTSC): FORCE | $(BUILD_NTSC)
	@echo "$(FLAGS_NTSC_CURRENT)" | cmp -s - $@ || echo "$(FLAGS_NTSC_CURRENT)" > $@

FORCE:

# ---------------------------------------------------------------------------
# PAL objects
# ---------------------------------------------------------------------------

$(BUILD_PAL)/rbcp.o: ../rbcp/rbcp.s ../rbcp/rbcp_defs.s rbcp_config.s $(FLAGS_PAL)
	$(AS) $(ASFLAGS_BASE) -DPAL=1 ../rbcp/rbcp.s -o $@

$(BUILD_PAL)/vic20_hw.o: src/vic20_hw.s src/vic20_defs.s $(FLAGS_PAL)
	$(AS) $(ASFLAGS_BASE) -DPAL=1 src/vic20_hw.s -o $@

$(BUILD_PAL)/vic20_boot.o: src/vic20_boot.s ../rbcp/rbcp_defs.s src/vic20_defs.s $(FLAGS_PAL)
	$(AS) $(ASFLAGS_BASE) -DPAL=1 src/vic20_boot.s -o $@

$(BUILD_PAL)/vectors.o: src/vectors.s $(FLAGS_PAL)
	$(AS) $(ASFLAGS_BASE) -DPAL=1 src/vectors.s -o $@

$(TARGET_PAL): $(OBJS_PAL) vic20_boot.cfg $(FLAGS_PAL)
	$(LD) $(LDFLAGS) $(OBJS_PAL) -o $@
	@echo "Output: $@ ($$(wc -c < $@) bytes)"

# ---------------------------------------------------------------------------
# NTSC objects
# ---------------------------------------------------------------------------

$(BUILD_NTSC)/rbcp.o: ../rbcp/rbcp.s ../rbcp/rbcp_defs.s rbcp_config.s $(FLAGS_NTSC)
	$(AS) $(ASFLAGS_BASE) -DNTSC=1 ../rbcp/rbcp.s -o $@

$(BUILD_NTSC)/vic20_hw.o: src/vic20_hw.s src/vic20_defs.s $(FLAGS_NTSC)
	$(AS) $(ASFLAGS_BASE) -DNTSC=1 src/vic20_hw.s -o $@

$(BUILD_NTSC)/vic20_boot.o: src/vic20_boot.s ../rbcp/rbcp_defs.s src/vic20_defs.s $(FLAGS_NTSC)
	$(AS) $(ASFLAGS_BASE) -DNTSC=1 src/vic20_boot.s -o $@

$(BUILD_NTSC)/vectors.o: src/vectors.s $(FLAGS_NTSC)
	$(AS) $(ASFLAGS_BASE) -DNTSC=1 src/vectors.s -o $@

$(TARGET_NTSC): $(OBJS_NTSC) vic20_boot.cfg $(FLAGS_NTSC)
	$(LD) $(LDFLAGS) $(OBJS_NTSC) -o $@
	@echo "Output: $@ ($$(wc -c < $@) bytes)"

# ---------------------------------------------------------------------------

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)