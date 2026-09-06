; plat_defs.s — what the C64 is, to the RBCP terminal
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen, the keys and the zero page.  Everything else the terminal needs
; is the same on every machine and lives in ../term.

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

; A line goes out with the display off.  See plat_dark.
PLAT_DARK       = 1

; ---------------------------------------------------------------------------
; The screen.  Forty columns by twenty-five rows: a title bar, a row naming the
; device, twenty-one rows of what has been sent, the line being typed, and a
; status bar.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DEVICE      = 1
ROW_TEXT_TOP    = 2
ROW_TEXT_BOT    = 22
ROW_INPUT       = 23
ROW_STATUS      = 24

COL_TITLE       = 1
COL_BRAND       = SCREEN_COLS - 12
COL_DEV         = 1
COL_PROTO       = SCREEN_COLS - 11      ; "RBCP n.n.n" is ten, hard right
COL_LEFT        = SCREEN_COLS - 8

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
ZP_SRC_LO   = $E2           ; plat_scroll reads a row through these
ZP_SRC_HI   = $E3

; ---------------------------------------------------------------------------
; The keyboard.  CIA1 port A drives a column low, port B reads rows low, and a
; clear bit means the key is down.  The data direction registers are set at
; reset by c64_hw_init.
;
; Both shift keys are read on their own rather than out of the table, so that a
; shift held with a letter cannot match as a key of its own.
; ---------------------------------------------------------------------------

KEY_LSHIFT_COL  = %11111101     ; PA1, PB7
KEY_LSHIFT_BIT  = %10000000
KEY_RSHIFT_COL  = %10111111     ; PA6, PB4
KEY_RSHIFT_BIT  = %00010000
