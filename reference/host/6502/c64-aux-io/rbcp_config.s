; rbcp_config.s — RBCP configuration for the C64 auxiliary I/O tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Three images, two sockets.
;
; The kernal build is an 8KB 2364 at $E000-$FFFF.  The machine boots into it,
; and the command page and the back channel are the first three pages of the
; image, where the tester's own code is not.
;
; The BASIC build is the same 8KB 2364 in the other socket, at $A000-$BFFF,
; with the machine's own kernal still fitted.  The kernal runs at reset and
; enters BASIC through the word at $A000, which is where this image is entered.
;
; The combined build is a 16KB 23128 spanning both ROM sockets: $A000-$BFFF
; where BASIC would be, and $E000-$FFFF where the kernal would be.  The BASIC
; half is blank and the tester does not need one, so the command page and the
; back channel go there.  The device then writes its replies into eight
; kilobytes of nothing, and every byte the machine boots out of is untouched.
;
; Build the second with BASIC_SOCKET=1 and the third with COMBINED=1.

.ifdef COMBINED

; The 23128 covers both sockets.  The image starts where BASIC would.
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

; The command page value relative to the start of the ROM image.  A low byte
; of $00 means a command byte held in X is sent with lda base,x — four cycles,
; and no page-cross penalty is reachable.
CONFIG_RBCP_CMD_PAGE_REL = CONFIG_RBCP_CMD_PAGE - CONFIG_ROM_BASE_HI

; The back channel sits immediately above the command page in every build.
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
