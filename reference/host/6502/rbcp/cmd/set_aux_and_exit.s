; set_aux_and_exit.s — SET_AUX_AND_EXIT
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_pause, rbcp_send_cmd

.code

; rbcp_cmd_set_aux_and_exit — as rbcp_cmd_set_aux, then leaves command-response
; mode. Arguments as rbcp_cmd_set_aux. Send only, no polling.
;
; Terminal: the device writes no response header, so there is nothing to poll
; and the caller must not try. It returns as soon as the bytes are out, which
; is before the device has finished holding — the caller owns the wait, and
; must not knock again until the hold has elapsed.
.export rbcp_cmd_set_aux_and_exit
rbcp_cmd_set_aux_and_exit:
    lda #RBCP_GRP_AUX
    sta rbcp_zp_0
    lda #RBCP_CMD_SET_AUX_AND_EXIT
    sta rbcp_zp_1
    lda #5
    jsr rbcp_send_cmd
    jmp rbcp_pause
