; set_aux_switch_exit.s — SET_AUX_SWITCH_EXIT
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_pause, rbcp_send_cmd

.code

; rbcp_cmd_set_aux_switch_exit — drives a pin and activates a RAM slot, then
; leaves command-response mode. Send only, no polling.
; Caller sets: rbcp_arg0=state, rbcp_arg1=after, rbcp_arg2=hold,
; rbcp_arg3=flags, rbcp_arg4=pin, rbcp_arg5=group, rbcp_arg6=slot.
;
; Flags picks the order — RBCP_AUX_PIN_FIRST or RBCP_AUX_SLOT_FIRST. Pin first
; is what a caller wants when the pin stops the host: the machine is held while
; the image underneath it changes. Under that ordering the device does not
; apply after until the switch is done, so the hold is at least as long as the
; switch takes however small a hold was asked for.
;
; Terminal, and returns before the device has finished, as
; rbcp_cmd_set_aux_and_exit does. Anything that must follow a slot switch has
; to be in the same command as the switch, which is what this command is for:
; after a switch the caller can rely on neither the new image having a
; back-channel region nor the observed addresses being unchanged.
.export rbcp_cmd_set_aux_switch_exit
rbcp_cmd_set_aux_switch_exit:
    lda #RBCP_GRP_AUX
    sta rbcp_zp_0
    lda #RBCP_CMD_SET_AUX_SWITCH_EXIT
    sta rbcp_zp_1
    lda #7
    jsr rbcp_send_cmd
    jmp rbcp_pause
