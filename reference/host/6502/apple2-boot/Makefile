# Makefile — Apple II RBCP bootloader
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Two binaries from one set of sources.  The F8 build is a 2KB image for the
# F8 socket of an Apple II or II+.  The EF build is an 8KB image for the EF
# socket of a IIe, which has no F8 socket.  Only the ROM's address and size
# differ, and both come from rbcp_config.s.
#
# COUNTDOWN sets how many seconds the menu waits before booting on its own.
#
# NV_FATAL=1 stops the boot when the device refuses to remember the choice,
# rather than booting it anyway.  For use while a device is under suspicion,
# since it tells a failed write apart from what fails after one.  The 2KB
# image has no room for it and says so.

AS           = ca65
LD           = ld65
COUNTDOWN   ?= 3
NV_FATAL    ?=
ASFLAGS_BASE = --cpu 6502 -I . -I src -D COUNTDOWN_SECS=$(COUNTDOWN) \
               $(if $(NV_FATAL),-D NV_FATAL=1)

# Every build option is part of the object directory name.  Timestamps and
# stamp files cannot then get it wrong: a different set of options simply has
# no objects yet, so it builds them, and the same set reuses its own.
BUILD      = build
VARIANT    = $(COUNTDOWN)$(if $(NV_FATAL),-nvfatal)
BUILD_F8   = $(BUILD)/f8-$(VARIANT)
BUILD_EF   = $(BUILD)/ef-$(VARIANT)
# The link output lives with the objects, under the countdown's own directory,
# and is copied to the name everything else uses.  The copy is unconditional:
# a fixed name cannot carry which value built it, so nothing may be inferred
# from its age.
TARGET_F8  = $(BUILD)/apple2_boot_f8.bin
TARGET_EF  = $(BUILD)/apple2_boot_ef.bin
LINKED_F8  = $(BUILD_F8)/apple2_boot_f8.bin
LINKED_EF  = $(BUILD_EF)/apple2_boot_ef.bin

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

all: $(LINKED_F8) $(LINKED_EF)
	@cp -f $(LINKED_F8) $(TARGET_F8)
	@cp -f $(LINKED_EF) $(TARGET_EF)
	@echo "Output: $(TARGET_F8) ($$(wc -c < $(TARGET_F8)) bytes, countdown $(COUNTDOWN)s)"
	@echo "Output: $(TARGET_EF) ($$(wc -c < $(TARGET_EF)) bytes, countdown $(COUNTDOWN)s)"

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

$(LINKED_F8): $(OBJS_F8) $(RBCP_LIB_F8) apple2_boot_f8.cfg
	$(LD) -C apple2_boot_f8.cfg $(OBJS_F8) $(RBCP_LIB_F8) -o $@ \
	      -m $(BUILD_F8)/apple2_boot.map

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

$(LINKED_EF): $(OBJS_EF) $(RBCP_LIB_EF) apple2_boot_ef.cfg
	$(LD) -C apple2_boot_ef.cfg $(OBJS_EF) $(RBCP_LIB_EF) -o $@ \
	      -m $(BUILD_EF)/apple2_boot.map

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
