; rbcp_config.s — RBCP configuration for the Apple IIe auxiliary I/O tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; An 8KB image in the IIe's EF socket, $E000-$FFFF, which is the one holding
; the reset vector.  A II or II+ has a 2KB F8 socket instead, and this does not
; fit in two kilobytes, so there is one build here and not two.

CONFIG_ROM_BASE_HI = $E0
CONFIG_ROM_SIZE = $2000

; The image's ROM type, from the spec's ROM Types table.  The reset screen
; offers the flash slots reporting this type and no others, because a slot of
; another size is not something this socket can be switched to.
;
; A IIe's EF socket holds a 24 pin mask ROM, and the One ROM boards that serve
; it are 28 pin parts fitted as a 2764.  That is what the device reports the
; slot as, so that is what this has to match.
CONFIG_ROM_TYPE = $0A       ; 2764, 8KB

; $FE is the second to last page of the image.  A command page only has to be
; a page the host never reads while the session is open, and everything this
; program runs has been copied to RAM before the session starts.  It falls in
; the unused space above the code.
CONFIG_RBCP_CMD_PAGE = $FE
CONFIG_RBCP_CMD_PAGE_REL = CONFIG_RBCP_CMD_PAGE - CONFIG_ROM_BASE_HI

; $FC00, and 512 bytes rather than the 64 the terminal manages with.  The
; reset screen reads the flash slot list, whose records are 32 bytes each, so
; the data section has to hold several of them at once.
CONFIG_RBCP_BCH_BASE = $FC00
CONFIG_RBCP_BCH_START = (CONFIG_RBCP_BCH_BASE - (CONFIG_ROM_BASE_HI * $100))
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
