# Makefile — VIC-20 RBCP pipe throughput test
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Two images from one set of sources, PAL and NTSC, which differ in where the
# picture sits and in the timer latch that makes a window exactly a second.
#
# There is no demo build.  Every figure this program reports comes from a
# device, and a build that made the answers up would report nothing worth
# looking at.

AS       = ca65
LD       = ld65
ASFLAGS  = --cpu 6502 -I . -I src -I ../common -I ../pipe

BUILD    = build
BUILD_P  = $(BUILD)/pal
BUILD_N  = $(BUILD)/ntsc

TARGET_P = $(BUILD)/vic20_pipe_pal.bin
TARGET_N = $(BUILD)/vic20_pipe_ntsc.bin

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.  One archive per image, since each is
# assembled against a different timer latch.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)

# What every machine's pipe tester shares, and what this one adds.
PIPE_DIR  = ../pipe
PIPE_SRCS = $(PIPE_DIR)/pipe.s $(PIPE_DIR)/session.s $(PIPE_DIR)/display.s \
            $(PIPE_DIR)/timing.s $(PIPE_DIR)/line.s $(PIPE_DIR)/send_lib.s \
            $(PIPE_DIR)/send_tuned.s $(PIPE_DIR)/fault.s
COMMON_SRCS = ../common/rbcp_recover.s
APP_SRCS    = src/plat.s

DEPS = src/plat_defs.s ../common/rbcp_stage.s $(PIPE_DIR)/pipe_defs.s \
       $(RBCP_DIR)/rbcp_defs.s rbcp_config.s

.PHONY: all clean

all: $(TARGET_P) $(TARGET_N)

# ---------------------------------------------------------------------------
# One rule set per image.  $(1) is the build directory, $(2) the extra ca65
# flags, $(3) the image.
# ---------------------------------------------------------------------------

define IMAGE

$(1)/rbcp/%.o: $$(RBCP_DIR)/%.s $$(RBCP_DIR)/rbcp_defs.s rbcp_config.s
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/rbcp.lib: $$(patsubst $$(RBCP_DIR)/%.s,$(1)/rbcp/%.o,$$(RBCP_SRCS))
	@rm -f $$@
	ar65 a $$@ $$^

$(1)/pipe/%.o: $$(PIPE_DIR)/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/common/%.o: ../common/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/app/%.o: src/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(3): $$(patsubst src/%.s,$(1)/app/%.o,$$(APP_SRCS)) \
      $$(patsubst $$(PIPE_DIR)/%.s,$(1)/pipe/%.o,$$(PIPE_SRCS)) \
      $$(patsubst ../common/%.s,$(1)/common/%.o,$$(COMMON_SRCS)) \
      $(1)/rbcp.lib vic20_pipe.cfg
	@mkdir -p $$(dir $$@)
	$$(LD) -C vic20_pipe.cfg $$(filter %.o,$$^) $(1)/rbcp.lib -o $$@ \
	       -m $(1)/map.txt
	@echo "Output: $$@ ($$$$(wc -c < $$@) bytes)"

endef

$(eval $(call IMAGE,$(BUILD_P),-D PAL=1,$(TARGET_P)))
$(eval $(call IMAGE,$(BUILD_N),-D NTSC=1,$(TARGET_N)))

clean:
	rm -rf $(BUILD)
