# Makefile — Apple II RBCP bootloader
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Two binaries from one set of sources.  The F8 build is a 2KB image for the
# F8 socket of an Apple II or II+.  The EF build is an 8KB image for the EF
# socket of a IIe, which has no F8 socket.  Only the ROM's address and size
# differ, and both come from rbcp_config.s.

AS           = ca65
LD           = ld65
ASFLAGS_BASE = --cpu 6502 -I . -I src

BUILD      = build
BUILD_F8   = $(BUILD)/f8
BUILD_EF   = $(BUILD)/ef
TARGET_F8  = $(BUILD)/apple2_boot_f8.bin
TARGET_EF  = $(BUILD)/apple2_boot_ef.bin

OBJS_F8 = $(BUILD_F8)/apple2_hw.o \
          $(BUILD_F8)/apple2_boot.o \
          $(BUILD_F8)/apple2_vectors.o

OBJS_EF = $(BUILD_EF)/apple2_hw.o \
          $(BUILD_EF)/apple2_boot.o \
          $(BUILD_EF)/apple2_vectors.o

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this bootloader refers to.  In 2KB that matters.  One archive per
# variant, since the two are assembled against different ROM addresses.
RBCP_DIR      = ../rbcp
RBCP_SRCS     = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)
RBCP_OBJS_F8  = $(patsubst $(RBCP_DIR)/%.s,$(BUILD_F8)/rbcp/%.o,$(RBCP_SRCS))
RBCP_OBJS_EF  = $(patsubst $(RBCP_DIR)/%.s,$(BUILD_EF)/rbcp/%.o,$(RBCP_SRCS))
RBCP_LIB_F8   = $(BUILD_F8)/rbcp.lib
RBCP_LIB_EF   = $(BUILD_EF)/rbcp.lib

SRC_DEPS = src/apple2_defs.s $(RBCP_DIR)/rbcp_defs.s rbcp_config.s

.PHONY: all clean test test-ef

all: $(TARGET_F8) $(TARGET_EF)

$(BUILD_F8) $(BUILD_EF):
	mkdir -p $@

# ---------------------------------------------------------------------------
# F8 — Apple II and II+, 2KB at $F800
# ---------------------------------------------------------------------------

$(BUILD_F8)/rbcp/%.o: $(RBCP_DIR)/%.s $(RBCP_DIR)/rbcp_defs.s rbcp_config.s | $(BUILD_F8)
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS_BASE) $< -o $@

$(RBCP_LIB_F8): $(RBCP_OBJS_F8)
	@rm -f $@
	ar65 a $@ $(RBCP_OBJS_F8)

$(BUILD_F8)/apple2_hw.o: src/apple2_hw.s $(SRC_DEPS) | $(BUILD_F8)
	$(AS) $(ASFLAGS_BASE) src/apple2_hw.s -o $@

$(BUILD_F8)/apple2_boot.o: src/apple2_boot.s $(SRC_DEPS) | $(BUILD_F8)
	$(AS) $(ASFLAGS_BASE) src/apple2_boot.s -o $@

$(BUILD_F8)/apple2_vectors.o: src/apple2_vectors.s | $(BUILD_F8)
	$(AS) $(ASFLAGS_BASE) src/apple2_vectors.s -o $@

$(TARGET_F8): $(OBJS_F8) $(RBCP_LIB_F8) apple2_boot_f8.cfg
	$(LD) -C apple2_boot_f8.cfg $(OBJS_F8) $(RBCP_LIB_F8) -o $@ \
	      -m $(BUILD_F8)/apple2_boot.map
	@echo "Output: $@ ($$(wc -c < $@) bytes)"

# ---------------------------------------------------------------------------
# EF — Apple IIe, 8KB at $E000
# ---------------------------------------------------------------------------

$(BUILD_EF)/rbcp/%.o: $(RBCP_DIR)/%.s $(RBCP_DIR)/rbcp_defs.s rbcp_config.s | $(BUILD_EF)
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS_BASE) -D EF=1 $< -o $@

$(RBCP_LIB_EF): $(RBCP_OBJS_EF)
	@rm -f $@
	ar65 a $@ $(RBCP_OBJS_EF)

$(BUILD_EF)/apple2_hw.o: src/apple2_hw.s $(SRC_DEPS) | $(BUILD_EF)
	$(AS) $(ASFLAGS_BASE) -D EF=1 src/apple2_hw.s -o $@

$(BUILD_EF)/apple2_boot.o: src/apple2_boot.s $(SRC_DEPS) | $(BUILD_EF)
	$(AS) $(ASFLAGS_BASE) -D EF=1 src/apple2_boot.s -o $@

$(BUILD_EF)/apple2_vectors.o: src/apple2_vectors.s | $(BUILD_EF)
	$(AS) $(ASFLAGS_BASE) -D EF=1 src/apple2_vectors.s -o $@

$(TARGET_EF): $(OBJS_EF) $(RBCP_LIB_EF) apple2_boot_ef.cfg
	$(LD) -C apple2_boot_ef.cfg $(OBJS_EF) $(RBCP_LIB_EF) -o $@ \
	      -m $(BUILD_EF)/apple2_boot.map
	@echo "Output: $@ ($$(wc -c < $@) bytes)"

# ---------------------------------------------------------------------------

# Both need the machine's ROM files, which are not in the repository.
test: all
	@[ -n "$(ROMS)" ] || { echo "usage: make test ROMS=<rom-dir>" >&2; exit 1; }
	@test/run.sh "$(ROMS)"

test-ef: all
	@[ -n "$(ROMS)" ] || { echo "usage: make test-ef ROMS=<rom-dir>" >&2; exit 1; }
	@RBCP_TARGET=ef test/run.sh "$(ROMS)"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)
