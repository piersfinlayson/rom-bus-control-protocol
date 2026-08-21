; get_nv_capability.s — GET_NV_CAPABILITY
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

.export rbcp_cmd_get_nv_capability
rbcp_cmd_get_nv_capability:
    lda #RBCP_GRP_NV
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_NV_CAPABILITY
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd
