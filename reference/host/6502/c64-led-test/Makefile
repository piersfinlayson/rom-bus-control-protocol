# Makefile — C64 RBCP LED tester
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Builds a 2364 image for each ROM socket and a 23128 image spanning both.
#
# make demo builds a kernal socket image that fakes the device, so every screen
# can be seen under an emulator.  BOARD selects the fake board and SCRIPT the
# screen it starts on.

AS       = ca65
LD       = ld65
ASFLAGS  = --cpu 6502 -I . -I src -I ../common -D LED_DIAGS=$(LED_DIAGS)

BUILD    = build
BUILD_K  = $(BUILD)/kernal
BUILD_B  = $(BUILD)/basic
BUILD_C  = $(BUILD)/combined
BUILD_D  = $(BUILD)/demo

TARGET_K = $(BUILD)/c64_led_kernal.bin
TARGET_B = $(BUILD)/c64_led_basic.bin
TARGET_C = $(BUILD)/c64_led_combined.bin
TARGET_D = $(BUILD)/c64_led_demo.bin

BOARD   ?= 0
SCRIPT  ?= 0
LED_DIAGS ?= 0

# BOARD, SCRIPT and LED_DIAGS only reach the sources through the command line,
# so make cannot see a change to any of them.  A build directory built with
# other values is deleted before make compares timestamps.
#
# $(1) is a build directory, $(2) its image and $(3) its values.
clean_if_changed = $(shell [ "`cat $(1)/.flags 2>/dev/null`" = "$(3)" ] || \
    { rm -rf $(1) $(2) && mkdir -p $(1) && echo "$(3)" > $(1)/.flags; })

$(call clean_if_changed,$(BUILD_K),$(TARGET_K),$(LED_DIAGS))
$(call clean_if_changed,$(BUILD_B),$(TARGET_B),$(LED_DIAGS))
$(call clean_if_changed,$(BUILD_C),$(TARGET_C),$(LED_DIAGS))
$(call clean_if_changed,$(BUILD_D),$(TARGET_D),$(BOARD) $(SCRIPT) $(LED_DIAGS))

# The RBCP library is an ar65 archive, so the linker takes only the command
# modules this application refers to.  One archive per image, since each is
# assembled for its own ROM address.
RBCP_DIR  = ../rbcp
RBCP_SRCS = $(RBCP_DIR)/rbcp_core.s $(wildcard $(RBCP_DIR)/cmd/*.s)

APP_SRCS = src/led_test.s src/charset.s src/ticker.s src/disc_glyphs.s \
           src/display.s src/leds.s
COMMON_SRCS = ../common/c64_hw.s ../common/c64_keys.s

# The demo never sends a command, so rbcp_recover.s isn't in it.
ROM_SRCS  = src/boot.s src/session_rom.s src/leds_dev.s
ROM_COMMON_SRCS = ../common/rbcp_recover.s
DEMO_SRCS = src/boot.s src/leds_fake.s
DEMO_COMMON_SRCS = ../common/rbcp_session_fake.s

DEPS = src/led_defs.s ../common/app_defs.s \
       ../common/c64_defs.s ../common/rbcp_stage.s $(RBCP_DIR)/rbcp_defs.s \
       rbcp_config.s

.PHONY: all demo glyphs clean test

all: $(TARGET_K) $(TARGET_B) $(TARGET_C)
demo: $(TARGET_D)

# ---------------------------------------------------------------------------
# One rule set per image, objects then link.  A define's name must not match
# any variable this Makefile reads, because $(NAME) expands to the whole block.
#
# $(1) is the build directory and $(2) the extra ca65 flags.
# ---------------------------------------------------------------------------

define OBJECT_RULES

$(1)/rbcp/%.o: $$(RBCP_DIR)/%.s $$(RBCP_DIR)/rbcp_defs.s rbcp_config.s
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/rbcp.lib: $$(patsubst $$(RBCP_DIR)/%.s,$(1)/rbcp/%.o,$$(RBCP_SRCS))
	@rm -f $$@
	ar65 a $$@ $$^

$(1)/app/%.o: src/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

$(1)/common/%.o: ../common/%.s $$(DEPS)
	@mkdir -p $$(dir $$@)
	$$(AS) $$(ASFLAGS) $(2) $$< -o $$@

endef

# $(1) is the build directory, $(2) the linker configuration, $(3) the image,
# $(4) the sources under src/ that differ between builds, and $(5) those under
# ../common/.

define LINK_RULE

$(3): $$(patsubst src/%.s,$(1)/app/%.o,$$(APP_SRCS) $(4)) \
      $$(patsubst ../common/%.s,$(1)/common/%.o,$$(COMMON_SRCS) $(5)) \
      $(1)/rbcp.lib $(2)
	@mkdir -p $$(dir $$@)
	$$(LD) -C $(2) $$(filter %.o,$$^) $(1)/rbcp.lib -o $$@ -m $(1)/map.txt \
	    -Ln $(1)/labels.txt
	@echo "Output: $$@ ($$$$(wc -c < $$@) bytes)"

endef

# The same for a packed image.  $(PACKER) builds it from ld65's head and
# payload, and fails one too big for its socket.

define PACKED_LINK_RULE

$(3): $$(patsubst src/%.s,$(1)/app/%.o,$$(APP_SRCS) $(4)) \
      $$(patsubst ../common/%.s,$(1)/common/%.o,$$(COMMON_SRCS) $(5)) \
      $(1)/rbcp.lib $(2) $$(PACKER)
	@mkdir -p $$(dir $$@)
	$$(LD) -C $(2) $$(filter %.o,$$^) $(1)/rbcp.lib -o $(1)/staged.bin \
	    -m $(1)/map.txt -Ln $(1)/labels.txt
	python3 $$(PACKER) --head $(1)/staged.bin \
	    --payload $(1)/staged.bin.payload --labels $(1)/labels.txt -o $$@

endef

PACKER = tools/pack_rom.py

ROM_FLAGS = -D ROM_IMAGE=1

$(eval $(call OBJECT_RULES,$(BUILD_K),$(ROM_FLAGS) -D PACKED=1))
$(eval $(call OBJECT_RULES,$(BUILD_B),$(ROM_FLAGS) -D PACKED=1 -D BASIC_SOCKET=1))
$(eval $(call OBJECT_RULES,$(BUILD_C),$(ROM_FLAGS) -D COMBINED=1))
$(eval $(call OBJECT_RULES,$(BUILD_D),$(ROM_FLAGS) -D PACKED=1 -D BOARD=$(BOARD) -D SCRIPT=$(SCRIPT)))

$(eval $(call PACKED_LINK_RULE,$(BUILD_K),c64_led_kernal.cfg,$(TARGET_K),$(ROM_SRCS),$(ROM_COMMON_SRCS)))
$(eval $(call PACKED_LINK_RULE,$(BUILD_B),c64_led_basic.cfg,$(TARGET_B),$(ROM_SRCS),$(ROM_COMMON_SRCS)))
$(eval $(call LINK_RULE,$(BUILD_C),c64_led_combined.cfg,$(TARGET_C),$(ROM_SRCS),$(ROM_COMMON_SRCS)))
$(eval $(call PACKED_LINK_RULE,$(BUILD_D),c64_led_kernal.cfg,$(TARGET_D),$(DEMO_SRCS),$(DEMO_COMMON_SRCS)))

# ROMS is the directory holding the C64's ROM files, which aren't in this
# repository.  TARGET selects the build, kernal by default.
#
# The keys select the RGB LED, step its colour twice to red and turn it on, so
# the final screen comes from the device's report, not the opening state.
test: all
	@[ -n "$(ROMS)" ] || { echo "usage: make test ROMS=<rom-dir> [TARGET=kernal|basic|combined]" >&2; exit 1; }
	@RBCP_TARGET=$(if $(TARGET),$(TARGET),kernal) \
	    RBCP_KEYS='F3;CRSR ↑ ↓|Crsr Down Up;CRSR ↑ ↓|Crsr Down Up;1  !' \
	    test/run.sh "$(ROMS)"

# gen_disc.py's output is committed, so a build requires only cc65.
glyphs:
	python3 tools/gen_disc.py src/disc_glyphs.s

clean:
	rm -rf $(BUILD)
