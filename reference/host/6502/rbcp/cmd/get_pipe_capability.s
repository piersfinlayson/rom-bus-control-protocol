; get_pipe_capability.s — GET_PIPE_CAPABILITY
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; ---------------------------------------------------------------------------
; Pipes — group $04
;
; A pipe runs from the host, through the device, to the pipe's far end, and
; carries the OUT direction, the IN direction or both. This library sends on a
; pipe and does not read from one. The host cannot observe the far end:
; PIPE_WRITE says only whether the bytes were taken, not that they arrived.
;
; No routine here waits or retries. A write that cannot be taken reports and
; returns, and the caller decides what to do about it — rbcp_zp_5 tells the two
; cases apart:
;   1 or 2 = the device did not answer, so retrying is pointless
;   3      = the pipe is full, so retrying may work once something drains it
;   4      = the library refused the arguments and sent nothing
;
; There is deliberately no routine for sending a whole string. The chunking
; loop belongs to the caller, which already holds the buffer and a pointer to
; it: putting it here would need library zero page that survives across
; rbcp_issue_cmd, and the ZP block ends at $100 with no room to grow.
; ---------------------------------------------------------------------------

; rbcp_cmd_get_pipe_capability: no input.
; On success RBCP_DATA_ADDR + RBCP_PIPE_CAP_COUNT holds the pipe count, which
; is zero on a device with no pipes.
;
; This is also the version check. The command takes no argument bytes, so a
; device implementing a protocol version without the Pipes group consumes
; nothing, fails it, and stays in step — carry set therefore means "no pipes
; here" whether the device is old or merely has none, and both answers lead the
; caller to the same place.
.export rbcp_cmd_get_pipe_capability
rbcp_cmd_get_pipe_capability:
    lda #RBCP_GRP_PIPES
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_PIPE_CAPABILITY
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd
