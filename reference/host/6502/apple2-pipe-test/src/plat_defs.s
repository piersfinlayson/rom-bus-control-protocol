; plat_defs.s — what an Apple IIe is, to the pipe throughput test
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen, the keys, the clock and the zero page.  Everything else the
; tester needs is the same on every machine and lives in ../pipe.

    .include "../rbcp/rbcp_defs.s"

; ---------------------------------------------------------------------------
; Soft switches
; ---------------------------------------------------------------------------

KBD             = $C000     ; bit 7 set = key waiting, bits 0-6 = ASCII
CLR80COL        = $C00C     ; 40 columns
CLRALTCHAR      = $C00E     ; primary character set, upper case and inverse
KBDSTRB         = $C010     ; any access clears the keyboard strobe
VBLBAR          = $C019     ; bit 7 follows the vertical blanking signal
TXTSET          = $C051     ; text rather than graphics
MIXCLR          = $C052     ; whole screen, not split
TXTPAGE1        = $C054     ; display page 1 at $0400
LORES           = $C056     ; low resolution rather than hi-res

; ---------------------------------------------------------------------------
; The clock
;
; A window is a fixed number of ticks, and it has to be a second, because the
; byte count in it is then the rate with no division.
;
; There is no free-running counter on this machine that a host may have, so the
; tick is counted in software off the vertical blanking bit.  Two frames make a
; tick, so a window is fifty frames on a PAL machine and sixty on an NTSC one.
;
; Two frames rather than one because the stall bound in pipe_defs.s is
; STALL_SECS seconds counted in a single byte of clock, and sixty ticks a
; second would not fit.
;
; The counter is in zero page rather than in bss so that reading it is three
; cycles, and because the macros below are expanded in files that neither
; import nor export it.
; ---------------------------------------------------------------------------

.ifdef PAL
PLAT_TICK_HZ    = 25
.else
PLAT_TICK_HZ    = 30
.endif

ZP_VBL      = $DC           ; bit 7 as the blanking bit was last read
ZP_HALF     = $DD           ; the first frame of a pair, or the second
ZP_TICK     = $DE           ; the tick, counting up and wrapping

; PLAT_CLOCK_READ leaves the tick in A.  PLAT_CLOCK_ELAPSED leaves the ticks
; since the byte at start in A, with the carry flag disturbed.  Macros rather
; than routines because timing_window_closed runs once a line, inside the
; measured window, where a jsr and its rts would be most of another percent.
.macro PLAT_CLOCK_READ
    lda ZP_TICK
.endmacro

.macro PLAT_CLOCK_ELAPSED start
    lda ZP_TICK
    sec
    sbc start
.endmacro

; The tick is counted in software, so the send paths carry a poll.  plat.s
; polls in the screen writer and in plat_key_stop as well, which are the two
; places a run spends thousands of cycles without sending anything.
PLAT_SW_TICK    = 1

; The video circuitry and the 6502 take alternate halves of every cycle, so
; fetching a row of characters costs the processor nothing and the device sees
; an unbroken command frame with the display on.
PLAT_DARK       = 0

; ---------------------------------------------------------------------------
; Text screen.  Rows are not contiguous.  Row R starts at $0400 +
; (R AND 7) * $80 + (R / 8) * $28.
; ---------------------------------------------------------------------------

SCREEN_BASE     = $0400
SCREEN_COLS     = 40
SCREEN_ROWS     = 24

; ---------------------------------------------------------------------------
; The screen.  Forty columns, so every figure gets its eight digits behind a
; label written out in full.  Twenty-four rows, so the status row and the two
; rows of key names sit one higher than the counters would put them.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DEVICE      = 1
ROW_VERSION     = 1         ; all three share the identity row here
ROW_PROTO       = 1
ROW_PATHS       = 3
ROW_RATE        = 5
ROW_BEST        = 6
ROW_MEAN        = 7
ROW_TOTAL       = 9
ROW_LINES       = 10
ROW_SECS        = 11
ROW_REFUSALS    = 13
ROW_ERRORS      = 14
ROW_STATUS      = 21
ROW_KEYS        = 22        ; and the row under it

; The title bar.  The name hard left, the brand hard right, and the whole row
; in inverse video behind both.
COL_TITLE       = 1
COL_BRAND       = SCREEN_COLS - 12
COL_DEV         = 1
COL_VER         = 17
COL_PROTO       = 28
COL_LABEL       = 1
COL_KEYS        = 1

; Numbers are eight digits wide, right-aligned, ending at column 29.
NUM_COL         = 22
NUM_WIDTH       = 8

; ---------------------------------------------------------------------------
; Zero page
;
; This ROM owns the machine from reset and never calls the monitor, so the
; whole page is free and the map is a matter of keeping the claims apart.
; $F0-$FF is the RBCP library's, fixed in rbcp_config.s.  The clock takes three
; bytes under the shared code's nine, and plat.s takes the rest.
; ---------------------------------------------------------------------------

ZP_APP0     = $DF
ZP_APP1     = $E0
ZP_APP2     = $E1
ZP_APP3     = $E2
ZP_APP4     = $E3
ZP_APP5     = $E4
ZP_APP6     = $E5
ZP_APP7     = $E6
ZP_APP8     = $E7

ZP_PTR_LO   = $E8           ; display.s points these at a string
ZP_PTR_HI   = $E9
ZP_TMP0     = $EA           ; plat.s's own scratch
ZP_TMP1     = $EB
ZP_TMP2     = $EC
ZP_TMP3     = $ED
ZP_SCR_LO   = $EE           ; plat_row points these at a screen row
ZP_SCR_HI   = $EF

; ---------------------------------------------------------------------------
; The keyboard.  One register holds the last key pressed, in ASCII, and there
; is nothing to say whether it is still held.  See plat_key_stop.
; ---------------------------------------------------------------------------

KEY_1_ASCII     = '1'
KEY_2_ASCII     = '2'
KEY_3_ASCII     = '3'
KEY_T_ASCII     = 'T'
KEY_T_LOWER     = 't'
KEY_RET_ASCII   = $0D
