; get_led_info.s — GET_LED_INFO
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_get_led_info: A = LED.
; On success RBCP_DATA_ADDR holds the type, the mode in force, the colour, the
; brightness and the period — see the RBCP_LED_INFO_* offsets — and
; + RBCP_LED_INFO_MODES a bit per mode the LED supports.
;
; The type is what a caller wanting a colour reads: LEDs are numbered per
; device, so the lowest-numbered RGB one is found rather than assumed.
;
; The LED number is this command's final argument byte, where $AA is the reset
; marker, so sending it would desynchronise the session rather than being
; rejected. This refuses it here and sends nothing, reporting rbcp_zp_5 = 4.
.export rbcp_cmd_get_led_info
rbcp_cmd_get_led_info:
    cmp #$AA
    beq @refuse
    sta rbcp_arg0
    lda #RBCP_GRP_LEDS
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_LED_INFO
    sta rbcp_zp_1
    lda #1
    jmp rbcp_issue_cmd
@refuse:
    lda #4
    sta rbcp_zp_5
    sec
    rts
