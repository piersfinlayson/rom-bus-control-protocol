; nv_poke_commit_byte.s — NV_POKE_COMMIT_BYTE
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd_long_poll

.code

; Caller sets: rbcp_arg0=byte, rbcp_arg1=loc_LSB, rbcp_arg2=loc_MSB, rbcp_arg3=RAM slot
.export rbcp_cmd_nv_poke_commit_byte
rbcp_cmd_nv_poke_commit_byte:
    lda #RBCP_GRP_NV
    sta rbcp_zp_0
    lda #RBCP_CMD_NV_POKE_COMMIT_BYTE
    sta rbcp_zp_1
    lda #4
    jmp rbcp_issue_cmd_long_poll
