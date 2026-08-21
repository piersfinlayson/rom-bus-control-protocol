; get_pipe_info.s — GET_PIPE_INFO
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_get_pipe_info: A = pipe.
; On success RBCP_DATA_ADDR holds type, flags, free, waiting and far end — see
; the RBCP_PIPE_INFO_* offsets. free and waiting both saturate at $FF, so each
; carries a real count only near its limit.
;
; The pipe number is this command's final argument byte, where $AA is the reset
; marker, so sending it would desynchronise the session rather than being
; rejected. This refuses it here and sends nothing, reporting rbcp_zp_5 = 4.
.export rbcp_cmd_get_pipe_info
rbcp_cmd_get_pipe_info:
    cmp #$AA
    beq @refuse
    sta rbcp_arg0
    lda #RBCP_GRP_PIPES
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_PIPE_INFO
    sta rbcp_zp_1
    lda #1
    jmp rbcp_issue_cmd
@refuse:
    lda #4
    sta rbcp_zp_5
    sec
    rts
