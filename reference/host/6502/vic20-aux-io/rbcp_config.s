; rbcp_config.s — RBCP configuration for the VIC-20 auxiliary I/O tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; An 8KB 2364 in the kernal socket, $E000-$FFFF.  The image holds the reset
; vector, so the machine boots into it, and the command page and the back
; channel are the first three pages of the image, where the tester's own code
; is not.

CONFIG_ROM_BASE_HI = $E0
CONFIG_ROM_SIZE = $2000

; The image's ROM type, from the spec's ROM Types table.  The reset screen
; offers the flash slots reporting this type and no others, because a slot of
; another size is not something this socket can be switched to.
CONFIG_ROM_TYPE = $02       ; 2364, 8KB

CONFIG_RBCP_CMD_PAGE = $E0
CONFIG_RBCP_BCH_BASE = $E100

; The command page value relative to the start of the ROM image.  A low byte
; of $00 means a command byte held in X is sent with lda base,x — four cycles,
; and no page-cross penalty is reachable.
CONFIG_RBCP_CMD_PAGE_REL = CONFIG_RBCP_CMD_PAGE - CONFIG_ROM_BASE_HI

; The back channel sits immediately above the command page.
CONFIG_RBCP_BCH_START = (CONFIG_RBCP_BCH_BASE - (CONFIG_ROM_BASE_HI * $100))

; 512 bytes rather than the 64 the terminal manages with.  The reset screen
; reads the flash slot list, whose records are 32 bytes each, so the data
; section has to hold several of them at once.
CONFIG_RBCP_BCH_SIZE = 512

; The progress and response bytes.  The image holds $00 at both, and neither
; these nor their inverses are $00, so a device that has said nothing yet
; cannot be read as having answered.
CONFIG_RBCP_COMPLETE = $BB  ; inverse = $44
CONFIG_RBCP_STATUS_OK = $CC ; inverse = $33

CONFIG_RBCP_POLL_TIMEOUT = $FF
CONFIG_RBCP_NV_POLL_TIMEOUT = $FFFF

; SET_AUX with a hold waits on its own timeout, not the NV one: they bound
; unrelated things.
CONFIG_RBCP_AUX_POLL_TIMEOUT = $FFFF

; No retries.  A timeout here means the device stopped answering, and this
; program wants that to end the run and say so rather than be papered over.
CONFIG_RBCP_TIMEOUT_RETRIES = $00

; Used by rbcp_reset and the switch-and-exit, both of which send in command
; mode with no back channel to poll.
CONFIG_RBCP_CMD_PAUSE = $04

; This program owns the machine from reset, so the top of zero page is free.
CONFIG_RBCP_ZP_BASE = $F0
CONFIG_RBCP_ZP_LENGTH = 16
