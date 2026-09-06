; plat_defs.s — what the VIC-20 is, to the pipe throughput test
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen, the keys, the clock and the zero page.  Everything else the
; tester needs is the same on every machine and lives in ../pipe.

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
; VIA1 ($9110-$911F) — the clock.  VIA2 carries the keyboard and the kernal's
; jiffy timer, so the tester leaves its timers alone.
; ---------------------------------------------------------------------------

VIA1_T1CL       = $9114     ; timer 1 counter low, and reading it clears IFR6
VIA1_T1CH       = $9115     ; writing it loads the counter from the latch
VIA1_T1LL       = $9116     ; timer 1 latch low
VIA1_ACR        = $911B
VIA1_IFR        = $911D
VIA1_IER        = $911E

VIA1_ACR_T1FREE = %01000000 ; timer 1 free-running, PB7 untouched

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
; The clock
;
; A window is a fixed number of timer 1 periods, and it has to be exactly a
; second, because the byte count in it is then the rate with no division.
;
; PAL is 1108405 Hz and 1108405 = 31 * 35755, so 31 periods of 35755 cycles is
; a second to the cycle.  NTSC is 1022727 Hz, which is 3 * 340909 with 340909
; prime, so no exact split exists: 28 periods of 36526 is 1022728 cycles, one
; cycle long, 0.98 parts per million.  At the rates being measured that is far
; under a single byte.
;
; A 6522 timer 1 period is the latch plus two cycles, so the latch is the
; period minus two.
;
; The 6522's second timer cannot be made to count the first one's underflows,
; so the tick is counted in software.  PLAT_SW_TICK puts a call to
; plat_clock_poll in the send paths, and the two macros below count as well,
; so the tick also moves while a run is doing nothing but waiting on a full
; pipe.  A period is about 32 ms and every one of those places is reached far
; more often than that.
; ---------------------------------------------------------------------------

.if .defined(PAL)
PLAT_TICK_HZ        = 31
T1_LATCH            = 35755 - 2
VIC_H_CENTER_VAL    = $0C
VIC_V_CENTER_VAL    = $26
.elseif .defined(NTSC)
PLAT_TICK_HZ        = 28
T1_LATCH            = 36526 - 2
VIC_H_CENTER_VAL    = $05
VIC_V_CENTER_VAL    = $19
.else
.error "Define PAL or NTSC (pass -DPAL=1 or -DNTSC=1 to ca65)"
.endif

; Bit 6 of the interrupt flag register is timer 1, which bit tests into V.
.macro PLAT_CLOCK_TICK
    bit VIA1_IFR
    bvc :+
    lda VIA1_T1CL               ; the read is what clears the flag
    inc ZP_TICK
:
.endmacro

; PLAT_CLOCK_READ leaves the tick in A.  PLAT_CLOCK_ELAPSED leaves the ticks
; since the byte at start in A, with the carry flag disturbed.  The tick counts
; up, so elapsed is now minus start.  Macros rather than routines because
; timing_window_closed runs once a line, inside the measured window, where a
; jsr and its rts would be most of another percent.
.macro PLAT_CLOCK_READ
    PLAT_CLOCK_TICK
    lda ZP_TICK
.endmacro

.macro PLAT_CLOCK_ELAPSED start
    PLAT_CLOCK_TICK
    lda ZP_TICK
    sec
    sbc start
.endmacro

; The tick is counted in software, so the send paths carry a poll.
PLAT_SW_TICK    = 1

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
; The screen.  22 by 23, so the tester draws its narrow layout: the device's
; three strings take a row each, the labels are short, and the figures sit in
; the right-hand half of the row their label starts.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DEVICE      = 1
ROW_VERSION     = 2
ROW_PROTO       = 3
ROW_PATHS       = 5
ROW_RATE        = 7
ROW_BEST        = 8
ROW_MEAN        = 9
ROW_TOTAL       = 11
ROW_LINES       = 12
ROW_SECS        = 13
ROW_REFUSALS    = 15
ROW_ERRORS      = 16
ROW_STATUS      = 19
ROW_KEYS        = 21        ; and the row under it

; The title bar.  The name hard left, the brand hard right, and the whole row
; reversed behind both.
COL_TITLE       = 1
COL_BRAND       = SCREEN_COLS - 11
COL_DEV         = 1
COL_VER         = 1
COL_PROTO       = 1
COL_LABEL       = 1
COL_KEYS        = 1

; Numbers are eight digits wide, right-aligned, ending at the last column.
NUM_COL         = 14
NUM_WIDTH       = 8

; ---------------------------------------------------------------------------
; Zero page
;
; The tester masks interrupts on entry and never calls the kernal again, so
; the whole page is free and the map is a matter of keeping the three claims
; apart.  $F0-$FF is the RBCP library's, fixed in rbcp_config.s.  plat.s takes
; eight bytes for its own pointers and one for the tick, and the shared code
; nine more.
; ---------------------------------------------------------------------------

ZP_PTR_LO   = $D0
ZP_PTR_HI   = $D1
ZP_TMP0     = $D2
ZP_TMP1     = $D3
ZP_TMP2     = $D4
ZP_TMP3     = $D5

ZP_SCR_LO   = $D6           ; plat_row points these at a screen row
ZP_SCR_HI   = $D7

ZP_TICK     = $D8           ; timer 1 periods, counted by PLAT_CLOCK_TICK

ZP_APP0     = $D9
ZP_APP1     = $DA
ZP_APP2     = $DB
ZP_APP3     = $DC
ZP_APP4     = $DD
ZP_APP5     = $DE
ZP_APP6     = $DF
ZP_APP7     = $E0
ZP_APP8     = $E1

; ---------------------------------------------------------------------------
; The keyboard.  VIA2 port B drives a column low, port A reads rows low.  The
; data direction registers are set at entry by boot_entry.
; ---------------------------------------------------------------------------

KEY_COL_0       = %11111110     ; PB0: 1, 3
KEY_COL_1       = %11111101     ; PB1: RETURN
KEY_COL_6       = %10111111     ; PB6: T
KEY_COL_7       = %01111111     ; PB7: 2

KEY_1_BIT       = %00000001     ; PA0
KEY_2_BIT       = %00000001     ; PA0
KEY_3_BIT       = %00000010     ; PA1
KEY_T_BIT       = %00000100     ; PA2
KEY_RETURN_BIT  = %10000000     ; PA7

; About 200 us at 1 MHz.
DEBOUNCE_COUNT  = 200
