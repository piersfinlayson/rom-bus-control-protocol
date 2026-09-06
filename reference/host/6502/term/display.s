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
    jsr text_new_row
    jsr plat_row
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
    .byte "PROTOCOL VERSION NOT SUPPORTED", 0
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

.endif
