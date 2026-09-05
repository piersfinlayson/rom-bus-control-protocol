; plat_defs.s — what the C64 is, to the reliability meter
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen, the key and the one thing this machine varies.  Everything else
; the meter needs is the same on every machine and lives in ../stress.

    .include "c64_defs.s"

; ---------------------------------------------------------------------------
; What a C64 varies
;
; The VIC-II takes cycles off the processor.  Every eighth raster line in the
; display window is a badline, where it stops the 6510 for 40 cycles or more to
; fetch a row of characters, and sprites and refresh take more on top.  Turning
; the display off stops all of it, and the meter counts the two cases apart
; because they are not the same machine as far as the device is concerned.
;
; Clearing bit 4 of $D011 is what stops it.  Nothing else here writes $D011.
; ---------------------------------------------------------------------------

PLAT_VARY       = 1
VIC_CTRL1_DEN   = %00010000

KEY_VARY        = $01

; ---------------------------------------------------------------------------
; The screen.  40 by 25, so every count gets its full ten digits and the
; failure record gets a row each.  A command's own two counts are ten digits
; apiece, and putting the errors last on the row lines them up under the
; per-setting errors below.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DEV         = 2
ROW_VER         = 3
ROW_PROTO       = 4
ROW_PIPE        = 5
ROW_BIG         = 7
ROW_RAW         = 9
ROW_HEAD        = 11
ROW_FIRST       = 12        ; through ROW_FIRST + TEST_COUNT - 1
ROW_VARY        = 17        ; and the row under it
ROW_NOTE        = 20
ROW_REC_SENT    = 21
ROW_REC_GOT     = 22
ROW_KEYS        = 24

COL_NAME        = 1
COL_SENT        = 14
COL_BAD         = 30

; The headline carries a figure for each setting of the display, since a
; figure averaging the two says nothing about the machine.  Two ten digit
; ratios behind their labels, with two spaces between the pair, is 39
; characters, which starting at column 1 ends in the last column.
COL_BIG_ON_LBL  = 1         ; "ON 1 IN"
COL_BIG_ON      = 9
COL_BIG_OFF_LBL = 21        ; "OFF 1 IN"
COL_BIG_OFF     = 30

; Sent and errors are both ten digit counts, and the two with their labels take
; the row as far as column 33.
COL_RAW_SENT_LBL = 1        ; "SENT", 1 to 4
COL_RAW_SENT     = 6        ; 6 to 15
COL_RAW_BAD_LBL  = 20       ; "ERR", 20 to 22
COL_RAW_BAD      = 24       ; 24 to 33

; Lost goes on the row under it, split by the setting the loss happened at,
; because a command the device never answered with the screen off says
; something a whole-run total does not.  Both counts are ten digits, and they
; sit in the same two columns as the per-setting counts further down the
; screen, so the row ends at column 39 like those do.
COL_RAW_LOST_LBL = 19       ; "LOST", 19 to 22
COL_RAW_LOST     = 24       ; 24 to 33, under the error count above it

; A setting's row carries what went out at it and what came back wrong.  The
; ratio is the band's job, and repeating it here would leave no room for the
; count that tells a setting with nothing wrong from one with nothing tried.
; Both counts are ten digits, so the row is the marker, ON or OFF, and the two
; labelled numbers, and that reaches column 39 exactly.
COL_VARY_SENTLBL = 6        ; "SENT", 6 to 9
COL_VARY_SENT    = 11       ; 11 to 20
COL_VARY_BADLBL  = 26       ; "ERR", 26 to 28
COL_VARY_BAD     = 30       ; 30 to 39

; ---------------------------------------------------------------------------
; Zero page the meter's screen writer owns.  $D0-$D6 is c64_hw.s's, $F0-$FF is
; the RBCP library's, and nothing else is running: this ROM owns the machine
; from reset and never calls the kernal.
; ---------------------------------------------------------------------------

ZP_SCR_LO   = $D7
ZP_SCR_HI   = $D8
ZP_COL_LO   = $D9
ZP_COL_HI   = $DA

; ---------------------------------------------------------------------------
; The S key: column 1, row 5 of the matrix.
; ---------------------------------------------------------------------------

KEY_S_COL       = %11111101
KEY_S_ROW_BIT   = %00100000

; A 40 column screen holds sent and wrong on one row, and lost on the next.
ROW_RAW_BAD      = ROW_RAW
ROW_RAW_LOST     = ROW_RAW + 1
