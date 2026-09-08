; plat_defs.s — what a C64 is, to the auxiliary I/O tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen, the keys and the zero page.  Everything else this program needs
; is the same on every machine and lives in ../aux-io.

    .include "c64_defs.s"

; ---------------------------------------------------------------------------
; Registers c64_defs.s does not name
; ---------------------------------------------------------------------------

; The kernal's NMI vector, which only the BASIC socket image has a use for.
NMINV           = $0318

; The display enable bit, and the raster counter plat_dark waits on.  Bit 8 of
; the raster line is bit 7 of VIC_CTRL1.
VIC_CTRL1_DEN   = %00010000
VIC_CTRL1_RST8  = %10000000
VIC_RASTER      = $D012

; The raster line the VIC-II decides the frame at.
VIC_DEN_LINE    = $30

; A VIC-II fetching characters takes the bus off the processor, so every
; exchange with the device happens with the display off.  See plat_dark.
PLAT_DARK       = 1

; About two seconds, measured on a C64.  A pass with nothing held is the
; keyboard matrix scan and little else, which works out at around half a
; millisecond, and the screen is dark for the reread itself.  Lower this to
; notice a pin sooner at the cost of a more frequent flicker.
SCAN_TICKS      = 4000

; ---------------------------------------------------------------------------
; The screen.  Forty columns by twenty-five rows: a title bar, the group and
; its pin count, the rings, the one line of plain English, and two rows of
; keys.  SCREEN_BASE, SCREEN_COLS and SCREEN_ROWS come from c64_defs.s.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DEVICE      = 1         ; what the device calls itself
ROW_GROUP       = 3         ; a blank row under the device row
ROW_COUNT       = 5         ; and another under the heading band
ROW_RINGS       = 7
ROW_RINGS_END   = 21
ROW_NOTE        = 22
ROW_KEYS1       = 23
KEY_LINES       = 2
LEGEND_LINES    = 2

COL_TITLE       = 1
COL_BRAND       = SCREEN_COLS - 12
COL_GROUP       = 2
COL_DEV_VER     = 16        ; the device row: type, version, protocol
COL_DEV_PROTO   = SCREEN_COLS - 11
COL_OF          = 31        ; "n OF m" at the right of the group row

; The all-pins screen: where the last group may start, where the device's own
; name goes, and how the pins are spread across a row.
ROW_ALL_END     = 20
COL_ALL         = 6
ALL_PER_ROW     = 16

; The reset screen's two columns.
COL_R_VAL       = 15        ; clear of "SELECTED PIN" on the widest row
COL_R_PIN       = 25

; ---------------------------------------------------------------------------
; Pins.  A power of two so that a pin's index into the tables is a shift.
; ---------------------------------------------------------------------------

MAX_PINS        = 64
MAX_PINS_SHIFT  = 6

; ---------------------------------------------------------------------------
; Zero page
;
; This ROM owns the machine from reset, so the whole page is free and the map
; is a matter of keeping the four claims apart.  $D0-$D6 is c64_hw.s's scratch
; and $F0-$FF is the RBCP library's, both fixed elsewhere.  The shared code
; takes nine bytes above them and the screen writer four more.
;
; ZP_PTR_LO/HI are c64_hw.s's, at $D0-$D1, and are the pointer display.s walks
; a string with.  Nothing here calls the c64_hw.s routine that wants them for
; itself, so the two claims cannot collide.
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
ZP_COL_LO   = $E2           ; and these at the colour row beside it
ZP_COL_HI   = $E3
