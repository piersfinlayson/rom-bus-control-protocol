; display.s — the layout, and every word that goes on a screen
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Every word this program puts on a screen is here.  Where each part of the
; display sits is the machine's business and comes from its plat_defs.s, and
; putting a character on the screen is plat_put's.  What is here is the layout
; and the words.
;
; The screen is a title bar, a text area holding the lines that have gone, the
; line being typed, and a status bar.  Both bars are reversed, so that the text
; area is the only part of the screen that looks like text.
;
; The text area carries both directions, so every row in it opens with a mark
; saying which way it went: > for a line that has gone and < for bytes that
; arrived.  The mark sits in column 0, under the prompt on the input row, so a
; line keeps the mark it was typed at as it scrolls up.
;
; What arrived is reversed as well, mark and all, as far along the row as the
; text goes.  A line that has gone is left plain.

    .include "term_defs.s"

.import plat_cls
.import plat_row
.import plat_put
.import plat_reverse
.import plat_scroll

.import device_type_buf
.import device_version_buf
.import proto_ver_buf

.import line_buf
.import line_len

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

text_row_now: .res 1        ; the row text_new_row last handed out
stat_code:  .res 1          ; what the status bar is saying

; The column the next received byte goes in, on the bottom row of the text
; area.  Zero means no row is open, which works because the first byte of one
; goes in column 1.
rx_col:     .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

.macro set_ptr addr
    lda #<addr
    sta ZP_PTR_LO
    lda #>addr
    sta ZP_PTR_HI
.endmacro

; ---------------------------------------------------------------------------
; display_init — a blank screen, the title bar, and an empty text area.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_init
display_init:
    jsr plat_cls
    lda #0                      ; nothing clears .bss, so the row starts closed
    sta rx_col

    set_ptr str_title
    lda #ROW_TITLE
    ldx #COL_TITLE
    jsr print_at

    set_ptr str_brand
    lda #ROW_TITLE
    ldx #COL_BRAND
    jsr print_at

    lda #ROW_TITLE              ; the band goes on last, behind both
    ldx #0
    ldy #SCREEN_COLS
    jsr plat_reverse

    lda #STAT_BLANK
    jsr display_status
    jmp display_input

; ---------------------------------------------------------------------------
; display_status — A = the status code.  The bar carries it and the count of
; characters the line has left, and is drawn whole each time either changes.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_status
display_status:
    cmp #STAT_COUNT
    bcc @in_range
    lda #STAT_BLANK
@in_range:
    sta stat_code
    ; fall through

; ---------------------------------------------------------------------------
; display_bar — the status bar as it now stands.  display_input calls this,
; the count being part of it.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

display_bar:
    lda #ROW_STATUS
    jsr blank_row

    lda stat_code
    asl a
    tax
    lda str_status_tab, x
    sta ZP_PTR_LO
    lda str_status_tab + 1, x
    sta ZP_PTR_HI
    lda #ROW_STATUS
    ldx #1
    jsr print_at

    set_ptr str_left
    lda #ROW_STATUS
    ldx #COL_LEFT + 3
    jsr print_at

    lda #ROW_STATUS
    ldx #0
    ldy #SCREEN_COLS
    jsr plat_reverse
    ; fall through

; ---------------------------------------------------------------------------
; display_count — how many characters the line has left, and nothing else on
; the bar.  A keystroke changes this and no other part of it.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_count
display_count:
    lda #ROW_STATUS
    jsr plat_row
    lda #LINE_MAX
    sec
    sbc line_len
    ldy #COL_LEFT
    jsr put_num
    lda #ROW_STATUS
    ldx #COL_LEFT
    ldy #2
    jmp plat_reverse

; ---------------------------------------------------------------------------
; display_input — the whole input row: the prompt, the line as it stands, and
; the cursor after it.  Drawn at startup and once a line has gone.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_input
display_input:
    lda #ROW_INPUT
    jsr blank_row

    lda #ROW_INPUT
    jsr plat_row
    ldy #0
    lda #'>'
    jsr plat_put
    ldx #0
@char:
    cpx line_len
    beq @cursor
    iny
    lda line_buf, x
    jsr plat_put
    inx
    bne @char
@cursor:
    jsr draw_cursor
    jmp display_count

; ---------------------------------------------------------------------------
; display_typed — the character just added to the line, and the cursor moved
; along.  Two cells, because redrawing the row on every key is what made both
; rows flicker.
;
; Called with line_len already counting the new character, so it is at column
; line_len and the cursor goes one to the right of it.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_typed
display_typed:
    lda #ROW_INPUT
    jsr plat_row
    ldy line_len
    lda line_buf - 1, y
    jsr plat_put
    jsr draw_cursor
    jmp display_count

; ---------------------------------------------------------------------------
; display_deleted — the cursor back one, and the cell it came out of blanked.
;
; Called with line_len already counting the character gone.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_deleted
display_deleted:
    lda #ROW_INPUT
    jsr plat_row
    ldy line_len
    iny
    iny                         ; where the cursor was
    lda #' '
    jsr plat_put
    jsr draw_cursor
    jmp display_count

; ---------------------------------------------------------------------------
; draw_cursor — a reversed space at column line_len + 1, the screen row already
; pointed at.  Clobbers A, X, Y and ZP_TMP0/1 through plat_reverse.
; ---------------------------------------------------------------------------

draw_cursor:
    ldy line_len
    iny
    lda #' '
    jsr plat_put
    lda #ROW_INPUT
    ldx line_len
    inx
    ldy #1
    jmp plat_reverse

; ---------------------------------------------------------------------------
; display_sent — the line that has just gone, on a row of the text area.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_sent
display_sent:
    lda #0                      ; the received row, if one is open, is finished
    sta rx_col                  ; with: the sent line goes below it
    jsr text_new_row
    jsr plat_row
    ldy #0
    lda #'>'
    jsr plat_put
    ldy #1
    ldx #0
@char:
    cpx line_len
    beq @done
    lda line_buf, x
    jsr plat_put
    iny
    inx
    bne @char
@done:
    rts

; ---------------------------------------------------------------------------
; display_rx_byte — A = a byte off the pipe, on the screen in inverse.
;
; A carriage return or a line feed ends the row rather than drawing anything,
; so a far end sending both ends one row and not two.  A row that fills up runs
; on to the next, and carries its own < so that a line running over two rows is
; marked on both.  Anything the screen cannot draw becomes a full stop, so a
; byte that arrived is always a mark on the screen and never a gap.
;
; The cell is turned over one at a time rather than the row at the end, because
; the row has no end until the far end sends one.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_rx_byte
display_rx_byte:
    and #$7F                    ; the screens hold 7 bit characters
    cmp #13
    beq display_rx_close
    cmp #10
    beq display_rx_close

    jsr rx_filter
    pha

    lda rx_col
    bne @have_row
    jsr rx_open_row
@have_row:
    lda rx_col
    cmp #SCREEN_COLS
    bcc @have_cell
    jsr rx_open_row             ; the row is full, so it runs on to a new one

@have_cell:
    lda #ROW_TEXT_BOT
    jsr plat_row
    ldy rx_col
    pla
    jsr plat_put
    lda #ROW_TEXT_BOT
    ldx rx_col
    ldy #1
    jsr plat_reverse
    inc rx_col
    rts

; ---------------------------------------------------------------------------
; display_rx_close — the received row is finished with, so the next byte starts
; a new one.  Called on a carriage return or a line feed, and wherever the
; session stops.
; Clobbers A.
; ---------------------------------------------------------------------------

.export display_rx_close
display_rx_close:
    lda #0
    sta rx_col
    rts

; ---------------------------------------------------------------------------
; rx_open_row — the text area up one, and the row that frees at the bottom
; marked as received and ready for the bytes.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

rx_open_row:
    jsr text_new_row
    jsr plat_row
    ldy #0
    lda #'<'
    jsr plat_put
    lda #ROW_TEXT_BOT
    ldx #0
    ldy #1
    jsr plat_reverse
    lda #1
    sta rx_col
    rts

; ---------------------------------------------------------------------------
; rx_filter — A = a byte, out as a character this screen draws.
;
; The screens hold one case and it is upper, and they draw $20-$3F and $41-$5A
; as themselves.  Everything else, control codes included, becomes a full stop.
; Clobbers A.
; ---------------------------------------------------------------------------

rx_filter:
    cmp #'a'
    bcc @not_lower
    cmp #'z' + 1
    bcs @not_lower
    sec
    sbc #$20
    rts
@not_lower:
    cmp #CHAR_FIRST
    bcc @dot
    cmp #CHAR_PUNCT_END
    bcc @out
    cmp #CHAR_ALPHA
    bcc @dot
    cmp #CHAR_ALPHA_END
    bcs @dot
@out:
    rts
@dot:
    lda #'.'
    rts

; ---------------------------------------------------------------------------
; display_device — what the device calls itself, on its own row under the
; title.  Drawn once, and never touched again, so it does not scroll away with
; what has been sent.
;
; The name and its version go hard left and the protocol version hard right,
; which is where the title bar above puts its two.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_device
display_device:
    set_ptr device_type_buf
    lda #ROW_DEVICE
    ldx #COL_DEV
    jsr print_at

    set_ptr device_version_buf
    lda #ROW_DEVICE
    ldx ZP_APP4
    inx
    jsr print_at

    set_ptr proto_ver_buf
.if SCREEN_COLS >= 32
    lda #ROW_DEVICE
.else
    lda #ROW_PROTO
.endif
    ldx #COL_PROTO
    jmp print_at

; ---------------------------------------------------------------------------
; text_new_row — the text area up one row, and the row that leaves free at the
; bottom.  Returns it in A, and leaves it in text_row_now.
;
; It scrolls whether or not the area is full, so a line that has gone always
; sits directly above the line being typed.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

text_new_row:
    jsr plat_scroll
    lda #ROW_TEXT_BOT
    sta text_row_now
    rts

; ---------------------------------------------------------------------------
; blank_row — A = row.  Spaces, in normal video.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

blank_row:
    jsr plat_row
    ldy #0
@loop:
    lda #' '
    jsr plat_put
    iny
    cpy #SCREEN_COLS
    bne @loop
    rts

; ---------------------------------------------------------------------------
; put_num — A = a number under 100, Y = column.  Two digits, the screen row
; already pointed at.  Y comes back one past the second digit.
; Clobbers A, X.
; ---------------------------------------------------------------------------

put_num:
    ldx #'0'
@tens:
    cmp #10
    bcc @units
    sec
    sbc #10
    inx
    jmp @tens
@units:
    pha
    txa
    jsr plat_put
    iny
    pla
    clc
    adc #'0'
    jsr plat_put
    iny
    rts

; ---------------------------------------------------------------------------
; print_at — A = row, X = column, ZP_PTR_LO/HI = a null-terminated ASCII
; string.  Stops at the right-hand edge.  Leaves the column it stopped at in
; ZP_APP4, so a caller can put the next string after this one.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

print_at:
    stx ZP_APP4                 ; column
    jsr plat_row
    lda #0
    sta ZP_APP5                 ; index into the string
@loop:
    ldy ZP_APP5
    lda (ZP_PTR_LO), y
    beq @done
    ldy ZP_APP4
    cpy #SCREEN_COLS
    bcs @done
    jsr plat_put
    inc ZP_APP4
    inc ZP_APP5
    bne @loop
@done:
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

str_status_tab:
    .word str_blank
    .word str_opening
    .word str_ready
    .word str_no_device
    .word str_enter_fail
    .word str_version
    .word str_no_pipe
    .word str_pipe_dir
    .word str_no_answer
    .word str_no_complete
    .word str_pipe_full
    .word str_not_armed
    .word str_no_recover
    .word str_send_only
    .word str_rx_fail

str_brand:
    .byte "PIERS.ROCKS", 0
str_left:
    .byte "LEFT", 0
str_blank:
    .byte 0
str_ready:
    .byte "READY", 0

.if SCREEN_COLS >= 32

str_title:
    .byte "RBCP TERMINAL", 0
str_opening:
    .byte "OPENING RBCP SESSION", 0
str_no_device:
    .byte "NO DEVICE ANSWERED THE KNOCK", 0
str_enter_fail:
    .byte "DEVICE REFUSED CMD-RESP MODE", 0
str_version:
    .byte "INCOMPATIBLE VERSION", 0
str_no_pipe:
    .byte "DEVICE HAS NO PIPE", 0
str_pipe_dir:
    .byte "PIPE 0 WILL NOT TAKE BYTES", 0
str_no_answer:
    .byte "DEVICE DID NOT TAKE THE LINE", 0
str_no_complete:
    .byte "DEVICE NEVER FINISHED WRITE", 0
str_pipe_full:
    .byte "PIPE FULL - RETURN SENDS IT AGAIN", 0
str_not_armed:
    .byte "NO SESSION - NOTHING TO SEND", 0
str_no_recover:
    .byte "DEVICE DID NOT COME BACK", 0
str_send_only:
    .byte "READY - NOTHING COMES BACK", 0
str_rx_fail:
    .byte "DEVICE REFUSED A READ", 0

.else

str_title:
    .byte "RBCP TERM", 0
str_opening:
    .byte "OPENING", 0
str_no_device:
    .byte "NO DEVICE", 0
str_enter_fail:
    .byte "NO CMD-RESP", 0
str_version:
    .byte "BAD PROTOCOL", 0
str_no_pipe:
    .byte "NO PIPE", 0
str_pipe_dir:
    .byte "NO HOST PIPE", 0
str_no_answer:
    .byte "NOT TAKEN", 0
str_no_complete:
    .byte "UNFINISHED", 0
str_pipe_full:
    .byte "PIPE FULL", 0
str_not_armed:
    .byte "NO SESSION", 0
str_no_recover:
    .byte "DEVICE GONE", 0
str_send_only:
    .byte "SEND ONLY", 0
str_rx_fail:
    .byte "READ REFUSED", 0

.endif
