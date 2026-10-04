; rbcp_config.s — RBCP configuration for the C64 LED tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The kernal socket build is the default.  BASIC_SOCKET selects the BASIC
; socket build and COMBINED the image spanning both.

.ifdef COMBINED

; The 23128 spanning both sockets.  The command page and back channel are in
; the BASIC half, which the machine doesn't boot from.
CONFIG_ROM_BASE_HI = $A0
CONFIG_ROM_SIZE = $4000
CONFIG_ROM_TYPE = $03       ; 23128, 16KB
CONFIG_RBCP_CMD_PAGE = $A0
CONFIG_RBCP_BCH_BASE = $A100

.elseif .defined(BASIC_SOCKET)

; The 2364 in the BASIC socket.
CONFIG_ROM_BASE_HI = $A0
CONFIG_ROM_SIZE = $2000
CONFIG_ROM_TYPE = $02       ; 2364, 8KB
CONFIG_RBCP_CMD_PAGE = $A0
CONFIG_RBCP_BCH_BASE = $A100

.else

; The 2364 in the kernal socket.
CONFIG_ROM_BASE_HI = $E0
CONFIG_ROM_SIZE = $2000
CONFIG_ROM_TYPE = $02       ; 2364, 8KB
CONFIG_RBCP_CMD_PAGE = $E0
CONFIG_RBCP_BCH_BASE = $E100

.endif

; The command page value relative to the start of the ROM image.  lda base,x
; never crosses a page, so every command byte takes four cycles.
CONFIG_RBCP_CMD_PAGE_REL = CONFIG_RBCP_CMD_PAGE - CONFIG_ROM_BASE_HI

; The back channel's offset in the ROM image.
CONFIG_RBCP_BCH_START = (CONFIG_RBCP_BCH_BASE - (CONFIG_ROM_BASE_HI * $100))

; An 8 byte header and a 504 byte data section.  More than this program reads,
; but the device is already configured for it.
CONFIG_RBCP_BCH_SIZE = 512

; The progress and response bytes are $00 in the image.  Neither these nor
; their inverses are $00, so a silent device can't read as having answered.
CONFIG_RBCP_COMPLETE = $BB  ; inverse = $44
CONFIG_RBCP_STATUS_OK = $CC ; inverse = $33

CONFIG_RBCP_POLL_TIMEOUT = $FF
CONFIG_RBCP_NV_POLL_TIMEOUT = $FFFF

; No retries.  A timeout here means the device stopped answering, and this
; program wants that to end the run and say so rather than be papered over.
CONFIG_RBCP_TIMEOUT_RETRIES = $00

; Used by rbcp_reset and rbcp_cmd_switch_and_exit, both of which send in
; command mode with no back channel to poll.
CONFIG_RBCP_CMD_PAUSE = $04

; The top of zero page is free because the image owns the machine from reset.
CONFIG_RBCP_ZP_BASE = $F0
CONFIG_RBCP_ZP_LENGTH = 16
