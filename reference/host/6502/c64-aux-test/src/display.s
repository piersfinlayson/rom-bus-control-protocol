; display.s — everything this program puts on the screen
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The seam
; --------
; The tables in pins.s are the interface.  This file reads them and never
; writes them.  The rest of the program passes a note code in A and never holds
; a string, a row, a column or a colour.
;
; Two rules a rewrite of this file has to keep, neither of them visible in the
; code:
;
;   - Write $0400 and $D800 directly.  No kernal screen calls.  CHROUT and the
;     rest of the editor work through $D0-$F2, which this program has taken for
;     its own zero page, so the screen memory is safe and the editor is not.
;
;   - Do not read $A000-$BFFF.  A stray read of the command page injects a
;     command byte into an open session.
;
; The picture
; -----------
; A pin is a ring.  Filled means the level is high, hollow means low.  The
; colour says who owns the pin: green the C64 is driving it, white it is free
; and only being read, grey the ROM is using it and it is not ours to touch.
;
; Ring size comes from how many drivable pins the group has, so a group of two
; gets a ring seven characters across and a group of forty gets a dot.  That is
; the only thing that changes between groups — the vocabulary does not.

    .include "aux_defs.s"

.import c64_clear_screen
.import c64_print_at
.import row_off_lo
.import row_scr_hi
.import row_col_hi

.import pins_group_count
.import pins_max_hold
.import pins_group_type
.import pins_group_pins
.import pins_group_drv
.import pin_flags
.import pin_state
.import pins_drv_at
.import pins_tier
.import pins_truncated
.import pins_slot
.import pins_flash_name
.import pins_dev_type
.import pins_dev_ver
.import pins_proto

.import cur_group
.import cur_slot

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

num_buf:    .res 4
ring_left:  .res 1
ring_tier:  .res 1

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
; row_ptrs — A = row.  Points ZP_APP0/1 at that screen row and ZP_APP2/3 at the
; matching colour row.  Clobbers A, X.
; ---------------------------------------------------------------------------

row_ptrs:
    tax
    lda row_off_lo, x
    sta ZP_SCR_LO
    sta ZP_COL_LO
    lda row_scr_hi, x
    sta ZP_SCR_HI
    lda row_col_hi, x
    sta ZP_COL_HI
    rts

; ---------------------------------------------------------------------------
; put_at — A = screen code, Y = column, X = colour.  Writes both planes at the
; row row_ptrs last selected.  Clobbers A.
; ---------------------------------------------------------------------------

.export put_at
put_at:
    sta (ZP_SCR_LO), y
    txa
    sta (ZP_COL_LO), y
    rts

; ---------------------------------------------------------------------------
; fill_row — A = screen code, X = colour.  Fills the whole selected row.
; Clobbers A, Y.
; ---------------------------------------------------------------------------

fill_row:
    ldy #SCREEN_COLS - 1
@loop:
    sta (ZP_SCR_LO), y
    pha
    txa
    sta (ZP_COL_LO), y
    pla
    dey
    bpl @loop
    rts

; ---------------------------------------------------------------------------
; clear_row — A = row.  Blanks it.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export clear_row
clear_row:
    jsr row_ptrs
    lda #CHAR_SPACE
    ldx #COL_WHITE
    jmp fill_row

; ---------------------------------------------------------------------------
; clear_rings — blanks every row the rings may occupy.
; Clobbers A, X, Y and ZP_APP7.
; ---------------------------------------------------------------------------

clear_rings:
    lda #ROW_RINGS
@loop:
    sta ZP_APP7
    jsr clear_row
    lda ZP_APP7
    clc
    adc #1
    cmp #ROW_RINGS_END + 1
    bne @loop
    rts

; ---------------------------------------------------------------------------
; print_at — string at ZP_PTR, A = row, X = column.  Wraps c64_print_at, which
; wants them in its own scratch.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

print_at:
    sta ZP_TMP0
    stx ZP_TMP1
    jmp c64_print_at

; ---------------------------------------------------------------------------
; put_dec — A = value 0-255, Y = column, X = colour.  Writes it with no
; leading zeros at the row row_ptrs last selected, and returns the column after
; the last digit in Y.  Clobbers A.
; ---------------------------------------------------------------------------

.export put_dec
put_dec:
    stx dec_colour
    sty dec_col
    ldx #0
@hundreds:
    cmp #100
    bcc @tens_start
    sbc #100
    inx
    bne @hundreds
@tens_start:
    stx num_buf + 0
    ldx #0
@tens:
    cmp #10
    bcc @units
    sbc #10
    inx
    bne @tens
@units:
    stx num_buf + 1
    sta num_buf + 2

    ldy dec_col
    lda num_buf + 0
    beq @skip_h
    jsr @digit
@skip_h:
    lda num_buf + 0
    ora num_buf + 1
    beq @skip_t
    lda num_buf + 1
    jsr @digit
@skip_t:
    lda num_buf + 2
    jsr @digit
    rts

@digit:
    clc
    adc #$30                    ; screen code for '0'
    ora dec_rev_flag            ; bit 7 reverses, for the cursor's number
    ldx dec_colour
    jsr put_at
    iny
    rts

; ---------------------------------------------------------------------------
; display_init — black on black with white text.  White on black rather than
; anything prettier: it is what reads on video.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export display_init
display_init:
    lda #0
    sta dec_rev_flag            ; BSS arrives holding whatever BASIC left
    lda #COL_BLACK
    sta VIC_BORDER
    sta VIC_BACKGROUND
    ldy #COL_WHITE
    jsr c64_clear_screen

    set_ptr str_title
    lda #ROW_TITLE
    ldx #12
    jmp print_at

; ---------------------------------------------------------------------------
; display_keys — the two key rows.  Written once and left alone, except while
; a blink or a move test is running, when they are cleared to keep the screen
; quiet and put back afterwards.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export display_keys
display_keys:
    set_ptr str_keys1
    lda #ROW_KEYS1
    ldx #1
    jsr print_at
    set_ptr str_keys2
    lda #ROW_KEYS2
    ldx #1
    jmp print_at

.export display_keys_clear
display_keys_clear:
    lda #ROW_KEYS1
    jsr clear_row
    lda #ROW_KEYS2
    jmp clear_row

; ---------------------------------------------------------------------------
; display_group — the group name, which group of how many, and how many of its
; pins can be driven.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export display_group
display_group:
    lda #ROW_GROUP
    jsr clear_row
    lda #ROW_COUNT
    jsr clear_row

    ; name, from the type byte
    ldx cur_group
    lda pins_group_type, x
    jsr type_name              ; sets ZP_PTR
    lda #ROW_GROUP
    ldx #COL_GROUP
    jsr print_at

    ; "n OF m" at the right
    lda #ROW_GROUP
    jsr row_ptrs
    lda cur_group
    clc
    adc #1
    ldy #31
    ldx #COL_WHITE
    jsr put_dec
    iny                         ; a space before OF
    sty ZP_APP5
    set_ptr str_of
    lda #ROW_GROUP
    ldx ZP_APP5
    jsr print_at
    lda #ROW_GROUP
    jsr row_ptrs
    lda pins_group_count
    ldy ZP_APP5
    iny
    iny
    iny                         ; past OF and the space after it
    ldx #COL_WHITE
    jsr put_dec

    ; "n OF m PINS CAN BE DRIVEN"
    lda #ROW_COUNT
    jsr row_ptrs
    ldx cur_group
    lda pins_group_drv, x
    ldy #COL_GROUP
    ldx #COL_WHITE
    jsr put_dec
    iny                         ; a space before OF
    sty ZP_APP5
    set_ptr str_of
    lda #ROW_COUNT
    ldx ZP_APP5
    jsr print_at
    lda #ROW_COUNT
    jsr row_ptrs
    ldx cur_group
    lda pins_group_pins, x
    ldy ZP_APP5
    iny
    iny
    iny
    iny
    ldx #COL_WHITE
    jsr put_dec
    sty ZP_APP5
    set_ptr str_drivable
    lda #ROW_COUNT
    ldx ZP_APP5
    inx
    jmp print_at

; ---------------------------------------------------------------------------
; type_name — A = group type byte.  Points ZP_PTR at what to call it.
; Types outside the protocol's table are shown as their number rather than
; guessed at, which is what a host is supposed to do with a value it has never
; seen.
; Clobbers A.
; ---------------------------------------------------------------------------

type_name:
    cmp #RBCP_AUX_TYPE_GPIO
    bne @not_gpio
    set_ptr str_gpio
    rts
@not_gpio:
    cmp #$80
    bne @not_imgsel
    set_ptr str_imgsel
    rts
@not_imgsel:
    cmp #$81
    bne @not_x
    set_ptr str_xpads
    rts
@not_x:
    cmp #RBCP_AUX_TYPE_NONE
    bne @unknown
    set_ptr str_none
    rts
@unknown:
    set_ptr str_type
    rts

; ---------------------------------------------------------------------------
; display_rings — the current group as rings, with the cursor on cur_slot.
;
; This does not clear first.  Every ring lands on the same cells every time, so
; redrawing over the top is enough, and blanking sixteen rows on each refresh
; makes the screen strobe — the rings are gone for as long as the clear takes,
; every frame.  display_rings_fresh is the one that clears, and the caller uses
; it when the picture is about to change shape.
;
; Nothing is drawn for a group with no drivable pins: there is no ring to draw,
; and display_note says so in words instead.
;
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_rings_fresh
display_rings_fresh:
    jsr clear_rings
    ; fall through

.export display_rings
display_rings:

    ldx cur_group
    lda pins_group_drv, x
    bne @have
    rts
@have:
    jsr pins_tier
    sta ring_tier

    ; left margin, from however many fit on a full row
    ldx cur_group
    lda pins_group_drv, x
    ldx ring_tier
    cmp tier_perrow, x
    bcc @narrow
    lda tier_perrow, x
@narrow:
    jsr row_width
    lda #SCREEN_COLS
    sec
    sbc ZP_APP8
    lsr a
    sta ring_left

    lda #0
    sta ZP_APP5                 ; slot
@slot_loop:
    ldx cur_group
    lda pins_group_drv, x
    cmp ZP_APP5
    beq @done
    jsr draw_slot
    inc ZP_APP5
    bne @slot_loop
@done:
    rts

; ---------------------------------------------------------------------------
; row_width — A = rings on the row, tier in ring_tier.  Returns the width they
; occupy in ZP_APP8.  Clobbers A, X.
; ---------------------------------------------------------------------------

row_width:
    ldx ring_tier
    tay                         ; count
    lda #0
@mul:
    clc
    adc tier_pitch, x
    dey
    bne @mul
    sec
    sbc tier_pitch, x
    clc
    adc tier_w, x
    sta ZP_APP8
    rts

; ---------------------------------------------------------------------------
; draw_slot — draws the ring for slot ZP_APP5 of the current group, and its pin
; number underneath.  Clobbers A, X, Y and ZP_APP6 to ZP_APP8.
; ---------------------------------------------------------------------------

draw_slot:
    ldx ring_tier

    ; bank = slot / perrow, position = slot mod perrow
    lda ZP_APP5
    ldy #0
@div:
    cmp tier_perrow, x
    bcc @div_done
    sec
    sbc tier_perrow, x
    iny
    bne @div
@div_done:
    sta ZP_APP6                 ; position within the bank
    sty ZP_APP7                 ; bank

    ; row = ROW_RINGS + bank * bankh
    lda #0
@mulrow:
    cpy #0
    beq @mulrow_done
    clc
    adc tier_bankh, x
    dey
    bne @mulrow
@mulrow_done:
    clc
    adc #ROW_RINGS
    sta ZP_APP7                 ; top row of this ring

    ; column = ring_left + position * pitch
    lda #0
    ldy ZP_APP6
@mulcol:
    cpy #0
    beq @mulcol_done
    clc
    adc tier_pitch, x
    dey
    bne @mulcol
@mulcol_done:
    clc
    adc ring_left
    sta ZP_APP6                 ; left column of this ring

    ; what to draw it as
    lda ZP_APP5
    ldx cur_group
    jsr pins_drv_at
    sta ZP_APP8                 ; pin number

    ldx cur_group
    txa
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc ZP_APP8
    tax                         ; table index
    lda pin_state, x
    and #PIN_LEVEL_BIT
    sta ring_filled
    lda pin_flags, x
    sta ring_pflags
    lda pin_state, x
    and #PIN_DRIVEN_BIT
    sta ring_driven

    jsr ring_colour
    sta ring_col

    jsr draw_ring
    jmp draw_pin_number

; ---------------------------------------------------------------------------
; ring_colour — from the flags and driven bits already in ring_pflags and
; ring_driven.  Returns the colour in A.
; ---------------------------------------------------------------------------

ring_colour:
    lda ring_pflags
    and #RBCP_AUX_FLAG_DRIVABLE
    beq @theirs
    lda ring_driven
    beq @free
    lda #COL_LIGHT_GREEN
    rts
@free:
    lda #COL_WHITE
    rts
@theirs:
    lda #COL_MED_GREY
    rts

; ---------------------------------------------------------------------------
; draw_ring — top row ZP_APP7, left column ZP_APP6, tier ring_tier, filled from
; ring_filled, colour ring_col.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

draw_ring:
    ldx ring_tier
    cpx #TIER_DOT
    bne @box

    ; one character: a filled or hollow circle
    lda ZP_APP7
    jsr row_ptrs
    lda ring_filled
    beq @dot_empty
    lda #SC_DOT_FULL
    bne @dot_put
@dot_empty:
    lda #SC_DOT_EMPTY
@dot_put:
    ldy ZP_APP6
    ldx ring_col
    jmp put_at

@box:
    ; top
    lda ZP_APP7
    jsr row_ptrs
    lda #SC_TL
    ldy ZP_APP6
    ldx ring_col
    jsr put_at
    jsr ring_span_horiz
    lda #SC_TR
    ldx ring_col
    jsr put_at

    ; middles
    ldx ring_tier
    lda tier_h, x
    sec
    sbc #2
    sta ring_rows
    lda ZP_APP7
    sta ring_row
@mid:
    inc ring_row
    lda ring_row
    jsr row_ptrs
    lda #SC_VERT
    ldy ZP_APP6
    ldx ring_col
    jsr put_at
    jsr ring_span_fill
    lda #SC_VERT
    ldx ring_col
    jsr put_at
    dec ring_rows
    bne @mid

    ; bottom
    inc ring_row
    lda ring_row
    jsr row_ptrs
    lda #SC_BL
    ldy ZP_APP6
    ldx ring_col
    jsr put_at
    jsr ring_span_horiz
    lda #SC_BR
    ldx ring_col
    jmp put_at

; ---------------------------------------------------------------------------
; ring_span_horiz — writes the ring's inner width as horizontal line, starting
; at column ZP_APP6 + 1.  Returns with Y on the column after.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

ring_span_horiz:
    ldx ring_tier
    lda tier_w, x
    sec
    sbc #2
    tax
    ldy ZP_APP6
    iny
@loop:
    lda #SC_HORIZ
    stx ring_span_tmp
    ldx ring_col
    jsr put_at
    ldx ring_span_tmp
    iny
    dex
    bne @loop
    rts

; ---------------------------------------------------------------------------
; ring_span_fill — as ring_span_horiz, with the ring's inside instead: reversed
; space where the level is high, blank where it is low.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

ring_span_fill:
    ldx ring_tier
    lda tier_w, x
    sec
    sbc #2
    tax
    ldy ZP_APP6
    iny
@loop:
    lda ring_filled
    beq @hollow
    lda #SC_FILL
    bne @put
@hollow:
    lda #SC_HOLLOW
@put:
    stx ring_span_tmp
    ldx ring_col
    jsr put_at
    ldx ring_span_tmp
    iny
    dex
    bne @loop
    rts

; ---------------------------------------------------------------------------
; draw_pin_number — under the ring, centred, reversed where this is the cursor.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

draw_pin_number:
    ldx ring_tier
    lda ZP_APP7
    clc
    adc tier_h, x
    jsr row_ptrs

    ; centre a one or two digit number in the ring's width
    lda ZP_APP8
    cmp #10
    bcc @one
    lda #2
    bne @have_w
@one:
    lda #1
@have_w:
    sta ring_span_tmp
    ldx ring_tier
    lda tier_w, x
    sec
    sbc ring_span_tmp
    lsr a
    clc
    adc ZP_APP6
    tay

    lda ZP_APP5
    cmp cur_slot
    bne @plain
    lda #$80                    ; reverse video, the only cursor on screen
    sta dec_rev_flag
    lda #COL_WHITE
    sta ring_cursor
    jmp @emit
@plain:
    lda #0
    sta dec_rev_flag
    lda ring_col
    sta ring_cursor
@emit:
    lda ZP_APP8
    ldx ring_cursor
    jsr put_dec
    lda #0
    sta dec_rev_flag
    rts

; ---------------------------------------------------------------------------
; display_note — A = a NOTE_ code.  The one line of plain English on the
; screen, and the only place the program explains itself.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export display_note
display_note:
    pha
    lda #ROW_NOTE
    jsr clear_row
    pla
    cmp #NOTE_COUNT
    bcs @out
    asl a
    tax
    lda note_tab, x
    sta ZP_PTR_LO
    lda note_tab + 1, x
    sta ZP_PTR_HI
    lda ZP_PTR_LO
    ora ZP_PTR_HI
    beq @out
    lda #ROW_NOTE
    ldx #COL_GROUP
    jmp print_at
@out:
    rts


; ---------------------------------------------------------------------------
; pin_glyph — A = table index.  Returns the screen code in A and the colour in
; X, by the same rule the rings use: fill is the level, colour is who owns it.
; Clobbers A, Y.
; ---------------------------------------------------------------------------

pin_glyph:
    tay
    lda pin_flags, y
    and #RBCP_AUX_FLAG_DRIVABLE
    beq @theirs
    lda pin_state, y
    and #PIN_DRIVEN_BIT
    beq @free
    ldx #COL_LIGHT_GREEN
    jmp @level
@free:
    ldx #COL_WHITE
    jmp @level
@theirs:
    ldx #COL_MED_GREY
@level:
    lda pin_state, y
    and #PIN_LEVEL_BIT
    beq @empty
    lda #SC_DOT_FULL
    rts
@empty:
    lda #SC_DOT_EMPTY
    rts

; ---------------------------------------------------------------------------
; display_all — every pin of every group, one character each, with what the
; device calls itself underneath.
;
; This is the screen for the question the rings deliberately do not answer:
; what the pins we are not allowed to touch are doing.  Same vocabulary, one
; character instead of seven, so nothing new has to be learned to read it.
;
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_all
display_all:
    lda #0
@wipe:
    pha
    jsr clear_row
    pla
    clc
    adc #1
    cmp #SCREEN_ROWS
    bne @wipe

    set_ptr str_all_title
    lda #ROW_TITLE
    ldx #16
    jsr print_at

    lda #2
    sta all_row
    lda #0
    sta all_group
@group:
    lda all_group
    cmp pins_group_count
    beq @to_tail
    lda all_row
    cmp #18
    bcc @room
@to_tail:
    jmp @tail
@room:

    ; group name and how many pins it holds
    ldx all_group
    lda pins_group_type, x
    jsr type_name
    lda all_row
    ldx #COL_GROUP
    jsr print_at
    lda all_row
    jsr row_ptrs
    ldx all_group
    lda pins_group_pins, x
    ldy #31
    ldx #COL_WHITE
    jsr put_dec
    iny
    sty ZP_APP5
    set_ptr str_pins
    lda all_row
    ldx ZP_APP5
    jsr print_at

    inc all_row

    ; the pins, sixteen to a row, each row labelled with its first pin number
    lda #0
    sta all_pin
@bank:
    ldx all_group
    lda all_pin
    cmp pins_group_pins, x
    beq @next_group

    lda all_row
    jsr row_ptrs
    lda all_pin
    ldy #COL_GROUP
    ldx #COL_WHITE
    jsr put_dec

    ldy #6
@cell:
    ldx all_group
    lda all_pin
    cmp pins_group_pins, x
    beq @bank_done
    txa
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc all_pin
    sty ZP_APP5
    jsr pin_glyph
    ldy ZP_APP5
    jsr put_at
    inc all_pin
    iny
    iny
    cpy #38
    bne @cell
@bank_done:
    inc all_row
    ldx all_group
    lda all_pin
    cmp pins_group_pins, x
    bne @bank

@next_group:
    inc all_row
    inc all_group
    jmp @group

@tail:
    set_ptr pins_dev_type
    lda #19
    ldx #COL_GROUP
    jsr print_at
    set_ptr pins_dev_ver
    lda #19
    ldx #14
    jsr print_at
    set_ptr pins_proto
    lda #19
    ldx #22
    jsr print_at

    set_ptr str_legend1
    lda #ROW_KEYS1
    ldx #1
    jsr print_at
    set_ptr str_legend2
    lda #ROW_KEYS2
    ldx #1
    jmp print_at

; ---------------------------------------------------------------------------
; display_reset — what is about to happen, before it happens.
;
; Everything on it is a fact the caller has already settled.  It is a screen
; rather than a key because the command is terminal: there is no response
; header to read afterwards and no way back into the session.
;
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_reset
display_reset:
    jsr clear_rings
    lda #ROW_NOTE
    jsr clear_row
    jsr display_keys_clear

    set_ptr str_r_title
    lda #6
    ldx #COL_GROUP
    jsr print_at

    set_ptr str_r_pin
    lda #9
    ldx #COL_GROUP
    jsr print_at
    ldx cur_group
    lda pins_group_type, x
    jsr type_name
    lda #9
    ldx #10
    jsr print_at
    lda #9
    jsr row_ptrs
    lda reset_pin
    ldy #25
    ldx #COL_WHITE
    jsr put_dec

    set_ptr str_r_hold
    lda #11
    ldx #COL_GROUP
    jsr print_at
    lda #11
    jsr row_ptrs
    lda #RESET_HOLD * 10
    ldy #10
    ldx #COL_WHITE
    jsr put_dec
    sty ZP_APP5
    set_ptr str_r_ms
    lda #11
    ldx ZP_APP5
    jsr print_at

    set_ptr str_r_order
    lda #13
    ldx #COL_GROUP
    jsr print_at

    set_ptr str_r_image
    lda #15
    ldx #COL_GROUP
    jsr print_at
    lda #15
    jsr row_ptrs
    lda reset_flash
    ldy #10
    ldx #COL_WHITE
    jsr put_dec
    set_ptr pins_flash_name
    lda #15
    ldx #14
    jsr print_at

    set_ptr str_r_ends
    lda #18
    ldx #COL_GROUP
    jsr print_at

    set_ptr str_r_pick
    lda #ROW_NOTE
    ldx #COL_GROUP
    jsr print_at
    set_ptr str_r_ask
    lda #ROW_KEYS1
    ldx #COL_GROUP
    jmp print_at

; ---------------------------------------------------------------------------
; display_fail — A = a FAIL_ code.  Replaces everything: on a machine with no
; device there is nothing else worth showing.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export display_fail
display_fail:
    pha
    jsr display_init
    jsr display_keys_clear
    pla
    cmp #FAIL_COUNT
    bcs @out
    asl a
    tax
    lda fail_tab, x
    sta ZP_PTR_LO
    lda fail_tab + 1, x
    sta ZP_PTR_HI
    lda #ROW_NOTE
    ldx #COL_GROUP
    jsr print_at
    set_ptr str_quit_only
    lda #ROW_KEYS1
    ldx #1
    jmp print_at
@out:
    rts

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

ring_filled:    .res 1
ring_driven:    .res 1
ring_pflags:    .res 1
ring_col:       .res 1
ring_rows:      .res 1
ring_row:       .res 1
ring_span_tmp:  .res 1
ring_cursor:    .res 1
dec_rev_flag:   .res 1
all_row:        .res 1
all_group:      .res 1
all_pin:        .res 1

.export reset_pin
.export reset_flash
reset_pin:      .res 1
reset_flash:    .res 1
dec_col:        .res 1
dec_colour:     .res 1

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

tier_w:         .byte 7, 5, 3, 1
tier_h:         .byte 5, 3, 3, 1
tier_pitch:     .byte 9, 7, 4, 2
tier_perrow:    .byte 4, 5, 9, 16
tier_bankh:     .byte 6, 4, 4, 2

str_title:      .byte "RBCP AUX I/O", 0
str_keys1:      .byte "CRSR PIN/GROUP  A ALL PINS  R RESET  Q", 0
str_keys2:      .byte "L LOW  H HIGH  Z REL  B BLINK  T TEST", 0
str_quit_only:  .byte "Q QUIT", 0
str_all_title:  .byte "ALL PINS", 0
str_pins:       .byte "PINS", 0
str_legend1:    .byte "GREEN DRIVEN BY C64   WHITE FREE", 0
str_legend2:    .byte "GREY IN USE BY ROM    ANY KEY BACK", 0
str_r_title:    .byte "EXIT AND RESET", 0
str_r_pin:      .byte "PIN", 0
str_r_hold:     .byte "HOLD", 0
str_r_ms:       .byte "MS LOW, THEN RELEASED", 0
str_r_order:    .byte "ORDER   PIN FIRST, THEN SLOT", 0
str_r_image:    .byte "IMAGE", 0
str_r_pick:     .byte "CRSR PICKS THE IMAGE", 0
str_r_ends:     .byte "THIS ENDS THE PROGRAM", 0
str_r_ask:      .byte "RETURN GOES  ANY OTHER KEY BACKS OUT", 0
str_of:         .byte "OF", 0
str_drivable:   .byte "PINS CAN BE DRIVEN", 0

str_gpio:       .byte "GPIO", 0
str_imgsel:     .byte "IMAGE SELECT", 0
str_xpads:      .byte "X PADS", 0
str_none:       .byte "UNSORTED PINS", 0
str_type:       .byte "OTHER PINS", 0

note_tab:
    .word 0
    .word str_n_pin
    .word str_n_nodrive
    .word str_n_blink
    .word str_n_low
    .word str_n_high
    .word str_n_rel
    .word str_n_done
    .word str_n_none
    .word str_n_refused
    .word str_n_lost
    .word str_n_notdrv
    .word str_n_trunc
    .word str_n_gone

str_n_pin:      .byte "", 0
str_n_nodrive:  .byte "EVERY PIN HERE IS IN USE BY THE ROM", 0
str_n_blink:    .byte "BLINKING - ANY KEY STOPS", 0
str_n_low:      .byte "MOVE TEST - HOLDING IT LOW", 0
str_n_high:     .byte "MOVE TEST - HOLDING IT HIGH", 0
str_n_rel:      .byte "MOVE TEST - LETTING IT GO", 0
str_n_done:     .byte "SOMETHING MOVED WITH IT", 0
str_n_none:     .byte "NOTHING MOVED WITH IT", 0
str_n_refused:  .byte "THE DEVICE REFUSED THAT", 0
str_n_lost:     .byte "THE DEVICE STOPPED ANSWERING", 0
str_n_notdrv:   .byte "THAT PIN IS NOT OURS TO DRIVE", 0
str_n_trunc:    .byte "MORE PINS THAN THIS SCREEN SHOWS", 0
str_n_gone:     .byte "SENT - THE SESSION IS OVER", 0

fail_tab:
    .word str_f_nodev
    .word str_f_enter
    .word str_f_version
    .word str_f_noaux
    .word str_f_clash
    .word str_f_slots
    .word str_f_noclean

str_f_nodev:    .byte "NO DEVICE ANSWERED THE KNOCK", 0
str_f_enter:    .byte "THE DEVICE REFUSED THE SESSION", 0
str_f_version:  .byte "THE DEVICE SPEAKS A VERSION WE DO NOT", 0
str_f_noaux:    .byte "THIS DEVICE HAS NO PINS TO DRIVE", 0
str_f_clash:    .byte "THE ROM ALREADY READS AS A REPLY", 0
str_f_slots:    .byte "THE DEVICE NEEDS TWO RAM SLOTS", 0
str_f_noclean:  .byte "NO FLASH SLOT MATCHES THIS ROM", 0
