# Makefile — C64 RBCP auxiliary I/O tester
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Two binaries from one set of sources.  rbcp_aux_test.prg talks to a device.
# rbcp_aux_demo.prg makes the answers up, so that every screen can be looked at
# under an emulator, and contains none of the device code.  BOARD picks which
# imaginary board the demo build describes.

AS       = ca65
LD       = ld65
C1541    = c1541
ASFLAGS  = --cpu 6502 -I . -I src -I ../common
LDFLAGS  = -C aux_test.cfg

BUILD    = build
BOARD   ?= 0
SCRIPT  ?= 0

# BOARD and SCRIPT only reach the sources through the command line, so make
# cannot see a change to either.  The stamp gives it something to depend on.
BOARD_STAMP = $(BUILD)/.board

PRG      = $(BUILD)/rbcp_aux_test.prg
DEMO     = $(BUILD)/rbcp_aux_demo.prg
D64      = $(BUILD)/rbcp-aux-test.d64
DISK_HDR = "piers.rocks,01"
DISK_FN  = "rbcp aux test"

# aux_test.o first so its ENTRY segment is the one SYS 2061 reaches.
COMMON_OBJS = $(BUILD)/aux_test.o \
              $(BUILD)/display.o \
              $(BUILD)/pins.o \
              $(BUILD)/rbcp.o \
              $(BUILD)/c64_hw.o

OBJS      = $(COMMON_OBJS) $(BUILD)/pins_dev.o
DEMO_OBJS = $(COMMON_OBJS) $(BUILD)/pins_fake.o

.PHONY: all demo clean FORCE

all: $(PRG) $(D64)
demo: $(DEMO)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/rbcp.o: ../rbcp/rbcp.s ../rbcp/rbcp_defs.s rbcp_config.s | $(BUILD)
	$(AS) $(ASFLAGS) ../rbcp/rbcp.s -o $@

$(BUILD)/c64_hw.o: ../common/c64_hw.s ../common/c64_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) ../common/c64_hw.s -o $@

$(BUILD)/aux_test.o: src/aux_test.s src/aux_defs.s $(BOARD_STAMP) | $(BUILD)
	$(AS) $(ASFLAGS) -D SCRIPT=$(SCRIPT) src/aux_test.s -o $@

$(BUILD)/display.o: src/display.s src/aux_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/display.s -o $@

$(BUILD)/pins.o: src/pins.s src/aux_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/pins.s -o $@

$(BUILD)/pins_dev.o: src/pins_dev.s src/aux_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/pins_dev.s -o $@

$(BOARD_STAMP): FORCE | $(BUILD)
	@echo "$(BOARD) $(SCRIPT)" | cmp -s - $@ || echo "$(BOARD) $(SCRIPT)" > $@

FORCE:

$(BUILD)/pins_fake.o: src/pins_fake.s src/aux_defs.s $(BOARD_STAMP) | $(BUILD)
	$(AS) $(ASFLAGS) -D BOARD=$(BOARD) src/pins_fake.s -o $@

$(PRG): $(OBJS) aux_test.cfg
	$(LD) $(LDFLAGS) $(OBJS) -o $@
	@echo "Output: $@ ($$(wc -c < $@) bytes)"

$(DEMO): $(DEMO_OBJS) aux_test.cfg
	$(LD) $(LDFLAGS) $(DEMO_OBJS) -o $@
	@echo "Output: $@ ($$(wc -c < $@) bytes, board $(BOARD))"

$(D64): $(PRG)
	@rm -f $@
	$(C1541) -format $(DISK_HDR) d64 $@ -write $(PRG) $(DISK_FN) > /dev/null
	@echo "Output: $@"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)
