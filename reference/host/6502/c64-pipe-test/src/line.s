; line.s — the payload
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; A line is 64 bytes, which is sixteen whole PIPE_WRITE payloads, so no write
; ever straddles a line boundary and the send loop never carries a partial one.
;
;   NNNN 012345678901234567890123456789012345678901234567890123456<CR><LF>
;   0123 5                                                     61 62 63
;
; Bytes 0 to 3 are the sequence as hex ASCII, byte 4 a space, bytes 5 to 61 the
; 57 character body, and 62 and 63 CR and LF.
;
; The body is a digit ruler with one cell replaced by '#', at body column
; sequence mod 57.  On a terminal that is a diagonal stripe scrolling up the
; screen with a 57 line period, against a ruler that gives the reader a column
; reference.  A dropped line shows twice over: the hex counter jumps and the
; diagonal breaks.
;
; Only three things change from line to line — the stripe leaves one cell and
; enters the next, and the sequence increments, which touches one digit on
; fifteen lines in sixteen.  Everything else is written once at the start of a
; run.
;
; TUNED4 holds the line in the operands of its unrolled block rather than in a
; buffer, so every write here goes through line_store, which mirrors it there
; when that path is selected.

    .include "pipe_defs.s"

.import tuned_op_lo
.import tuned_op_hi

BODY_START  = 5
BODY_LEN    = 57

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export line_buf
.export tuned_mode

line_buf:       .res 64
stripe_col:     .res 1      ; body column holding the '#'
stripe_digit:   .res 1      ; the ruler digit that column should hold
tuned_mode:     .res 1      ; non-zero when writes mirror into the block

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; line_store — A = byte, X = line index.  Writes the buffer, and the block
; operand too when TUNED4 is running.
;
; The four sequence digits are line bytes 0 to 3, which are block 0's four
; payload operands at fixed addresses, so they would need no lookup.  The
; stripe would not: it moves one line byte per line and crosses a block
; boundary every fourth.  A 128 byte table covers both without that arithmetic,
; at 24 cycles a patched byte against about 10 — 42 cycles a line, on a line
; that costs about 1500.  Two things are patched per line plus the sequence.
;
; Clobbers A, Y.  Preserves X.
; ---------------------------------------------------------------------------

.export line_store
line_store:
    sta line_buf, x
    ldy tuned_mode
    beq @done
    sta ZP_APP6
    lda tuned_op_lo, x
    sta ZP_APP0
    lda tuned_op_hi, x
    sta ZP_APP1
    lda ZP_APP6
    ldy #0
    sta (ZP_APP0), y
@done:
    rts

; ---------------------------------------------------------------------------
; line_to_tuned — copies the buffer into the block operands.  Called once, when
; a TUNED4 run starts, after the line has been built.
;
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export line_to_tuned
line_to_tuned:
    lda #1
    sta tuned_mode
    ldx #0
@loop:
    lda line_buf, x
    jsr line_store
    inx
    cpx #64
    bne @loop
    rts

; ---------------------------------------------------------------------------
; line_reset — builds the whole line and starts the sequence at 0000.  Called
; once at the start of a run.
;
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export line_reset
line_reset:
    lda #'0'
    ldx #0
    jsr line_store
    lda #'0'
    ldx #1
    jsr line_store
    lda #'0'
    ldx #2
    jsr line_store
    lda #'0'
    ldx #3
    jsr line_store

    lda #' '
    ldx #4
    jsr line_store

    lda #0
    sta ZP_APP7                 ; ruler digit
    ldx #BODY_START
@body:
    lda ZP_APP7
    clc
    adc #'0'
    jsr line_store
    inc ZP_APP7
    lda ZP_APP7
    cmp #10
    bne @no_wrap
    lda #0
    sta ZP_APP7
@no_wrap:
    inx
    cpx #(BODY_START + BODY_LEN)
    bne @body

    lda #13
    ldx #62
    jsr line_store
    lda #10
    ldx #63
    jsr line_store

    lda #0
    sta stripe_col
    sta stripe_digit
    lda #'#'
    ldx #BODY_START
    jmp line_store

; ---------------------------------------------------------------------------
; line_next — the stripe leaves its cell for the next one and the sequence
; increments.  Called after each line has gone out.
;
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export line_next
line_next:
    lda stripe_digit            ; put the ruler back where the stripe was
    clc
    adc #'0'
    ldx stripe_col
    inx                         ; body column to line index
    inx
    inx
    inx
    inx
    jsr line_store

    inc stripe_col
    inc stripe_digit
    lda stripe_digit
    cmp #10
    bne @digit_ok
    lda #0
    sta stripe_digit
@digit_ok:
    lda stripe_col
    cmp #BODY_LEN
    bne @col_ok
    lda #0                      ; wraps to column 0, whose ruler digit is 0
    sta stripe_col
    sta stripe_digit
@col_ok:
    lda #'#'
    ldx stripe_col
    inx
    inx
    inx
    inx
    inx
    jsr line_store

    ; fall through

; ---------------------------------------------------------------------------
; line_inc_seq — the four hex digits, least significant first.  One digit
; changes on fifteen lines in sixteen.
;
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

line_inc_seq:
    ldx #3
@digit:
    lda line_buf, x
    cmp #'9'
    bne @not_nine
    lda #'A'
    jmp line_store
@not_nine:
    cmp #'F'
    beq @carry
    clc
    adc #1
    jmp line_store
@carry:
    lda #'0'
    jsr line_store
    dex
    bpl @digit
    rts
