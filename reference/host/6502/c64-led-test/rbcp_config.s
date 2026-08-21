; rbcp_config.s — RBCP configuration for the C64 LED tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

; The device sits in the C64's BASIC socket (U3, 2364), serving a stock BASIC
; image.  Nothing in the machine's service paths — the NMI vectors, the IRQ
; handler, the screen editor, the disk routines — runs through BASIC ROM, so
; all of them stay usable while a session is open.  The one rule this program
; keeps is that it neither executes nor reads $A000-$BFFF between the knock and
; the exit.
;
; SET_LED never waits: the device answers a hold without sitting out its
; duration, so there is no LED equivalent of the auxiliary group's hold
; timeout.

; The BASIC ROM is mapped at $A000.
CONFIG_ROM_BASE_HI = $A0

; A 2364 is 8KB.
CONFIG_ROM_SIZE = $2000

; The image's ROM type, from the spec's ROM Types table.  Only flash slots
; reporting this are candidates for the clean exit, or for the image the reset
; switches to.
CONFIG_ROM_TYPE = $02       ; 2364

; Command page $A000.  A low byte of $00 means a command byte held in X is sent
; with lda $A000,x — four cycles, and no page-cross penalty is reachable.
CONFIG_RBCP_CMD_PAGE = $A0

; The command page value relative to the start of the ROM image.
CONFIG_RBCP_CMD_PAGE_REL = CONFIG_RBCP_CMD_PAGE - CONFIG_ROM_BASE_HI

; Back channel immediately above the command page.
CONFIG_RBCP_BCH_BASE = $A100
CONFIG_RBCP_BCH_START = (CONFIG_RBCP_BCH_BASE - (CONFIG_ROM_BASE_HI * $100))

; 512 bytes: an 8 byte header and a 504 byte data section.  SLOT_PEEK asks for
; 256 bytes at a time during image verification, so the data section has to
; hold at least that.
CONFIG_RBCP_BCH_SIZE = 512

; The program reads $A104 and $A105 before it knocks and refuses to run if
; either already holds one of these four values, which would make the poll
; sequence read a false complete.
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

; $F0-$FF.  Under a running kernal this is RS-232 pointers, the free bytes at
; $FB-$FE, and the tail of the screen editor's line link table.  The program
; saves $D0-$FF whole on entry and restores it on exit, so what is underneath
; does not matter — see the zero page notes in app_defs.s.
CONFIG_RBCP_ZP_BASE = $F0
CONFIG_RBCP_ZP_LENGTH = 16
