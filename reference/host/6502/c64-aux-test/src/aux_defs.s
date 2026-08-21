; aux_defs.s — constants for the C64 auxiliary I/O tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The zero page this program claims, the kernal locations it touches and the
; refusals a session can return are all in app_defs.s, shared with the other
; C64 testers.

    .include "app_defs.s"

; Screen and colour row pointers, built by display.s from the c64_hw.s tables.
ZP_SCR_LO   = ZP_APP0
ZP_SCR_HI   = ZP_APP1
ZP_COL_LO   = ZP_APP2
ZP_COL_HI   = ZP_APP3

; ---------------------------------------------------------------------------
; Ring glyphs, verified against chargen-901225-01.bin
; ---------------------------------------------------------------------------

SC_TL           = $55       ; rounded top left
SC_TR           = $49       ; rounded top right
SC_BL           = $4A       ; rounded bottom left
SC_BR           = $4B       ; rounded bottom right
SC_HORIZ        = $40
SC_VERT         = $5D
SC_FILL         = $A0       ; reversed space
SC_HOLLOW       = $20
SC_DOT_FULL     = $51       ; filled circle, the one character tier
SC_DOT_EMPTY    = $57       ; hollow circle

; ---------------------------------------------------------------------------
; Ring tiers.  The tier is chosen from a group's drivable pin count so that
; every group fills the screen with the largest ring that fits.
;
; Rows per bank is the ring height plus the pin number underneath it.  Ring
; rows run from ROW_RINGS to ROW_RINGS_END, which is what bounds each tier's
; bank count and so its pin capacity.
; ---------------------------------------------------------------------------

TIER_BIG        = 0         ; 7x5, 4 across, 2 banks   -> 8 pins
TIER_MID        = 1         ; 5x3, 5 across, 4 banks   -> 20 pins
TIER_SMALL      = 2         ; 3x3, 9 across, 4 banks   -> 36 pins
TIER_DOT        = 3         ; 1x1, 16 across, 4 banks  -> 64 pins

; ---------------------------------------------------------------------------
; Limits.  A device reporting more than these is shown up to the limit and
; told about on the status row — never silently truncated.
;
; Four groups is one more than any One ROM board exposes.  Sixty-four pins is
; what the smallest tier that still reads on video can show: sixteen across,
; four banks.
; ---------------------------------------------------------------------------

MAX_GROUPS      = 4
MAX_PINS        = 64        ; per group, and the stride of the pin tables

; ---------------------------------------------------------------------------
; How long the reset pin is held low before it is released.  In units of 10ms,
; as the protocol counts holds, and well inside the 2.55 seconds that argument
; can express.
;
; The reset screen shows this as milliseconds, and works it out with an eight
; bit multiply, so the value has to stay small enough for the answer to fit.
; ---------------------------------------------------------------------------

RESET_HOLD      = 20        ; 200ms
.assert RESET_HOLD <= 25, error, "RESET_HOLD in ms must fit in a byte"

; ---------------------------------------------------------------------------
; Screen layout
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_GROUP       = 2         ; group name, and "n OF m" at the right
ROW_COUNT       = 3         ; "n OF m PINS CAN BE DRIVEN"
ROW_RINGS       = 5
ROW_RINGS_END   = 20
ROW_NOTE        = 22        ; the one plain-English line about the cursor pin
ROW_KEYS1       = 23
ROW_KEYS2       = 24

COL_GROUP       = 2

; ---------------------------------------------------------------------------
; Status codes.  Passed to display_note in A.  Nothing outside display.s holds
; a string.
; ---------------------------------------------------------------------------

NOTE_BLANK      = $00
NOTE_NO_DRIVE   = $01       ; every pin in this group is in use by the ROM
NOTE_BLINKING   = $02
NOTE_TEST_LOW   = $03
NOTE_TEST_HIGH  = $04
NOTE_TEST_REL   = $05
NOTE_TEST_DONE  = $06       ; followed by what moved with it
NOTE_TEST_NONE  = $07
NOTE_REFUSED    = $08       ; the device rejected a SET_AUX
NOTE_LOST       = $09       ; the device stopped answering
NOTE_NOT_DRIVABLE = $0A
NOTE_TRUNCATED  = $0B       ; the device reports more than this program shows
NOTE_GONE       = $0C       ; a terminal command has been sent
NOTE_COUNT      = $0D

; ---------------------------------------------------------------------------
; Startup refusals.  The session's own are in app_defs.s and this program's
; follow on from them.  Shown in place of everything else.
; ---------------------------------------------------------------------------

FAIL_NO_AUX     = SESS_FAIL_COUNT
FAIL_COUNT      = SESS_FAIL_COUNT + 1

; ---------------------------------------------------------------------------
; Keyboard.  The matrix positions live in the table at the end of aux_test.s,
; which c64_keys.s walks.  These are the codes it returns.
; ---------------------------------------------------------------------------

KEY_PIN_NEXT    = $01
KEY_PIN_PREV    = $02
KEY_GRP_NEXT    = $03
KEY_GRP_PREV    = $04
KEY_LOW_CODE    = $05
KEY_HIGH_CODE   = $06
KEY_REL_CODE    = $07
KEY_BLINK_CODE  = $08
KEY_TEST_CODE   = $09
KEY_ALL_CODE    = $0A
KEY_RESET_CODE  = $0B
KEY_QUIT_CODE   = $0C
KEY_RETURN_CODE = $0D

; ---------------------------------------------------------------------------
; Pin table encoding
;
; pin_flags holds what GET_AUX_PIN_INFO reported.  pin_state holds the level
; and driven bytes folded into two bits, because that is all the ring needs.
; ---------------------------------------------------------------------------

PIN_LEVEL_BIT   = $01
PIN_DRIVEN_BIT  = $02
