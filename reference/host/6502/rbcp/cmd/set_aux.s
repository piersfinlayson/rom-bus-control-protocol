; set_aux.s — SET_AUX
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd_aux_poll

.code

; rbcp_cmd_set_aux — drives a pin.
; Caller sets: rbcp_arg0=state, rbcp_arg1=after, rbcp_arg2=hold,
; rbcp_arg3=pin, rbcp_arg4=group. Hold is in units of 10ms, zero to hold the
; state until something else changes it.
;
; Waits on CONFIG_RBCP_AUX_POLL_TIMEOUT rather than the ordinary poll, because
; a hold does not complete until it has elapsed and the device does not answer
; before then.
;
; What bounds the wait is the poll loop's two counter bytes, not the constant:
; about 0.86 seconds on a PAL C64 however large the constant is set, against
; the 2.55 seconds the protocol's hold argument can express. Ask for a longer
; hold than that and this reports failure through rbcp_zp_5 = 2 while the
; device carries on holding.
.export rbcp_cmd_set_aux
rbcp_cmd_set_aux:
    lda #RBCP_GRP_AUX
    sta rbcp_zp_0
    lda #RBCP_CMD_SET_AUX
    sta rbcp_zp_1
    lda #5
    jmp rbcp_issue_cmd_aux_poll
