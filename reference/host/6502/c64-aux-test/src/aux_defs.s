; aux_defs.s — constants for the C64 auxiliary I/O tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Zero page
; ---------
; Three claims: the RBCP library at $F0-$FF, the c64_hw.s scratch at $D0-$D6,
; and this program's own at $D7-$DF.  $D0-$FF is saved whole on entry and
; restored on exit, for the reasons set out at the top of aux_test.s.
;
; That is safe only while nothing else is running in it, which means interrupts
; masked and no kernal or BASIC call in flight.  The screen editor is broken for
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

; Screen and colour row pointers, built by display.s from the c64_hw.s tables.
ZP_SCR_LO   = ZP_APP0
ZP_SCR_HI   = ZP_APP1
ZP_COL_LO   = ZP_APP2
ZP_COL_HI   = ZP_APP3

; The saved block: $D0 to $FF inclusive.
ZP_SAVE_BASE  = $D0
ZP_SAVE_COUNT = $30

; ---------------------------------------------------------------------------
; Kernal and BASIC locations this program relies on
; ---------------------------------------------------------------------------

NMINV           = $0318     ; NMI vector, kernal jmp ($0318) target
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

CIA2_CRA_RUN    = %00000001     ; continuous, count phi2
CIA2_CRB_RUN    = %01000001     ; continuous, count Timer A underflows

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
TIER_COUNT      = 4

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
NOTE_PIN        = $01       ; the cursor pin, described from the pin tables
NOTE_NO_DRIVE   = $02       ; every pin in this group is in use by the ROM
NOTE_BLINKING   = $03
NOTE_TEST_LOW   = $04
NOTE_TEST_HIGH  = $05
NOTE_TEST_REL   = $06
NOTE_TEST_DONE  = $07       ; followed by what moved with it
NOTE_TEST_NONE  = $08
NOTE_REFUSED    = $09       ; the device rejected a SET_AUX
NOTE_LOST       = $0A       ; the device stopped answering
NOTE_NOT_DRIVABLE = $0B
NOTE_TRUNCATED  = $0C       ; the device reports more than this program shows
NOTE_GONE       = $0D       ; a terminal command has been sent
NOTE_COUNT      = $0E

; ---------------------------------------------------------------------------
; Startup refusals.  Shown in place of everything else.
; ---------------------------------------------------------------------------

FAIL_NO_DEVICE  = $00
FAIL_ENTER      = $01
FAIL_VERSION    = $02
FAIL_NO_AUX     = $03
FAIL_CLASH      = $04       ; the image already holds a configured value
FAIL_RAM_SLOTS  = $05       ; fewer than two RAM slots
FAIL_NO_CLEAN   = $06       ; no flash slot matches, so there is no clean exit
FAIL_COUNT      = $07

; ROM type of the image being served, from the spec's ROM Types table.  Only
; flash slots reporting this are candidates for the clean exit, or for the
; image the reset switches to.
ROM_TYPE_2364   = $02

; ---------------------------------------------------------------------------
; Keyboard.  $DC00 drives a column low, $DC01 reads rows low.  The kernal has
; already set CIA1 DDRA to output and DDRB to input, so neither is touched.
; ---------------------------------------------------------------------------

KEY_COL_0       = %11111110     ; PB2 CRSR right, PB7 CRSR down
KEY_COL_1       = %11111101     ; PB2 A, PB4 Z, PB7 left shift
KEY_COL_2       = %11111011     ; PB1 R, PB6 T
KEY_COL_3       = %11110111     ; PB4 B, PB5 H
KEY_COL_5       = %11011111     ; PB2 L
KEY_COL_6       = %10111111     ; PB4 right shift
KEY_COL_7       = %01111111     ; PB6 Q

KEY_CRSR_RT_BIT = %00000100     ; col 0
KEY_CRSR_DN_BIT = %10000000     ; col 0
KEY_A_BIT       = %00000100     ; col 1
KEY_Z_BIT       = %00010000     ; col 1
KEY_LSHIFT_BIT  = %10000000     ; col 1
KEY_R_BIT       = %00000010     ; col 2
KEY_T_BIT       = %01000000     ; col 2
KEY_B_BIT       = %00010000     ; col 3
KEY_H_BIT       = %00100000     ; col 3
KEY_L_BIT       = %00000100     ; col 5
KEY_RSHIFT_BIT  = %00010000     ; col 6
KEY_Q_BIT       = %01000000     ; col 7
KEY_RETURN_BIT  = %00000010     ; col 0

; Key codes returned by the scanner
KEY_NONE_CODE   = $00
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

; ---------------------------------------------------------------------------
; Pin table encoding
;
; pin_flags holds what GET_AUX_PIN_INFO reported.  pin_state holds the level
; and driven bytes folded into two bits, because that is all the ring needs.
; ---------------------------------------------------------------------------

PIN_LEVEL_BIT   = $01
PIN_DRIVEN_BIT  = $02
