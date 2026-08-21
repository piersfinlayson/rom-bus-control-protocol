; get_aux_group_info.s — GET_AUX_GROUP_INFO
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_get_aux_group_info: A = group.
; On success RBCP_DATA_ADDR holds the group type and its pin count — see the
; RBCP_AUX_GROUP_* offsets. A pin count of zero means 256, and a group is never
; empty.
.export rbcp_cmd_get_aux_group_info
rbcp_cmd_get_aux_group_info:
    sta rbcp_arg0
    lda #RBCP_GRP_AUX
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_AUX_GROUP_INFO
    sta rbcp_zp_1
    lda #1
    jmp rbcp_issue_cmd
