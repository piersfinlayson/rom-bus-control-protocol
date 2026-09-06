; send_tuned.s — TUNED4, the hand-tuned send path
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; A command byte is sent by reading the address whose low eight bits are that
; byte.  So a whole PIPE_WRITE frame is ten plain lda abs, four cycles each,
; with the bytes sitting in the low halves of the operands.  Nothing is
; computed at send time.
;
; rbcp_send_cmd spends 19 cycles per argument — lda rbcp_arg0,y / sta
; rbcp_sm_arg+1 / lda abs / iny / dex / bne — against four here.  That
; difference is what LIB4 against TUNED4 measures.
;
; One block per PIPE_WRITE, sixteen blocks to a 64 byte line, so block n
; carries line bytes 4n to 4n+3 in its own operands.  The block is written out
; sixteen times rather than looped because the loop is the thing being removed.
;
; Cycle budget per write, with the device answering on the first poll:
;   ten lda abs                     40
;   sta of the token                 3
;   jsr                              6
;   poll and its rts                40
;   bcs not taken                    2
;                                   91
;
; The retry on refusal is a two byte branch back to the top of the same block,
; which re-reads the token as a retry must.  Asking the pipe how much room it
; has is a command in its own right, so the token has moved either way.
; PIPE_WRITE is all or nothing, so the same four bytes go again — and whether
; they go again at all is fault.s's decision, not this file's.

    .include "pipe_defs.s"

.import fault_note
.import fault_stall
.import fault_write_refused
.import run_abort
.if PLAT_SW_TICK
.import plat_clock_poll
.endif

CMD_BASE = CONFIG_RBCP_CMD_PAGE * $100

; Offsets within one block, and the size of it.  The operand low byte of an
; lda abs is one past the opcode.
BLOCK_SIZE  = 34
PAY0_OFF    = 12
PAY_STEP    = 3

; The token goes in zero page, not main RAM.  An absolute store would make the
; block 35 bytes rather than 34 and cost a cycle on every one of the sixteen
; writes in a line.
tuned_tok = ZP_APP8

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; send_tuned_line — sends the 64 bytes now held in the block operands.
; Returns carry clear.  A timeout does not return here at all — tuned_poll
; jumps to run_abort, which restores the stack pointer.
; ---------------------------------------------------------------------------

.export send_tuned_line
.export tuned_blocks
send_tuned_line:
    lda #0
    sta fault_stall             ; the stall bound is per line
tuned_blocks:
.repeat 16
:   lda RBCP_TOKEN_LSB_ADDR                     ; +0
    sta tuned_tok                               ; +3
    lda CMD_BASE + RBCP_GRP_PIPES               ; +5
    lda CMD_BASE + RBCP_CMD_PIPE_WRITE          ; +8
    lda CMD_BASE                                ; +11, payload 0
    lda CMD_BASE                                ; +14, payload 1
    lda CMD_BASE                                ; +17, payload 2
    lda CMD_BASE                                ; +20, payload 3
    lda CMD_BASE + 0                            ; +23, pipe 0
    lda CMD_BASE + RBCP_PIPE_WRITE_MAX          ; +26, count 4
    jsr tuned_poll                              ; +29
    bcs :-                                      ; +32, refused, same bytes again
.endrepeat
tuned_blocks_end:
    rts

.assert (tuned_blocks_end - tuned_blocks) = BLOCK_SIZE * 16, error, "BLOCK_SIZE does not match the block"

; ---------------------------------------------------------------------------
; tuned_poll — the protocol's polling sequence with nothing between the reads.
;
; Nine or ten cycles an iteration, against the library's forty three — its
; progress loop calls pause on every iteration that does not see complete.
; Part of any LIB4 against TUNED4 gap is that, not send cost.
;
; Both loops count RBCP_POLL_TIMEOUT iterations, which is what rbcp_poll_token
; and rbcp_poll_progress count, so the two paths give a device the same number
; of chances to answer.  The wall time differs, and by exactly the pause the
; library adds and this does not.
;
; Returns carry set if the write should go again.  A device that stopped
; answering is not a return value — it abandons the run through run_abort, and
; so does a refusal fault.s has decided not to retry.
;
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.assert RBCP_POLL_TIMEOUT > 0, error, "A run needs a bounded poll"

tuned_poll:
.if PLAT_SW_TICK
    jsr plat_clock_poll         ; a machine whose clock is counted in software
.endif
    ldx #<RBCP_POLL_TIMEOUT
@token:
    lda RBCP_TOKEN_LSB_ADDR
    cmp tuned_tok
    bne @progress
    dex
    bne @token
    lda #STAT_NO_ANSWER
    jsr fault_note
    jmp run_abort

@progress:
    ldx #<RBCP_POLL_TIMEOUT
@prog_loop:
    lda RBCP_PROGRESS_ADDR
    cmp #RBCP_COMPLETE
    beq @response
    dex
    bne @prog_loop
    lda #STAT_NO_COMPLETE
    jsr fault_note
    jmp run_abort

@response:
    lda RBCP_RESPONSE_ADDR
    cmp #RBCP_STATUS_OK
    beq @ok
    lda #RBCP_PIPE_WRITE_MAX
    jsr fault_write_refused
    bcs @lost
    sec                         ; the same four bytes again
    rts
@lost:
    jmp run_abort
@ok:
    clc
    rts

; ---------------------------------------------------------------------------
; Where each line byte's operand lives.  Line byte K is payload K mod 4 of
; block K div 4.
; ---------------------------------------------------------------------------

.rodata

.export tuned_op_lo
.export tuned_op_hi

tuned_op_lo:
.repeat 64, k
    .byte <(tuned_blocks + (k / 4) * BLOCK_SIZE + PAY0_OFF + (k .mod 4) * PAY_STEP)
.endrepeat

tuned_op_hi:
.repeat 64, k
    .byte >(tuned_blocks + (k / 4) * BLOCK_SIZE + PAY0_OFF + (k .mod 4) * PAY_STEP)
.endrepeat
