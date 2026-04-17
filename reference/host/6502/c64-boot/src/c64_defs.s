; c64_defs.s — C64 hardware register and memory map constants
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; ZP addresses must match rbcp_defs.s layout.

; ---------------------------------------------------------------------------
; 6510 CPU port
; ---------------------------------------------------------------------------

CPU_DDR         = $00
CPU_PORT        = $01

CPU_DDR_VAL     = %00101111 ; bits 0,1,2,3,5 as output
CPU_PORT_VAL    = %00100111 ; HIRAM=1, LORAM=1, CHAREN=1, CASSWR=0, MOTOR=0

; ---------------------------------------------------------------------------
; VIC-II
; ---------------------------------------------------------------------------

VIC_CTRL1       = $D011
VIC_CTRL2       = $D016
VIC_MEMSETUP    = $D018
VIC_BORDER      = $D020
VIC_BACKGROUND  = $D021

VIC_CTRL1_VAL   = %00011011 ; screen on, 25 rows, normal height, y-scroll=3
VIC_CTRL2_VAL   = %00001000 ; 40 cols, normal width, multicolour off
VIC_MEMSETUP_VAL= %00010100 ; screen at $0400, charset at $1000 (char ROM)

; ---------------------------------------------------------------------------
; CIA1 — keyboard matrix
; ---------------------------------------------------------------------------

CIA1_PRA        = $DC00     ; port A: column select (output)
CIA1_PRB        = $DC01     ; port B: row read     (input)
CIA1_DDRA       = $DC02
CIA1_DDRB       = $DC03

; ---------------------------------------------------------------------------
; CIA2 — VIC-II bank
; ---------------------------------------------------------------------------

CIA2_PRA        = $DD00
CIA2_DDRA       = $DD02

CIA2_DDRA_VAL   = %00000011 ; PA0, PA1 as output
CIA2_PRA_VAL    = %11111100 ; bank 0 ($0000-$3FFF)

; ---------------------------------------------------------------------------
; Screen / colour RAM
; ---------------------------------------------------------------------------

SCREEN_BASE     = $0400
COLOUR_RAM      = $D800
SCREEN_COLS     = 40
SCREEN_ROWS     = 25

; ---------------------------------------------------------------------------
; Character codes (C64 screen codes, uppercase/graphics charset)
; ---------------------------------------------------------------------------

CHAR_SPACE      = $20
CHAR_GT         = $3E       ; '>' screen code
CHAR_SPACE_REV  = $A0       ; reversed space

; ---------------------------------------------------------------------------
; Colours
; ---------------------------------------------------------------------------

COL_BLACK       = 0
COL_WHITE       = 1
COL_LIGHT_BLUE  = 14

; ---------------------------------------------------------------------------
; Keyboard matrix
; CIA1_PRA drives columns active-low; CIA1_PRB reads rows active-low.
; Bit clear in PRB = key pressed.
; ---------------------------------------------------------------------------

; Commodore key: column 7, row 5
KEY_CBM_COL     = %01111111
KEY_CBM_ROW_BIT = %00100000

; RETURN: column 1, row 0
KEY_RET_COL     = %11111101
KEY_RET_ROW_BIT = %00000001

; Cursor up/down: column 7, row 7
KEY_CRS_COL     = %01111111
KEY_CRS_ROW_BIT = %10000000

; Left SHIFT: column 1, row 7
KEY_LSH_COL     = %11111101
KEY_LSH_ROW_BIT = %10000000

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
; Hardware/boot scratch at $EB-$EE.
; ---------------------------------------------------------------------------

ZP_PTR_LO  = $EB
ZP_PTR_HI  = $EC
ZP_TMP0    = $ED
ZP_TMP1    = $EE