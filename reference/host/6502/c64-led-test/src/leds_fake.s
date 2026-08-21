; leds_fake.s — a device that is not there
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Provides the leds.s interface out of a table instead of a device, so that
; every screen this program can draw is reachable under an emulator.  It is
; never linked into the shipped binary: the Makefile builds rbcp_led_test.prg
; from leds_dev.s and rbcp_led_demo.prg from this.
;
; What it models, and why each part is here:
;
;   - Several boards, chosen by BOARD at assembly time, so that a monochrome
;     LED, an RGB one, a device with neither and a device with more than this
;     program shows can all be looked at.
;   - A device that answers a SET_LED the way the protocol says it should, so
;     that the readback line means something here — and one board where it does
;     not, so the screen that catches it can be seen too.
;   - A cost per command close to the real one, so the refresh rate on screen
;     is the rate a device would give rather than an emulator's.
;
; What it does not model: the RBCP command encoding, the polling sequence, the
; knock, and every way a real device can refuse.  None of those are visible on
; screen, which is the whole reason this file can stand in.

    .include "led_defs.s"

.import fake_cost

.import leds_count
.import leds_truncated
.import leds_max_period
.import leds_max_hold
.import led_type
.import led_mode
.import led_red
.import led_green
.import led_blue
.import led_bright
.import led_period
.import led_modes
.import want_mode
.import want_pal
.import want_bright
.import want_period
.import want_hold
.import mode_takes_period
.import mode_min_period
.import pal_r
.import pal_g
.import pal_b

; ---------------------------------------------------------------------------
; Boards.  BOARD is -D on the assembler command line, defaulting to 0.
;
;   0  a monochrome green status LED and an RGB one, and a device that can time
;      both a period and a hold.  The board this program was drawn for.
;   1  one RGB LED on a device that accepts neither a period nor a hold.
;   2  no LEDs at all.
;   3  three LEDs, one more than this program shows, and LED 0 reports a
;      brightness of its own whatever it is given.
; ---------------------------------------------------------------------------

.ifndef BOARD
BOARD = 0
.endif

.if BOARD = 0
BOARD_LEDS     = 2
BOARD_PERIOD   = 255
BOARD_HOLD     = 255
BOARD_LIES     = 0
.endif

.if BOARD = 1
BOARD_LEDS     = 1
BOARD_PERIOD   = 0
BOARD_HOLD     = 0
BOARD_LIES     = 0
.endif

.if BOARD = 2
BOARD_LEDS     = 0
BOARD_PERIOD   = 0
BOARD_HOLD     = 0
BOARD_LIES     = 0
.endif

.if BOARD = 3
BOARD_LEDS     = 3
BOARD_PERIOD   = 255
BOARD_HOLD     = 255
BOARD_LIES     = 1
.endif

; What the device picks when the host names no colour.  Any colour would do —
; the point is that it is visibly not one this program asked for.
DEV_CHOICE_R    = $75
DEV_CHOICE_G    = $CE
DEV_CHOICE_B    = $C8

MODE_DEFAULT_PERIOD = 20        ; two seconds, in the units the protocol uses

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

; The state the fake device is holding.  leds_scan copies it into the led_
; tables, which is what the display reads.
fake_mode:      .res MAX_LEDS
fake_r:         .res MAX_LEDS
fake_g:         .res MAX_LEDS
fake_b:         .res MAX_LEDS
fake_bright:    .res MAX_LEDS
fake_period:    .res MAX_LEDS
set_led_num:    .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; leds_discover — fills the tables from the board table.  A board with no LEDs
; refuses exactly as a device with none would.
; ---------------------------------------------------------------------------

.export leds_discover
leds_discover:
    lda #0
    sta leds_truncated
.if BOARD_LEDS = 0
    lda #FAIL_NO_LEDS
    sec
    rts
.else
.if BOARD_LEDS > MAX_LEDS
    lda #1
    sta leds_truncated
    lda #MAX_LEDS
.else
    lda #BOARD_LEDS
.endif
    sta leds_count
    lda #BOARD_PERIOD
    sta leds_max_period
    lda #BOARD_HOLD
    sta leds_max_hold

    ldx #0
@each:
    lda board_type, x
    sta led_type, x
    lda board_modes, x
    sta led_modes, x
    lda #RBCP_LED_OFF
    sta fake_mode, x
    lda board_r, x
    sta fake_r, x
    lda board_g, x
    sta fake_g, x
    lda board_b, x
    sta fake_b, x
    lda #100
    sta fake_bright, x
    lda #0
    sta fake_period, x
    inx
    cpx leds_count
    bne @each

    jsr leds_scan
    clc
    rts
.endif

; ---------------------------------------------------------------------------
; leds_scan — a fake device is always there.
; ---------------------------------------------------------------------------

.export leds_scan
leds_scan:
    ldx #0
@each:
    jsr fake_cost
    lda fake_mode, x
    sta led_mode, x
    lda fake_r, x
    sta led_red, x
    lda fake_g, x
    sta led_green, x
    lda fake_b, x
    sta led_blue, x
    lda fake_bright, x
    sta led_bright, x
    lda fake_period, x
    sta led_period, x
    inx
    cpx leds_count
    bne @each
    clc
    rts

; ---------------------------------------------------------------------------
; leds_set — A = LED.  Applies the want_ tables the way the protocol says a
; device should: a monochrome LED keeps its own colour, three zeroes leave the
; colour to the device, a brightness of zero leaves that to the device too, and
; a mode that takes no period reports none.
; ---------------------------------------------------------------------------

.export leds_set
leds_set:
    jsr fake_cost
    sta set_led_num
    tax
    lda want_mode, x
    sta fake_mode, x

    lda led_type, x
    cmp #RBCP_LED_TYPE_RGB
    bne @colour_done            ; monochrome, so its colour is not ours to set
    ldy want_pal, x
    beq @device_colour
    dey
    lda pal_r, y
    sta fake_r, x
    lda pal_g, y
    sta fake_g, x
    lda pal_b, y
    sta fake_b, x
    jmp @colour_done
@device_colour:
    lda #DEV_CHOICE_R
    sta fake_r, x
    lda #DEV_CHOICE_G
    sta fake_g, x
    lda #DEV_CHOICE_B
    sta fake_b, x
@colour_done:

.if BOARD_LIES
    cpx #0
    beq @own_brightness         ; this LED reports its own whatever it is given
.endif
    lda want_bright, x
    bne @store_bright
@own_brightness:
    lda #100
@store_bright:
    sta fake_bright, x

    ; The period the device ends up holding: none where the mode takes none,
    ; the mode's own default where the host named nothing, otherwise what was
    ; asked for.
    lda want_mode, x
    tay
    lda #0
    sta fake_period, x
    lda mode_period_tab, y
    beq @done
.if BOARD_PERIOD = 0
    ; this device accepts no period at all
.else
    lda want_period, x
    bne @store_period
    lda #MODE_DEFAULT_PERIOD
@store_period:
    sta fake_period, x
.endif
@done:
    clc
    rts

; ---------------------------------------------------------------------------
; leds_mode_info — A = LED, X = mode.
; ---------------------------------------------------------------------------

.export leds_mode_info
leds_mode_info:
    jsr fake_cost
    lda #0
    sta mode_takes_period
    sta mode_min_period
    cpx #6
    bcs @none
.if BOARD_PERIOD = 0
    jmp @none
.else
    lda mode_period_tab, x
    beq @none
    sta mode_takes_period
    lda #5                      ; half a second is as short as this one goes
    sta mode_min_period
    clc
    rts
.endif
@none:
    sec
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; Which modes take a period.  Off and On never do, and the protocol leaves the
; rest to the device.
mode_period_tab:
    .byte 0, 0, 1, 1, 1, 1

.if BOARD_LEDS > 0
; A row per LED: its type, the modes it supports as the bitmap GET_LED_INFO
; reports, and the colour it shows.  A monochrome LED's colour is fixed; an RGB
; one starts dark and is given a colour by the first SET_LED.
.if BOARD = 1
board_type:  .byte RBCP_LED_TYPE_RGB
board_modes: .byte %00111111
board_r:     .byte $00
board_g:     .byte $00
board_b:     .byte $00
.else
board_type:  .byte RBCP_LED_TYPE_MONO, RBCP_LED_TYPE_RGB
board_modes: .byte %00000111, %00111111  ; the status LED has Off, On and Blink
board_r:     .byte $56, $00
board_g:     .byte $AC, $00
board_b:     .byte $4D, $00
.endif
.endif
