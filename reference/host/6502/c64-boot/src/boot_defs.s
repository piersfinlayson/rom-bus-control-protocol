; boot_defs.s — bootloader definitions not in c64_defs.s
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

    .include "c64_defs.s"

; ---------------------------------------------------------------------------
; VIC-II
; ---------------------------------------------------------------------------

; The display enable bit.
VIC_CTRL1_DEN   = %00010000

; ---------------------------------------------------------------------------
; CIA2 timers.  Timer A counts a millisecond of clock cycles and timer B
; counts timer A.
; ---------------------------------------------------------------------------

CIA2_TALO       = $DD04
CIA2_TAHI       = $DD05
CIA2_TBLO       = $DD06
CIA2_TBHI       = $DD07
CIA2_ICR        = $DD0D
CIA2_CRA        = $DD0E
CIA2_CRB        = $DD0F

CIA_ICR_NONE    = %01111111     ; clear every interrupt enable
CIA_CRA_RUN     = %00010001     ; start, load the latch, count clock cycles
CIA_CRB_RUN     = %01010001     ; start, load the latch, count timer A

; Clock cycles in a millisecond, less one, because a timer runs from its latch
; down to zero.
MS_LATCH_PAL    = 985 - 1
MS_LATCH_NTSC   = 1023 - 1

; ---------------------------------------------------------------------------
; The record of the session's commands.  See diag.s.
; ---------------------------------------------------------------------------

ZP_ENT_LO       = $D7           ; the entry being written or read
ZP_ENT_HI       = $D8

; One entry.  The frame is first so that it can be read as one run of bytes.
ENT_GROUP       = 0
ENT_CMD         = 1
ENT_ARGS        = 2             ; nine bytes, the most a command has
ENT_COUNT       = 11            ; how many of them were sent
ENT_TOK         = 12            ; token LSB before the command went out
ENT_STAGE       = 13            ; 0 if completed, else a STAGE_ from rbcp_stage.s
ENT_MS          = 14            ; milliseconds to completion or the timeout
ENT_HDR         = 16            ; response header as read afterwards
ENT_SIZE        = 32

; Group, command, token LSB and MSB, progress and response.
HDR_LEN         = 6

; The menu path with an NV commit sends eleven commands.
ENT_MAX         = 12

; Sends a command through the RBCP library routine and records it.  A and X
; are passed to the routine unchanged, and its A and carry are returned.
.macro recorded routine
    jsr diag_begin
    jsr routine
    jsr diag_end
.endmacro
