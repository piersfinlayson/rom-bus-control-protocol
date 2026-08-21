# Makefile — C64 RBCP LED tester
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Two binaries from one set of sources.  rbcp_led_test.prg talks to a device.
# rbcp_led_demo.prg makes the answers up, so that every screen can be looked at
# under an emulator, and contains none of the device code.  BOARD picks which
# imaginary board the demo build describes.

AS       = ca65
LD       = ld65
C1541    = c1541
ASFLAGS  = --cpu 6502 -I . -I src -I ../common
LDFLAGS  = -C led_test.cfg

BUILD    = build

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)
RBCP_OBJS = $(patsubst $(RBCP_DIR)/%.s,$(BUILD)/rbcp/%.o,$(RBCP_SRCS))
RBCP_LIB  = $(BUILD)/rbcp.lib

BOARD   ?= 0
SCRIPT  ?= 0

# BOARD and SCRIPT only reach the sources through the command line, so make
# cannot see a change to either.  The stamp gives it something to depend on.
BOARD_STAMP = $(BUILD)/.board

PRG      = $(BUILD)/rbcp_led_test.prg
DEMO     = $(BUILD)/rbcp_led_demo.prg
D64      = $(BUILD)/rbcp-led-test.d64
DISK_HDR = "piers.rocks,01"
DISK_FN  = "rbcp led test"

# led_test.o first so its ENTRY segment is the one SYS 2061 reaches.
COMMON_OBJS = $(BUILD)/led_test.o \
              $(BUILD)/charset.o \
              $(BUILD)/ticker.o \
              $(BUILD)/disc_glyphs.o \
              $(BUILD)/display.o \
              $(BUILD)/leds.o \
              $(BUILD)/c64_hw.o \
              $(BUILD)/c64_app.o \
              $(BUILD)/c64_keys.o

OBJS      = $(COMMON_OBJS) $(BUILD)/leds_dev.o  $(BUILD)/rbcp_session.o
DEMO_OBJS = $(COMMON_OBJS) $(BUILD)/leds_fake.o $(BUILD)/rbcp_session_fake.o

.PHONY: all demo clean FORCE

all: $(PRG) $(D64)
demo: $(DEMO)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/rbcp/%.o: $(RBCP_DIR)/%.s $(RBCP_DIR)/rbcp_defs.s rbcp_config.s | $(BUILD)
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) $< -o $@

$(RBCP_LIB): $(RBCP_OBJS)
	@rm -f $@
	ar65 a $@ $(RBCP_OBJS)

$(BUILD)/c64_hw.o: ../common/c64_hw.s ../common/c64_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) ../common/c64_hw.s -o $@

$(BUILD)/c64_app.o: ../common/c64_app.s ../common/app_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) ../common/c64_app.s -o $@

$(BUILD)/c64_keys.o: ../common/c64_keys.s ../common/app_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) ../common/c64_keys.s -o $@

$(BUILD)/rbcp_session.o: ../common/rbcp_session.s ../common/app_defs.s rbcp_config.s | $(BUILD)
	$(AS) $(ASFLAGS) ../common/rbcp_session.s -o $@

$(BUILD)/rbcp_session_fake.o: ../common/rbcp_session_fake.s ../common/app_defs.s rbcp_config.s | $(BUILD)
	$(AS) $(ASFLAGS) ../common/rbcp_session_fake.s -o $@

$(BUILD)/led_test.o: src/led_test.s src/led_defs.s src/disc_glyphs.inc $(BOARD_STAMP) | $(BUILD)
	$(AS) $(ASFLAGS) -D SCRIPT=$(SCRIPT) src/led_test.s -o $@

$(BUILD)/display.o: src/display.s src/led_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/display.s -o $@

$(BUILD)/leds.o: src/leds.s src/led_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/leds.s -o $@

$(BUILD)/charset.o: src/charset.s src/led_defs.s src/disc_glyphs.inc src/disc_glyphs.inc | $(BUILD)
	$(AS) $(ASFLAGS) src/charset.s -o $@

$(BUILD)/ticker.o: src/ticker.s src/led_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/ticker.s -o $@

# The disc's characters are generated.  The rule is here so a change to the
# generator rebuilds them, and the output is committed so a build needs only
# cc65.
$(BUILD)/disc_glyphs.o: src/disc_glyphs.s src/led_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/disc_glyphs.s -o $@

.PHONY: glyphs
glyphs:
	python3 tools/gen_disc.py src/disc_glyphs.s

$(BUILD)/leds_dev.o: src/leds_dev.s src/led_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/leds_dev.s -o $@

$(BOARD_STAMP): FORCE | $(BUILD)
	@echo "$(BOARD) $(SCRIPT)" | cmp -s - $@ || echo "$(BOARD) $(SCRIPT)" > $@

FORCE:

$(BUILD)/leds_fake.o: src/leds_fake.s src/led_defs.s $(BOARD_STAMP) | $(BUILD)
	$(AS) $(ASFLAGS) -D BOARD=$(BOARD) src/leds_fake.s -o $@

$(PRG): $(OBJS) $(RBCP_LIB) led_test.cfg
	$(LD) $(LDFLAGS) $(OBJS) $(RBCP_LIB) -o $@
	@echo "Output: $@ ($$(wc -c < $@) bytes)"

$(DEMO): $(DEMO_OBJS) $(RBCP_LIB) led_test.cfg
	$(LD) $(LDFLAGS) $(DEMO_OBJS) $(RBCP_LIB) -o $@
	@echo "Output: $@ ($$(wc -c < $@) bytes, board $(BOARD))"

$(D64): $(PRG)
	@rm -f $@
	$(C1541) -format $(DISK_HDR) d64 $@ -write $(PRG) $(DISK_FN) > /dev/null
	@echo "Output: $@"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)
