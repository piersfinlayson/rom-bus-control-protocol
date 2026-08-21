; get_device_type.s — GET_DEVICE_TYPE
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

.export rbcp_cmd_get_device_type
rbcp_cmd_get_device_type:
    lda #RBCP_GRP_READ
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_DEVICE_TYPE
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd
