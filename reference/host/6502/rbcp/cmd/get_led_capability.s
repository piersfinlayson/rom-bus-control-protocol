; get_led_capability.s — GET_LED_CAPABILITY
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_get_led_capability: no input.
; On success RBCP_DATA_ADDR + RBCP_LED_CAP_COUNT holds how many LEDs the device
; has, which is zero on a device with none, and + RBCP_LED_CAP_MAX_PERIOD and
; + RBCP_LED_CAP_MAX_HOLD the largest period and hold it accepts.
;
; This is also the version check.  The command takes no argument bytes, so a
; device implementing a protocol version without the LEDs group consumes
; nothing, fails it, and stays in step — carry set therefore means "no LEDs
; here" whether the device is old or merely has none, and both answers lead the
; caller to the same place.
.export rbcp_cmd_get_led_capability
rbcp_cmd_get_led_capability:
    lda #RBCP_GRP_LEDS
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_LED_CAPABILITY
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd
