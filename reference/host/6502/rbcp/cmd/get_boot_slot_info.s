; get_boot_slot_info.s — GET_BOOT_SLOT_INFO
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_get_boot_slot_info: no input.
; On success RBCP_DATA_ADDR + RBCP_BOOT_SLOT_INFO_FLASH holds the flash slot
; the device loaded at boot, and + RBCP_BOOT_SLOT_INFO_RAM the RAM slot it went
; into. Either is $FF where the device loaded none or does not know.
;
; Since protocol 0.1.2. It takes no argument bytes, so an older device fails it
; and the session stays in step.
.export rbcp_cmd_get_boot_slot_info
rbcp_cmd_get_boot_slot_info:
    lda #RBCP_GRP_READ
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_BOOT_SLOT_INFO
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd
