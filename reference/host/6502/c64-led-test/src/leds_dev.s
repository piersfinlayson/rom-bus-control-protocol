; leds_dev.s — the leds.s interface, against a real device
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Everything here runs with interrupts masked and the program executing from
; RAM.  Between the knock and the exit nothing may read $A000-$BFFF except the
; command page reads the protocol makes and the back-channel reads it requires.
;
; Opening the session, reading the device's identity and finding a clean way
; out are rbcp_session.s's, shared with the other testers.  What is left here
; is the LEDs group and nothing else.
;
; This file has never run.  There is no 6502 emulator here that speaks RBCP and
; the demo build deliberately does not exercise it: hardware is the only thing
; that can.

    .include "led_defs.s"

.import rbcp_cmd_get_led_capability
.import rbcp_cmd_get_led_info
.import rbcp_cmd_get_led_mode_info
.import rbcp_cmd_set_led

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
.bss
; ---------------------------------------------------------------------------

scan_led:       .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; leds_discover — the capability, then every LED's record.
;
; GET_LED_CAPABILITY takes no argument bytes, so a device whose protocol
; version predates the LEDs group fails it and stays in step.  Carry set means
; no LEDs here whether the device is old or merely has none, and both answers
; lead to the same screen.
;
; Carry clear armed, carry set refused with a FAIL_ code in A.
; ---------------------------------------------------------------------------

.export leds_discover
leds_discover:
    lda #0
    sta leds_truncated

    jsr rbcp_cmd_get_led_capability
    bcs @none
    lda RBCP_DATA_ADDR + RBCP_LED_CAP_COUNT
    bne @have
@none:
    lda #FAIL_NO_LEDS
    sec
    rts

@have:
    cmp #MAX_LEDS + 1
    bcc @fits
    ldx #1
    stx leds_truncated
    lda #MAX_LEDS
@fits:
    sta leds_count
    lda RBCP_DATA_ADDR + RBCP_LED_CAP_MAX_PERIOD
    sta leds_max_period
    lda RBCP_DATA_ADDR + RBCP_LED_CAP_MAX_HOLD
    sta leds_max_hold

    jsr leds_scan
    bcc @done
    lda #SESS_FAIL_NO_DEVICE
    sec
    rts
@done:
    clc
    rts

; ---------------------------------------------------------------------------
; leds_scan — one GET_LED_INFO per LED, so the picture is as live as the
; device is fast.
; Carry set means the device stopped answering.
; ---------------------------------------------------------------------------

.export leds_scan
leds_scan:
    lda #0
    sta scan_led
@loop:
    lda scan_led
    jsr rbcp_cmd_get_led_info
    bcs @fail
    ldx scan_led
    lda RBCP_DATA_ADDR + RBCP_LED_INFO_TYPE
    sta led_type, x
    lda RBCP_DATA_ADDR + RBCP_LED_INFO_MODE
    sta led_mode, x
    lda RBCP_DATA_ADDR + RBCP_LED_INFO_RED
    sta led_red, x
    lda RBCP_DATA_ADDR + RBCP_LED_INFO_GREEN
    sta led_green, x
    lda RBCP_DATA_ADDR + RBCP_LED_INFO_BLUE
    sta led_blue, x
    lda RBCP_DATA_ADDR + RBCP_LED_INFO_BRIGHTNESS
    sta led_bright, x
    lda RBCP_DATA_ADDR + RBCP_LED_INFO_PERIOD
    sta led_period, x
    lda RBCP_DATA_ADDR + RBCP_LED_INFO_MODES
    sta led_modes, x
    inc scan_led
    lda scan_led
    cmp leds_count
    bne @loop
    clc
    rts
@fail:
    sec
    rts

; ---------------------------------------------------------------------------
; leds_set — A = LED.  Sends what the want_ tables hold for it.
;
; A palette entry of zero is the device's own choice, which the protocol spells
; as three zero colour bytes, so no special case is needed beyond not indexing
; the table.
;
; Carry set means the device refused, which is the answer to a brightness over
; a hundred, a period outside the mode's range, a hold past the device's
; maximum and a mode the LED does not have.  This program checks the mode
; itself before it gets here, so a refusal is the device disagreeing with what
; it reported.
; ---------------------------------------------------------------------------

.export leds_set
leds_set:
    tax
    lda want_mode, x
    sta rbcp_arg0

    ldy want_pal, x
    beq @device_colour
    dey                         ; entry 1 is the first table row
    lda pal_r, y
    sta rbcp_arg1
    lda pal_g, y
    sta rbcp_arg2
    lda pal_b, y
    sta rbcp_arg3
    jmp @rest
@device_colour:
    lda #0
    sta rbcp_arg1
    sta rbcp_arg2
    sta rbcp_arg3
@rest:
    lda want_bright, x
    sta rbcp_arg4
    lda want_period, x
    sta rbcp_arg5
    lda want_hold, x
    sta rbcp_arg6
    txa
    jmp rbcp_cmd_set_led

; ---------------------------------------------------------------------------
; leds_mode_info — A = LED, X = mode.  Fills mode_takes_period and
; mode_min_period.
;
; A refusal is not an error worth showing: it means the LED does not have the
; mode, and a caller that asked anyway reads it the same way it reads a mode
; that takes no period.  Both come back as no period.
; ---------------------------------------------------------------------------

.export leds_mode_info
leds_mode_info:
    jsr rbcp_cmd_get_led_mode_info
    bcs @none
    lda RBCP_DATA_ADDR + RBCP_LED_MODE_FLAGS
    and #RBCP_LED_MODE_TAKES_PERIOD
    sta mode_takes_period
    lda RBCP_DATA_ADDR + RBCP_LED_MODE_MIN_PERIOD
    sta mode_min_period
    clc
    rts
@none:
    lda #0
    sta mode_takes_period
    sta mode_min_period
    sec
    rts
