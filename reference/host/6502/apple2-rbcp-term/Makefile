# Makefile — Apple IIe RBCP terminal
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# One 8KB image for the IIe's EF socket.
#
# make selftest builds a second image, which types a known script by itself.
# It is how the terminal is tested on a machine with nobody at the keyboard,
# and it is what make test runs.

AS       = ca65
LD       = ld65
ASFLAGS  = --cpu 6502 -I . -I src -I ../common -I ../term

BUILD    = build
BUILD_M  = $(BUILD)/main
BUILD_S  = $(BUILD)/selftest

TARGET   = $(BUILD)/apple2_term.bin
TARGET_S = $(BUILD)/apple2_term_selftest.bin

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)

# What every machine's terminal shares, and what this one adds.
TERM_DIR  = ../term
TERM_SRCS = $(TERM_DIR)/term.s $(TERM_DIR)/session.s $(TERM_DIR)/display.s
COMMON_SRCS = ../common/rbcp_recover.s
APP_SRCS    = src/plat.s

DEPS = src/plat_defs.s ../common/rbcp_stage.s $(TERM_DIR)/term_defs.s \
       $(RBCP_DIR)/rbcp_defs.s rbcp_config.s

.PHONY: all selftest clean test

all: $(TARGET)

selftest: $(TARGET_S)

# ---------------------------------------------------------------------------
# One rule set per image.  $(1) is the build directory, $(2) the extra ca65
# flags, $(3) the image, and $(4) any object beyond the ones every image holds.
# ---------------------------------------------------------------------------

define IMAGE

$(1)/rbcp/%.o: $$(RBCP_DIR)/%.s $$(RBCP_DIR)/rbcp_defs.s rbcp_config.s
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/rbcp.lib: $$(patsubst $$(RBCP_DIR)/%.s,$(1)/rbcp/%.o,$$(RBCP_SRCS))
	@rm -f $$@
	ar65 a $$@ $$^

$(1)/term/%.o: $$(TERM_DIR)/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/common/%.o: ../common/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/app/%.o: src/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(3): $$(patsubst src/%.s,$(1)/app/%.o,$$(APP_SRCS)) \
      $$(patsubst $$(TERM_DIR)/%.s,$(1)/term/%.o,$$(TERM_SRCS)) \
      $$(patsubst ../common/%.s,$(1)/common/%.o,$$(COMMON_SRCS)) \
      $(4) $(1)/rbcp.lib apple2_term.cfg
	@mkdir -p $$(dir $$@)
	$$(LD) -C apple2_term.cfg $$(filter %.o,$$^) $(1)/rbcp.lib -o $$@ -m $(1)/map.txt
	@echo "Output: $$@ ($$$$(wc -c < $$@) bytes)"

endef

$(eval $(call IMAGE,$(BUILD_M),,$(TARGET),))
$(eval $(call IMAGE,$(BUILD_S),-D SELFTEST=1,$(TARGET_S),$(BUILD_S)/term/selftest.o))

# Needs the machine's ROM files, which are not in the repository.
test: $(TARGET_S)
	@[ -n "$(ROMS)" ] || { echo "usage: make test ROMS=<rom-dir>" >&2; exit 1; }
	@test/run.sh "$(ROMS)"

clean:
	rm -rf $(BUILD)
