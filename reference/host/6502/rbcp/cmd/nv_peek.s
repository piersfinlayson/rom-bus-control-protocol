; nv_peek.s — NV_PEEK
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; Caller sets: rbcp_arg0=count, rbcp_arg1=loc_LSB, rbcp_arg2=loc_MSB
.export rbcp_cmd_nv_peek
rbcp_cmd_nv_peek:
    lda #RBCP_GRP_NV
    sta rbcp_zp_0
    lda #RBCP_CMD_NV_PEEK
    sta rbcp_zp_1
    lda #3
    jmp rbcp_issue_cmd
