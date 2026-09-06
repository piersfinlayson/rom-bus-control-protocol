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
.import fault_stall
.import fault_stage
.import fault_write_refused

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
; PIPE_WRITE takes all four bytes or none, so a failure of any kind resends the
; same ones.  fault.s decides how many times and for how long, and names the
; reason when it decides the run is over.
;
; A retry goes back to the gather rather than to the send, because asking the
; pipe how much room it has is itself a command and overwrites rbcp_arg0.  That
; costs about fifty cycles on a path that has already lost a command.
;
; Returns carry clear, or carry set if the run should stop.
; Clobbers A, X, Y and the RBCP arguments.
; ---------------------------------------------------------------------------

.export send_lib_line
send_lib_line:
    lda #0
    sta line_pos
    sta fault_stall             ; the stall bound is per line

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
    cmp #STAGE_REFUSED
    beq @refused                ; it answered, and said no

    jsr fault_stage             ; 1 or 2 — nothing to retry to
    sec
    rts

@refused:
    lda chunk_count
    jsr fault_write_refused
    bcc @chunk                  ; the same bytes again, gathered afresh
    rts                         ; carry set, with the reason in fault_stat

@taken:
    lda line_pos_next
    sta line_pos
    cmp #64
    bne @chunk
    clc
    rts
