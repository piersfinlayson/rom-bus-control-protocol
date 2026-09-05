; rbcp_config.s — RBCP configuration for the VIC-20 reliability meter
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; An 8KB 2364 in the VIC-20's kernal socket, $E000-$FFFF.  The machine boots
; into it.  The command page and the back channel are the first three pages of
; the image, where the meter's own code is not.
;
; The timeouts and the retry count below are what this program measures with.
; A retry would hide the thing it exists to count, so there are none.

CONFIG_ROM_BASE_HI = $E0
CONFIG_ROM_SIZE = $2000

CONFIG_RBCP_CMD_PAGE = $E0
CONFIG_RBCP_CMD_PAGE_REL = CONFIG_RBCP_CMD_PAGE - CONFIG_ROM_BASE_HI

CONFIG_RBCP_BCH_BASE = $E100
CONFIG_RBCP_BCH_START = (CONFIG_RBCP_BCH_BASE - (CONFIG_ROM_BASE_HI * $100))

; 64 bytes: an 8 byte header and a 56 byte data section.  The longest reply the
; meter reads is a device name, which is 24 bytes and a terminator.  A small
; region leaves the rest of the page for the image, which matters nowhere here
; but costs nothing either.
CONFIG_RBCP_BCH_SIZE = 64

; The progress and response bytes.  The image holds $00 at both, and neither
; these nor their inverses are $00, so a device that has said nothing yet
; cannot be read as having answered.
CONFIG_RBCP_COMPLETE = $BB  ; inverse = $44
CONFIG_RBCP_STATUS_OK = $CC ; inverse = $33

CONFIG_RBCP_POLL_TIMEOUT = $FF
CONFIG_RBCP_NV_POLL_TIMEOUT = $FFFF
CONFIG_RBCP_AUX_POLL_TIMEOUT = $FFFF

; No retries.  A timeout here means the device did not answer, and that is the
; measurement rather than something to paper over.
CONFIG_RBCP_TIMEOUT_RETRIES = $00

; Used by rbcp_reset, which sends in command mode with no back channel to poll.
CONFIG_RBCP_CMD_PAUSE = $04

CONFIG_RBCP_ZP_BASE = $F0
CONFIG_RBCP_ZP_LENGTH = 16
