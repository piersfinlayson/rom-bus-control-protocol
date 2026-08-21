; load_slot.s — LOAD_SLOT
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_load_slot: A = RAM slot, X = flash slot.
.export rbcp_cmd_load_slot
rbcp_cmd_load_slot:
    sta rbcp_arg0
    stx rbcp_arg1
    lda #RBCP_GRP_MODIFY
    sta rbcp_zp_0
    lda #RBCP_CMD_LOAD_SLOT
    sta rbcp_zp_1
    lda #2
    jmp rbcp_issue_cmd
