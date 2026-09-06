; rbcp_config.s — RBCP configuration for the VIC-20 RBCP terminal
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; An 8KB 2364 in the kernal socket, $E000-$FFFF.  The image holds the reset
; vector, so the machine boots into it, and the command page and the back
; channel are the first three pages of the image, where the terminal's own code
; is not.

CONFIG_ROM_BASE_HI = $E0
CONFIG_ROM_SIZE = $2000

CONFIG_RBCP_CMD_PAGE = $E0
CONFIG_RBCP_BCH_BASE = $E100

; The command page value relative to the start of the ROM image.  A low byte
; of $00 means a command byte held in X is sent with lda base,x — four cycles,
; and no page-cross penalty is reachable.
CONFIG_RBCP_CMD_PAGE_REL = CONFIG_RBCP_CMD_PAGE - CONFIG_ROM_BASE_HI

; The back channel sits immediately above the command page.
CONFIG_RBCP_BCH_START = (CONFIG_RBCP_BCH_BASE - (CONFIG_ROM_BASE_HI * $100))

; 512 bytes: an 8 byte header and a 504 byte data section.  The largest reply
; the terminal reads is a device name, which is nowhere near that, but a region
; the device has already been configured for costs nothing to keep.
CONFIG_RBCP_BCH_SIZE = 512

; The progress and response bytes.  The image holds $00 at both, and neither
; these nor their inverses are $00, so a device that has said nothing yet
; cannot be read as having answered.
CONFIG_RBCP_COMPLETE = $BB  ; inverse = $44
CONFIG_RBCP_STATUS_OK = $CC ; inverse = $33

CONFIG_RBCP_POLL_TIMEOUT = $FF
CONFIG_RBCP_NV_POLL_TIMEOUT = $FFFF
CONFIG_RBCP_AUX_POLL_TIMEOUT = $FFFF

; Three goes at a command the device never received.  The retry covers that one
; case and no other, so a line cannot arrive twice through it, and a typed line
; is worth a second go rather than an error on the screen.
CONFIG_RBCP_TIMEOUT_RETRIES = $03

; Used by rbcp_reset, which sends in command mode with no back channel to poll.
CONFIG_RBCP_CMD_PAUSE = $04

; The terminal owns the machine from reset, so the top of zero page is free.
CONFIG_RBCP_ZP_BASE = $F0
CONFIG_RBCP_ZP_LENGTH = 16
