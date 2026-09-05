; stress_defs.s — what every machine's reliability meter shares
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The meter is one program built for several machines.  This file and the
; four beside it are the same on all of them.  What differs is the screen, the
; keys, and the one thing the machine varies, and those come from the
; application's own plat_defs.s and plat.s.
;
; What a platform must define here, in plat_defs.s:
;
;   SCREEN_COLS, SCREEN_ROWS    the screen the meter draws on
;   ROW_*, COL_*                where each part of the display goes
;   PLAT_VARY                   1 if the machine varies something, 0 if not
;   KEY_VARY                    the key that switches it, where it does
;
; and in plat.s:
;
;   plat_init                   the display, from RAM, before the first knock
;   plat_cls                    a blank screen
;   plat_row      A = row       points the screen writer at a row
;   plat_put      A = ASCII, Y = column, X = a COLR_ role
;   plat_key                    a KEY_ code, or KEY_NONE_CODE
;   plat_vary_set A = 1 on      only where PLAT_VARY is 1
;   plat_vary_word              the word for it, and plat_key_word for the
;                               key, only where PLAT_VARY is 1

    .include "plat_defs.s"
    .include "rbcp_stage.s"

; ---------------------------------------------------------------------------
; The commands under test
;
; Four shapes rather than one.  A fault in how the device takes bytes off the
; bus should reach every command, and should mangle each into something
; different, because the bytes that make up a frame differ.  A fault that only
; ever touches one group is a different animal, and this is how the two are
; told apart.
;
; The arguments are fixed and chosen to be always valid, so a refusal means
; something went wrong rather than that the device disagreed with the request.
; ---------------------------------------------------------------------------

TEST_COUNT      = 4
TEST_STRIDE     = 6         ; group, cmd, argument count, three arguments

TEST_NOP        = 0
TEST_PROTO      = 1
TEST_LED_INFO   = 2
TEST_LED_MODE   = 3

; ---------------------------------------------------------------------------
; The machine's own variable
;
; A machine whose video steals cycles from the processor has two rates, not
; one, and the counts are kept apart so that a run which switches between them
; still says what each was.  A machine that varies nothing has one column and
; no key.
; ---------------------------------------------------------------------------

.if PLAT_VARY
VARY_COUNT = 2              ; on, then off
.else
VARY_COUNT = 1
.endif

VARY_ON  = 0                ; and the index into the counters
VARY_OFF = 1

; ---------------------------------------------------------------------------
; How often things happen
;
; A phase is a fixed number of commands and ends with a line down the pipe, so
; the pipe is the heartbeat as well as the result.  The screen is redrawn far
; more often than that, and the numbers on it are worked out only when it is.
; ---------------------------------------------------------------------------

PHASE_COMMANDS  = $2000     ; 8192 commands a phase
DRAW_COMMANDS   = 250       ; one screen refresh per this many commands
PIPE_TRIES      = 4         ; goes at one chunk of the report before giving up
OPEN_TRIES      = 4         ; goes at each command that finds the report's pipe

; ---------------------------------------------------------------------------
; Colour roles.  The meter asks for a role and the machine decides what that
; looks like, or ignores it where the screen has no colour.
; ---------------------------------------------------------------------------

COLR_PLAIN  = 0
COLR_DIM    = 1
COLR_HEAD   = 2
COLR_BIG    = 3
COLR_OK     = 4
COLR_BAD    = 5
COLR_WARN   = 6
COLR_TITLE  = 7     ; and everything from here up is reverse video, where the
COLR_BAND   = 8     ; machine has any

; ---------------------------------------------------------------------------
; Why a session refused to start.  Returned in A by sess_open with carry set.
; ---------------------------------------------------------------------------

FAIL_NO_DEVICE  = $00       ; the knock token never moved
FAIL_ENTER      = $01       ; the device refused ENTER_CMD_RESP
FAIL_VERSION    = $02       ; the device speaks a protocol this cannot
FAIL_COUNT      = $03

; ---------------------------------------------------------------------------
; Keys.  Every machine returns this for nothing held, and its own codes above.
; ---------------------------------------------------------------------------

KEY_NONE_CODE   = $00

; ---------------------------------------------------------------------------
; Counter widths
;
; Every count is four bytes.  Commands sent, because a run left alone
; overnight passes a million an hour.  Failures, whether counted against a
; setting or against one of the four commands, because two bytes stop at
; 65,535 and a device getting one in four wrong reaches that in minutes — and
; a count that has wrapped reads as a small number rather than as a broken
; one.  Lost, the failures the device never answered at all, is four bytes and
; kept against a setting like the rest, because a command lost at one setting
; and one lost at the other are different results.
; ---------------------------------------------------------------------------

.macro INC32 base
    .local done
    inc base + 0, x
    bne done
    inc base + 1, x
    bne done
    inc base + 2, x
    bne done
    inc base + 3, x
done:
.endmacro
