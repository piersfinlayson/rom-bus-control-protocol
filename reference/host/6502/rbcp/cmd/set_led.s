; set_led.s — SET_LED
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_set_led: A = LED.
; Caller sets first: rbcp_arg0=mode, rbcp_arg1=red, rbcp_arg2=green,
; rbcp_arg3=blue, rbcp_arg4=brightness, rbcp_arg5=period, rbcp_arg6=hold.
;
; A colour of three zeroes leaves the choice to the device, as does a
; brightness of zero and a period of zero.  A mode that takes no colour ignores
; one, as does an LED with no colour to set.  A hold of zero leaves the mode in
; force until something changes it.
;
; The device does not wait out the hold before answering, and the hold outlives
; the session, so a caller may set a mode and leave.
;
; The LED number is this command's final argument byte, where $AA is the reset
; marker, so sending it would desynchronise the session rather than being
; rejected. This refuses it here and sends nothing, reporting rbcp_zp_5 = 4.
.export rbcp_cmd_set_led
rbcp_cmd_set_led:
    cmp #$AA
    beq @refuse
    sta rbcp_arg7
    lda #RBCP_GRP_LEDS
    sta rbcp_zp_0
    lda #RBCP_CMD_SET_LED
    sta rbcp_zp_1
    lda #8
    jmp rbcp_issue_cmd
@refuse:
    lda #4
    sta rbcp_zp_5
    sec
    rts
