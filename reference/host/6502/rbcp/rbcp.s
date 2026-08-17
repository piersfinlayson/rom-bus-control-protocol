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
    jsr pause   ; Add a delay between polls
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
    jsr pause
    jsr rbcp_reset_stage_2
    jsr pause
    jsr rbcp_reset_stage_3
    jsr pause
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
    jsr rbcp_send_cmd
    jsr pause
    rts

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

.export rbcp_cmd_get_protocol_version
rbcp_cmd_get_protocol_version:
    lda #RBCP_GRP_READ
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_PROTOCOL_VERSION
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd

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

; ---------------------------------------------------------------------------
; Pipes — group $04
;
; A pipe carries bytes from the host out through the device, to whatever the
; device has at the far end. The host cannot observe that end: PIPE_WRITE says
; only whether the bytes were taken.
;
; No routine here waits or retries. A write that cannot be taken reports and
; returns, and the caller decides what to do about it — rbcp_zp_5 tells the two
; cases apart:
;   1 or 2 = the device did not answer, so retrying is pointless
;   3      = the pipe is full, so retrying may work once something drains it
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

; rbcp_cmd_get_pipe_info: A = pipe.
; On success RBCP_DATA_ADDR holds type, flags and free — see the
; RBCP_PIPE_INFO_* offsets. free saturates at $FF, so it only carries a real
; count once the pipe is nearly full.
.export rbcp_cmd_get_pipe_info
rbcp_cmd_get_pipe_info:
    sta rbcp_arg0
    lda #RBCP_GRP_PIPES
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_PIPE_INFO
    sta rbcp_zp_1
    lda #1
    jmp rbcp_issue_cmd

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

; rbcp_cmd_get_aux_group_info: A = group.
; On success RBCP_DATA_ADDR holds the group type and its pin count — see the
; RBCP_AUX_GROUP_* offsets. A pin count of zero means 256, and a group is never
; empty.
.export rbcp_cmd_get_aux_group_info
rbcp_cmd_get_aux_group_info:
    sta rbcp_arg0
    lda #RBCP_GRP_AUX
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_AUX_GROUP_INFO
    sta rbcp_zp_1
    lda #1
    jmp rbcp_issue_cmd

; rbcp_cmd_get_aux_pin_info: A = pin, X = group.
; On success RBCP_DATA_ADDR holds flags, level and driven — see the
; RBCP_AUX_PIN_* offsets. Level and driven mean nothing unless
; RBCP_AUX_FLAG_READABLE is set in flags.
;
; This is the one command here a caller issues in bulk: a host showing a whole
; group calls it once per pin, every refresh.
.export rbcp_cmd_get_aux_pin_info
rbcp_cmd_get_aux_pin_info:
    sta rbcp_arg0
    stx rbcp_arg1
    lda #RBCP_GRP_AUX
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_AUX_PIN_INFO
    sta rbcp_zp_1
    lda #2
    jmp rbcp_issue_cmd

; rbcp_cmd_set_aux — drives a pin.
; Caller sets: rbcp_arg0=state, rbcp_arg1=after, rbcp_arg2=hold,
; rbcp_arg3=pin, rbcp_arg4=group. Hold is in units of 10ms, zero to hold the
; state until something else changes it.
;
; Waits on CONFIG_RBCP_AUX_POLL_TIMEOUT rather than the ordinary poll, because
; a hold does not complete until it has elapsed and the device does not answer
; before then.
;
; What bounds the wait is the poll loop's two counter bytes, not the constant:
; about 0.86 seconds on a PAL C64 however large the constant is set, against
; the 2.55 seconds the protocol's hold argument can express. Ask for a longer
; hold than that and this reports failure through rbcp_zp_5 = 2 while the
; device carries on holding.
.export rbcp_cmd_set_aux
rbcp_cmd_set_aux:
    lda #RBCP_GRP_AUX
    sta rbcp_zp_0
    lda #RBCP_CMD_SET_AUX
    sta rbcp_zp_1
    lda #5
    jmp rbcp_issue_cmd_aux_poll

; rbcp_cmd_set_aux_and_exit — as rbcp_cmd_set_aux, then leaves command-response
; mode. Arguments as rbcp_cmd_set_aux. Send only, no polling.
;
; Terminal: the device writes no response header, so there is nothing to poll
; and the caller must not try. It returns as soon as the bytes are out, which
; is before the device has finished holding — the caller owns the wait, and
; must not knock again until the hold has elapsed.
.export rbcp_cmd_set_aux_and_exit
rbcp_cmd_set_aux_and_exit:
    lda #RBCP_GRP_AUX
    sta rbcp_zp_0
    lda #RBCP_CMD_SET_AUX_AND_EXIT
    sta rbcp_zp_1
    lda #5
    jsr rbcp_send_cmd
    jmp pause

; rbcp_cmd_set_aux_switch_exit — drives a pin and activates a RAM slot, then
; leaves command-response mode. Send only, no polling.
; Caller sets: rbcp_arg0=state, rbcp_arg1=after, rbcp_arg2=hold,
; rbcp_arg3=flags, rbcp_arg4=pin, rbcp_arg5=group, rbcp_arg6=slot.
;
; Flags picks the order — RBCP_AUX_PIN_FIRST or RBCP_AUX_SLOT_FIRST. Pin first
; is what a caller wants when the pin stops the host: the machine is held while
; the image underneath it changes. Under that ordering the device does not
; apply after until the switch is done, so the hold is at least as long as the
; switch takes however small a hold was asked for.
;
; Terminal, and returns before the device has finished, as
; rbcp_cmd_set_aux_and_exit does. Anything that must follow a slot switch has
; to be in the same command as the switch, which is what this command is for:
; after a switch the caller can rely on neither the new image having a
; back-channel region nor the observed addresses being unchanged.
.export rbcp_cmd_set_aux_switch_exit
rbcp_cmd_set_aux_switch_exit:
    lda #RBCP_GRP_AUX
    sta rbcp_zp_0
    lda #RBCP_CMD_SET_AUX_SWITCH_EXIT
    sta rbcp_zp_1
    lda #7
    jsr rbcp_send_cmd
    jmp pause

.export rbcp_check_protocol_version
.export rbcp_check_protocol_version_min

; rbcp_check_protocol_version: checks host's RBCP implementation version
; against this library's supported version.
; Output: carry clear = compatible, carry set = incompatible
rbcp_check_protocol_version:
    lda #RBCP_SUPPORTED_PROTOCOL_MAJOR
    sta rbcp_arg0
    lda #RBCP_SUPPORTED_PROTOCOL_MINOR
    sta rbcp_arg1
    lda #RBCP_SUPPORTED_PROTOCOL_PATCH
    sta rbcp_arg2
    ; fall through

; rbcp_check_protocol_version_min: checks hosts' RBCP implemenation verrsion
; against caller-supplied minimum
; Input: rbcp_arg0 = minimum major, rbcp_arg1 = minimum minor, rbcp_arg2 = minimum patch
; Output: carry clear = compatible, carry set = incompatible
rbcp_check_protocol_version_min:
    jsr rbcp_cmd_get_protocol_version
    bcs @fail

    lda RBCP_DATA_ADDR + 0      ; major must match exactly
    cmp rbcp_arg0
    bne @fail

    lda rbcp_arg0               ; which rule set?
    bne @major_nonzero

    ; major == 0: minor exact, patch >=
    lda RBCP_DATA_ADDR + 1
    cmp rbcp_arg1
    bne @fail
    lda RBCP_DATA_ADDR + 2
    cmp rbcp_arg2
    bcc @fail
    clc
    rts

@major_nonzero:
    lda RBCP_DATA_ADDR + 1      ; device minor >= expected minor
    cmp rbcp_arg1
    bcc @fail
    bne @ok                     ; device minor > expected, patch irrelevant
    lda RBCP_DATA_ADDR + 2      ; minor equal, check patch >=
    cmp rbcp_arg2
    bcc @fail
@ok:
    clc
    rts
@fail:
    sec
    rts

pause:
    stx rbcp_zp_3
    ldx #CONFIG_RBCP_CMD_PAUSE
@pause_loop:
    dex
    bne @pause_loop
    ldx rbcp_zp_3
    rts

.export rbcp_cmd_get_nv_capability
rbcp_cmd_get_nv_capability:
    lda #RBCP_GRP_NV
    sta rbcp_zp_0
    lda #RBCP_CMD_GET_NV_CAPABILITY
    sta rbcp_zp_1
    lda #0
    jmp rbcp_issue_cmd

; Caller sets: rbcp_arg0=count, rbcp_arg1=loc_LSB, rbcp_arg2=loc_MSB
.export rbcp_cmd_nv_peek
rbcp_cmd_nv_peek:
    lda #RBCP_GRP_NV
    sta rbcp_zp_0
    lda #RBCP_CMD_NV_PEEK
    sta rbcp_zp_1
    lda #3
    jmp rbcp_issue_cmd

; Caller sets: rbcp_arg0=byte, rbcp_arg1=loc_LSB, rbcp_arg2=loc_MSB, rbcp_arg3=RAM slot
.export rbcp_cmd_nv_poke_commit_byte
rbcp_cmd_nv_poke_commit_byte:
    lda #RBCP_GRP_NV
    sta rbcp_zp_0
    lda #RBCP_CMD_NV_POKE_COMMIT_BYTE
    sta rbcp_zp_1
    lda #4
    jmp rbcp_issue_cmd_long_poll