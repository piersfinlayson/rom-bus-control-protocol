; leds.s — the LED tables, and everything derived from them
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The seam
; --------
; This file owns the tables.  Two files fill them and only one of them is ever
; linked: leds_dev.s talks to a real device over RBCP, leds_fake.s makes the
; answers up.  Everything else in the program reads these tables and does not
; know which was built.
;
; The interface both must provide, with the session already open:
;
;   leds_discover   no input.  Fills leds_count, the two capability limits and
;                   every LED's record.  Carry set means there are no LEDs to
;                   show, with a FAIL_ code in A.
;   leds_scan       refreshes every LED's record.  Carry set means the device
;                   stopped answering.
;   leds_set        A = LED, using want_mode and the want_ tables.  Carry set
;                   means the device refused.
;   leds_mode_info  A = LED, X = mode.  Fills mode_takes_period and
;                   mode_min_period.  Carry set means the device refused, which
;                   a caller reads as "no period on this mode".
;
; Two sets of values, and the difference matters
; ----------------------------------------------
; The want_ tables are what this program last asked for.  The led_ tables are
; what GET_LED_INFO reports.  The screen draws the second, always — a device
; that quietly ignores a colour or clamps a brightness should show up as
; itself, not as what was hoped for.  Comparing the two is the readback check.

    .include "led_defs.s"

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export leds_count
.export leds_truncated
.export leds_max_period
.export leds_max_hold
.export led_type
.export led_mode
.export led_red
.export led_green
.export led_blue
.export led_bright
.export led_period
.export led_modes
.export want_mode
.export want_pal
.export want_bright
.export want_period
.export want_hold
.export mode_takes_period
.export mode_min_period
.export show_col
.export show_dith

leds_count:     .res 1              ; LEDs this program will show
leds_truncated: .res 1              ; the device reported more than we show
leds_max_period: .res 1             ; 100ms units, zero if no period is accepted
leds_max_hold:  .res 1              ; 100ms units, zero if no hold is timed

; What GET_LED_INFO reports.
led_type:       .res MAX_LEDS
led_mode:       .res MAX_LEDS
led_red:        .res MAX_LEDS
led_green:      .res MAX_LEDS
led_blue:       .res MAX_LEDS
led_bright:     .res MAX_LEDS       ; percentage, zero where the LED has none
led_period:     .res MAX_LEDS       ; 100ms units, zero for none in force
led_modes:      .res MAX_LEDS       ; bit N set where mode N is supported

; What this program last asked for.  want_pal is an index into the palette in
; display.s rather than three bytes, because a C64 keyboard is a bad way to
; type a colour and the palette is the whole of what this program will send.
want_mode:      .res MAX_LEDS
want_pal:       .res MAX_LEDS       ; 0 means the device chooses
want_bright:    .res MAX_LEDS       ; 0 means the device chooses
want_period:    .res MAX_LEDS       ; 0 means the mode's own default
want_hold:      .res MAX_LEDS       ; 0 means until something changes it

; What GET_LED_MODE_INFO last reported, for the mode under the cursor.
mode_takes_period: .res 1
mode_min_period:   .res 1

; How each disc is to be drawn at this instant: the C64 colour, and which of
; the three halftones of the disc to draw it from.  led_test.s works these out
; from the mode, the brightness and where the animation has got to, and
; display.s draws them and nothing else.
show_col:       .res MAX_LEDS
show_dith:      .res MAX_LEDS

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; leds_supports — A = LED, X = mode.  Carry set if that LED reports the mode.
;
; Modes above 7 are not in the bitmap, which reports 0x00 to 0x07 and nothing
; else, so this answers no for them.  Nothing here offers one.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export leds_supports
leds_supports:
    cpx #8
    bcs @no
    tay
    lda led_modes, y
@shift:
    cpx #0
    beq @test
    lsr a
    dex
    bne @shift
@test:
    lsr a                       ; bit 0 into carry
    rts
@no:
    clc
    rts

; ---------------------------------------------------------------------------
; leds_level — A = LED.  Returns how brightly a lit disc should be drawn,
; LVL_QTR through LVL_BRIGHT, from the brightness the device reports.
;
; Whether the LED is lit at all is the mode's business and this does not ask.
; An LED reporting no brightness has none to report, and is drawn at full.
; Clobbers A, X.
; ---------------------------------------------------------------------------

.export leds_level
leds_level:
    tax
    lda led_bright, x
    beq @bright                 ; no brightness on this LED, so show it lit
    cmp #34
    bcc @quarter
    cmp #67
    bcc @half
    cmp #100
    bcc @full
@bright:
    lda #LVL_BRIGHT
    rts
@full:
    lda #LVL_FULL
    rts
@half:
    lda #LVL_HALF
    rts
@quarter:
    lda #LVL_QTR
    rts

; ---------------------------------------------------------------------------
; leds_nearest — A = LED.  Returns the palette entry closest to the colour the
; device reports for it, which is what the disc is drawn in.
;
; All three zero means the device states no colour, and there is nothing to
; approximate: entry 0 covers both that and the LED whose colour the host never
; set.  Black is not in the palette, so it can never be the answer to anything
; else.
;
; The differences are quartered before they are added so that the total fits a
; byte.  That is more than enough to pick between fifteen colours this far
; apart, and it is a colour name and a disc that come out of it, not a match.
;
; Clobbers A, X, Y and ZP_APP4 to ZP_APP7.
; ---------------------------------------------------------------------------

.export leds_nearest
leds_nearest:
    tax
    lda led_red, x
    sta ZP_APP4
    ora led_green, x
    ora led_blue, x
    beq @none                   ; no colour stated

    lda led_green, x
    sta ZP_APP5
    lda led_blue, x
    sta ZP_APP6

    ldy #0                      ; palette entry - 1, so the table index
    lda #$FF
    sta ZP_APP7                 ; best distance so far
    ldx #0                      ; best entry so far
@try:
    lda pal_r, y
    sec
    sbc ZP_APP4
    bcs @r_pos
    eor #$FF
    adc #1
@r_pos:
    lsr a
    lsr a
    sta ZP_APP0

    lda pal_g, y
    sec
    sbc ZP_APP5
    bcs @g_pos
    eor #$FF
    adc #1
@g_pos:
    lsr a
    lsr a
    clc
    adc ZP_APP0
    sta ZP_APP0

    lda pal_b, y
    sec
    sbc ZP_APP6
    bcs @b_pos
    eor #$FF
    adc #1
@b_pos:
    lsr a
    lsr a
    clc
    adc ZP_APP0

    cmp ZP_APP7
    bcs @next
    sta ZP_APP7
    tya
    tax
    inx                         ; entry 0 is the device's own choice
@next:
    iny
    cpy #(PICK_COUNT - 1)
    bne @try
    txa
    rts
@none:
    lda #0
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; The palette.  Entry 0 is the device's own choice, sent as three zeroes.
; Entries 1 to 15 are the C64's own colours, so an entry's number is also its
; colour number, and what goes on the wire is the colour the screen is showing
; rather than an approximation of it.  Black is not offered: whether an LED is
; lit is carried by its mode, so a colour being set is always one meant to be
; seen.
;
; Values are VICE's, which is as close to a real machine as this can get
; without measuring one.

; The brighter partner of each colour, for an LED at full brightness.  Where a
; colour has none it is its own, so full and nearly full look the same on it
; rather than wrong.
.export brighter
brighter:
    .byte COL_WHITE, COL_WHITE, COL_LIGHT_RED, COL_CYAN
    .byte COL_PURPLE, COL_LIGHT_GREEN, COL_LIGHT_BLUE, COL_YELLOW
    .byte COL_ORANGE, COL_ORANGE, COL_LIGHT_RED, COL_MED_GREY
    .byte COL_LIGHT_GREY, COL_LIGHT_GREEN, COL_LIGHT_BLUE, COL_WHITE

.export pal_r
.export pal_g
.export pal_b
pal_r:  .byte $FF, $81, $75, $8E, $56, $2E, $ED, $8E, $55, $C4, $4A, $7B, $A9, $70, $B2
pal_g:  .byte $FF, $33, $CE, $3C, $AC, $2C, $F1, $50, $38, $6C, $4A, $7B, $FF, $6D, $B2
pal_b:  .byte $FF, $38, $C8, $97, $4D, $9B, $71, $29, $00, $71, $4A, $7B, $9F, $EB, $B2
