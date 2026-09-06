; rbcp_config.s — RBCP configuration for the Apple IIe RBCP terminal
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; An 8KB image in the IIe's EF socket, $E000-$FFFF, which is the one holding
; the reset vector.  A II or II+ has a 2KB F8 socket instead, and the terminal
; does not fit in two kilobytes, so there is one build here and not two.

CONFIG_ROM_BASE_HI = $E0
CONFIG_ROM_SIZE = $2000

; $FE is the second to last page of the image.  A command page only has to be
; a page the host never reads while the session is open, and everything the
; terminal runs has been copied to RAM before the session starts.  It falls in
; the unused space above the code.
CONFIG_RBCP_CMD_PAGE = $FE
CONFIG_RBCP_CMD_PAGE_REL = CONFIG_RBCP_CMD_PAGE - CONFIG_ROM_BASE_HI

; $FFB0 puts the back channel at the top of the image, under the 6502 vectors,
; so the code below it is one unbroken run.  The host reads this region while
; the session is open, so the page holding it cannot be the command page.
CONFIG_RBCP_BCH_BASE = $FFB0
CONFIG_RBCP_BCH_START = (CONFIG_RBCP_BCH_BASE - (CONFIG_ROM_BASE_HI * $100))

; 64 bytes: an 8 byte header and a 56 byte data section.  The longest reply the
; terminal reads is a device name, which is 24 bytes and a terminator.
CONFIG_RBCP_BCH_SIZE = 64

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
