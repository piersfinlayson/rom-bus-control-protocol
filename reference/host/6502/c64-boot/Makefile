# Makefile — C64 RBCP Kernal Bootloader
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Two images from one set of sources.  The kernal build is an 8KB 2364 for a
# longboard.  The combined build is a 16KB 23128 for a shortboard.  Only the
# addresses differ, set in rbcp_config.s.

FLAGS_FILE = build/.flags
CURRENT_FLAGS = PAUSE_BEFORE_RESET=$(if $(PAUSE_BEFORE_RESET),1,0)
AS      = ca65
LD      = ld65
ASFLAGS = --cpu 6502 -I . -I src -I ../common -D PAUSE_BEFORE_RESET=$(if $(PAUSE_BEFORE_RESET),1,0)

BUILD    = build
BUILD_K  = $(BUILD)/kernal
BUILD_C  = $(BUILD)/combined
TARGET_K = $(BUILD)/c64_boot.bin
TARGET_C = $(BUILD)/c64_boot_combined.bin

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.  One archive per image, since each is
# assembled against a different ROM address.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)

COMMON_SRCS = ../common/c64_hw.s ../common/c64_menu.s ../common/vectors.s \
              ../common/rbcp_recover.s
APP_SRCS    = src/c64_boot.s src/diag.s

DEPS = src/boot_defs.s ../common/c64_defs.s ../common/rbcp_stage.s \
       $(RBCP_DIR)/rbcp_defs.s rbcp_config.s $(FLAGS_FILE)

.PHONY: all clean test

all: $(TARGET_K) $(TARGET_C)

$(FLAGS_FILE): FORCE
	@mkdir -p build
	@echo "$(CURRENT_FLAGS)" | cmp -s - $@ || echo "$(CURRENT_FLAGS)" > $@

FORCE:

# ---------------------------------------------------------------------------
# One rule set per image.  $(1) is the build directory, $(2) the extra ca65
# flags, $(3) the linker configuration and $(4) the image.
# ---------------------------------------------------------------------------

define IMAGE_RULES

$(1)/rbcp/%.o: $$(RBCP_DIR)/%.s $$(RBCP_DIR)/rbcp_defs.s rbcp_config.s $$(FLAGS_FILE)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/rbcp.lib: $$(patsubst $$(RBCP_DIR)/%.s,$(1)/rbcp/%.o,$$(RBCP_SRCS))
	@rm -f $$@
	ar65 a $$@ $$^

$(1)/common/%.o: ../common/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/app/%.o: src/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(4): $$(patsubst ../common/%.s,$(1)/common/%.o,$$(COMMON_SRCS)) \
      $$(patsubst src/%.s,$(1)/app/%.o,$$(APP_SRCS)) \
      $(1)/rbcp.lib $(3)
	$$(LD) -C $(3) $$(filter %.o,$$^) $(1)/rbcp.lib -o $$@ -m $(1)/map.txt
	@echo "Output: $$@ ($$$$(wc -c < $$@) bytes)"

endef

$(eval $(call IMAGE_RULES,$(BUILD_K),,c64_boot.cfg,$(TARGET_K)))
$(eval $(call IMAGE_RULES,$(BUILD_C),-D COMBINED=1,c64_boot_combined.cfg,$(TARGET_C)))

# ROMS is the directory of C64 ROM files, which aren't in this repository.
test: all
	@[ -n "$(ROMS)" ] || { echo "usage: make test ROMS=<rom-dir> [TARGET=kernal|combined]" >&2; exit 1; }
	@RBCP_TARGET=$(if $(TARGET),$(TARGET),kernal) test/run.sh "$(ROMS)"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD)
