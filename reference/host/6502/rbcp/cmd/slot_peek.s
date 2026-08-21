; slot_peek.s — SLOT_PEEK
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_slot_peek — reads bytes out of a RAM slot into the data section.
; Caller sets: rbcp_arg0=count, rbcp_arg1/2/3=24-bit slot offset (little-endian),
; rbcp_arg4=RAM slot.  A count of 0 means 256 bytes.
;
; The slot read need not be the active one, and an inactive slot is not visible
; to the host any other way — the back-channel only ever shows the active slot.
;
; On success the bytes are at RBCP_DATA_ADDR onwards, so the caller must have a
; data section at least as large as the count it asks for.
.export rbcp_cmd_slot_peek
rbcp_cmd_slot_peek:
    lda #RBCP_GRP_READ
    sta rbcp_zp_0
    lda #RBCP_CMD_SLOT_PEEK
    sta rbcp_zp_1
    lda #5
    jmp rbcp_issue_cmd
