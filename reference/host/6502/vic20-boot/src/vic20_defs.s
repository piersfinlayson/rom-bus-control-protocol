; vic20_defs.s — VIC-20 hardware register and memory map constants
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; ZP addresses must match rbcp_defs.s layout.

.include "../rbcp/rbcp_defs.s"

; ---------------------------------------------------------------------------
; VIC chip ($9000-$900F)
; ---------------------------------------------------------------------------

VIC_H_CENTER    = $9000     ; bits 0-6: horizontal centering; bit 7: interlace
VIC_V_CENTER    = $9001     ; vertical centering
VIC_COL_COUNT   = $9002     ; bits 0-6: column count; bit 7: video matrix VA9
VIC_ROW_COUNT   = $9003     ; bits 1-6: row count; bit 0: char height (0=8px)
VIC_RASTER      = $9004     ; raster beam line
VIC_MEM         = $9005     ; bits 0-3: char memory start; bits 4-7: video matrix address
VIC_LIGHTPEN_H  = $9006
VIC_LIGHTPEN_V  = $9007
VIC_PADDLE_X    = $9008
VIC_PADDLE_Y    = $9009
VIC_OSC1        = $900A
VIC_OSC2        = $900B
VIC_OSC3        = $900C
VIC_NOISE       = $900D
VIC_AUX_VOL     = $900E     ; bits 0-3: volume; bits 4-7: auxiliary colour
VIC_COLOUR      = $900F     ; bits 0-2: border colour; bit 3: reverse; bits 4-7: background

; PAL/NTSC-dependent centering values.
; Pass -DPAL=1 or -DNTSC=1 to ca65.
.if .defined(PAL)
VIC_H_CENTER_VAL    = $0C
VIC_V_CENTER_VAL    = $26
.elseif .defined(NTSC)
VIC_H_CENTER_VAL    = $05
VIC_V_CENTER_VAL    = $19
.else
.error "Define PAL or NTSC (pass -DPAL=1 or -DNTSC=1 to ca65)"
.endif

; Fixed VIC register values (same for PAL and NTSC).
; Screen at $1E00: $9005 bits 4-7 = $F -> base $1C00, VA9=1 -> +$200 = $1E00.
; $9002 bit 7 = 1 sets VA9; bits 0-6 = 22 columns.
VIC_COL_COUNT_VAL   = $96   ; 22 columns, VA9=1 (screen at $1E00)
VIC_ROW_COUNT_VAL   = $2E   ; 23 rows, 8-pixel characters
VIC_MEM_VAL         = $F0   ; video matrix $1E00, character ROM at $8000

VIC_COLOUR_VAL      = $08   ; black background, black border, normal video
VIC_COLOUR_ERR      = $0A   ; black background, red border (error state)

; ---------------------------------------------------------------------------
; VIA2 — keyboard matrix ($9120-$912F)
; Port B ($9120): column select (output, active low)
; Port A ($9121): row read     (input,  active low)
; ---------------------------------------------------------------------------

VIA2_PRB        = $9120     ; port B: column select (output)
VIA2_PRA        = $9121     ; port A: row read      (input)
VIA2_DDRB       = $9122
VIA2_DDRA       = $9123

VIA2_DDRB_VAL   = $FF      ; port B all output (drives columns)
VIA2_DDRA_VAL   = $00      ; port A all input  (reads rows)

; ---------------------------------------------------------------------------
; Screen / colour RAM
; Screen at $1E00 (22x23 = 506 bytes).
; Colour RAM at $9600 (VA9=1 selects upper half of $9400-$97FF).
; ---------------------------------------------------------------------------

SCREEN_BASE     = $1E00
COLOUR_RAM      = $9600
SCREEN_COLS     = 22
SCREEN_ROWS     = 23

; ---------------------------------------------------------------------------
; Character codes (VIC-20 screen codes, uppercase/graphics charset)
; ---------------------------------------------------------------------------

CHAR_SPACE      = $20
CHAR_GT         = $3E       ; '>' screen code
CHAR_SPACE_REV  = $A0       ; reversed space

; ---------------------------------------------------------------------------
; Colours
; ---------------------------------------------------------------------------

COL_BLACK       = 0
COL_WHITE       = 1
COL_RED         = 2
COL_CYAN        = 3
COL_PURPLE      = 4
COL_GREEN       = 5
COL_BLUE        = 6
COL_YELLOW      = 7
COL_ORANGE      = 8
COL_BROWN       = 9
COL_LIGHT_RED   = 10
COL_DARK_GREY   = 11
COL_MED_GREY    = 12
COL_LIGHT_GREEN = 13
COL_LIGHT_BLUE  = 14
COL_LIGHT_GREY  = 15

; ---------------------------------------------------------------------------
; Keyboard matrix
; VIA2_PRB drives columns active-low; VIA2_PRA reads rows active-low.
; Bit clear in PRA = key pressed.
; ---------------------------------------------------------------------------

; Commodore key: column 5, row 0
KEY_CBM_COL     = %11011111
KEY_CBM_ROW_BIT = %00000001

; RETURN: column 1, row 7
KEY_RET_COL     = %11111101
KEY_RET_ROW_BIT = %10000000

; Cursor down: column 3, row 7
; Left SHIFT:  column 3, row 1  (same column — both readable in one PRA read)
KEY_CRS_COL     = %11110111
KEY_CRS_ROW_BIT = %10000000
KEY_LSH_ROW_BIT = %00000010

; Right SHIFT: column 4, row 6
KEY_RSH_COL     = %11101111
KEY_RSH_ROW_BIT = %01000000

; Key tokens
KEY_NONE        = $00
KEY_UP          = $01
KEY_DOWN        = $02
KEY_RETURN      = $03

; ---------------------------------------------------------------------------
; Debounce loop count (~200 us at 1 MHz phi2)
; ---------------------------------------------------------------------------

DEBOUNCE_COUNT  = 200

; ---------------------------------------------------------------------------
; Zero-page addresses — shared with rbcp_defs.s
; Hardware/boot scratch at $D0-$D6.
; ---------------------------------------------------------------------------

ZP_PTR_LO  = $D0
ZP_PTR_HI  = $D1
ZP_TMP0    = $D2
ZP_TMP1    = $D3
ZP_TMP2    = $D4
ZP_TMP3    = $D5
ZP_TMP4    = $D6