; display.s — the layout, and every word that goes on a screen
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Every word this program puts on a screen is here.  Where each part of the
; display sits is the machine's business and comes from its plat_defs.s, and
; putting a character on the screen is plat_put's and plat_glyph's.  What is
; here is the layout and the words.
;
; The tables in pins.s are the other interface.  This file reads them and never
; writes them.  The rest of the program passes a note code in A and never holds
; a string, a row or a column.
;
; The picture
; -----------
; A pin is a ring.  Filled means the level is high, hollow means low.  Who owns
; the pin goes to plat_glyph as a role: the host is driving it, it is free and
; only being read, or the ROM is using it and it is not ours to touch.  A
; machine with colour draws the three the same and colours them.  A machine
; without varies the character.
;
; Ring size comes from how many drivable pins the group has, so a group of two
; gets the largest ring the screen has room for and a group of forty gets a
; dot.  That is the only thing that changes between groups — the vocabulary
; does not.

    .include "auxio_defs.s"

.import plat_cls
.import plat_row
.import plat_put
.import plat_glyph
.import plat_fill_row
.import plat_reverse

.import tier_w
.import tier_h
.import tier_pitch
.import tier_perrow
.import tier_bankh

.import pins_group_count
.import pins_group_type
.import pins_group_pins
.import pins_group_drv
.import pin_flags
.import pin_state
.import pins_drv_at
.import pins_index
.import pins_reversed
.import pins_tier
.import sess_flash_name
.import sess_dev_type
.import sess_dev_ver
.import sess_proto

.import cur_group
.import cur_slot
.import cur_page

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

num_buf:        .res 4
ring_left:      .res 1
ring_tier:      .res 1
ring_filled:    .res 1
ring_driven:    .res 1
ring_pflags:    .res 1
ring_role:      .res 1
ring_rows:      .res 1
ring_row:       .res 1
ring_span_tmp:  .res 1
all_row:        .res 1
all_group:      .res 1
all_pin:        .res 1
all_first:      .res 1          ; the first and last pin the current row holds
all_last:       .res 1
dec_col:        .res 1          ; where put_dec started
dec_len:        .res 1          ; and how many digits it wrote
dec_role:       .res 1
str_col:        .res 1          ; print_str walks the screen with one index
str_idx:        .res 1          ; and the string with another


.export reset_pin
.export reset_flash
reset_pin:      .res 1
reset_flash:    .res 1

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
; print_str — string at ZP_PTR, A = row, X = column, in COLR_TEXT.  Stops at
; the null or at the right edge, whichever comes first, so a device supplying
; a name longer than the screen cannot write past it.
;
; The screen column and the offset into the string are two different numbers,
; and neither is kept in the app zero page: callers hold a column across a
; call to this.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export print_str
print_str:
    stx str_col                 ; before plat_row, which takes X for the row
    jsr plat_row
    lda #0
    sta str_idx
@loop:
    ldy str_idx
    lda (ZP_PTR_LO), y
    beq @done
    ldy str_col
    cpy #SCREEN_COLS
    bcs @done
    ldx #COLR_TEXT
    jsr plat_put
    inc str_col
    inc str_idx
    bne @loop
@done:
    rts

; ---------------------------------------------------------------------------
; clear_row — A = row.  Blanks it.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export clear_row
clear_row:
    jsr plat_row
    lda #' '
    ldx #COLR_TEXT
    jmp plat_fill_row

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
; put_dec — A = value 0-255, Y = column, X = a COLR_ role.  Writes it with no
; leading zeros at the row plat_row last selected, and returns the column after
; the last digit in Y.  dec_col and dec_len are left saying where it went, for
; a caller that wants to reverse it.
; Clobbers A.
; ---------------------------------------------------------------------------

.export put_dec
put_dec:
    stx dec_role
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

    tya
    sec
    sbc dec_col
    sta dec_len
    rts

@digit:
    clc
    adc #'0'
    ldx dec_role
    jsr plat_put
    iny
    rts

; ---------------------------------------------------------------------------
; display_init — a blank screen and the title bar.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_init
display_init:
    jsr plat_cls

    set_ptr str_title
    lda #ROW_TITLE
    ldx #COL_TITLE
    jsr print_str

    set_ptr str_brand
    lda #ROW_TITLE
    ldx #COL_BRAND
    jsr print_str

    lda #ROW_TITLE              ; the band goes on last, behind both
    ldx #0
    ldy #SCREEN_COLS
    jmp plat_reverse

; ---------------------------------------------------------------------------
; display_device — what the device calls itself, on the row under the title.
;
; The strings are read once while the session is opening, so this can only be
; drawn after that.  Every page keeps it, and the all-pins page redraws it
; because it clears the screen on the way in.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_device
display_device:
    lda #ROW_DEVICE
    jsr clear_row
    set_ptr sess_dev_type
    lda #ROW_DEVICE
    ldx #COL_GROUP
    jsr print_str
    set_ptr sess_dev_ver
    lda #ROW_DEVICE
    ldx str_col                 ; where the name ended, plus a space
    inx
    jsr print_str
.if SCREEN_COLS >= 32
    set_ptr sess_proto
    lda #ROW_DEVICE
    ldx #COL_DEV_PROTO
    jsr print_str
.endif
    rts

; ---------------------------------------------------------------------------
; display_keys — the key rows.  Written once and left alone, except while a
; blink is running, when they are cleared to keep the screen
; quiet and put back afterwards.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; display_frame — the parts every page has: a blank screen, the title bar and
; the device row.  A page draws its own body over this and nothing else may
; assume what a previous page left behind.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_frame
display_frame:
    jsr display_init
    jmp display_device

; ---------------------------------------------------------------------------

.export display_keys
display_keys:
    ldx #0
@loop:
    stx ZP_APP5
    txa
    clc
    adc #ROW_KEYS1
    jsr clear_row               ; the reset screen writes a longer line here
    lda ZP_APP5
    asl a
    tax
    lda str_keys_tab, x
    sta ZP_PTR_LO
    lda str_keys_tab + 1, x
    sta ZP_PTR_HI
    lda ZP_APP5
    clc
    adc #ROW_KEYS1
    ldx #COL_GROUP
    jsr print_str
    ldx ZP_APP5
    inx
    cpx #KEY_LINES
    bne @loop
    rts

.export display_keys_clear
display_keys_clear:
    ldx #0
@loop:
    stx ZP_APP5
    txa
    clc
    adc #ROW_KEYS1
    jsr clear_row
    ldx ZP_APP5
    inx
    cpx #KEY_LINES
    bne @loop
    rts

; ---------------------------------------------------------------------------
; display_group — the group name, which group of how many, and how many of its
; pins can be driven.
; Clobbers A, X, Y and the app zero page.
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
    jsr print_str

    jsr display_page
    jsr band

    ; "n OF m PINS CAN BE DRIVEN"
    lda #ROW_COUNT
    jsr plat_row
    ldx cur_group
    lda pins_group_drv, x
    ldy #COL_GROUP
    ldx #COLR_TEXT
    jsr put_dec
    iny                         ; a space before OF
    sty ZP_APP5
    set_ptr str_of
    lda #ROW_COUNT
    ldx ZP_APP5
    jsr print_str
    lda #ROW_COUNT
    jsr plat_row
    ldx cur_group
    lda pins_group_pins, x
    ldy ZP_APP5
    iny
    iny
    iny                         ; past OF and the space after it
    ldx #COLR_TEXT
    jsr put_dec
    sty ZP_APP5
    set_ptr str_drivable
    lda #ROW_COUNT
    ldx ZP_APP5
    inx
    jmp print_str

; ---------------------------------------------------------------------------
; display_page — "n OF m" at the right of the group row.  There is one page per
; group of pins and one more after them holding every pin at once, and this is
; what tells you which of them you are looking at.
; Clobbers A, X, Y and ZP_APP5.
; ---------------------------------------------------------------------------

display_page:
    lda #ROW_GROUP
    jsr plat_row
    lda cur_page
    clc
    adc #1
    ldy #COL_OF
    ldx #COLR_TEXT
    jsr put_dec
    iny                         ; a space before OF
    sty ZP_APP5
    set_ptr str_of
    lda #ROW_GROUP
    ldx ZP_APP5
    jsr print_str
    lda #ROW_GROUP
    jsr plat_row
    lda pins_group_count
    clc
    adc #1                      ; the all-pins page is one past the last group
    ldy ZP_APP5
    iny
    iny
    iny                         ; past OF and the space after it
    ldx #COLR_TEXT
    jsr put_dec
    sty str_col                 ; band reverses up to here
    rts

; ---------------------------------------------------------------------------
; band — turns the group row over from the name to the end of the page count,
; so the heading reads as one thing rather than two facts at opposite ends of
; a line.  The width is fixed, so the reset screen, which has no page count,
; still gets the same band as every other page.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

band:
    ldy #COL_OF + 6 - COL_GROUP ; "n OF m" is six columns, however few pages
    lda #ROW_GROUP
    ldx #COL_GROUP
    jmp plat_reverse

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
    cmp #RBCP_AUX_TYPE_IMGSEL
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
; redrawing over the top is enough, and blanking the ring rows on each refresh
; makes the screen strobe — the rings are gone for as long as the clear takes,
; every pass.  display_rings_fresh is the one that clears, and the caller uses
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
    jsr pins_index
    tax
    lda pin_state, x
    and #PIN_LEVEL_BIT
    sta ring_filled
    lda pin_flags, x
    sta ring_pflags
    lda pin_state, x
    and #PIN_DRIVEN_BIT
    sta ring_driven

    jsr ring_colour
    sta ring_role

    jsr draw_ring
    jmp draw_pin_number

; ---------------------------------------------------------------------------
; ring_colour — the role, from the flags and driven bits already in
; ring_pflags and ring_driven.  Returns it in A.
; ---------------------------------------------------------------------------

ring_colour:
    lda ring_pflags
    and #RBCP_AUX_FLAG_DRIVABLE
    beq @theirs
    lda ring_driven
    beq @free
    lda #COLR_OURS
    rts
@free:
    lda #COLR_FREE
    rts
@theirs:
    lda #COLR_THEIRS
    rts

; ---------------------------------------------------------------------------
; draw_ring — top row ZP_APP7, left column ZP_APP6, tier ring_tier, filled from
; ring_filled, role ring_role.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

draw_ring:
    ldx ring_tier
    cpx #TIER_DOT
    bne @box

    ; one character, which carries the level as well as the role
    lda ZP_APP7
    jsr plat_row
    lda ring_filled
    beq @dot_empty
    lda #GLY_DOT_HIGH
    bne @dot_put
@dot_empty:
    lda #GLY_DOT_LOW
@dot_put:
    ldy ZP_APP6
    ldx ring_role
    jmp plat_glyph

@box:
    ; top
    lda ZP_APP7
    jsr plat_row
    lda #GLY_TL
    ldy ZP_APP6
    ldx ring_role
    jsr plat_glyph
    jsr ring_span_horiz
    lda #GLY_TR
    ldx ring_role
    jsr plat_glyph

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
    jsr plat_row
    lda #GLY_VERT
    ldy ZP_APP6
    ldx ring_role
    jsr plat_glyph
    jsr ring_span_fill
    lda #GLY_VERT
    ldx ring_role
    jsr plat_glyph
    dec ring_rows
    bne @mid

    ; bottom
    inc ring_row
    lda ring_row
    jsr plat_row
    lda #GLY_BL
    ldy ZP_APP6
    ldx ring_role
    jsr plat_glyph
    jsr ring_span_horiz
    lda #GLY_BR
    ldx ring_role
    jmp plat_glyph

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
    lda #GLY_HORIZ
    stx ring_span_tmp
    ldx ring_role
    jsr plat_glyph
    ldx ring_span_tmp
    iny
    dex
    bne @loop
    rts

; ---------------------------------------------------------------------------
; ring_span_fill — as ring_span_horiz, with the ring's inside instead: the
; high glyph where the level is high, the low one where it is not.
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
    lda #GLY_HIGH
    bne @put
@hollow:
    lda #GLY_LOW
@put:
    stx ring_span_tmp
    ldx ring_role
    jsr plat_glyph
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
    sta ring_row
    jsr plat_row

    ; centre the label in the ring's width
    ldx cur_group
    lda pins_group_type, x
    sta ZP_APP3
    lda ZP_APP8
    jsr pin_label_width
    sta ring_span_tmp
    ldx ring_tier
    lda tier_w, x
    sec
    sbc ring_span_tmp
    bcs @centred
    lda #0                      ; a number wider than its ring starts at its
@centred:                       ; left edge rather than a column short of $FF
    lsr a
    clc
    adc ZP_APP6
    tay

    lda ZP_APP8
    ldx ring_role
    jsr put_pin_label

    lda ZP_APP5
    cmp cur_slot
    bne @plain
    lda ring_row                ; the cursor, and the only one on screen
    ldx dec_col
    ldy dec_len
    jmp plat_reverse
@plain:
    rts

; ---------------------------------------------------------------------------
; put_pin_label — A = pin number, X = a COLR_ role, Y = column, and the group
; in all_group or cur_group as the caller has already set ZP_APP3.
;
; An image-select pin is named by letter, because that is what a One ROM calls
; its pads and what the board is silkscreened with.  Everything else is
; numbered.  Y comes back after the label either way, and dec_col and dec_len
; say where it went.
; Clobbers A.
; ---------------------------------------------------------------------------

put_pin_label:
    pha
    lda ZP_APP3
    cmp #RBCP_AUX_TYPE_IMGSEL
    beq @letter
    cmp #RBCP_AUX_TYPE_XPADS
    bne @plain
    pla                         ; X pads are called X1 upwards, not X0
    clc
    adc #1
    jmp put_dec
@plain:
    pla
    jmp put_dec
@letter:
    sty dec_col
    lda #1
    sta dec_len
    pla
    clc
    adc #'A'
    jsr plat_put
    iny
    rts

; ---------------------------------------------------------------------------
; pin_label_width — A = pin number, the group type in ZP_APP3.  How many
; columns its label takes, so a ring can centre it.  Clobbers A.
; ---------------------------------------------------------------------------

pin_label_width:
    ldy ZP_APP3
    cpy #RBCP_AUX_TYPE_IMGSEL
    beq @one
    cpy #RBCP_AUX_TYPE_XPADS
    bne @check
    clc
    adc #1
@check:
    cmp #10
    bcc @one
    lda #2
    rts
@one:
    lda #1
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
    jmp print_str
@out:
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

.export display_all_fresh
display_all_fresh:
    set_ptr str_all_title
    lda #ROW_GROUP
    ldx #COL_GROUP
    jsr print_str
    jsr display_page
    jsr band
    ; fall through

.export display_all
display_all:
    lda #ROW_COUNT + 1
    sta all_row
    lda #0
    sta all_group
@group:
    lda all_group
    cmp pins_group_count
    beq @to_tail
    lda all_row
    cmp #ROW_ALL_END
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
    jsr print_str
    lda all_row
    jsr plat_row
    ldx all_group
    lda pins_group_pins, x
    ldy #COL_OF
    ldx #COLR_TEXT
    jsr put_dec
    iny
    sty ZP_APP5
    set_ptr str_pins
    lda all_row
    ldx ZP_APP5
    jsr print_str

    inc all_row
    inc all_row                 ; a blank line, so a heading owns what is under it

    ; The pins, ALL_PER_ROW to a row.  An image-select group runs right to
    ; left here as it does on its own page, so its row is walked from the
    ; highest pin down and labelled with the one at the left-hand end.
    ldx all_group
    lda pins_group_type, x
    sta ZP_APP3
    lda #0
    sta all_pin
@bank:
    ldx all_group
    lda all_pin
    cmp pins_group_pins, x
    bne @row
    jmp @next_group
@row:
    lda all_pin
    sta all_first

    ; the last pin this row holds
    lda all_first
    clc
    adc #ALL_PER_ROW
    ldx all_group
    cmp pins_group_pins, x
    bcc @have_last
    lda pins_group_pins, x
@have_last:
    sec
    sbc #1
    sta all_last

    ; the label is whichever end of the row is drawn first
    lda all_row
    jsr plat_row
    lda ZP_APP3
    jsr pins_reversed
    bcs @label_high
    lda all_first
    jmp @label
@label_high:
    lda all_last
@label:
    ldy #COL_GROUP
    ldx #COLR_TEXT
    jsr put_pin_label

    ldy #COL_ALL
@cell:
    lda ZP_APP3
    jsr pins_reversed
    bcs @down
    lda all_pin
    jmp @emit
@down:
    lda all_last                ; all_last - (all_pin - all_first)
    clc
    adc all_first
    sec
    sbc all_pin
@emit:
    ldx all_group
    jsr pins_index
    sty ZP_APP5
    jsr pin_glyph               ; glyph in A, role in X
    ldy ZP_APP5
    jsr plat_glyph
    iny
    iny
    inc all_pin
    lda all_pin
    cmp all_last
    beq @cell
    bcc @cell
    inc all_row
    ldx all_group
    lda all_pin
    cmp pins_group_pins, x
    beq @next_group
    jmp @bank

@next_group:
    inc all_row
    inc all_group
    jmp @group

@tail:
.if SCREEN_COLS >= 32
    set_ptr str_leg_ours
    lda #ROW_KEYS1
    ldx #COLR_OURS
    jsr legend_line
    set_ptr str_leg_free
    lda #ROW_KEYS1
    ldx #COLR_FREE
    ldy #COL_GROUP + 18
    jsr legend_at
    set_ptr str_leg_theirs
    lda #ROW_KEYS1 + 1
    ldx #COLR_THEIRS
    jsr legend_line
    set_ptr str_leg_high
    ldy #COL_GROUP + 18
    ldx #COLR_FREE
    lda #ROW_KEYS1 + 1
    jmp legend_high
.else
    set_ptr str_leg_ours
    lda #ROW_KEYS1
    ldx #COLR_OURS
    jsr legend_line
    set_ptr str_leg_free
    lda #ROW_KEYS1 + 1
    ldx #COLR_FREE
    jsr legend_line
    set_ptr str_leg_theirs
    lda #ROW_KEYS1 + 2
    ldx #COLR_THEIRS
    jsr legend_line
    set_ptr str_leg_high
    ldy #COL_GROUP
    ldx #COLR_FREE
    lda #ROW_KEYS1 + 3
    jmp legend_high
.endif

; ---------------------------------------------------------------------------
; legend_line — A = row, X = a COLR_ role, ZP_PTR = what to call it.  Draws the
; character this machine uses for that role and the phrase beside it, so the
; legend says what is on the screen rather than naming a colour a screen may
; not have.
;
; legend_at is the same with the column in Y.
; Clobbers A, X, Y and ZP_APP5 to ZP_APP7.
; ---------------------------------------------------------------------------

legend_high:
    sta ZP_APP7
    sty ZP_APP6
    stx ZP_APP5
    jsr plat_row
    lda #GLY_DOT_HIGH           ; what a high pin looks like on this page
    ldy ZP_APP6
    ldx ZP_APP5
    jsr plat_glyph
    lda ZP_APP7
    ldx ZP_APP6
    inx
    inx
    jmp print_str

legend_line:
    ldy #COL_GROUP
legend_at:
    sta ZP_APP7                 ; row
    sty ZP_APP6                 ; column
    stx ZP_APP5                 ; role
    jsr plat_row
    lda #GLY_DOT_LOW
    ldy ZP_APP6
    ldx ZP_APP5
    jsr plat_glyph
    lda ZP_APP7
    ldx ZP_APP6
    inx
    inx
    jmp print_str

; ---------------------------------------------------------------------------
; pin_glyph — A = table index.  Returns the glyph in A and the role in X, by
; the same rule the rings use: fill is the level, role is who owns it.
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
    ldx #COLR_OURS
    bne @level
@free:
    ldx #COLR_FREE
    bne @level
@theirs:
    ldx #COLR_THEIRS
@level:
    lda pin_state, y
    and #PIN_LEVEL_BIT
    beq @empty
    lda #GLY_DOT_HIGH
    rts
@empty:
    lda #GLY_DOT_LOW
    rts

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
    jsr display_frame
    lda #ROW_GROUP
    jsr clear_row
    lda #ROW_COUNT
    jsr clear_row

    set_ptr str_r_title
    lda #ROW_GROUP
    ldx #COL_GROUP
    jsr print_str
    jsr band

    set_ptr str_r_pin
    lda #ROW_R_PIN
    ldx #COL_GROUP
    jsr print_str
    ldx cur_group
    lda pins_group_type, x
    sta ZP_APP3                 ; the name this group gives its pins
    jsr type_name
    lda #ROW_R_PIN
    ldx #COL_R_VAL
    jsr print_str
    lda #ROW_R_PIN
    jsr plat_row
    lda reset_pin
    ldy #COL_R_PIN
    ldx #COLR_TEXT
    jsr put_pin_label

    set_ptr str_r_hold
    lda #ROW_R_HOLD
    ldx #COL_GROUP
    jsr print_str
    lda #ROW_R_HOLD
    jsr plat_row
    lda #RESET_HOLD * 10
    ldy #COL_R_VAL
    ldx #COLR_TEXT
    jsr put_dec
    sty ZP_APP5
    set_ptr str_r_ms
    lda #ROW_R_HOLD
    ldx ZP_APP5
    jsr print_str

    set_ptr str_r_image
    lda #ROW_R_IMAGE
    ldx #COL_GROUP
    jsr print_str
    lda #ROW_R_IMAGE
    jsr plat_row
    lda reset_flash
    ldy #COL_R_VAL
    ldx #COLR_TEXT
    jsr put_dec
    set_ptr sess_flash_name
.if SCREEN_COLS >= 32
    lda #ROW_R_IMAGE
    ldx #COL_R_VAL + 4
.else
    lda #ROW_R_IMAGE + 1
    ldx #COL_GROUP
.endif
    jsr print_str

    set_ptr str_r_ends
    lda #ROW_R_ENDS
    ldx #COL_GROUP
    jsr print_str

    set_ptr str_r_pick
    lda #ROW_NOTE
    ldx #COL_GROUP
    jsr print_str
    set_ptr str_r_ask
    lda #ROW_KEYS1
    ldx #COL_GROUP
    jsr print_str
    set_ptr str_r_back
    lda #ROW_KEYS1 + 1
    ldx #COL_GROUP
    jmp print_str

; ---------------------------------------------------------------------------
; display_fail — A = a FAIL_ code.  Replaces everything: on a machine with no
; device there is nothing else worth showing.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_fail
display_fail:
    pha
    jsr display_init
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
    jmp print_str
@out:
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

str_brand:      .byte "PIERS.ROCKS", 0
str_leg_ours:   .byte "DRIVEN BY US", 0
str_leg_free:   .byte "FREE", 0
str_leg_theirs: .byte "IN USE BY ROM", 0
str_leg_high:   .byte "HIGH", 0
str_of:         .byte "OF", 0
str_pins:       .byte "PINS", 0
str_gpio:       .byte "GPIO", 0
str_imgsel:     .byte "IMAGE SELECT", 0
str_xpads:      .byte "X PINS", 0
str_none:       .byte "UNSORTED PINS", 0
str_type:       .byte "OTHER PINS", 0

str_keys_tab:
    .word str_keys1
    .word str_keys2
.if KEY_LINES > 2
    .word str_keys3
.endif

.if SCREEN_COLS >= 32

str_title:      .byte "RBCP AUX I/O", 0
str_all_title:  .byte "ALL PINS", 0
str_keys1:      .byte "CRSR MOVES  [ ] PAGE  R RESET", 0
str_keys2:      .byte "L LOW  H HIGH  Z REL  B BLINK", 0
str_drivable:   .byte "PINS CAN BE DRIVEN", 0
str_r_title:    .byte "EXIT AND RESET", 0
str_r_pin:      .byte "SELECTED PIN", 0
str_r_hold:     .byte "HELD LOW FOR", 0
str_r_ms:       .byte "MS, THEN RELEASED", 0
str_r_image:    .byte "IMAGE", 0
str_r_pick:     .byte "CRSR PICKS THE IMAGE", 0
str_r_back:     .byte "Z GOES BACK", 0
str_r_ends:     .byte "THIS ENDS THE PROGRAM", 0
str_r_ask:      .byte "RETURN RESETS THE MACHINE", 0

str_n_nodrive:  .byte "EVERY PIN HERE IS IN USE BY THE ROM", 0
str_n_blink:    .byte "BLINKING - ANY KEY STOPS", 0
str_n_refused:  .byte "THE DEVICE REFUSED THAT", 0
str_n_lost:     .byte "THE DEVICE STOPPED ANSWERING", 0
str_n_notdrv:   .byte "THAT PIN IS NOT OURS TO DRIVE", 0
str_n_trunc:    .byte "MORE PINS THAN THIS SCREEN SHOWS", 0
str_n_gone:     .byte "SENT - THE SESSION IS OVER", 0
str_n_noimage:  .byte "NO IMAGE HERE MATCHES THIS ROM", 0
str_n_noswitch: .byte "THIS DEVICE CANNOT SWITCH IMAGES", 0

str_f_nodev:    .byte "NO DEVICE ANSWERED THE KNOCK", 0
str_f_enter:    .byte "THE DEVICE REFUSED THE SESSION", 0
str_f_version:  .byte "THE DEVICE SPEAKS A VERSION WE DO NOT", 0
str_f_noaux:    .byte "THIS DEVICE HAS NO PINS TO DRIVE", 0

.else

str_title:      .byte "RBCP I/O", 0
str_all_title:  .byte "ALL PINS", 0
str_keys1:      .byte "CRSR MOVES  [ ] PAGE", 0
str_keys2:      .byte "L LOW H HIGH Z REL", 0
str_keys3:      .byte "B BLINK  R RESET", 0
str_drivable:   .byte "CAN BE DRIVEN", 0
str_r_title:    .byte "EXIT AND RESET", 0
str_r_pin:      .byte "PIN", 0
str_r_hold:     .byte "LOW", 0
str_r_ms:       .byte "MS", 0
str_r_image:    .byte "IMAGE", 0
str_r_pick:     .byte "CRSR PICKS THE IMAGE", 0
str_r_back:     .byte "Z GOES BACK", 0
str_r_ends:     .byte "THIS ENDS THE PROGRAM", 0
str_r_ask:      .byte "RETURN RESETS", 0

str_n_nodrive:  .byte "ALL IN USE BY THE ROM", 0
str_n_blink:    .byte "BLINKING - ANY KEY", 0
str_n_refused:  .byte "THE DEVICE REFUSED THAT", 0
str_n_lost:     .byte "THE DEVICE STOPPED", 0
str_n_notdrv:   .byte "NOT OURS TO DRIVE", 0
str_n_trunc:    .byte "MORE PINS THAN FIT", 0
str_n_gone:     .byte "SENT - SESSION OVER", 0
str_n_noimage:  .byte "NO IMAGE MATCHES THIS", 0
str_n_noswitch: .byte "IT CANNOT SWITCH IMAGES", 0

str_f_nodev:    .byte "NO DEVICE", 0
str_f_enter:    .byte "THE DEVICE REFUSED US", 0
str_f_version:  .byte "A VERSION WE DO NOT KNOW", 0
str_f_noaux:    .byte "NO PINS TO DRIVE", 0

.endif

note_tab:
    .word 0
    .word str_n_nodrive
    .word str_n_blink
    .word str_n_refused
    .word str_n_lost
    .word str_n_notdrv
    .word str_n_trunc
    .word str_n_gone
    .word str_n_noimage
    .word str_n_noswitch

fail_tab:
    .word str_f_nodev           ; FAIL_NO_DEVICE
    .word str_f_enter           ; FAIL_ENTER
    .word str_f_version         ; FAIL_VERSION
    .word str_f_noaux           ; FAIL_NO_AUX
