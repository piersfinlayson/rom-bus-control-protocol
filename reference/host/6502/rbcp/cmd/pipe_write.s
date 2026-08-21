; pipe_write.s — PIPE_WRITE
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_pipe_write: A = count (1-4), X = pipe.
; Caller populates rbcp_arg0..rbcp_arg3 with the payload first — the arguments
; are the payload's home, so nothing is copied.
;
; All or nothing: on carry set the device took none of the bytes, so the caller
; resends the same ones rather than working out how far it got. Every value is
; legal in the payload, $AA included, because count is the final argument and
; its range excludes $AA.
.export rbcp_cmd_pipe_write
rbcp_cmd_pipe_write:
    sta rbcp_arg5           ; count
    stx rbcp_arg4           ; pipe
    lda #RBCP_GRP_PIPES
    sta rbcp_zp_0
    lda #RBCP_CMD_PIPE_WRITE
    sta rbcp_zp_1
    lda #6
    jmp rbcp_issue_cmd
