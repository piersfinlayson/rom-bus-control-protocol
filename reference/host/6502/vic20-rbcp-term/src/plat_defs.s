; plat_defs.s — what the VIC-20 is, to the RBCP terminal
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen, the keys and the zero page.  Everything else the terminal needs
; is the same on every machine and lives in ../term.

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

; ---------------------------------------------------------------------------
; Screen and colour RAM
; ---------------------------------------------------------------------------

SCREEN_BASE     = $1E00
COLOUR_RAM      = $9600
SCREEN_COLS     = 22
SCREEN_ROWS     = 23

COL_BLACK       = 0
COL_WHITE       = 1

; ---------------------------------------------------------------------------
; The screen.  Twenty-two columns by twenty-three rows: a title bar, two rows
; naming the device, eighteen rows of what has been sent, the line being typed,
; and a status bar.
;
; Two rows for the device, because twenty-two columns will not hold what it
; calls itself and what protocol it speaks side by side.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DEVICE      = 1
ROW_PROTO       = 2
ROW_TEXT_TOP    = 3
ROW_TEXT_BOT    = 20
ROW_INPUT       = 21
ROW_STATUS      = 22

COL_DEV         = 0
COL_PROTO       = 0

; Twenty-two columns hold the name and the brand only if the name starts hard
; against the edge.
COL_TITLE       = 0
COL_BRAND       = SCREEN_COLS - 11
COL_LEFT        = SCREEN_COLS - 8

; ---------------------------------------------------------------------------
; Zero page
;
; The terminal masks interrupts on entry and never calls the kernal again, so
; the whole page is free and the map is a matter of keeping the three claims
; apart.  $F0-$FF is the RBCP library's, fixed in rbcp_config.s.  plat.s takes
; eight bytes for its own pointers, and the shared code nine more.
; ---------------------------------------------------------------------------

ZP_PTR_LO   = $D0
ZP_PTR_HI   = $D1
ZP_TMP0     = $D2
ZP_TMP1     = $D3
ZP_TMP2     = $D4
ZP_TMP3     = $D5

ZP_SCR_LO   = $D6           ; plat_row points these at a screen row
ZP_SCR_HI   = $D7
ZP_SRC_LO   = $D8           ; plat_scroll reads a row through these
ZP_SRC_HI   = $D9

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
; shift held with a letter cannot match as a key of its own.
; ---------------------------------------------------------------------------

KEY_LSHIFT_COL  = %11110111     ; PB3, PA1
KEY_LSHIFT_BIT  = %00000010
KEY_RSHIFT_COL  = %11101111     ; PB4, PA6
KEY_RSHIFT_BIT  = %01000000

; About 200 us at 1 MHz.
DEBOUNCE_COUNT  = 200
