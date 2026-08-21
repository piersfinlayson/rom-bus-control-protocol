; rbcp_core.s — RBCP protocol library, framing and session
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

; No C64-specific references. All addresses come from rbcp_defs.s.
;
; All code is in the CODE segment (post-relocation, runs from RAM).
;
; Library layout
; --------------
; This file holds what every host needs: the knock, command framing, the
; polling of the back-channel, the reset sequence and the pause.  Each command
; is a module of its own under cmd/, and the whole lot is built into rbcp.lib
; with ar65.  The linker takes a module out of a library only where something
; refers to it, so a host links the commands it calls and nothing else.  A
; command a host does not call costs it nothing, and no configuration says so.
;
; RBCP_READ macro
; ---------------
; Issues one ROM address read encoding byte_val on A0-A7. For compile-time
; constant values the macro generates a plain LDA absolute. For runtime values
; rbcp_send_cmd uses self-modification: the byte value is stored into the low
; byte of the LDA absolute operand, then the instruction is executed. This
; works because post-relocation all code runs from RAM.
;
; Self-modification detail
; ------------------------
; LDA absolute = $AD <lo> <hi>. At the patch site the instruction is assembled
; as LDA $E000 ($AD $00 $E0). At runtime: STA patch+1 writes the desired byte
; into the lo byte, giving LDA $E0XX, which reads from the ROM address that
; encodes XX on A0-A7. The value read is discarded.

.include "rbcp_defs.s"

; Check the configuration values for validity
.assert CONFIG_RBCP_CMD_PAGE >= CONFIG_ROM_BASE_HI, error, "The command page must be within the ROM space"
.assert CONFIG_RBCP_BCH_BASE >= CONFIG_ROM_BASE_HI * $100, error, "The back-channel region must be within the ROM space"
.assert (CONFIG_RBCP_BCH_START >= (CONFIG_RBCP_CMD_PAGE_REL + 1) * $100) .or (CONFIG_RBCP_BCH_START + CONFIG_RBCP_BCH_SIZE <= CONFIG_RBCP_CMD_PAGE_REL * $100), error, "The back-channel region must not overlap with the command page"
.assert CONFIG_RBCP_BCH_START + CONFIG_RBCP_BCH_SIZE <= CONFIG_ROM_SIZE, error, "The back-channel region must fit within the ROM image size"

; RBCP_READ — compile-time constant only. No leading '(' or ca65 sees indirect.
.macro RBCP_READ byte_val
    lda RBCP_CMD_HI * $100 + (byte_val & $FF)
.endmacro

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; rbcp_knock — sends "!RBCP!" as 6 ROM address reads. Clobbers: A.
; ---------------------------------------------------------------------------

.export rbcp_knock
rbcp_knock:
    RBCP_READ RBCP_KNOCK_0
    RBCP_READ RBCP_KNOCK_1
    RBCP_READ RBCP_KNOCK_2
    RBCP_READ RBCP_KNOCK_3
    RBCP_READ RBCP_KNOCK_4
    RBCP_READ RBCP_KNOCK_5
    rts

; ---------------------------------------------------------------------------
; rbcp_send_cmd
; Sends GROUP, CMD, and argument bytes as ROM address reads.
;
; Caller sets before JSR:
;   rbcp_zp_0   = GROUP byte
;   rbcp_zp_1   = CMD byte
;   A           = argument count (0-9)
;   rbcp_arg0..rbcp_arg8 populated as needed
;
; Nine is the protocol's maximum for any command (ENTER_CMD_RESP), and is the
; size of the argument buffer in rbcp_defs.s.
;
; Clobbers: A, X
; ---------------------------------------------------------------------------

.export rbcp_send_cmd
rbcp_send_cmd:
    sta rbcp_zp_4           ; save argument count

    lda rbcp_zp_0
    sta rbcp_sm_group+1
rbcp_sm_group:
    lda RBCP_CMD_HI * $100 ; GROUP — lo byte patched above

    lda rbcp_zp_1
    sta rbcp_sm_cmd+1
rbcp_sm_cmd:
    lda RBCP_CMD_HI * $100 ; CMD — lo byte patched above

    lda rbcp_zp_4
    beq rbcp_send_done
    tax
    ldy #0
rbcp_send_arg_loop:
    lda rbcp_arg0, y
    sta rbcp_sm_arg+1
rbcp_sm_arg:
    lda RBCP_CMD_HI * $100 ; ARG — lo byte patched above
    iny
    dex
    bne rbcp_send_arg_loop

rbcp_send_done:
    rts

; ---------------------------------------------------------------------------
; rbcp_save_token — saves token LSB to rbcp_zp_2. Clobbers: A.
; ---------------------------------------------------------------------------

.export rbcp_save_token
rbcp_save_token:
    lda RBCP_TOKEN_LSB_ADDR
    sta rbcp_zp_2
    rts

; ---------------------------------------------------------------------------
; rbcp_poll_token — polls until token LSB differs from rbcp_zp_2.
; Returns carry clear = success, carry set = timeout. Clobbers: A, X.
; ---------------------------------------------------------------------------

.export rbcp_poll_token
rbcp_poll_token:
.if RBCP_POLL_TIMEOUT > 0
    ldx #<RBCP_POLL_TIMEOUT
.endif
rbcp_pt_loop:
    lda RBCP_TOKEN_LSB_ADDR
    cmp rbcp_zp_2
    bne rbcp_pt_ok
.if RBCP_POLL_TIMEOUT > 0
    dex
    bne rbcp_pt_loop
    sec
    rts
.else
    jmp rbcp_pt_loop
.endif
rbcp_pt_ok:
    clc
    rts

; ---------------------------------------------------------------------------
; rbcp_poll_progress — polls until progress = RBCP_COMPLETE.
; Returns carry clear = success, carry set = timeout. Clobbers: A, X.
; ---------------------------------------------------------------------------

.export rbcp_poll_progress
rbcp_poll_progress:
.if RBCP_POLL_TIMEOUT > 0
    ldx #<RBCP_POLL_TIMEOUT
.endif
rbcp_pp_loop:
    lda RBCP_PROGRESS_ADDR
    cmp #RBCP_COMPLETE
    beq rbcp_pp_ok
.if RBCP_POLL_TIMEOUT > 0
    jsr rbcp_pause   ; Add a delay between polls
    dex
    bne rbcp_pp_loop
    sec
    rts
.else
    jmp rbcp_pp_loop
.endif
rbcp_pp_ok:
    clc
    rts

.export rbcp_poll_progress_long
rbcp_poll_progress_long:
.if RBCP_NV_POLL_TIMEOUT > 0
    ldx #<RBCP_NV_POLL_TIMEOUT
    ldy #>RBCP_NV_POLL_TIMEOUT
    jmp rbcp_ppl_timed
.else
    jmp rbcp_ppl_forever
.endif

; rbcp_poll_progress_aux — as rbcp_poll_progress_long, on its own timeout.
.export rbcp_poll_progress_aux
rbcp_poll_progress_aux:
.if RBCP_AUX_POLL_TIMEOUT > 0
    ldx #<RBCP_AUX_POLL_TIMEOUT
    ldy #>RBCP_AUX_POLL_TIMEOUT
    jmp rbcp_ppl_timed
.else
    jmp rbcp_ppl_forever
.endif

; The two loops both long polls share.  X and Y are the countdown, so the
; longest wait either can express is 256 * 255 iterations of about 13 cycles —
; roughly 0.86 seconds on a PAL C64, whatever its constant is set to.
rbcp_ppl_timed:
    lda RBCP_PROGRESS_ADDR
    cmp #RBCP_COMPLETE
    beq rbcp_ppl_ok
    dex
    bne rbcp_ppl_timed
    dey
    bne rbcp_ppl_timed
    sec
    rts

rbcp_ppl_forever:
    lda RBCP_PROGRESS_ADDR
    cmp #RBCP_COMPLETE
    bne rbcp_ppl_forever
rbcp_ppl_ok:
    clc
    rts

; ---------------------------------------------------------------------------
; rbcp_check_response — carry clear if RBCP_STATUS_OK, set otherwise.
; Clobbers: A.
; ---------------------------------------------------------------------------

.export rbcp_check_response
rbcp_check_response:
    lda RBCP_RESPONSE_ADDR
    cmp #RBCP_STATUS_OK
    beq rbcp_cr_ok
    sec
    rts
rbcp_cr_ok:
    clc
    rts

; ---------------------------------------------------------------------------
; rbcp_issue_cmd — save_token → send_cmd → poll_token → poll_progress
;                  → check_response.
; Returns carry clear = success, carry set = failure. Clobbers: A, X, Y.
; Takes rbcp_zp_3 = 0 for normal progress poll, 1 for rbcp_poll_progress_long.
; ---------------------------------------------------------------------------
; On failure, rbcp_zp_5 holds the stage that failed:
;   1 = token poll timeout (command not received)
;   2 = progress poll timeout (received but never completed)
;   3 = response = FAILED

.export rbcp_issue_cmd_long_poll
rbcp_issue_cmd_long_poll:
    tax
    lda #1
    sta rbcp_zp_3
    txa
    jmp rbcp_issue_cmd_body

; rbcp_issue_cmd_aux_poll: as rbcp_issue_cmd, waiting on RBCP_AUX_POLL_TIMEOUT.
.export rbcp_issue_cmd_aux_poll
rbcp_issue_cmd_aux_poll:
    tax
    lda #2
    sta rbcp_zp_3
    txa
    jmp rbcp_issue_cmd_body

.export rbcp_issue_cmd
rbcp_issue_cmd:
    tax
    lda #0
    sta rbcp_zp_3
    txa

rbcp_issue_cmd_body:
    sta rbcp_zp_4
    lda #$FF
    sta rbcp_zp_5

.if RBCP_TIMEOUT_RETRIES > 0
    lda #RBCP_TIMEOUT_RETRIES
    sta rbcp_zp_6
.endif
@tok_attempt:
    jsr rbcp_save_token
    lda rbcp_zp_4
    jsr rbcp_send_cmd
    jsr rbcp_poll_token
    bcc @tok_ok
.if RBCP_TIMEOUT_RETRIES > 0
    dec rbcp_zp_6
    bpl @tok_attempt
.endif
    lda #1
    jmp @err
@tok_ok:
    lda rbcp_zp_3
    beq @short_poll
    cmp #2
    beq @aux_poll
    jsr rbcp_poll_progress_long
    jmp @poll_done
@aux_poll:
    jsr rbcp_poll_progress_aux
@poll_done:
    bcs @prog_fail
    bcc @prog_ok
@short_poll:
    jsr rbcp_poll_progress
    bcc @prog_ok
@prog_fail:
    lda #2
    jmp @err
@prog_ok:
    jsr rbcp_check_response
    bcc @rsp_ok
    lda #3
@err:
    sta rbcp_zp_5
    sec
    rts
@rsp_ok:
    clc
    rts



; ---------------------------------------------------------------------------
; Command helpers
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; rbcp_reset — issues the full RBCP reset sequence:
;   Stage 1: 5 × RBCP_RESET, no knock — flushes any partially-received
;            command (max 9 arg bytes + 2 framing bytes) and triggers
;            execution of whatever command was in progress.
;   pause  — allows that command to complete.
;   Stage 2: 1 × RBCP_RESET, no knock — resets the now-idle device.
;   pause  — allows reset to complete.
;   Stage 3: knock + 1 × RBCP_RESET — resets the device if it was in
;            command-response mode, where a knock is required to re-
;            establish framing before a reset is recognised.
;   pause  — allows reset to complete.
; Clobbers: A, X, Y.
; ---------------------------------------------------------------------------
.export rbcp_reset
rbcp_reset:
    jsr rbcp_reset_stage_1
    jsr rbcp_pause
    jsr rbcp_reset_stage_2
    jsr rbcp_pause
    jsr rbcp_reset_stage_3
    jsr rbcp_pause
    rts

rbcp_cmd_reset:
    lda #RBCP_GRP_RESET
    sta rbcp_zp_0
    lda #RBCP_CMD_RESET
    sta rbcp_zp_1
    lda #0
    jmp rbcp_send_cmd

.export rbcp_reset_stage_1
rbcp_reset_stage_1:
    ldy #5
@loop:
    jsr rbcp_cmd_reset
    dey
    bne @loop
    rts

.export rbcp_reset_stage_2
rbcp_reset_stage_2:
    jsr rbcp_cmd_reset
    rts

.export rbcp_reset_stage_3
rbcp_reset_stage_3:
    jsr rbcp_knock
    jsr rbcp_cmd_reset
    rts


; The pause every command mode send needs, and the send after a terminal
; command, where there is no back-channel to say when the device is ready.
.export rbcp_pause
rbcp_pause:
    stx rbcp_zp_3
    ldx #CONFIG_RBCP_CMD_PAUSE
@pause_loop:
    dex
    bne @pause_loop
    ldx rbcp_zp_3
    rts
