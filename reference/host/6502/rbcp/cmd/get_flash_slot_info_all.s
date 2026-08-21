; get_flash_slot_info_all.s — GET_FLASH_SLOT_INFO_ALL
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

.export rbcp_cmd_get_flash_slot_info_all
rbcp_cmd_get_flash_slot_info_all:
    lda #RBCP_GRP_READ
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_FLASH_SLOT_INFO_ALL
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd
