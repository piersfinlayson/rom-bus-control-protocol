; led_defs.s — constants for the C64 LED tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The zero page this program claims, the kernal locations it touches and the
; refusals a session can return are all in app_defs.s, shared with the other
; C64 testers.

    .include "app_defs.s"
    .include "disc_glyphs.inc"

; Screen and colour row pointers, built by display.s from the c64_hw.s tables.
ZP_SCR_LO   = ZP_APP0
ZP_SCR_HI   = ZP_APP1
ZP_COL_LO   = ZP_APP2
ZP_COL_HI   = ZP_APP3

; ---------------------------------------------------------------------------
; Limits
;
; Two LEDs, side by side, each big enough to say inside itself what it is
; doing.  That is what a One ROM has — one status LED and one RGB — and a third
; disc of this size does not fit across 40 columns.  A device reporting more is
; shown as its first two and says so on screen rather than truncating quietly.
; ---------------------------------------------------------------------------

MAX_LEDS        = 2

; ---------------------------------------------------------------------------
; The disc.  Thirteen cells across and eleven down, which is round on a C64
; because its pixels are taller than they are wide.  The glyph tables are in
; display.s.
; ---------------------------------------------------------------------------

DISC_W          = 13
DISC_H          = 11
DISC_CELLS      = DISC_W * DISC_H

SC_SPACE        = $20
SC_SOLID        = $A0       ; reversed space

; How lit a disc is drawn.  A C64 cell has one colour and no brightness, so
; below full the disc is a halftone of itself, and at full the colour's
; brighter partner is used where it has one.
; An LED whose mode is Off is a grey lens, because that is what an unlit LED
; looks like sitting on a board.  An LED that is dark for an instant of a blink
; or a breathe is not that: it has gone out, and the way to draw gone out is
; for there to be nothing there.
LVL_BLACK       = 0         ; out, this instant
LVL_DARK        = 1         ; not lit at all: the LED's body, which is grey
LVL_QTR         = 2
LVL_HALF        = 3
LVL_FULL        = 4
LVL_BRIGHT      = 5

; Which of the three character sets the disc is drawn from at each level.
DITH_QUARTER    = 0
DITH_HALF       = 1
DITH_SOLID      = 2

; ---------------------------------------------------------------------------
; Animation
;
; What the LED is doing is drawn as it happens, on the C64's own clock, at the
; period the device reports.  The two are not synchronised and cannot be — the
; point is that both the board and the screen are worth looking at.
; ---------------------------------------------------------------------------

ANIM_STEPS_BLINK   = 2
ANIM_STEPS_BREATHE = 8
ANIM_STEPS_CYCLE   = 8
ANIM_STEPS_BEACON  = 8

ANIM_BEACON_TICKS  = 12     ; 120ms a step, which is a beacon rather than a blink
ANIM_DEFAULT_PERIOD = 20    ; two seconds, where the device reports none

; ---------------------------------------------------------------------------
; CIA2 — timing.  CIA1 carries the keyboard matrix and the kernal's own timer
; and is left as found.
; ---------------------------------------------------------------------------

VIC_RASTER      = $D012

CIA2_TB_LO      = $DD06
CIA2_TB_HI      = $DD07
CIA2_CRB        = $DD0F

; ---------------------------------------------------------------------------
; Screen layout
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DISC        = 2         ; through ROW_DISC + DISC_H - 1
ROW_DISC_TEXT   = 6         ; three lines inside the disc, 6 to 8
ROW_LABEL       = 14        ; the number and type under each disc
ROW_LED_KEYS    = 15        ; and the key that picks it, under that
ROW_MODES       = 17
ROW_MODE_KEYS   = 18        ; the key for each mode, under the mode it sets
ROW_NOTE        = 20
ROW_KEYS1       = 21
ROW_KEYS2       = 22
ROW_KEYS3       = 23
ROW_READ        = 24        ; what the device read back against what was sent

COL_DISC_0      = 4
COL_DISC_1      = 23

; The colour screen: a live preview on the left, the palette on the right.
ROW_PICK        = 3         ; eight entries a column
COL_PICK_A      = 18
COL_PICK_B      = 29
COL_PREVIEW     = 2
ROW_PREVIEW     = 3
ROW_SENDS       = 15
PICK_COUNT      = 16        ; the device's own choice, then fifteen colours

; ---------------------------------------------------------------------------
; Startup refusals.  The session's own are in app_defs.s and this program's
; follow on from them.
; ---------------------------------------------------------------------------

FAIL_NO_LEDS    = SESS_FAIL_COUNT
FAIL_COUNT      = SESS_FAIL_COUNT + 1

; ---------------------------------------------------------------------------
; Status codes.  Passed to display_note in A.  Nothing outside display.s holds
; a string.
; ---------------------------------------------------------------------------

NOTE_BLANK      = $00
NOTE_REFUSED    = $01       ; the device rejected a SET_LED
NOTE_LOST       = $02       ; the device stopped answering
NOTE_NO_COLOUR  = $03       ; this LED's colour is not the host's to set
NOTE_NO_PERIOD  = $04       ; this mode takes no period on this LED
NOTE_NO_HOLD    = $05       ; the device times no holds
NOTE_UNSUPPORTED = $06      ; this LED does not have that mode
NOTE_TRUNCATED  = $07       ; the device reports more LEDs than this shows
NOTE_PARADE     = $08
NOTE_GONE       = $09
NOTE_COUNT      = $0A

; ---------------------------------------------------------------------------
; What the last SET_LED reads back as.  The only check this program can make
; on its own: nothing it reads proves an LED lit, but a device that reports
; back something other than what it was given has been caught in the act.
; ---------------------------------------------------------------------------

READ_NONE       = $00       ; nothing has been set yet
READ_MATCH      = $01
READ_DIFFERS    = $02
READ_REFUSED    = $03
READ_COUNT      = $04

; ---------------------------------------------------------------------------
; Keyboard.  The matrix positions live in the table at the end of led_test.s,
; which c64_keys.s walks.  These are the codes it returns.
; ---------------------------------------------------------------------------

KEY_LED_NEXT    = $01
KEY_LED_PREV    = $02
KEY_COL_NEXT    = $03       ; cursor up and down step the colour in place
KEY_COL_PREV    = $04
KEY_MODE_0      = $05       ; through KEY_MODE_5, in mode order
KEY_MODE_1      = $06
KEY_MODE_2      = $07
KEY_MODE_3      = $08
KEY_MODE_4      = $09
KEY_MODE_5      = $0A
KEY_COLOURS     = $0B       ; the colour screen
KEY_BRIGHT      = $0C
KEY_PERIOD      = $0D
KEY_HOLD        = $0E
KEY_PARADE      = $0F
KEY_ALL         = $10
KEY_QUIT        = $11
KEY_RETURN_CODE = $12
KEY_LED_0       = $13       ; F1 and F3 pick an LED without walking to it
KEY_LED_1       = $14

; ---------------------------------------------------------------------------
; The values the stepping keys walk.  Each is a short list because a C64
; keyboard is a bad way to type a number and a bad number is worth nothing
; here: what these are for is putting the LED somewhere a camera can see.
; ---------------------------------------------------------------------------

BRIGHT_STEPS    = 5         ; device chooses, 25, 50, 75, 100
HOLD_STEPS      = 5         ; until changed, 0.5s, 1s, 2s, 5s
PERIOD_STEPS    = 5         ; the mode's default, 0.5s, 1s, 2s, 5s
