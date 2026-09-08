; plat_defs.s — what an Apple IIe is, to the auxiliary I/O tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen, the keys and the zero page.  Everything else this program needs
; is the same on every machine and lives in ../aux-io.

    .include "../rbcp/rbcp_defs.s"

; ---------------------------------------------------------------------------
; Soft switches
; ---------------------------------------------------------------------------

KBD             = $C000     ; bit 7 set = key waiting, bits 0-6 = ASCII
CLR80COL        = $C00C     ; 40 columns
CLRALTCHAR      = $C00E     ; primary character set, upper case and inverse
KBDSTRB         = $C010     ; any access clears the keyboard strobe
TXTSET          = $C051     ; text rather than graphics
MIXCLR          = $C052     ; whole screen, not split
TXTPAGE1        = $C054     ; display page 1 at $0400
LORES           = $C056     ; low resolution rather than hi-res

; The video circuitry and the 6502 take alternate halves of every cycle, so
; fetching a row of characters costs the processor nothing and the device sees
; an unbroken command frame with the display on.  There is nothing for
; blanking the screen to fix, so plat_dark and plat_light do nothing and the
; group is reread every pass through the loop.
PLAT_DARK       = 0

SCAN_TICKS      = 1         ; nothing to blank, so reread every pass

; ---------------------------------------------------------------------------
; Text screen.  Rows are not contiguous.  Row R starts at $0400 +
; (R AND 7) * $80 + (R / 8) * $28.
; ---------------------------------------------------------------------------

SCREEN_BASE     = $0400
SCREEN_COLS     = 40
SCREEN_ROWS     = 24

; ---------------------------------------------------------------------------
; The screen.  A title bar, the group and its pin count, the rings, the one
; line of plain English, and two rows of keys.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DEVICE      = 1         ; what the device calls itself
ROW_GROUP       = 3         ; a blank row under the device row
ROW_COUNT       = 5         ; and another under the heading band
ROW_RINGS       = 7
ROW_RINGS_END   = 20
ROW_NOTE        = 21
ROW_KEYS1       = 22
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
ROW_ALL_END     = 19
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
; This ROM owns the machine from reset and never calls the monitor, so the
; whole page is free and the map is a matter of keeping the claims apart.
; $F0-$FF is the RBCP library's, fixed in rbcp_config.s.
; ---------------------------------------------------------------------------

ZP_APP0     = $DF
ZP_APP1     = $E0
ZP_APP2     = $E1
ZP_APP3     = $E2
ZP_APP4     = $E3
ZP_APP5     = $E4
ZP_APP6     = $E5
ZP_APP7     = $E6
ZP_APP8     = $E7

ZP_PTR_LO   = $E8           ; display.s points these at a string
ZP_PTR_HI   = $E9
ZP_TMP0     = $EA           ; plat.s's own scratch
ZP_TMP1     = $EB
ZP_TMP2     = $EC
ZP_TMP3     = $ED
ZP_SCR_LO   = $EE           ; plat_row points these at a screen row
ZP_SCR_HI   = $EF

; ---------------------------------------------------------------------------
; The keyboard.  One register holds the last key pressed, in ASCII, and holds
; it until the strobe is cleared.
; ---------------------------------------------------------------------------

KEY_LEFT_ARROW  = $08
KEY_RIGHT_ARROW = $15
KEY_UP_ARROW    = $0B
KEY_DOWN_ARROW  = $0A
