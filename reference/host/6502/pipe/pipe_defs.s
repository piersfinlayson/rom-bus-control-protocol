; pipe_defs.s — what every machine's pipe throughput test shares
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The tester is one program built for several machines.  This file and the
; eight beside it are the same on all of them.  What differs is the screen, the
; keys, the clock and the zero page, and those come from the application's own
; plat_defs.s and plat.s.  ../README.md lists the whole interface.

    .include "plat_defs.s"
    .include "rbcp_stage.s"

; ---------------------------------------------------------------------------
; Status codes.  Passed to display_status in A.  Nothing outside display.s
; holds a string.
; ---------------------------------------------------------------------------

STAT_BLANK      = $00
STAT_OPENING    = $01       ; knocking and entering command-response mode
STAT_ARMED      = $02
STAT_NO_DEVICE  = $03       ; no token increment — nothing answered the knock
STAT_ENTER_FAIL = $04       ; the device answered but refused ENTER_CMD_RESP
STAT_VERSION    = $05
STAT_NO_PIPE    = $06
STAT_PIPE_DIR   = $07       ; pipe 0 does not carry OUT
STAT_RUNNING    = $08
STAT_STOPPED    = $09
STAT_NO_ANSWER  = $0A       ; the token never moved, so nothing received it
STAT_NOT_ARMED  = $0B
STAT_NO_COMPLETE = $0C      ; the token moved and the command never finished
STAT_BAD_REFUSAL = $0D      ; a write refused while the pipe had room for it
STAT_PIPE_STUCK = $0E       ; the pipe stayed full for STALL_SECS
STAT_NO_RECOVER = $0F       ; the device did not come back after a reset
STAT_COUNT      = $10

; ---------------------------------------------------------------------------
; What a failed write is given before the run ends.  See fault.s.
; ---------------------------------------------------------------------------

; Immediate retries of a refused write before the pipe is asked how much room
; it has.  Eight of them cost about 800 cycles, which is under a millisecond.
FAULT_BURST     = 8

; How long a pipe that really is full may stay that way.  The clock's low byte
; is read to measure it, which is unambiguous below 256 ticks.
STALL_SECS      = 5
STALL_TICKS     = STALL_SECS * PLAT_TICK_HZ

.assert STALL_TICKS < 256, error, "The stall bound outgrows one byte of clock"

; ---------------------------------------------------------------------------
; Send paths.  The order is the order they appear on the paths row.
; ---------------------------------------------------------------------------

PATH_LIB4       = 0
PATH_LIB1       = 1
PATH_TUNED4     = 2
PATH_COUNT      = 3

; ---------------------------------------------------------------------------
; Key codes.  plat_key returns one of these, and the machine's own matrix, or
; whatever else it reads, stays behind that.
; ---------------------------------------------------------------------------

KEY_NONE_CODE   = $00
KEY_1_CODE      = $01
KEY_2_CODE      = $02
KEY_3_CODE      = $03
KEY_T_CODE      = $04
KEY_RET_CODE    = $05
