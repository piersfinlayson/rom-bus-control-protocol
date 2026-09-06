; plat_defs.s — what the C64 is, to the pipe throughput test
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen, the keys, the clock and the zero page.  Everything else the
; tester needs is the same on every machine and lives in ../pipe.

    .include "c64_defs.s"

; ---------------------------------------------------------------------------
; Registers c64_defs.s does not name
; ---------------------------------------------------------------------------

VIC_RASTER      = $D012     ; raster line, bit 8 in VIC_CTRL1 bit 7

; The kernal's NMI vector, which only the BASIC socket image has a use for.
NMINV           = $0318

; The display enable bit.  Clearing it stops every fetch the VIC-II makes.
VIC_CTRL1_DEN   = %00010000

; CIA2 carries the clock.  CIA1 has the keyboard matrix and is read for keys
; and nothing else.
CIA2_TA_LO      = $DD04
CIA2_TA_HI      = $DD05
CIA2_TB_LO      = $DD06
CIA2_TB_HI      = $DD07
CIA2_CRA        = $DD0E
CIA2_CRB        = $DD0F

; Timer A: continuous, count phi2, start.
CIA2_CRA_RUN    = %00000001
; Timer B: continuous, count Timer A underflows, start.
CIA2_CRB_RUN    = %01000001

; ---------------------------------------------------------------------------
; The clock
;
; A window is a fixed number of Timer A underflows, and it has to be exactly a
; second, because the byte count in it is then the rate with no division.
;
; The PAL clock is 985248 Hz and 985248 = 32 * 30789, so 32 periods of 30789
; cycles is a second to the cycle.  NTSC is 1022727 Hz, near enough
; 14318181/14, which is not an integer multiple of anything useful: 32 periods
; of 31960 is 1022720 cycles, 6.8 parts per million short.  At the rates being
; measured that is far under a single byte.
;
; A CIA reloads from its latch and counts down through zero, so the value
; written is the period minus one.  Which of the two latches is loaded is
; settled at run time — see plat_video_pal.
;
; Timer B counts Timer A underflows and is read as the tick.  It counts down,
; which is why elapsed is start minus now.
; ---------------------------------------------------------------------------

PLAT_TICK_HZ    = 32
PAL_TA_LATCH    = 30789 - 1
NTSC_TA_LATCH   = 31960 - 1

; PLAT_CLOCK_READ leaves the tick in A.  PLAT_CLOCK_ELAPSED leaves the ticks
; since the byte at start in A, with the carry flag disturbed.  Macros rather
; than routines because timing_window_closed is fourteen cycles and runs once a
; line, inside the measured window, where a jsr and its rts would be most of
; another percent.
.macro PLAT_CLOCK_READ
    lda CIA2_TB_LO
.endmacro

.macro PLAT_CLOCK_ELAPSED start
    lda start
    sec
    sbc CIA2_TB_LO
.endmacro

; The tick comes off a timer, so nothing has to be counted in software and the
; send paths carry no poll.
PLAT_SW_TICK    = 0

; A run blanks the display.  See plat_dark.
PLAT_DARK       = 1

; ---------------------------------------------------------------------------
; The screen.  40 by 25, so every figure gets its eight digits behind a label
; written out in full.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DEVICE      = 1
ROW_VERSION     = 1         ; all three share the identity row here
ROW_PROTO       = 1
ROW_PATHS       = 3
ROW_RATE        = 5
ROW_BEST        = 6
ROW_MEAN        = 7
ROW_TOTAL       = 9
ROW_LINES       = 10
ROW_SECS        = 11
ROW_REFUSALS    = 13
ROW_ERRORS      = 14
ROW_STATUS      = 22
ROW_KEYS        = 23        ; and the row under it

; The title bar.  The name hard left, the brand hard right, and the whole row
; reversed behind both.
COL_TITLE       = 1
COL_BRAND       = SCREEN_COLS - 12
COL_DEV         = 1
COL_VER         = 17
COL_PROTO       = 28
COL_LABEL       = 1
COL_KEYS        = 1

; Numbers are eight digits wide, right-aligned, ending at column 29.
NUM_COL         = 22
NUM_WIDTH       = 8

; ---------------------------------------------------------------------------
; Zero page
;
; This ROM owns the machine from reset, so the whole page is free and the map
; is a matter of keeping the four claims apart.  $D0-$D6 is c64_hw.s's scratch
; and $F0-$FF is the RBCP library's, both fixed elsewhere.  The shared code
; takes nine bytes above them and the screen writer two more.
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

ZP_SCR_LO   = $E0           ; plat_row points these at a screen row
ZP_SCR_HI   = $E1

; ---------------------------------------------------------------------------
; The keyboard.  CIA1 port A drives a column low, port B reads rows low.  The
; data direction registers are set at reset by plat_enter.
; ---------------------------------------------------------------------------

KEY_COL_0       = %11111110     ; PA0: RETURN
KEY_COL_1       = %11111101     ; PA1: 3
KEY_COL_2       = %11111011     ; PA2: T
KEY_COL_7       = %01111111     ; PA7: 1, 2

KEY_RETURN_BIT  = %00000010     ; PB1
KEY_1_BIT       = %00000001     ; PB0
KEY_2_BIT       = %00001000     ; PB3
KEY_3_BIT       = %00000001     ; PB0
KEY_T_BIT       = %01000000     ; PB6
