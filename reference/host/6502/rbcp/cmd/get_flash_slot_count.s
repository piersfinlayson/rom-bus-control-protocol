; get_flash_slot_count.s — GET_FLASH_SLOT_COUNT
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

.export rbcp_cmd_get_flash_slot_count
rbcp_cmd_get_flash_slot_count:
    lda #RBCP_GRP_READ
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_FLASH_SLOT_COUNT
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd
