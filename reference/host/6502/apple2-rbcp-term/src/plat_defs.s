; plat_defs.s — what an Apple IIe is, to the RBCP terminal
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen, the keys and the zero page.  Everything else the terminal needs
; is the same on every machine and lives in ../term.

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
; an unbroken command frame with the display on.
PLAT_DARK       = 0

; ---------------------------------------------------------------------------
; Text screen.  Rows are not contiguous.  Row R starts at $0400 +
; (R AND 7) * $80 + (R / 8) * $28.
; ---------------------------------------------------------------------------

SCREEN_BASE     = $0400
SCREEN_COLS     = 40
SCREEN_ROWS     = 24

; ---------------------------------------------------------------------------
; The screen.  Forty columns by twenty-four rows: a title bar, a row naming the
; device, twenty rows of what has been sent, the line being typed, and a status
; bar.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DEVICE      = 1
ROW_TEXT_TOP    = 2
ROW_TEXT_BOT    = 21
ROW_INPUT       = 22
ROW_STATUS      = 23

COL_TITLE       = 1
COL_BRAND       = SCREEN_COLS - 12
COL_DEV         = 1
COL_PROTO       = SCREEN_COLS - 11      ; "RBCP n.n.n" is ten, hard right
COL_LEFT        = SCREEN_COLS - 8

; ---------------------------------------------------------------------------
; Zero page
;
; This ROM owns the machine from reset and never calls the monitor, so the
; whole page is free and the map is a matter of keeping the claims apart.
; $F0-$FF is the RBCP library's, fixed in rbcp_config.s.  The shared code takes
; nine bytes and plat.s the rest.
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
ZP_SRC_LO   = $DD           ; plat_scroll reads a row through these
ZP_SRC_HI   = $DE

; ---------------------------------------------------------------------------
; The keyboard.  One register holds the last key pressed, in ASCII, and holds
; it until the strobe is cleared.  The two keys that are not characters are the
; ones the terminal has to name.
; ---------------------------------------------------------------------------

KEY_LEFT_ARROW  = $08       ; what this machine sends for a rubbed out letter
KEY_DEL_ASCII   = $7F       ; and what the DELETE key on a IIe sends
