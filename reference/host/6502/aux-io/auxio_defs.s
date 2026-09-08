; auxio_defs.s — what every machine's auxiliary I/O tester shares
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The tester is one program built for several machines.  This file and the
; five beside it are the same on all of them.  What differs is the screen, the
; keys, the glyphs a ring is drawn from and the zero page, and those come from
; the application's own plat_defs.s and plat.s.

    .include "plat_defs.s"

; ---------------------------------------------------------------------------
; The platform interface
;
; In plat_defs.s, as constants:
;
;   SCREEN_COLS, SCREEN_ROWS  The screen.  Under 32 columns gets the narrow
;                             layout.
;   ROW_*, COL_*              Where each part of the display goes.
;   MAX_PINS                  The most pins of one group this screen can show,
;                             and the stride of the pin tables.
;   PLAT_DARK                 1 if the machine's video steals cycles from the
;                             processor and plat_dark stops it, 0 if not.
;   ZP_APP0-8, ZP_PTR_LO/HI   The zero page the shared code walks tables and
;                             strings with.
;
; In plat.s, as routines:
;
;   plat_init         The display, from RAM, before anything is asked of the
;                     device.
;   plat_cls          A blank screen.
;   plat_row          A = row.  Points the screen writer at it.
;   plat_put          A = ASCII, Y = column, X = a COLR_ role.  Y comes back
;                     untouched.
;   plat_glyph        A = a GLY_ index, Y = column, X = a COLR_ role.  Y comes
;                     back untouched.  The machine decides what each pairing
;                     looks like, which is how a screen with no colour still
;                     says who owns a pin.
;   plat_fill_row     A = ASCII, X = a COLR_ role.  Fills the selected row.
;   plat_reverse      A = row, X = column, Y = length.  Reverses that run.
;   plat_key          A key code, or KEY_NONE_CODE.  Once per press, so a
;                     held key does not arrive twice.
;   plat_dark         Stops the video stealing cycles, and plat_light puts it
;   plat_light        back.  The pair nests, and neither touches a register or
;                     a flag, so either can sit between a call and the branch
;                     on its carry.  Both are present whatever PLAT_DARK says.
;
; and the tier tables tier_w, tier_h, tier_pitch, tier_perrow, tier_bankh and
; tier_cap, which are the ring sizes this screen has room for.
;
; and auxio_run, which the machine's reset entry jumps to once the code is in
; RAM.  It does not return.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; Colour roles.  The program asks for a role and the machine decides what it
; looks like.  A screen with no colour varies the glyph instead, which is why
; the role goes to plat_glyph as well as plat_put.
;
; Both machines with colour draw them red, white and blue: red is what the host
; is driving, white is free, blue belongs to the ROM.  Saturated ones, because
; on a black screen a pale colour reads as grey, and they have to hold up at
; the single character the smallest ring tier draws.
; ---------------------------------------------------------------------------

COLR_THEIRS     = 0         ; the ROM is using this pin
COLR_FREE       = 1         ; nobody is driving it
COLR_OURS       = 2         ; the host is driving it
COLR_TEXT       = 3
COLR_TITLE      = 4         ; the title bar, reversed where there is reverse

; ---------------------------------------------------------------------------
; Ring glyphs.  An index, not a character: a machine with colour draws all
; three roles the same and lets the colour say which, and a machine without
; draws a different character for each.
; ---------------------------------------------------------------------------

GLY_TL          = 0
GLY_TR          = 1
GLY_BL          = 2
GLY_BR          = 3
GLY_HORIZ       = 4
GLY_VERT        = 5
GLY_HIGH        = 6         ; inside a ring whose level is high
GLY_LOW         = 7         ; inside a ring whose level is low
GLY_DOT_HIGH    = 8         ; the whole ring, at the one character tier
GLY_DOT_LOW     = 9

; ---------------------------------------------------------------------------
; Ring tiers.  The tier is chosen from a group's drivable pin count so that
; every group fills the screen with the largest ring that fits.  What each one
; measures is the machine's, in its tier tables.
; ---------------------------------------------------------------------------

TIER_BIG        = 0
TIER_MID        = 1
TIER_SMALL      = 2
TIER_DOT        = 3

; ---------------------------------------------------------------------------
; Limits.  A device reporting more than these is shown up to the limit and
; told about on the status row — never silently truncated.
;
; Four groups is one more than any One ROM board exposes.  MAX_PINS is the
; machine's, because it is what the smallest tier that still reads on that
; screen can show.
; ---------------------------------------------------------------------------

MAX_GROUPS      = 4

; ---------------------------------------------------------------------------
; Group types this program treats specially.
;
; An image-select group is a number the host reads as one, so its pins are
; drawn right to left and named by letter.  X pins are drawn right to left too
; and numbered from one, which is what the pads are called.  Every other type
; is drawn left to right and numbered from zero.
; ---------------------------------------------------------------------------

RBCP_AUX_TYPE_IMGSEL = $80
RBCP_AUX_TYPE_XPADS  = $81

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
; The rescan tick, in passes through the main loop, which the machine sets
; because a pass is however long its keyboard takes to say nothing.
;
; The loop rereads the current group with one GET_AUX_PIN_INFO per pin, and on
; a machine whose display has to go off for the exchange that is the whole
; screen dark for the length of it.  Anything pressed rereads at once, so the
; tick is only how long an unattended screen takes to notice a pin that moved
; on its own.
;
; It is sixteen bits because a pass with nothing held is a few hundred cycles,
; so a byte of them is a fiftieth of a second and a screen that goes dark that
; often is a screen that flickers.
; ---------------------------------------------------------------------------

.assert SCAN_TICKS > 0, error, "the rescan tick has to be at least one pass"

; ---------------------------------------------------------------------------
; The reset screen.  Its title goes where every other page's heading goes and
; is banded the same way, and the rest is laid out from ROW_RINGS down, so a
; machine only has to say where the rings start and stop.
; ---------------------------------------------------------------------------

ROW_R_PIN       = ROW_RINGS
ROW_R_HOLD      = ROW_RINGS + 2
ROW_R_IMAGE     = ROW_RINGS + 4
ROW_R_ENDS      = ROW_RINGS + 7

.assert ROW_R_ENDS <= ROW_RINGS_END, error, "the reset screen does not fit"

; ---------------------------------------------------------------------------
; The rows below the rings.  How many of each the layout wants is settled by
; the layout, so a machine that declares the wrong number is caught here rather
; than by a line of text running off the bottom of the screen.
; ---------------------------------------------------------------------------

.if SCREEN_COLS >= 32
.assert KEY_LINES = 2, error, "the wide layout has two key rows"
.assert LEGEND_LINES = 2, error, "the wide layout has two legend rows"
.else
.assert KEY_LINES = 3, error, "the narrow layout has three key rows"
.assert LEGEND_LINES = 4, error, "the narrow layout has four legend rows"
.endif

.assert ROW_KEYS1 + KEY_LINES <= SCREEN_ROWS, error, "the key rows do not fit"
.assert ROW_KEYS1 + LEGEND_LINES <= SCREEN_ROWS, error, "the legend does not fit"
.assert ROW_NOTE < ROW_KEYS1, error, "the note row is not above the key rows"

; ---------------------------------------------------------------------------
; Status codes.  Passed to display_note in A.  Nothing outside display.s holds
; a string.
; ---------------------------------------------------------------------------

NOTE_BLANK      = $00
NOTE_NO_DRIVE   = $01       ; every pin in this group is in use by the ROM
NOTE_BLINKING   = $02
NOTE_REFUSED    = $03       ; the device rejected a SET_AUX
NOTE_LOST       = $04       ; the device stopped answering
NOTE_NOT_DRIVABLE = $05
NOTE_TRUNCATED  = $06       ; the device reports more than this program shows
NOTE_GONE       = $07       ; a terminal command has been sent
NOTE_NO_IMAGE   = $08       ; no flash slot holds an image of this ROM's type
NOTE_NO_SWITCH  = $09       ; the device has nowhere to load one into
NOTE_COUNT      = $0A

; ---------------------------------------------------------------------------
; Startup refusals.  Shown in place of everything else.
; ---------------------------------------------------------------------------

FAIL_NO_DEVICE  = $00       ; nothing answered the knock
FAIL_ENTER      = $01       ; it answered and refused ENTER_CMD_RESP
FAIL_VERSION    = $02       ; it speaks a protocol version this does not
FAIL_NO_AUX     = $03       ; it has no pins
FAIL_COUNT      = $04

; ---------------------------------------------------------------------------
; Keys.  These are the codes plat_key returns, whatever the machine reads to
; arrive at them.
;
; The four cursor keys walk the grid of pins on a page.  The two page keys move
; between pages, of which there is one per group of pins and one more holding
; every pin at once.
; ---------------------------------------------------------------------------

KEY_NONE_CODE   = $00
KEY_PIN_NEXT    = $01
KEY_PIN_PREV    = $02
KEY_ROW_NEXT    = $03
KEY_ROW_PREV    = $04
KEY_LOW_CODE    = $05
KEY_HIGH_CODE   = $06
KEY_REL_CODE    = $07
KEY_BLINK_CODE  = $08
KEY_PAGE_NEXT   = $09
KEY_PAGE_PREV   = $0A
KEY_RESET_CODE  = $0B
KEY_RETURN_CODE = $0D

; ---------------------------------------------------------------------------
; Pin table encoding
;
; pin_flags holds what GET_AUX_PIN_INFO reported.  pin_state holds the level
; and driven bytes folded into two bits, because that is all the ring needs.
; ---------------------------------------------------------------------------

PIN_LEVEL_BIT   = $01
PIN_DRIVEN_BIT  = $02
