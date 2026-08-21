; get_protocol_version.s — GET_PROTOCOL_VERSION
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

.export rbcp_cmd_get_protocol_version
rbcp_cmd_get_protocol_version:
    lda #RBCP_GRP_READ
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_PROTOCOL_VERSION
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd
