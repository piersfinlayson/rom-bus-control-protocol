; plat_defs.s — what a VIC-20 is, to the reliability meter
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen, the keys, and what this machine varies.  Everything else the
; meter needs is the same on every machine and lives in ../stress.

    .include "../rbcp/rbcp_defs.s"

; ---------------------------------------------------------------------------
; What a VIC-20 varies: nothing
;
; The VIC-I and the 6502 take alternate halves of every cycle, so fetching a
; row of characters costs the processor nothing and there are no badlines to
; stop.  Blanking the screen would change the number of commands a second not
; at all, and would take the meter's own answer off the screen.  So this
; machine has no key and one column of counters, and a figure from a VIC-20 is
; comparable with a C64's screen-on figure and not with anything else.
; ---------------------------------------------------------------------------

PLAT_VARY       = 0

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

; PAL and NTSC put the picture in different places.  Pass -DPAL=1 or -DNTSC=1.
.if .defined(PAL)
VIC_H_CENTER_VAL    = $0C
VIC_V_CENTER_VAL    = $26
.elseif .defined(NTSC)
VIC_H_CENTER_VAL    = $05
VIC_V_CENTER_VAL    = $19
.else
.error "Define PAL or NTSC (pass -DPAL=1 or -DNTSC=1 to ca65)"
.endif

VIC_COL_COUNT_VAL   = $96   ; 22 columns, VA9 set, so the screen is at $1E00
VIC_ROW_COUNT_VAL   = $2E   ; 23 rows, 8 pixel characters
VIC_MEM_VAL         = $F0   ; video matrix $1E00, character ROM at $8000
VIC_COLOUR_VAL      = $08   ; black background, black border, normal video

; ---------------------------------------------------------------------------
; VIA2 — the keyboard matrix ($9120-$912F)
; ---------------------------------------------------------------------------

VIA2_PRB        = $9120     ; port B: column select, output, active low
VIA2_PRA        = $9121     ; port A: row read, input, active low
VIA2_DDRB       = $9122
VIA2_DDRA       = $9123
VIA2_DDRB_VAL   = $FF
VIA2_DDRA_VAL   = $00

; ---------------------------------------------------------------------------
; Screen and colour RAM
; ---------------------------------------------------------------------------

SCREEN_BASE     = $1E00
COLOUR_RAM      = $9600
SCREEN_COLS     = 22
SCREEN_ROWS     = 23

COL_BLACK       = 0
COL_WHITE       = 1
COL_RED         = 2
COL_CYAN        = 3
COL_PURPLE      = 4
COL_GREEN       = 5
COL_BLUE        = 6
COL_YELLOW      = 7

; ---------------------------------------------------------------------------
; The screen the meter draws on.  Twenty-two columns, so the run's counts take
; a row each, the command names are short and the failure record is terse.
;
; A command's own counts get eight digits and five, not the ten the run's own
; counts get.  There is nothing left to give them on a 22 column screen, and a
; count that outgrows its column fills with plus signs rather than showing a
; number that is not the count.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DEV         = 1
ROW_VER         = 2
ROW_PROTO       = 3
ROW_PIPE        = 4
ROW_BIG         = 6
ROW_RAW         = 8
ROW_RAW_BAD     = 9
ROW_RAW_LOST    = 10
ROW_HEAD        = 11
ROW_FIRST       = 12        ; through ROW_FIRST + TEST_COUNT - 1
ROW_NOTE        = 17
ROW_REC_SENT    = 18
ROW_REC_GOT     = 19
ROW_KEYS        = 22

COL_NAME        = 1
COL_SENT        = 9
COL_BAD         = 17
COL_BIG         = 6

; Sent, errors and lost are a row each: the error count is ten digits and
; there is no room beside it on a 22 column screen.  Lost sits under the
; errors, which is where it belongs anyway: it is the part of them the device
; never answered.
COL_RAW_SENT_LBL = 1        ; "SENT", 1 to 4
COL_RAW_SENT     = 6        ; 6 to 15
COL_RAW_BAD_LBL  = 3        ; "ERR", 3 to 5
COL_RAW_BAD      = 7        ; 7 to 16
COL_RAW_LOST_LBL = 2        ; "LOST", 2 to 5
COL_RAW_LOST     = 7        ; 7 to 16

; ---------------------------------------------------------------------------
; Zero page.  $F0-$FF is the RBCP library's.  Nothing else is running: this
; ROM owns the machine from reset and never calls the kernal.
; ---------------------------------------------------------------------------

ZP_PTR_LO   = $D0
ZP_PTR_HI   = $D1
ZP_TMP0     = $D2
ZP_TMP1     = $D3
ZP_TMP2     = $D4
ZP_TMP3     = $D5
ZP_SCR_LO   = $D6
ZP_SCR_HI   = $D7
ZP_COL_LO   = $D8
ZP_COL_HI   = $D9
