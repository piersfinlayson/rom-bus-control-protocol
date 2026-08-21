; apple2_defs.s — Apple II hardware register and memory map constants
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; ZP addresses must match rbcp_defs.s layout.

.include "../rbcp/rbcp_defs.s"

; ---------------------------------------------------------------------------
; Soft switches
;
; CLR80COL and CLRALTCHAR are IIe and later.  On a II or II+ the addresses
; decode to nothing and the writes are ignored.
; ---------------------------------------------------------------------------

KBD             = $C000     ; bit 7 set = key waiting, bits 0-6 = ASCII
CLR80COL        = $C00C     ; 40 columns
CLRALTCHAR      = $C00E     ; primary character set
KBDSTRB         = $C010     ; any access clears the keyboard strobe
TXTSET          = $C051     ; text rather than graphics
MIXCLR          = $C052     ; whole screen, not split
TXTPAGE1        = $C054     ; display page 1 at $0400
LORES           = $C056     ; low resolution rather than hi-res

; ---------------------------------------------------------------------------
; Autostart ROM power-up flags
;
; The autostart ROM warm starts when $03F4 equals $03F3 EOR $A5, and cold
; starts otherwise.  Zeroing both makes the comparison fail, so the image the
; user picks cold starts and boots a disk.
; ---------------------------------------------------------------------------

PWRUP_VECT_CK   = $03F3
PWRUP_BYTE      = $03F4

RESET_VECTOR    = $FFFC

; ---------------------------------------------------------------------------
; Text screen
;
; Rows are not contiguous.  Row R starts at $0400 + (R AND 7) * $80 +
; (R / 8) * $28.
; ---------------------------------------------------------------------------

SCREEN_BASE     = $0400
SCREEN_COLS     = 40
SCREEN_ROWS     = 24

; ---------------------------------------------------------------------------
; Character codes, as the display hardware wants them.  Normal video is ASCII
; with bit 7 set.  Inverse video is the same character with bits 7 and 6
; clear, so AND #$3F inverts and ORA #$80 puts it back.
; ---------------------------------------------------------------------------

CHAR_SPACE      = $A0
CHAR_GT         = $BE       ; '>'

; ---------------------------------------------------------------------------
; Keys, as read from KBD with bit 7 still set.  A II and II+ keyboard has no
; up or down arrow, so left and right move the selection as well.
; ---------------------------------------------------------------------------

KEY_NONE        = $00
KEY_RETURN      = $8D
KEY_LEFT        = $88
KEY_RIGHT       = $95
KEY_UP          = $8B
KEY_DOWN        = $8A
KEY_SPACE       = $A0
KEY_1           = $B1
KEY_9           = $B9

; ---------------------------------------------------------------------------
; Zero-page addresses — shared with rbcp_defs.s, which takes $F0-$FF.
; ---------------------------------------------------------------------------

ZP_PTR_LO  = $E8
ZP_PTR_HI  = $E9
ZP_TMP0    = $EA
ZP_TMP1    = $EB
ZP_TMP2    = $EC
ZP_TMP3    = $ED
ZP_TMP4    = $EE
