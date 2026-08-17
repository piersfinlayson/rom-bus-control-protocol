; pipe_defs.s — constants for the C64 pipe throughput test
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Zero page
; ---------
; Three claims: the RBCP library at $F0-$FF, the c64_hw.s scratch at $D0-$D6,
; and this program's own at $D7-$DF.  There is no contiguous hole in that range
; to use instead — $D0-$D8 is screen editor state, $D9-$F2 is LDTB1, the screen
; line link table, $F3-$F4 the colour RAM pointer, $F5-$F6 KEYLOG, $F7-$FA the
; RS-232 buffer pointers, $FB-$FE the four free bytes and $FF a BASIC
; temporary.  So $D0-$FF is saved whole on entry and restored on exit.
;
; That is safe only while nothing else is running in it, which means interrupts
; masked and no kernal or BASIC call in flight.  Both hold from the sei in
; pipe_test.s to the restore on the way out.  The screen editor is broken for
; that whole span, which is why the screen is written directly and the first
; kernal screen call happens after the restore.

    .include "c64_defs.s"

; ---------------------------------------------------------------------------
; Application zero page — between the c64_hw.s scratch and the RBCP block
; ---------------------------------------------------------------------------

ZP_APP0     = $D7
ZP_APP1     = $D8
ZP_APP2     = $D9
ZP_APP3     = $DA
ZP_APP4     = $DB
ZP_APP5     = $DC
ZP_APP6     = $DD
ZP_APP7     = $DE
ZP_APP8     = $DF

; The saved block: $D0 to $FF inclusive.
ZP_SAVE_BASE  = $D0
ZP_SAVE_COUNT = $30

; ---------------------------------------------------------------------------
; Kernal and BASIC locations this program relies on
; ---------------------------------------------------------------------------

NMINV           = $0318     ; NMI vector, kernal jmp ($0318) target
PALNTSC         = $02A6     ; kernal's video standard flag: 0 = NTSC, 1 = PAL
KEY_NDX         = $00C6     ; kernal keyboard buffer count, zeroed on the way out
KERNAL_CLRSCR   = $E544     ; called only after the zero page restore

; ---------------------------------------------------------------------------
; CIA2 — timing.  CIA1 carries the keyboard matrix and the kernal's own timer
; and is left as found.
; ---------------------------------------------------------------------------

CIA2_TA_LO      = $DD04
CIA2_TA_HI      = $DD05
CIA2_TB_LO      = $DD06
CIA2_TB_HI      = $DD07
CIA2_ICR        = $DD0D
CIA2_CRA        = $DD0E
CIA2_CRB        = $DD0F

; Timer A: continuous, count phi2, start.  Underflows every 65536 cycles.
CIA2_CRA_RUN    = %00000001
; Timer B: continuous, count Timer A underflows, start.
CIA2_CRB_RUN    = %01000001

; ---------------------------------------------------------------------------
; Keyboard.  $DC00 drives a column low, $DC01 reads rows low.  The kernal has
; already set CIA1 DDRA to output and DDRB to input, so neither is touched.
; ---------------------------------------------------------------------------

KEY_COL_0       = %11111110     ; PA0: RETURN
KEY_COL_1       = %11111101     ; PA1: 3
KEY_COL_2       = %11111011     ; PA2: T
KEY_COL_7       = %01111111     ; PA7: 1, 2, Q

KEY_RETURN_BIT  = %00000010     ; PB1
KEY_1_BIT       = %00000001     ; PB0
KEY_2_BIT       = %00001000     ; PB3
KEY_3_BIT       = %00000001     ; PB0
KEY_T_BIT       = %01000000     ; PB6
KEY_Q_BIT       = %01000000     ; PB6

; ---------------------------------------------------------------------------
; Status codes.  Passed to display_status in A.  Nothing outside display.s
; holds a string.
; ---------------------------------------------------------------------------

STAT_BLANK      = $00
STAT_CHECKING   = $01       ; reading the BASIC image before the knock
STAT_OPENING    = $02       ; knocking and entering command-response mode
STAT_ARMED      = $03
STAT_CLASH      = $04       ; $A104 or $A105 already holds a configured value
STAT_NO_DEVICE  = $05       ; no token increment — nothing answered the knock
STAT_ENTER_FAIL = $06       ; the device answered but refused ENTER_CMD_RESP
STAT_VERSION    = $07
STAT_NO_PIPE    = $08
STAT_PIPE_DIR   = $09       ; pipe 0 does not carry host-to-device
STAT_RAM_SLOTS  = $0A       ; fewer than two RAM slots
STAT_DIRTY_EXIT = $0B       ; left command-response mode without a clean slot
STAT_RUNNING    = $0C
STAT_STOPPED    = $0D
STAT_LOST       = $0E       ; the device stopped answering mid-run
STAT_NOT_ARMED  = $0F
STAT_VERIFYING  = $10       ; looking for a flash slot matching the served image
STAT_NO_CLEAN   = $11       ; no flash slot matches, so there is no clean exit
STAT_COUNT      = $12

; ---------------------------------------------------------------------------
; Screen rows.  Only display.s uses these.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DEVICE      = 1
ROW_SLOTS       = 2
ROW_PATHS       = 4
ROW_RATE        = 6
ROW_BEST        = 7
ROW_TOTAL       = 9
ROW_LINES       = 10
ROW_SECS        = 11
ROW_REFUSALS    = 13
ROW_ERRORS      = 14
ROW_MEAN        = 16
ROW_STATUS      = 22
ROW_KEYS        = 24

; Numbers are eight digits wide, right-aligned, ending at column 29.
NUM_COL         = 22
NUM_WIDTH       = 8

; ROM type of the image being served, from the spec's ROM Types table.  Only
; flash slots reporting this are candidates for the clean exit.
ROM_TYPE_2364   = $02

; Send paths.  The order is the order they appear on the paths row.
PATH_LIB4       = 0
PATH_LIB1       = 1
PATH_TUNED4     = 2
PATH_COUNT      = 3

; Key codes returned by the scanner
KEY_NONE_CODE   = $00
KEY_1_CODE      = $01
KEY_2_CODE      = $02
KEY_3_CODE      = $03
KEY_T_CODE      = $04
KEY_Q_CODE      = $05
KEY_RET_CODE    = $06
