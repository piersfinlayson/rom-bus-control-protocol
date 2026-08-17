; send_lib.s — LIB4 and LIB1, the library exactly as it ships
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Nothing here is tuned.  The point of these two paths is what a host gets from
; rbcp_cmd_pipe_write without doing anything clever, and what the difference
; between four bytes a command and one says about per-byte against per-command
; cost.

    .include "pipe_defs.s"

.import rbcp_cmd_pipe_write
.import line_buf
.import refusals

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export chunk_count

chunk_count:    .res 1      ; 4 for LIB4, 1 for LIB1
line_pos:       .res 1
line_pos_next:  .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; send_lib_line — sends line_buf in chunks of chunk_count.
;
; rbcp_arg0 is $F7, and the 6502 has no lda zp,x for the accumulator, so ca65
; emits absolute indexed.  $00F7 plus four stays inside page zero, so no page
; crossing penalty is reachable.  rbcp_cmd_pipe_write fills rbcp_arg4 and
; rbcp_arg5 itself, which is why the gather stops at rbcp_arg3.
;
; A refusal is the pipe being full: PIPE_WRITE took none of the bytes, so the
; same ones go again and a counter moves.  A token or progress timeout is the
; device not answering, which ends the run.
;
; Returns carry clear, or carry set if the run should stop.
; Clobbers A, X, Y and the RBCP arguments.
; ---------------------------------------------------------------------------

.export send_lib_line
send_lib_line:
    lda #0
    sta line_pos

@chunk:
    ldy line_pos
    ldx #0
@gather:
    lda line_buf, y
    sta rbcp_arg0, x
    iny
    inx
    cpx chunk_count
    bne @gather
    sty line_pos_next           ; the send clobbers Y

@send:
    lda chunk_count
    ldx #0                      ; pipe 0
    jsr rbcp_cmd_pipe_write
    bcc @taken

    lda rbcp_zp_5
    cmp #3
    bne @abort                  ; 1 or 2 — nothing answered, so no retry
    inc refusals
    bne @send
    inc refusals + 1
    jmp @send

@taken:
    lda line_pos_next
    sta line_pos
    cmp #64
    bne @chunk
    clc
    rts

@abort:
    sec
    rts
