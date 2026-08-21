# Makefile — C64 RBCP pipe throughput test
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

AS       = ca65
LD       = ld65
C1541    = c1541
ASFLAGS  = --cpu 6502 -I . -I src -I ../common
LDFLAGS  = -C pipe_test.cfg

BUILD    = build

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)
RBCP_OBJS = $(patsubst $(RBCP_DIR)/%.s,$(BUILD)/rbcp/%.o,$(RBCP_SRCS))
RBCP_LIB  = $(BUILD)/rbcp.lib

PRG      = $(BUILD)/rbcp_pipe_test.prg
D64      = $(BUILD)/rbcp-pipe-test.d64
DISK_HDR = "piers.rocks,01"
DISK_FN  = "rbcp pipe test"

# pipe_test.o first so its ENTRY segment is the one SYS 2061 reaches.
OBJS     = $(BUILD)/pipe_test.o \
           $(BUILD)/session.o \
           $(BUILD)/display.o \
           $(BUILD)/timing.o \
           $(BUILD)/line.o \
           $(BUILD)/send_lib.o \
           $(BUILD)/send_tuned.o \
           $(BUILD)/c64_hw.o

.PHONY: all clean

all: $(PRG) $(D64)

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

$(BUILD)/pipe_test.o: src/pipe_test.s src/pipe_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/pipe_test.s -o $@

$(BUILD)/session.o: src/session.s src/pipe_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/session.s -o $@

$(BUILD)/display.o: src/display.s src/pipe_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/display.s -o $@

$(BUILD)/timing.o: src/timing.s src/pipe_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/timing.s -o $@

$(BUILD)/line.o: src/line.s src/pipe_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/line.s -o $@

$(BUILD)/send_lib.o: src/send_lib.s src/pipe_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/send_lib.s -o $@

$(BUILD)/send_tuned.o: src/send_tuned.s src/pipe_defs.s | $(BUILD)
	$(AS) $(ASFLAGS) src/send_tuned.s -o $@

$(PRG): $(OBJS) $(RBCP_LIB) pipe_test.cfg
	$(LD) $(LDFLAGS) $(OBJS) $(RBCP_LIB) -o $@
	@echo "Output: $@ ($$(wc -c < $@) bytes)"

$(D64): $(PRG)
	@rm -f $@
	$(C1541) -format $(DISK_HDR) d64 $@ -write $(PRG) $(DISK_FN) > /dev/null
	@echo "Output: $@"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)
