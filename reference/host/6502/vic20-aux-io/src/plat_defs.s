; plat_defs.s — what a VIC-20 is, to the auxiliary I/O tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen, the keys and the zero page.  Everything else this program needs
; is the same on every machine and lives in ../aux-io.

    .include "../rbcp/rbcp_defs.s"

; ---------------------------------------------------------------------------
; VIC chip ($9000-$900F)
; ---------------------------------------------------------------------------

VIC_H_CENTER    = $9000
VIC_V_CENTER    = $9001
VIC_COL_COUNT   = $9002
VIC_ROW_COUNT   = $9003
VIC_RASTER      = $9004
VIC_MEM         = $9005
VIC_LIGHTPEN_H  = $9006
VIC_LIGHTPEN_V  = $9007
VIC_PADDLE_X    = $9008
VIC_PADDLE_Y    = $9009
VIC_OSC1        = $900A
VIC_OSC2        = $900B
VIC_OSC3        = $900C
VIC_NOISE       = $900D
VIC_AUX_VOL     = $900E
VIC_COLOUR      = $900F

VIC_COL_COUNT_VAL   = $96   ; 22 columns, VA9 set, so the screen is at $1E00
VIC_ROW_COUNT_VAL   = $2E   ; 23 rows, 8 pixel characters
VIC_MEM_VAL         = $F0   ; video matrix $1E00, character ROM at $8000
VIC_COLOUR_VAL      = $08   ; black background, black border, normal video

; ---------------------------------------------------------------------------
; VIA1 ($9110-$911F).  Nothing here uses its timers.  The IER is written at
; entry, so that RESTORE raises nothing.
; ---------------------------------------------------------------------------

VIA1_IER        = $911E

; ---------------------------------------------------------------------------
; VIA2 — the keyboard matrix ($9120-$912F)
; ---------------------------------------------------------------------------

VIA2_PRB        = $9120     ; port B: column select, output, active low
VIA2_PRA        = $9121     ; port A: row read, input, active low
VIA2_DDRB       = $9122
VIA2_DDRA       = $9123
VIA2_IER        = $912E
VIA2_DDRB_VAL   = $FF
VIA2_DDRA_VAL   = $00

; Writing this to an IER clears every enable it has.
VIA_IER_NONE    = $7F

; ---------------------------------------------------------------------------
; The picture
;
; PAL and NTSC put the picture in different places, and nothing else in this
; program differs between the two.
; ---------------------------------------------------------------------------

.if .defined(PAL)
VIC_H_CENTER_VAL    = $0C
VIC_V_CENTER_VAL    = $26
.elseif .defined(NTSC)
VIC_H_CENTER_VAL    = $05
VIC_V_CENTER_VAL    = $19
.else
.error "Define PAL or NTSC (pass -DPAL=1 or -DNTSC=1 to ca65)"
.endif

; The VIC-I and the 6502 take alternate halves of every cycle, so fetching a
; row of characters costs the processor nothing and takes the bus off nobody.
; There is nothing for blanking the screen to fix.
PLAT_DARK       = 0

SCAN_TICKS      = 1         ; nothing to blank, so reread every pass

; ---------------------------------------------------------------------------
; Screen and colour RAM.  Colour RAM sits a fixed $7800 above the screen, so
; plat_row builds the colour pointer from the screen one rather than from a
; second table.
; ---------------------------------------------------------------------------

SCREEN_BASE     = $1E00
COLOUR_RAM      = $9600
COLOUR_OFFSET   = >(COLOUR_RAM - SCREEN_BASE)
SCREEN_COLS     = 22
SCREEN_ROWS     = 23

; The eight the VIC-I can draw a character in.  Three of them carry the roles:
; red for a pin this machine is driving, white for one nobody is, and blue —
; the dimmest of the eight — for one the ROM is using and we may not touch.
COL_BLACK       = 0
COL_WHITE       = 1
COL_RED         = 2
COL_GREEN       = 5
COL_BLUE        = 6
COL_CYAN        = 3

; ---------------------------------------------------------------------------
; The screen.  Twenty-two columns by twenty-three rows: a title bar, the group
; and its pin count, the rings, the one line of plain English, and the keys.
;
; Three key rows rather than the two a forty column screen needs, and four
; legend rows on the all-pins screen where forty columns takes two.  The legend
; is the taller of the pair, so it is what fixes ROW_KEYS1 at the fourth row
; from the bottom.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_GROUP       = 2
ROW_COUNT       = 4         ; a blank row under the heading band
ROW_DEVICE      = 1         ; no blank row under it, 23 rows do not stretch
ROW_RINGS       = 6
ROW_RINGS_END   = 17
ROW_NOTE        = 18
ROW_KEYS1       = 19
KEY_LINES       = 3
LEGEND_LINES    = 4

; The title and the brand fit side by side only with the title hard against
; the left edge.
COL_TITLE       = 0
COL_BRAND       = SCREEN_COLS - 11
COL_GROUP       = 0
COL_DEV_VER     = 9         ; the device row: type, then version
COL_OF          = 14        ; "n OF m" at the right of the group row

; The all-pins screen: where the last group may start, where the device's own
; name goes, and how the pins are spread across a row.  Nine pins to a row is
; what fits with the row's first pin number in front of them.
ROW_ALL_END     = 15
COL_ALL         = 4
ALL_PER_ROW     = 9

; The reset screen's two columns.  COL_R_VAL clears the longest label on that
; screen, which is IMAGE.
COL_R_VAL       = 7
COL_R_PIN       = 19

; ---------------------------------------------------------------------------
; Pins.  A power of two so that a pin's index into the tables is a shift.
;
; The pin tables cost four bytes per pin per group, so halving this would give
; the 3K expansion back five hundred and twelve bytes.  It stays at sixty-four
; because the shared code reaches a group's slice with six shifts written out
; rather than with MAX_PINS_SHIFT, in pins.s, pins_dev.s and auxio.s, and any
; other value has those disagreeing with pins_index.  It fits either way.
; ---------------------------------------------------------------------------

MAX_PINS        = 64
MAX_PINS_SHIFT  = 6

; ---------------------------------------------------------------------------
; Zero page
;
; This ROM owns the machine from reset and never calls the kernal, so the
; whole page is free and the map is a matter of keeping the claims apart.
; $F0-$FF is the RBCP library's, fixed in rbcp_config.s.
; ---------------------------------------------------------------------------

ZP_PTR_LO   = $D0           ; display.s points these at a string
ZP_PTR_HI   = $D1
ZP_TMP0     = $D2           ; plat.s's own scratch
ZP_TMP1     = $D3
ZP_TMP2     = $D4
ZP_TMP3     = $D5

ZP_SCR_LO   = $D6           ; plat_row points these at a screen row
ZP_SCR_HI   = $D7
ZP_COL_LO   = $D8           ; and these at the colour row beside it
ZP_COL_HI   = $D9

ZP_APP0     = $DA
ZP_APP1     = $DB
ZP_APP2     = $DC
ZP_APP3     = $DD
ZP_APP4     = $DE
ZP_APP5     = $DF
ZP_APP6     = $E0
ZP_APP7     = $E1
ZP_APP8     = $E2

; ---------------------------------------------------------------------------
; The keyboard.  VIA2 port B drives a column low, port A reads rows low, and a
; clear bit means the key is down.  The data direction registers are set at
; entry by boot_entry.
;
; Both shift keys are read on their own rather than out of the table, so that a
; shift held with a cursor key cannot match as a key of its own.
; ---------------------------------------------------------------------------

KEY_LSHIFT_COL  = %11110111     ; PB3, PA1
KEY_LSHIFT_BIT  = %00000010
KEY_RSHIFT_COL  = %11101111     ; PB4, PA6
KEY_RSHIFT_BIT  = %01000000

; About 200 us at 1 MHz.
DEBOUNCE_COUNT  = 200
