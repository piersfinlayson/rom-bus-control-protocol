; get_flash_slot_info.s — GET_FLASH_SLOT_INFO
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_get_flash_slot_info: A = flash slot.  One record, so a host with a
; back-channel too small for the whole list can still read every name, one
; command at a time.  The device needs 64 bytes of back-channel for this.
.export rbcp_cmd_get_flash_slot_info
rbcp_cmd_get_flash_slot_info:
    sta rbcp_arg0
    lda #RBCP_GRP_READ
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_FLASH_SLOT_INFO
    sta rbcp_zp_1
    lda #1
    jmp rbcp_issue_cmd
