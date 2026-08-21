; get_aux_capability.s — GET_AUX_CAPABILITY
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; ---------------------------------------------------------------------------
; Auxiliary I/O — group $05
;
; Device pins the host can drive and read. The device does not know what is
; wired to one, so nothing here names a purpose: a pin is a group and a number,
; and what happens when it moves is the caller's business.
;
; Group and pin numbering is dense from zero and comes from the device, so a
; caller reads the group count from GET_AUX_CAPABILITY and matches groups on
; the type byte GET_AUX_GROUP_INFO returns. Group indices are not stable across
; boards: a board with no pins of some kind exposes one fewer group, and the
; groups after it move down.
;
; A pin's state outlives the session. Leaving command-response mode does not
; put a driven pin back, and neither does RBCP_RESET — only a device reset.
; ---------------------------------------------------------------------------

; rbcp_cmd_get_aux_capability: no input.
; On success RBCP_DATA_ADDR + RBCP_AUX_CAP_GROUPS holds the group count, which
; is zero on a device with no auxiliary pins, and + RBCP_AUX_CAP_MAX_HOLD the
; largest hold it will accept.
;
; This is also the version check. The command takes no argument bytes, so a
; device implementing a protocol version without the Auxiliary I/O group
; consumes nothing, fails it, and stays in step — carry set therefore means "no
; auxiliary pins here" whether the device is old or merely has none, and both
; answers lead the caller to the same place.
.export rbcp_cmd_get_aux_capability
rbcp_cmd_get_aux_capability:
    lda #RBCP_GRP_AUX
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_AUX_CAPABILITY
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd
