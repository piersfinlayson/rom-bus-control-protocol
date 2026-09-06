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

    .include "led_defs.s"

.import rbcp_cmd_get_led_capability
.import rbcp_cmd_get_led_info
.import rbcp_cmd_get_led_mode_info
.import rbcp_cmd_set_led
.import rbcp_recover

.import display_dark
.import display_light

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
.import fail_stage
.import fail_gone
.import fail_group
.import fail_cmd
.import fail_led
.import fail_sent_tok
.import fail_hdr
.import leds_ok_lo
.import leds_ok_hi
.import leds_bad_lo
.import leds_bad_hi
.import mode_takes_period
.import mode_min_period
.import pal_r
.import pal_g
.import pal_b

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

scan_led:       .res 1
send_tries:     .res 1          ; goes left on the command in hand
mode_led:       .res 1          ; what leds_mode_info was asked, kept for a retry
mode_num:       .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; How many times one command is sent before the device is given up on.  Each
; go past the first has a reset and a re-entry in front of it.
DEV_TRIES = 3

; ---------------------------------------------------------------------------
; try_start — arms the count for the command about to go out.  Clobbers A.
; ---------------------------------------------------------------------------

try_start:
    lda #DEV_TRIES
    sta send_tries
    rts

; ---------------------------------------------------------------------------
; try_again — whether to send the command that just failed again.  The caller
; notes the failure first, because fail_stage is read here.
;
; A refusal is the device's answer and would be its answer again, so that comes
; straight back.  Anything else slipped the frame by a byte, which leaves the
; device waiting for argument bytes that will never arrive or out of
; command-response mode altogether.  rbcp_recover's reset and re-entry cover
; both, and only then is there anywhere for the command to go.
;
; Carry clear send it again, carry set do not, and fail_gone says whether the
; device is still there.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

try_again:
    lda #0
    sta fail_gone
    lda fail_stage
    cmp #STAGE_REFUSED
    beq @no
    jsr rbcp_recover
    bcs @gone
    dec send_tries
    bne @yes
@no:
    sec
    rts
@gone:
    lda #1
    sta fail_gone
    sec
    rts
@yes:
    clc
    rts

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
    jsr display_dark
    jsr discover_body
    jmp display_light

discover_body:
    lda #0
    sta leds_truncated

    jsr try_start
@cap:
    jsr rbcp_cmd_get_led_capability
    bcc @count
    lda rbcp_zp_5
    cmp #STAGE_REFUSED
    beq @none                   ; a version that predates the group says so
    jsr note_failure
    jsr try_again
    bcc @cap
    lda fail_gone
    bne @dead
@none:
    lda #FAIL_NO_LEDS
    sec
    rts
@dead:
    lda #SESS_FAIL_NO_DEVICE
    sec
    rts

@count:
    lda RBCP_DATA_ADDR + RBCP_LED_CAP_COUNT
    bne @have
    jmp @none

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

    jsr scan_body
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
    jsr display_dark
    jsr scan_body
    jmp display_light

scan_body:
    lda #0
    sta scan_led
@loop:
    jsr try_start
@send:
    lda scan_led
    sta fail_led
    jsr rbcp_cmd_get_led_info
    bcs @fail
    jsr note_ok
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
    jsr note_failure
    jsr try_again
    bcc @send
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
    jsr display_dark
    jsr set_body
    jmp display_light

; The arguments are built again on every go, because a recovery sends commands
; of its own and leaves nothing of them.
set_body:
    sta fail_led
    jsr try_start
@send:
    lda fail_led
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
    jsr rbcp_cmd_set_led
    bcs @fail
    jsr note_ok
    clc
    rts
@fail:
    jsr note_failure
    jsr try_again
    bcc @send
    sec
    rts

; ---------------------------------------------------------------------------
; note_ok — one more command the device answered.  Leaves the carry alone,
; because both callers are about to report it.  Clobbers nothing.
; ---------------------------------------------------------------------------

note_ok:
    inc leds_ok_lo
    bne @done
    inc leds_ok_hi
@done:
    rts

; ---------------------------------------------------------------------------
; note_failure — what the host asked for and what the device had written, at
; the moment a command went wrong.
;
; rbcp_zp_5 is the stage the library reached: 1 the token never moved, 2 it
; moved and the command never completed, 3 the device answered failure.
; rbcp_zp_0 and rbcp_zp_1 still hold the group and command that were sent, and
; rbcp_zp_2 the token as it stood before they went out.
;
; The header is copied here rather than read where it is drawn.  A device that
; has stopped answering will not be answering later either, and the six bytes
; are its own account of the last command it saw.
; Clobbers A, X.
; ---------------------------------------------------------------------------

note_failure:
    inc leds_bad_lo
    bne @counted
    inc leds_bad_hi
@counted:
    lda rbcp_zp_5
    sta fail_stage
    lda rbcp_zp_0
    sta fail_group
    lda rbcp_zp_1
    sta fail_cmd
    lda rbcp_zp_2
    sta fail_sent_tok
    ldx #0
@byte:
    lda CONFIG_RBCP_BCH_BASE, x
    sta fail_hdr, x
    inx
    cpx #6
    bne @byte
    rts

; ---------------------------------------------------------------------------
; leds_mode_info — A = LED, X = mode.  Fills mode_takes_period and
; mode_min_period.
;
; A refusal is not an error worth showing — it means the LED does not have the
; mode, and a caller that asked anyway reads it the same way it reads a mode
; that takes no period.  Both come back as no period.
; ---------------------------------------------------------------------------

.export leds_mode_info
leds_mode_info:
    jsr display_dark
    jsr mode_info_body
    jmp display_light

mode_info_body:
    sta mode_led
    stx mode_num
    jsr try_start
@send:
    lda mode_led
    ldx mode_num
    jsr rbcp_cmd_get_led_mode_info
    bcs @fail
    lda RBCP_DATA_ADDR + RBCP_LED_MODE_FLAGS
    and #RBCP_LED_MODE_TAKES_PERIOD
    sta mode_takes_period
    lda RBCP_DATA_ADDR + RBCP_LED_MODE_MIN_PERIOD
    sta mode_min_period
    clc
    rts
@fail:
    lda rbcp_zp_5
    cmp #STAGE_REFUSED
    beq @none                   ; the LED does not have the mode
    jsr note_failure
    jsr try_again
    bcc @send
@none:
    lda #0
    sta mode_takes_period
    sta mode_min_period
    sec
    rts
