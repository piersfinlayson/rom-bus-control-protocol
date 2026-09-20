; amiga_defs.s — the meter's own constants
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The hardware, the screen geometry and the chip RAM layout are in
; ../amiga-common/amiga_defs.s, which is included before this file.

; ---------------------------------------------------------------------------
; The commands under test
;
; Four frames rather than one.  A fault in how the device takes bytes off the
; bus reaches every command and mangles each into something different, because
; the bytes that make up a frame differ.  A fault confined to one group shows
; in a single row instead, and the per-command counts are how the two are told
; apart.
;
; Every one is valid on any device that answers the group at all, and the
; arguments are chosen so the device has nothing to disagree with.
; ---------------------------------------------------------------------------
TEST_COUNT          EQU 4
TEST_STRIDE         EQU 6                   ; group, cmd, count, 3 arguments

; ---------------------------------------------------------------------------
; Chip DMA
;
; Two states, on and off, counted apart for the whole run.  README.md says why.
; ---------------------------------------------------------------------------
VARY_COUNT          EQU 2                   ; on, then off
VARY_ON             EQU 0                   ; and the index into the counters
VARY_OFF            EQU 1

; The key that asks for the switch.
; amiga_getkey returns a letter in the case it was typed in, and the meter
; takes it either way.
KEY_VARY            EQU 'S'
KEY_VARY_LOWER      EQU 's'

; DMACON, written with bit 15 set to turn bits on and clear to turn them off.
DMAF_SETCLR         EQU $8000
DMAF_MASTER         EQU $0200

; ---------------------------------------------------------------------------
; Phase and refresh intervals
;
; A phase is a fixed number of commands and ends with a line down the pipe, so
; the pipe is the heartbeat as well as the result.  The screen is redrawn far
; more often than that, and the numbers on it are worked out only when it is.
; ---------------------------------------------------------------------------
PHASE_COMMANDS      EQU $2000               ; 8192 commands a phase
DRAW_COMMANDS       EQU 250                 ; commands between screen refreshes
OPEN_TRIES          EQU 4                   ; goes at each command that finds
                                            ; the report's pipe
RECOVER_TRIES       EQU 3                   ; resets before the device is given
                                            ; up for lost

; ---------------------------------------------------------------------------
; Pens.  amiga_stress.s gives each of these its colour before the common
; palette is included.  Gold stays the two bands and the brand, so a label in
; its own pen does not compete with them.
; ---------------------------------------------------------------------------
PEN_LABEL           EQU 6                   ; every label and heading
PEN_WARN            EQU 7                   ; there is no pipe to report down
PEN_MARK            EQU 8                   ; which state of chip DMA is running
PEN_BAD             EQU 14                  ; error and lost counts

; ---------------------------------------------------------------------------
; Screen layout — 40 columns by the 25 rows an NTSC machine shows
;
; Every count is a 32-bit count, so every number field is the ten digits
; 4294967295 takes.  Two of them and their labels fill a row exactly.
; ---------------------------------------------------------------------------
ROW_TITLE           EQU 0
ROW_DEV             EQU 2
ROW_VER             EQU 3
ROW_PROTO           EQU 4
ROW_PIPE            EQU 5
ROW_BIG             EQU 7                   ; the headline band
ROW_RAW             EQU 9                   ; the run's sent and errors
ROW_LOST            EQU 10
ROW_HEAD            EQU 11
ROW_FIRST           EQU 12                  ; through ROW_FIRST+TEST_COUNT-1
ROW_VARY            EQU 17                  ; and the row under it
ROW_NOTE            EQU 20                  ; the last failure, three rows
ROW_REC_SENT        EQU 21
ROW_REC_GOT         EQU 22
ROW_KEYS            EQU 24

COL_TITLE           EQU 1
COL_BRAND           EQU SCREEN_COLS-12      ; "PIERS.ROCKS" and a space
COL_TEXT            EQU 1
COL_NAME            EQU 1                   ; a command's name
COL_SENT            EQU 14                  ; and its two counts
COL_BAD             EQU 30

; The headline carries a figure for each state of chip DMA.  Two ten-digit
; ratios sit behind their labels, the second ending in the last column.
COL_BIG_ON_LBL      EQU 1                   ; "ON 1 IN"
COL_BIG_ON          EQU 9
COL_BIG_OFF_LBL     EQU 21                  ; "OFF 1 IN"
COL_BIG_OFF         EQU 30

COL_RAW_SENT_LBL    EQU 1                   ; "SENT"
COL_RAW_SENT        EQU 6
COL_RAW_BAD_LBL     EQU 20                  ; "ERR"
COL_RAW_BAD         EQU 24

; Lost goes on the row under the errors it is part of, in the same columns.
COL_RAW_LOST_LBL    EQU 19                  ; "LOST"
COL_RAW_LOST        EQU 24

COL_HEAD_SENT       EQU 20                  ; the headings over the two count
COL_HEAD_BAD        EQU 35                  ; columns

; Each state's row carries its marker, ON or OFF, and its own sent and errors.
; The ratio is the band's job, and repeating it here would leave no room for
; the count that tells a state with nothing wrong from one with nothing tried.
COL_VARY_MARK       EQU 2
COL_VARY_SENTLBL    EQU 6                   ; "SENT"
COL_VARY_SENT       EQU 11
COL_VARY_BADLBL     EQU 26                  ; "ERR"
COL_VARY_BAD        EQU 30

; ---------------------------------------------------------------------------
; The number fields
;
; Every count on the screen has a slot, and the slot holds the characters that
; go in the field rather than the count they came from.  A refresh fills every
; slot and then writes them out, which is what stops the totals and the rows
; under them being a photograph of two different moments.
;
; There are two of each slot, one for what the numbers say now and one for
; what the screen already has, and only the characters that differ are
; written.  Most of a ten-digit count is the same as it was last time.
;
; Beside the two slots each field keeps the count its characters were made
; from.  Turning a 32-bit count into ten digits is the dearest thing a refresh
; does, and on a run with nothing going wrong most of the counts have not
; moved at all since the last one.
; ---------------------------------------------------------------------------
FLD_BIG_ON          EQU 0
FLD_BIG_OFF         EQU 1
FLD_SENT            EQU 2
FLD_ERR             EQU 3
FLD_LOST            EQU 4
FLD_CMD             EQU 5                   ; sent then errors, per command
FLD_VARY            EQU FLD_CMD+(TEST_COUNT*2)
FLD_COUNT           EQU FLD_VARY+(VARY_COUNT*2)

; A field is exactly one converted number wide, so staging one is a copy.
NUM_DIGITS          EQU 10
FLD_WIDTH           EQU NUM_DIGITS

; ---------------------------------------------------------------------------
; The report line
;
; The longest is a phase line.  A setting's three numbers cannot all be ten
; digits at once: a ten-digit count over a divisor of d digits leaves a
; quotient of at most eleven less d, so the error count and the ratio together
; are eleven digits however the two fall.  Twenty one digits and the words
; around them is as much as one setting can take, and the run's lost count and
; the newline come after the second of them.
; ---------------------------------------------------------------------------
LINE_MAX            EQU 128

; ---------------------------------------------------------------------------
; Error numbers, indices into the error message table.  Only a session that
; never opened ends this way.  A device that stops answering partway through
; leaves the counts on the screen, because the counts are the result.
; ---------------------------------------------------------------------------
ERR_NO_DEVICE       EQU 0
ERR_ENTER           EQU 1
ERR_VERSION         EQU 2

; ---------------------------------------------------------------------------
; The meter's variables, in the chip RAM the application owns.  The common
; code owns VAR_BASE+0 to 24, APP_BASE+$158 to $15A, APP_BASE+$160 to $165 and
; APP_BASE+$170 to $177, and the library's un-swap buffer is at $2200, so
; everything here starts clear of them.  Longs are at even offsets.
; ---------------------------------------------------------------------------
MTR_VARS            EQU APP_BASE+$400

MTR_DEV_TYPE        EQU MTR_VARS+$000       ; 25 bytes, read once
MTR_DEV_VER         EQU MTR_VARS+$020       ; 25
MTR_PROTO           EQU MTR_VARS+$040       ; 12

; What each command has been asked to do and how often it went wrong, for the
; whole run, because the headline is the run.
MTR_CMD_SENT        EQU MTR_VARS+$050       ; TEST_COUNT longs
MTR_CMD_BAD         EQU MTR_VARS+$060

; The same again, split by the state of chip DMA.  The headline comes off
; these, so errors is a long like sent — a device getting one in four wrong
; passes 65535 in minutes, and a count that has wrapped reads as a small
; number rather than as a broken one.
MTR_VARY_SENT       EQU MTR_VARS+$070       ; VARY_COUNT longs
MTR_VARY_BAD        EQU MTR_VARS+$078

; The failures the device never answered at all, against the state they
; happened under.  Every one of these is also counted in MTR_VARY_BAD.
MTR_LOST            EQU MTR_VARS+$080

MTR_CUR_TEST        EQU MTR_VARS+$088
MTR_VARY_IDX        EQU MTR_VARS+$089       ; 0 chip DMA on, 1 off
MTR_VARY_OFF        EQU MTR_VARS+$08A       ; and where that puts the counters
MTR_JITTER          EQU MTR_VARS+$08B       ; the loop padding's shift register
MTR_DRAW_LEFT       EQU MTR_VARS+$08C       ; word
MTR_PHASE_NO        EQU MTR_VARS+$08E       ; word
MTR_PHASE_LEFT      EQU MTR_VARS+$090       ; long
MTR_VARY_PEND       EQU MTR_VARS+$094       ; `S` has asked for the other state

; The last failure, whole.  Taken from the library's own scratch and from the
; response header at the moment it happened, because a device that has stopped
; answering will not answer a question about it later either.
MTR_FAIL_STAGE      EQU MTR_VARS+$098       ; 1 not taken, 2 unfinished, 3 refused
MTR_FAIL_TEST       EQU MTR_VARS+$099       ; which of the four
MTR_FAIL_GROUP      EQU MTR_VARS+$09A       ; and the frame that went out
MTR_FAIL_CMD        EQU MTR_VARS+$09B
MTR_FAIL_ARGS       EQU MTR_VARS+$09C       ; 3
MTR_FAIL_TOK        EQU MTR_VARS+$09F       ; the token before sending
MTR_FAIL_HDR        EQU MTR_VARS+$0A0       ; 6, the header at the failure

MTR_NUM_VAL         EQU MTR_VARS+$0A8       ; long, what the arithmetic eats
MTR_NUM_DEN         EQU MTR_VARS+$0AC       ; long, what num_div divides by
MTR_NUM_TXT         EQU MTR_VARS+$0B0       ; 10 digits, right aligned
MTR_NUM_FIRST       EQU MTR_VARS+$0BA       ; the first of them

MTR_LINE            EQU MTR_VARS+$0C0       ; LINE_MAX bytes and the null that
                                            ; ends them
MTR_LINE_LEN        EQU MTR_VARS+$142

MTR_NOW             EQU MTR_VARS+$150       ; FLD_COUNT*FLD_WIDTH
MTR_SHOWN           EQU MTR_VARS+$200       ; and what the screen already has
MTR_WAS             EQU MTR_VARS+$300       ; FLD_COUNT longs, the count each
                                            ; field's characters were made from
MTR_DIRTY           EQU MTR_VARS+$348       ; FLD_COUNT bytes, 1 where this
                                            ; refresh wrote the slot
MTR_FIRST_DRAW      EQU MTR_VARS+$360       ; 1 until the first refresh is out
MTR_END             EQU MTR_VARS+$364
