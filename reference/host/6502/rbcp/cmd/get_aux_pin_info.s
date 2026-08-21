; get_aux_pin_info.s — GET_AUX_PIN_INFO
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_get_aux_pin_info: A = pin, X = group.
; On success RBCP_DATA_ADDR holds flags, level and driven — see the
; RBCP_AUX_PIN_* offsets. Level and driven mean nothing unless
; RBCP_AUX_FLAG_READABLE is set in flags.
;
; This is the one command here a caller issues in bulk: a host showing a whole
; group calls it once per pin, every refresh.
.export rbcp_cmd_get_aux_pin_info
rbcp_cmd_get_aux_pin_info:
    sta rbcp_arg0
    stx rbcp_arg1
    lda #RBCP_GRP_AUX
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_AUX_PIN_INFO
    sta rbcp_zp_1
    lda #2
    jmp rbcp_issue_cmd
