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
;   jsr / rts                       12
;   poll, first time lucky          36
;   bcs not taken                    2
;                                   93
;
; The retry on refusal is a two byte branch back to the top of the same block,
; which re-reads the token as a retry must.  PIPE_WRITE is all or nothing, so
; the same four bytes go again.

    .include "pipe_defs.s"

.import refusals
.import run_abort

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
; Returns carry clear.  A timeout does not return here at all: tuned_poll
; jumps to run_abort, which restores the stack pointer.
; ---------------------------------------------------------------------------

.export send_tuned_line
.export tuned_blocks
send_tuned_line:
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
; Nine or ten cycles an iteration, against the library's forty three: its
; progress loop calls pause on every iteration that does not see complete.
; Part of any LIB4 against TUNED4 gap is that, not send cost.
;
; Returns carry set if the device refused the write, which is the pipe being
; full and worth retrying.  A timeout is not a return value — it abandons the
; run through run_abort.
;
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

tuned_poll:
    ldx #0
    ldy #0
@token:
    lda RBCP_TOKEN_LSB_ADDR
    cmp tuned_tok
    bne @progress
    dex
    bne @token
    dey
    bne @token
    jmp run_abort

@progress:
    ldx #0
    ldy #0
@prog_loop:
    lda RBCP_PROGRESS_ADDR
    cmp #RBCP_COMPLETE
    beq @response
    dex
    bne @prog_loop
    dey
    bne @prog_loop
    jmp run_abort

@response:
    lda RBCP_RESPONSE_ADDR
    cmp #RBCP_STATUS_OK
    beq @ok
    inc refusals
    bne @refused
    inc refusals + 1
@refused:
    sec
    rts
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
