; rbcp.s — RBCP protocol library
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

; No C64-specific references. All addresses come from rbcp_defs.s.
;
; All code is in the CODE segment (post-relocation, runs from RAM).
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
;   A           = argument count (0-5)
;   rbcp_arg0..rbcp_arg4 populated as needed
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
; ---------------------------------------------------------------------------
; On failure, rbcp_zp_5 holds the stage that failed:
;   1 = token poll timeout (command not received)
;   2 = progress poll timeout (received but never completed)
;   3 = response = FAILED
.export rbcp_issue_cmd
rbcp_issue_cmd:
    tay
    jsr rbcp_save_token
    tya
    jsr rbcp_send_cmd
    jsr rbcp_poll_token
    bcc @tok_ok
    lda #1
    sta rbcp_zp_5
    sec
    rts
@tok_ok:
    jsr rbcp_poll_progress
    bcc @prog_ok
    lda #2
    sta rbcp_zp_5
    sec
    rts
@prog_ok:
    jsr rbcp_check_response
    bcc @rsp_ok
    lda #3
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
; The spec defines a reset sequence as being:
; - 4 x resets (no knock)
; - pause
; - 1 x knock
; - 1 x reset
; - pause
;
; Two different methods are provided for each stage so the host can decide
; what pause to include between them (as it depends on clock speed, etc.).
; ---------------------------------------------------------------------------
rbcp_cmd_reset:
    lda #RBCP_GRP_RESET
    sta rbcp_zp_0
    lda #RBCP_CMD_RESET
    sta rbcp_zp_1
    lda #0
    jmp rbcp_send_cmd

.export rbcp_reset_stage_1
rbcp_reset_stage_1:
    jsr rbcp_cmd_reset
    jsr rbcp_cmd_reset
    jsr rbcp_cmd_reset
    jsr rbcp_cmd_reset
    rts

.export rbcp_reset_stage_2
rbcp_reset_stage_2:
    jsr rbcp_knock
    jsr rbcp_cmd_reset
    rts

; ---------------------------------------------------------------------------
; This is more complex than the other commands because it needs to first
; confirm the back channel is live by polling for pending/complete.
; A0 = location, A1 = size_id (caller sets rbcp_arg0/1).
; ---------------------------------------------------------------------------
.export rbcp_cmd_config_and_enter_cmd_resp
rbcp_cmd_config_and_enter_cmd_resp:
    lda #RBCP_GRP_CTRL
    sta rbcp_zp_0
    lda #RBCP_CMD_CONFIG_AND_ENTER_CMD_RESP
    sta rbcp_zp_1
    lda #RBCP_COMPLETE
    sta rbcp_arg2
    lda #RBCP_STATUS_OK
    sta rbcp_arg3
    lda #4
    jsr rbcp_send_cmd

    ; Poll progress until pending or complete — confirms back channel is live
.if RBCP_POLL_TIMEOUT > 0
    ldx #<RBCP_POLL_TIMEOUT
.endif
@poll_active:
    lda RBCP_PROGRESS_ADDR
    cmp #RBCP_PENDING
    beq @poll_complete
    cmp #RBCP_COMPLETE
    beq @check_response
.if RBCP_POLL_TIMEOUT > 0
    dex
    bne @poll_active
    sec
    rts
.else
    jmp @poll_active
.endif

@poll_complete:
    jsr rbcp_poll_progress
    bcs @fail

@check_response:
    jsr rbcp_check_response
    rts

@fail:
    sec
    rts

.export rbcp_cmd_get_ram_slot_info_all
rbcp_cmd_get_ram_slot_info_all:
    lda #RBCP_GRP_READ
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_RAM_SLOT_INFO_ALL
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd

.export rbcp_cmd_get_flash_slot_info_all
rbcp_cmd_get_flash_slot_info_all:
    lda #RBCP_GRP_READ
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_FLASH_SLOT_INFO_ALL
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd

; rbcp_cmd_load_slot: A = RAM slot, X = flash slot.
.export rbcp_cmd_load_slot
rbcp_cmd_load_slot:
    sta rbcp_arg0
    stx rbcp_arg1
    lda #RBCP_GRP_MODIFY
    sta rbcp_zp_0
    lda #RBCP_CMD_LOAD_SLOT
    sta rbcp_zp_1
    lda #2
    jmp rbcp_issue_cmd

; rbcp_cmd_switch_and_exit: A = RAM slot. Send only, no polling.
.export rbcp_cmd_switch_and_exit
rbcp_cmd_switch_and_exit:
    sta rbcp_arg0
    lda #RBCP_GRP_CTRL
    sta rbcp_zp_0
    lda #RBCP_CMD_SWITCH_AND_EXIT
    sta rbcp_zp_1
    lda #1
    jmp rbcp_send_cmd

.export rbcp_cmd_get_device_type
rbcp_cmd_get_device_type:
    lda #RBCP_GRP_READ
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_DEVICE_TYPE
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd

.export rbcp_cmd_get_device_version
rbcp_cmd_get_device_version:
    lda #RBCP_GRP_READ
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_DEVICE_VERSION
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd