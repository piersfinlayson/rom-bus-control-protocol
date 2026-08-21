; enter_cmd_resp.s — ENTER_CMD_RESP
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_check_response, rbcp_knock, rbcp_poll_progress, rbcp_poll_token, rbcp_save_token, rbcp_send_cmd

.code

; ---------------------------------------------------------------------------
; rbcp_cmd_enter_cmd_resp — issues ENTER_CMD_RESP with a preceding knock.
;
; This function sets the arguments based on the rbcp_config.s configuration.
;
; If the token LSB does not increment within the poll timeout the command
; was silently discarded by the device (e.g. misaligned address, out-of-range
; command page, or prohibited complete/status-OK value) and command-response
; mode has not been entered.
;
; On failure, rbcp_zp_5 holds the stage that failed:
;   1 = token poll timeout (command not received / silently discarded)
;   2 = progress poll timeout (received but never completed)
;   3 = response = FAILED
; Returns carry clear = success, carry set = failure. Clobbers: A, X, Y.
; ---------------------------------------------------------------------------
.export rbcp_cmd_enter_cmd_resp
rbcp_cmd_enter_cmd_resp:
    lda #$FF
    sta rbcp_zp_5           ; clear error code

    lda #RBCP_GRP_CTRL
    sta rbcp_zp_0
    lda #RBCP_CMD_ENTER_CMD_RESP
    sta rbcp_zp_1

    lda #CONFIG_RBCP_CMD_PAGE_REL
    sta rbcp_arg0
    lda #0
    sta rbcp_arg1
    lda #<CONFIG_RBCP_BCH_START
    sta rbcp_arg2
    lda #>CONFIG_RBCP_BCH_START
    sta rbcp_arg3
    lda #0
    sta rbcp_arg4
    lda #<CONFIG_RBCP_BCH_SIZE
    sta rbcp_arg5
    lda #>CONFIG_RBCP_BCH_SIZE
    sta rbcp_arg6
    lda #RBCP_COMPLETE
    sta rbcp_arg7
    lda #RBCP_STATUS_OK
    sta rbcp_arg8

.if RBCP_TIMEOUT_RETRIES > 0
    lda #RBCP_TIMEOUT_RETRIES
    sta rbcp_zp_6
.endif
@tok_attempt:
    jsr rbcp_save_token
    jsr rbcp_knock
    lda #9
    jsr rbcp_send_cmd
    jsr rbcp_poll_token
    bcc @tok_ok
.if RBCP_TIMEOUT_RETRIES > 0
    dec rbcp_zp_6
    bpl @tok_attempt
.endif
    lda #1
    jmp @fail
@tok_ok:
    jsr rbcp_poll_progress
    bcc @prog_ok
    lda #2
    jmp @fail
@prog_ok:
    jsr rbcp_check_response
    bcc @ok
    lda #3
@fail:
    sta rbcp_zp_5
    sec
    rts
@ok:
    clc
    rts
