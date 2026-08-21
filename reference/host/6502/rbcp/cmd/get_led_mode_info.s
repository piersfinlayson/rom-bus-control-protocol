; get_led_mode_info.s — GET_LED_MODE_INFO
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_get_led_mode_info: A = LED, X = mode.
; On success RBCP_DATA_ADDR + RBCP_LED_MODE_FLAGS says whether the mode takes a
; period on this LED, and + RBCP_LED_MODE_MIN_PERIOD the shortest it accepts.
;
; A caller naming no period of its own gets the mode's default and never needs
; this command.
;
; The LED number is this command's final argument byte, where $AA is the reset
; marker, so sending it would desynchronise the session rather than being
; rejected. This refuses it here and sends nothing, reporting rbcp_zp_5 = 4.
.export rbcp_cmd_get_led_mode_info
rbcp_cmd_get_led_mode_info:
    cmp #$AA
    beq @refuse
    sta rbcp_arg1
    stx rbcp_arg0
    lda #RBCP_GRP_LEDS
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_LED_MODE_INFO
    sta rbcp_zp_1
    lda #2
    jmp rbcp_issue_cmd
@refuse:
    lda #4
    sta rbcp_zp_5
    sec
    rts
