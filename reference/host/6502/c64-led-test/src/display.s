; display.s — everything this program puts on the screen
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The seam
; --------
; The tables in leds.s are the interface.  This file reads them and never
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
; An LED is a disc, in the colour the device says the LED is showing, filled as
; brightly as it says it is lit, doing what it says it is doing, with the mode
; written inside it.  Two of them side by side, in the order the device numbers
; them.
;
; The disc is drawn from what GET_LED_INFO reports and never from what the host
; asked for.  A device that ignores a colour or clamps a brightness shows up as
; itself.
;
; The disc is a real circle rather than the octagon the ROM character set can
; manage: the VIC takes its characters from RAM here, and charset.s puts an
; ellipse sampled per pixel into them.  Dimming ANDs that same ellipse with a
; halftone, so brightness never changes the shape.
;
; What is lit at any instant comes from show_col and show_dith, which led_test.s
; works out from the mode and the clock.  This file draws them and does not know
; whether it is watching a blink or a still LED.

    .include "led_defs.s"

.import c64_clear_screen
.import c64_print_at
.import row_off_lo
.import row_scr_hi
.import row_col_hi

.import leds_count
.import leds_truncated
.import leds_max_period
.import leds_max_hold
.import led_type
.import led_mode
.import led_red
.import led_green
.import led_blue
.import led_bright
.import led_period
.import led_modes
.import show_col
.import show_dith
.import want_pal

.import disc_class
.import disc_level_lo
.import disc_level_hi
.import leds_nearest
.import leds_supports
.import pal_r
.import pal_g
.import pal_b

.import sess_dev_type
.import sess_dev_ver
.import sess_proto

.import cur_led
.import pick_index

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

num_buf:        .res 4
dec_colour:     .res 1
dec_col:        .res 1
dec_rev_flag:   .res 1

line_buf:       .res 16
line_len:       .res 1

span_row:       .res 1
span_col:       .res 1
span_wid:       .res 1
line_colour:    .res 1
line_rev:       .res 1          ; $80 while text is being punched out of a disc
buf_col:        .res 1
buf_idx:        .res 1

disc_left:      .res 1          ; the disc being drawn
disc_colour:    .res 1
disc_glyph:     .res 1          ; what every cell becomes below full brightness
disc_top:       .res 1          ; the row the disc starts on
disc_end:       .res 1
disc_row:       .res 1
disc_col:       .res 1          ; column within the disc
disc_scr:       .res 1          ; and the screen column it lands on
disc_idx:       .res 1
tbl_idx:        .res 1

; A disc is put together here and then written to the screen in one go.  Drawing
; it straight to the screen means the beam can catch it half done, and what that
; looks like is the words inside it disappearing for a frame every time the
; brightness changes.
cell_out:       .res DISC_CELLS

; What is on the screen now, so that a pass which changes nothing writes
; nothing.  The scan runs continuously and a disc rewritten every pass flickers,
; which on a screen whose whole job is to be compared with an LED is the one
; thing it must not do.
shown_valid:    .res 1
shown_cursor:   .res 1
shown_type:     .res MAX_LEDS
shown_mode:     .res MAX_LEDS
shown_red:      .res MAX_LEDS
shown_green:    .res MAX_LEDS
shown_blue:     .res MAX_LEDS
shown_bright:   .res MAX_LEDS
shown_period:   .res MAX_LEDS
shown_col:      .res MAX_LEDS
shown_dith:     .res MAX_LEDS

all_row:        .res 1
tmp_row:        .res 1
tmp_mode:       .res 1
tmp_pick:       .res 1
pick_rgb:       .res 1

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
; row_ptrs — A = row.  Points ZP_SCR at that screen row and ZP_COL at the
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
; print_at — string at ZP_PTR, A = row, X = column.  Wraps c64_print_at, which
; wants them in its own scratch and writes only the screen plane, so the colour
; is whatever the row was cleared to.  Clobbers A, X, Y.
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
    ora dec_rev_flag
    ldx dec_colour
    jsr put_at
    iny
    rts

; ---------------------------------------------------------------------------
; put_dec3 — as put_dec but always three digits, so a column of them lines up.
; A = value, Y = column, X = colour.  Clobbers A, and returns Y after.
; ---------------------------------------------------------------------------

put_dec3:
    stx dec_colour
    ldx #0
@hundreds:
    cmp #100
    bcc @tens
    sbc #100
    inx
    bne @hundreds
@tens:
    stx num_buf + 0
    ldx #0
@tens_loop:
    cmp #10
    bcc @units
    sbc #10
    inx
    bne @tens_loop
@units:
    stx num_buf + 1
    sta num_buf + 2
    ldx #0
@emit:
    lda num_buf, x
    clc
    adc #$30
    stx ZP_APP8
    ldx dec_colour
    jsr put_at
    iny
    ldx ZP_APP8
    inx
    cpx #3
    bne @emit
    rts

; ---------------------------------------------------------------------------
; The line buffer.  Text that has to be measured before it is placed — the
; three lines inside a disc, and the label under one — is built here first and
; centred afterwards.
; ---------------------------------------------------------------------------

buf_reset:
    lda #0
    sta line_len
    rts

; buf_str — appends the string at ZP_PTR.  Clobbers A, Y.
buf_str:
    ldy #0
@loop:
    lda (ZP_PTR_LO), y
    beq @done
    sty ZP_APP8
    ldy line_len
    sta line_buf, y
    inc line_len
    ldy ZP_APP8
    iny
    bne @loop
@done:
    rts

; buf_ch — appends the character in A.  Clobbers Y.
buf_ch:
    ldy line_len
    sta line_buf, y
    inc line_len
    rts

; buf_dec — appends A in decimal, no leading zeros.  Clobbers A, X, Y.
buf_dec:
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

    lda num_buf + 0
    beq @skip_h
    clc
    adc #'0'
    jsr buf_ch
@skip_h:
    lda num_buf + 0
    ora num_buf + 1
    beq @skip_t
    lda num_buf + 1
    clc
    adc #'0'
    jsr buf_ch
@skip_t:
    lda num_buf + 2
    clc
    adc #'0'
    jmp buf_ch

; buf_secs — appends A, in the protocol's 100ms units, as seconds: "2.0S".
; Clobbers A, X, Y.
buf_secs:
    ldx #0
@tens:
    cmp #10
    bcc @done
    sbc #10
    inx
    bne @tens
@done:
    sta ZP_APP7                 ; tenths
    txa
    jsr buf_dec
    lda #'.'
    jsr buf_ch
    lda ZP_APP7
    clc
    adc #'0'
    jsr buf_ch
    lda #'S'
    jmp buf_ch

; ---------------------------------------------------------------------------
; buf_put — writes the buffer centred on the span that starts at column X and
; is Y cells wide, at the row in A, in line_colour.  line_rev of $80 reverses
; every cell, which is how text inside a lit disc is punched out of it.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

buf_put:
    sta span_row
    stx span_col
    sty span_wid
    jsr row_ptrs

    ; Blank the span first.  What goes in it changes length — a label gains
    ; brackets when the cursor arrives and loses them when it leaves — and
    ; writing the shorter one over the longer one would leave its ends behind.
    ldy span_col
    lda span_wid
    sta buf_idx
@blank:
    lda #SC_SPACE
    ldx line_colour
    jsr put_at
    iny
    dec buf_idx
    bne @blank

    lda span_wid
    sec
    sbc line_len
    lsr a                       ; half the slack
    clc
    adc span_col
    sta buf_col                 ; first column

    lda #0
    sta buf_idx
@loop:
    ldx buf_idx
    cpx line_len
    beq @done
    lda line_buf, x
    jsr scr_code
    ora line_rev                ; $80 reverses
    pha
    txa
    clc
    adc buf_col
    tay
    pla
    ldx line_colour
    jsr put_at
    inc buf_idx
    bne @loop
@done:
    rts

; ---------------------------------------------------------------------------
; scr_code — A = ASCII, returns the screen code.
;
; The two ranges are not the same.  ASCII $20 to $3F — space, the digits and
; the punctuation this program uses — are their own screen codes.  ASCII $40 to
; $5F, which is the letters and the brackets around the cursor's label, move
; down by $40.
; ---------------------------------------------------------------------------

scr_code:
    cmp #$40
    bcc @out
    cmp #$60
    bcs @out
    sec
    sbc #$40
@out:
    rts

; ---------------------------------------------------------------------------
; display_init — black on black with white text.  White on black rather than
; anything prettier: it is what reads on video, and it is what leaves a lit
; disc as the only colour on the screen.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export display_init
display_init:
    lda #0
    sta shown_valid
    sta dec_rev_flag
    lda #COL_BLACK
    sta VIC_BORDER
    sta VIC_BACKGROUND
    ldy #COL_WHITE
    jsr c64_clear_screen

    lda #ROW_TITLE
    jsr row_ptrs
    lda #SC_SPACE
    ldx #COL_LIGHT_BLUE
    jsr fill_row
    set_ptr str_title
    lda #ROW_TITLE
    ldx #1
    jsr print_at
    set_ptr str_brand
    lda #ROW_TITLE
    ldx #SCREEN_COLS - 12
    jsr print_at
    ; the title bar is reversed, so every cell on it gets bit 7
    lda #ROW_TITLE
    jsr row_ptrs
    ldy #SCREEN_COLS - 1
@rev:
    lda (ZP_SCR_LO), y
    ora #$80
    sta (ZP_SCR_LO), y
    dey
    bpl @rev
    rts

; ---------------------------------------------------------------------------
; display_keys — the four key rows.  Written once and left alone, except while
; a parade is running, when they are cleared to keep the screen quiet.
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
    jsr print_at
    set_ptr str_keys3
    lda #ROW_KEYS3
    ldx #1
    jmp print_at

.export display_keys_clear
display_keys_clear:
    lda #ROW_KEYS1
    jsr clear_row
    lda #ROW_KEYS2
    jsr clear_row
    lda #ROW_KEYS3
    jmp clear_row

; ---------------------------------------------------------------------------
; display_leds — every disc whose LED has changed since the last call, and
; every label if the cursor has moved.
;
; display_leds_fresh draws the lot, and is what to call after anything that
; cleared the screen.
;
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_leds_fresh
display_leds_fresh:
    lda #0
    sta shown_valid
    ; fall through

.export display_leds
display_leds:
    lda #0
    sta disc_idx
@each:
    jsr disc_changed
    bcc @cursor
    jsr draw_disc
    jsr draw_label
    jsr note_shown
    jmp @next
@cursor:
    lda shown_cursor
    cmp cur_led
    beq @next
    jsr set_disc_left
    jsr draw_label
@next:
    inc disc_idx
    lda disc_idx
    cmp leds_count
    bne @each

    lda cur_led
    sta shown_cursor
    lda #1
    sta shown_valid
    rts

; ---------------------------------------------------------------------------
; wait_lower_border — holds until the beam is below the last text row.
;
; A disc redrawn while the beam is crossing it tears: the top comes out at the
; new brightness and the bottom is still at the old one, once per change.
; Starting in the lower border leaves the blanking and the top border to draw
; in, which is enough for the disc that changed.
; Clobbers A.
; ---------------------------------------------------------------------------

wait_lower_border:
    lda VIC_CTRL1
    bmi wait_lower_border       ; the raster is past line 255
    lda VIC_RASTER
    cmp #251
    bcc wait_lower_border
    rts

; ---------------------------------------------------------------------------
; disc_changed — carry set if the LED at disc_idx is not what is on screen.
; Clobbers A, X.
; ---------------------------------------------------------------------------

disc_changed:
    lda shown_valid
    beq @yes
    ldx disc_idx
    lda led_type, x
    cmp shown_type, x
    bne @yes
    lda led_mode, x
    cmp shown_mode, x
    bne @yes
    lda led_red, x
    cmp shown_red, x
    bne @yes
    lda led_green, x
    cmp shown_green, x
    bne @yes
    lda led_blue, x
    cmp shown_blue, x
    bne @yes
    lda led_bright, x
    cmp shown_bright, x
    bne @yes
    lda led_period, x
    cmp shown_period, x
    bne @yes
    lda show_col, x
    cmp shown_col, x
    bne @yes
    lda show_dith, x
    cmp shown_dith, x
    bne @yes
    clc
    rts
@yes:
    sec
    rts

; note_shown — records what was just drawn.  Clobbers A, X.
note_shown:
    ldx disc_idx
    lda led_type, x
    sta shown_type, x
    lda led_mode, x
    sta shown_mode, x
    lda led_red, x
    sta shown_red, x
    lda led_green, x
    sta shown_green, x
    lda led_blue, x
    sta shown_blue, x
    lda led_bright, x
    sta shown_bright, x
    lda led_period, x
    sta shown_period, x
    lda show_col, x
    sta shown_col, x
    lda show_dith, x
    sta shown_dith, x
    rts

; ---------------------------------------------------------------------------
; draw_disc — draws the disc for disc_idx.
;
; The colour is the palette entry nearest what the device reports, so an LED
; the device chose a colour for is drawn in that colour and not in the one this
; program last asked for.  Grey is what an LED with no colour stated gets: it
; says so without pretending to be one.
;
; Below full brightness every cell of the disc becomes the same dither glyph,
; corners included.  That loses the diagonal cut and leaves the disc a little
; more octagonal, which is a far smaller change than the one the eye is being
; asked to see.
; ---------------------------------------------------------------------------

draw_disc:
    jsr set_disc_left
    lda #ROW_DISC
    sta disc_top

    ldx disc_idx
    lda show_col, x
    sta disc_colour
    ldy show_dith, x
    lda disc_level_lo, y
    sta ZP_PTR_LO
    lda disc_level_hi, y
    sta ZP_PTR_HI

    ; The text is always punched out of the disc rather than drawn in its
    ; colour.  A green word on a green halftone cannot be read, and being read
    ; next to the board is the whole point of putting it there.
    lda #$80
    sta line_rev

    jsr compose_cells
    jsr disc_text
    jmp blit_disc

; ---------------------------------------------------------------------------
; set_disc_left — the column the disc for disc_idx starts on.  A device with
; one LED puts it in the middle rather than off to the left.
; Clobbers A.
; ---------------------------------------------------------------------------

set_disc_left:
    lda leds_count
    cmp #1
    bne @two
    lda #(COL_DISC_0 + COL_DISC_1) / 2
    bne @have                   ; always taken
@two:
    lda disc_idx
    bne @right
    lda #COL_DISC_0
    bne @have                   ; always taken
@right:
    lda #COL_DISC_1
@have:
    sta disc_left
    rts

; ---------------------------------------------------------------------------
; draw_cells — draws one disc at disc_left in disc_colour, with ZP_PTR pointing
; at the character table for the brightness wanted.
;
; Each cell has a class — its shape — and each class is a character in each of
; the three tables.  A cell the disc does not reach is class zero, which every
; table gives as a space.
;
; Every cell of the thirteen by eleven box is written, including those spaces.
; Writing only the disc would leave whatever was there before showing through,
; and the text inside changes length: a mode that was BREATHE and is now ON
; would keep the ends of the longer word.
;
; Clobbers A, X, Y, ZP_APP0 to ZP_APP5.
; ---------------------------------------------------------------------------

compose_cells:
    lda ZP_PTR_LO
    sta ZP_APP4
    lda ZP_PTR_HI
    sta ZP_APP5

    ldx #0
@cell:
    lda disc_class, x
    tay
    lda (ZP_APP4), y
    sta cell_out, x
    inx
    cpx #DISC_CELLS
    bne @cell
    rts

; ---------------------------------------------------------------------------
; blit_disc — writes the composed disc to the screen, starting once the beam is
; below the last text row so that it is never caught half written.
; Clobbers A, X, Y, ZP_APP0 to ZP_APP3.
; ---------------------------------------------------------------------------

blit_disc:
    jsr wait_lower_border

    lda #0
    sta tbl_idx
    lda disc_top
    sta disc_row
    clc
    adc #DISC_H
    sta disc_end
@row:
    lda disc_row
    jsr row_ptrs
    ldx tbl_idx
    ldy disc_left
@cell:
    lda cell_out, x
    sta (ZP_SCR_LO), y
    lda disc_colour
    sta (ZP_COL_LO), y
    inx
    iny
    txa
    sec
    sbc tbl_idx
    cmp #DISC_W
    bne @cell
    lda tbl_idx
    clc
    adc #DISC_W
    sta tbl_idx
    inc disc_row
    lda disc_row
    cmp disc_end
    bne @row
    rts

; ---------------------------------------------------------------------------
; disc_text — what the LED is doing, written inside it: the mode, the colour,
; and the brightness and period in force.
; ---------------------------------------------------------------------------

disc_text:
    ldx disc_idx
    lda led_mode, x
    jsr build_mode
    lda #ROW_DISC_TEXT - ROW_DISC
    jsr buf_cells

    jsr build_colour
    lda #ROW_DISC_TEXT - ROW_DISC + 1
    jsr buf_cells

    jsr build_values
    lda #ROW_DISC_TEXT - ROW_DISC + 2
    jmp buf_cells

; ---------------------------------------------------------------------------
; buf_cells — lays the line buffer into the composed disc, centred, on the row
; A of the disc.  line_rev of $80 reverses it, which is how the words are
; punched out of the disc rather than written over it.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

buf_cells:
    sta ZP_APP7                 ; the row
    asl a
    asl a                       ; four rows' worth
    sta ZP_APP8
    asl a                       ; eight
    clc
    adc ZP_APP8                 ; twelve
    clc
    adc ZP_APP7                 ; and thirteen, which is the width
    sta buf_col

    lda #DISC_W
    sec
    sbc line_len
    lsr a
    clc
    adc buf_col
    sta buf_col

    lda #0
    sta buf_idx
@loop:
    ldx buf_idx
    cpx line_len
    beq @done
    lda line_buf, x
    jsr scr_code
    ora line_rev
    ldx buf_col
    sta cell_out, x
    inc buf_col
    inc buf_idx
    bne @loop
@done:
    rts

; ---------------------------------------------------------------------------
; build_mode — A = mode.  A mode the protocol does not name is shown as its
; number rather than as nothing: a device is allowed one, and a host that
; cannot say what it is looking at is worse than one that says a number.
; ---------------------------------------------------------------------------

build_mode:
    pha
    jsr buf_reset
    pla
    cmp #6
    bcs @unnamed
    asl a
    tax
    lda mode_names, x
    sta ZP_PTR_LO
    lda mode_names + 1, x
    sta ZP_PTR_HI
    jmp buf_str
@unnamed:
    pha
    set_ptr str_mode
    jsr buf_str
    pla
    jmp buf_dec

; ---------------------------------------------------------------------------
; build_colour — the name of the palette entry nearest what the device reports.
; ---------------------------------------------------------------------------

build_colour:
    jsr buf_reset
    lda disc_idx
    jsr leds_nearest
    ; fall through

; buf_pick_name — A = palette entry, appended to the line buffer.
buf_pick_name:
    bne @named
    set_ptr str_device
    jmp buf_str
@named:
    asl a
    tax
    lda colour_names - 2, x     ; entry 1 is the first name
    sta ZP_PTR_LO
    lda colour_names - 1, x
    sta ZP_PTR_HI
    jmp buf_str

; ---------------------------------------------------------------------------
; build_values — the brightness and the period, either of which an LED or a
; mode may not have, and neither of which is shown as a zero.  Zero is not a
; brightness and not a period, and printing one would say it was.
; ---------------------------------------------------------------------------

build_values:
    jsr buf_reset
    ldx disc_idx
    lda led_bright, x
    beq @no_bright
    jsr buf_dec
    lda #'%'
    jsr buf_ch
@no_bright:
    ldx disc_idx
    lda led_period, x
    beq @done
    ldy line_len
    beq @period
    lda #' '
    jsr buf_ch
@period:
    ldx disc_idx
    lda led_period, x
    jmp buf_secs
@done:
    rts

; ---------------------------------------------------------------------------
; draw_label — the number and type under a disc.  The one under the cursor is
; bracketed and white, the other grey, which is the only thing on this screen
; that says where the keys will land.
; ---------------------------------------------------------------------------

draw_label:
    jsr buf_reset
    lda disc_idx
    cmp cur_led
    bne @plain
    lda #'['
    jsr buf_ch
@plain:
    set_ptr str_led
    jsr buf_str
    lda disc_idx
    jsr buf_dec
    lda #' '
    jsr buf_ch

    ldx disc_idx
    lda led_type, x
    cmp #RBCP_LED_TYPE_MONO
    bne @not_mono
    set_ptr str_mono
    jsr buf_str
    jmp @close
@not_mono:
    cmp #RBCP_LED_TYPE_RGB
    bne @unnamed
    set_ptr str_rgb
    jsr buf_str
    jmp @close
@unnamed:
    pha
    lda #'T'
    jsr buf_ch
    pla
    jsr buf_dec
@close:
    lda disc_idx
    cmp cur_led
    bne @colour
    lda #']'
    jsr buf_ch
    lda #COL_WHITE
    bne @set                    ; always taken
@colour:
    lda #COL_MED_GREY
@set:
    sta line_colour
    lda #0
    sta line_rev
    lda #ROW_LABEL
    ldx disc_left
    ldy #DISC_W
    jsr buf_put

    ; and the key that picks it, under its name, for the same reason the mode
    ; keys sit under the modes.
    jsr buf_reset
    lda disc_idx
    asl a
    tax
    lda led_key_names, x
    sta ZP_PTR_LO
    lda led_key_names + 1, x
    sta ZP_PTR_HI
    jsr buf_str
    lda #COL_WHITE
    sta line_colour
    lda #ROW_LED_KEYS
    ldx disc_left
    ldy #DISC_W
    jmp buf_put

; ---------------------------------------------------------------------------
; put_str — string at ZP_PTR, Y = column, X = colour, at the row row_ptrs last
; selected.  Writes both planes, which print_at does not.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

put_str:
    stx line_colour
    sty buf_col
    lda #0
    sta buf_idx
@loop:
    ldy buf_idx
    lda (ZP_PTR_LO), y
    beq @done
    jsr scr_code
    pha
    tya
    clc
    adc buf_col
    tay
    pla
    ldx line_colour
    jsr put_at
    inc buf_idx
    bne @loop
@done:
    rts

; ---------------------------------------------------------------------------
; put_hex — A = value, Y = column, X = colour.  Two digits behind a dollar,
; because the one thing shown this way is a bitmap and a bitmap in decimal is
; unreadable.  Clobbers A, and returns Y after the last digit.
; ---------------------------------------------------------------------------

put_hex:
    stx dec_colour
    pha
    lda #'$'                    ; $20 to $3F are their own screen codes
    jsr put_at
    iny
    pla
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr @nybble
    pla
    and #$0F
@nybble:
    cmp #10
    bcc @digit
    sec
    sbc #9                      ; letters are screen codes 1 to 26
    bne @emit                   ; always taken
@digit:
    clc
    adc #'0'
@emit:
    ldx dec_colour
    jsr put_at
    iny
    rts

; ---------------------------------------------------------------------------
; display_modes — which modes this LED has, with the key that sets each one
; underneath it.
;
; The number is the protocol's mode number and the key is the same number, so
; there is nowhere better to put it than under the word it selects.  A mode
; this LED does not have is grey and has no key shown, because pressing it
; would only be refused.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export display_modes
display_modes:
    lda #ROW_MODES
    jsr clear_row
    lda #ROW_MODE_KEYS
    jsr clear_row
    lda #ROW_MODES
    jsr row_ptrs
    set_ptr str_modes
    ldy #0
    ldx #COL_MED_GREY
    jsr put_str

    lda #0
    sta tmp_mode                 ; the mode being listed
@each:
    lda cur_led
    ldx tmp_mode
    jsr leds_supports
    lda #COL_WHITE
    bcs @have
    lda #COL_DARK_GREY
@have:
    pha
    lda tmp_mode
    asl a
    tax
    lda mode_names, x
    sta ZP_PTR_LO
    lda mode_names + 1, x
    sta ZP_PTR_HI
    ldx tmp_mode
    ldy mode_cols, x
    pla
    tax
    jsr put_str
    inc tmp_mode
    lda tmp_mode
    cmp #6
    bne @each

    ; and the key for each, on the row below
    lda #ROW_MODE_KEYS
    jsr row_ptrs
    lda #0
    sta tmp_mode
@key:
    lda cur_led
    ldx tmp_mode
    jsr leds_supports
    bcc @next
    ldx tmp_mode
    ldy mode_key_cols, x
    txa
    clc
    adc #'0'                    ; the digits are their own screen codes
    ldx #COL_WHITE
    jsr put_at
@next:
    inc tmp_mode
    lda tmp_mode
    cmp #6
    bne @key
    rts

; ---------------------------------------------------------------------------
; display_read — what the last SET_LED read back as.
;
; This is the only check the program can make on its own.  Nothing it reads
; proves an LED lit — GET_LED_INFO answers out of the same place SET_LED wrote
; — but a device reporting back something other than what it was given has been
; caught, and the ALL LEDS screen has the numbers.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export display_read
display_read:
    pha
    lda #ROW_READ
    jsr clear_row
    pla
    cmp #READ_COUNT
    bcs @out
    cmp #READ_NONE
    beq @out
    asl a
    tax
    lda read_tab, x
    sta ZP_PTR_LO
    lda read_tab + 1, x
    sta ZP_PTR_HI
    txa
    lsr a
    tax
    lda read_col, x
    pha
    lda #ROW_READ
    jsr row_ptrs
    pla
    tax
    ldy #0
    jmp put_str
@out:
    rts

; ---------------------------------------------------------------------------
; display_note — A = a NOTE_ code.  The one plain line about what just
; happened.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export display_note
display_note:
    pha
    lda #ROW_NOTE
    jsr clear_row
    pla
    cmp #NOTE_COUNT
    bcs @out
    cmp #NOTE_BLANK
    beq @out
    asl a
    tax
    lda note_tab, x
    sta ZP_PTR_LO
    lda note_tab + 1, x
    sta ZP_PTR_HI
    lda #ROW_NOTE
    jsr row_ptrs
    ldy #0
    ldx #COL_YELLOW
    jmp put_str
@out:
    rts

; ---------------------------------------------------------------------------
; display_fail — A = a refusal code.  Replaces everything: on a machine with no
; device, or one this program will not touch, there is nothing else to show.
; Clobbers A, X, Y.
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
    jsr row_ptrs
    ldy #1
    ldx #COL_LIGHT_RED
    jsr put_str
    lda #ROW_KEYS1
    jsr row_ptrs
    set_ptr str_quit_only
    ldy #1
    ldx #COL_MED_GREY
    jmp put_str
@out:
    rts

; ---------------------------------------------------------------------------
; clear_rows — A = first row, X = last.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

clear_rows:
    stx ZP_APP8
@loop:
    sta tmp_row
    jsr clear_row
    lda tmp_row
    cmp ZP_APP8
    beq @done
    clc
    adc #1
    bne @loop                   ; always taken
@done:
    rts

; ---------------------------------------------------------------------------
; display_colours — the colour screen.
;
; The list is the C64's own fifteen, and picking one sends that colour's real
; RGB triple, so the disc on the left and the LED on the board are the same
; number rather than approximations of each other.  That is the whole reason a
; side by side comparison means anything.
;
; Black is not offered.  Whether an LED is lit is carried by its mode, so a
; colour being set is always one meant to be seen.
;
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_colours
display_colours:
    lda #ROW_TITLE + 1
    ldx #SCREEN_ROWS - 1
    jsr clear_rows

    lda #ROW_TITLE + 1
    jsr row_ptrs
    set_ptr str_colour_for
    ldy #1
    ldx #COL_MED_GREY
    jsr put_str
    lda cur_led
    ldy #16
    ldx #COL_WHITE
    jsr put_dec

    ; the preview, at full brightness in the colour being looked at
    lda #ROW_PREVIEW
    sta disc_top
    lda #COL_PREVIEW
    sta disc_left
    lda pick_index
    bne @have_colour
    lda #COL_MED_GREY
@have_colour:
    sta disc_colour
    ldx #DITH_SOLID
    lda disc_level_lo, x
    sta ZP_PTR_LO
    lda disc_level_hi, x
    sta ZP_PTR_HI
    jsr compose_cells

    jsr buf_reset
    lda pick_index
    jsr buf_pick_name
    lda #$80
    sta line_rev
    lda #DISC_H / 2
    jsr buf_cells
    jsr blit_disc
    lda #0
    sta line_rev

    ; the list, eight entries a column
    lda #0
    sta tmp_pick
@entry:
    lda tmp_pick
    and #7
    clc
    adc #ROW_PICK
    jsr row_ptrs

    lda tmp_pick
    cmp #8
    bcc @col_a
    ldy #COL_PICK_B
    bne @swatch                 ; always taken
@col_a:
    ldy #COL_PICK_A
@swatch:
    sty buf_col
    ldx tmp_pick
    bne @own
    ldx #COL_DARK_GREY          ; the device's own choice has no swatch to show
@own:
    lda #SC_SOLID
    jsr put_at

    jsr buf_reset
    lda tmp_pick
    jsr buf_pick_name
    lda tmp_pick
    cmp pick_index
    bne @plain
    lda #$80
    sta line_rev
    lda #COL_WHITE
    bne @write                  ; always taken
@plain:
    lda #0
    sta line_rev
    lda #COL_MED_GREY
@write:
    sta line_colour
    lda tmp_pick
    and #7
    clc
    adc #ROW_PICK
    ldx buf_col
    inx
    inx
    ldy line_len                ; no centring: the names line up on the left
    jsr buf_put

    inc tmp_pick
    lda tmp_pick
    cmp #PICK_COUNT
    bne @entry

    lda #0
    sta line_rev

    ; what this actually puts on the wire
    lda #ROW_SENDS
    jsr row_ptrs
    set_ptr str_sends
    ldy #0
    ldx #COL_WHITE
    jsr put_str
    ldx pick_index
    beq @zeroes
    dex
    stx pick_rgb
    lda pal_r, x
    ldy #7
    ldx #COL_WHITE
    jsr put_dec3
    ldx pick_rgb
    lda pal_g, x
    ldy #11
    ldx #COL_WHITE
    jsr put_dec3
    ldx pick_rgb
    lda pal_b, x
    ldy #15
    ldx #COL_WHITE
    jsr put_dec3
    jmp @sends_done
@zeroes:
    lda #0
    ldy #7
    ldx #COL_WHITE
    jsr put_dec3
    lda #0
    ldy #11
    ldx #COL_WHITE
    jsr put_dec3
    lda #0
    ldy #15
    ldx #COL_WHITE
    jsr put_dec3
@sends_done:
    lda #ROW_SENDS + 1
    jsr row_ptrs
    set_ptr str_wire
    ldy #0
    ldx #COL_MED_GREY
    jsr put_str

    lda #ROW_KEYS2
    jsr row_ptrs
    set_ptr str_pick_keys1
    ldy #1
    ldx #COL_MED_GREY
    jsr put_str
    lda #ROW_KEYS3
    jsr row_ptrs
    set_ptr str_pick_keys2
    ldy #1
    ldx #COL_MED_GREY
    jmp put_str

; ---------------------------------------------------------------------------
; display_all — every byte GET_LED_INFO reported, and the two capability
; limits, and what the device calls itself.
;
; This is the screen the readback line points at.  It is the only place the
; numbers are, and it is where a device that reports back something other than
; what it was given is caught in full.
;
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_all
display_all:
    lda #ROW_TITLE + 1
    ldx #SCREEN_ROWS - 1
    jsr clear_rows

    lda #2
    jsr row_ptrs
    set_ptr str_all_head
    ldy #0
    ldx #COL_MED_GREY
    jsr put_str

    lda #0
    sta all_row
@led:
    lda all_row
    clc
    adc #4
    jsr row_ptrs

    lda all_row
    ldy #0
    ldx #COL_WHITE
    jsr put_dec

    ldx all_row
    lda led_type, x
    cmp #RBCP_LED_TYPE_MONO
    bne @not_mono
    set_ptr str_mono
    jmp @type_out
@not_mono:
    cmp #RBCP_LED_TYPE_RGB
    bne @type_num
    set_ptr str_rgb
@type_out:
    ldy #2
    ldx #COL_WHITE
    jsr put_str
    jmp @mode
@type_num:
    ldy #2
    ldx #COL_WHITE
    jsr put_dec3

@mode:
    ldx all_row
    lda led_mode, x
    cmp #6
    bcs @mode_num
    asl a
    tax
    lda mode_names, x
    sta ZP_PTR_LO
    lda mode_names + 1, x
    sta ZP_PTR_HI
    ldy #7
    ldx #COL_WHITE
    jsr put_str
    jmp @rgb
@mode_num:
    ldy #7
    ldx #COL_WHITE
    jsr put_dec3

@rgb:
    ldx all_row
    lda led_red, x
    ldy #15
    ldx #COL_WHITE
    jsr put_dec3
    ldx all_row
    lda led_green, x
    ldy #19
    ldx #COL_WHITE
    jsr put_dec3
    ldx all_row
    lda led_blue, x
    ldy #23
    ldx #COL_WHITE
    jsr put_dec3
    ldx all_row
    lda led_bright, x
    ldy #27
    ldx #COL_WHITE
    jsr put_dec3
    ldx all_row
    lda led_period, x
    ldy #31
    ldx #COL_WHITE
    jsr put_dec3
    ldx all_row
    lda led_modes, x
    ldy #35
    ldx #COL_WHITE
    jsr put_hex

    inc all_row
    lda all_row
    cmp leds_count
    beq @limits
    jmp @led

@limits:
    lda #8
    jsr row_ptrs
    set_ptr str_max_period
    ldy #0
    ldx #COL_MED_GREY
    jsr put_str
    lda leds_max_period
    ldy #12
    ldx #COL_WHITE
    jsr put_dec3
    set_ptr str_max_hold
    ldy #18
    ldx #COL_MED_GREY
    jsr put_str
    lda leds_max_hold
    ldy #28
    ldx #COL_WHITE
    jsr put_dec3

    lda #10
    jsr row_ptrs
    lda #<sess_dev_type
    sta ZP_PTR_LO
    lda #>sess_dev_type
    sta ZP_PTR_HI
    ldy #0
    ldx #COL_WHITE
    jsr put_str
    lda #<sess_dev_ver
    sta ZP_PTR_LO
    lda #>sess_dev_ver
    sta ZP_PTR_HI
    ldy #14
    ldx #COL_WHITE
    jsr put_str
    lda #<sess_proto
    sta ZP_PTR_LO
    lda #>sess_proto
    sta ZP_PTR_HI
    ldy #24
    ldx #COL_WHITE
    jsr put_str

    lda leds_truncated
    beq @keys
    lda #12
    jsr row_ptrs
    set_ptr str_truncated
    ldy #0
    ldx #COL_YELLOW
    jsr put_str
@keys:
    lda #ROW_KEYS3
    jsr row_ptrs
    set_ptr str_any_key
    ldy #1
    ldx #COL_MED_GREY
    jmp put_str

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; Where each mode's name starts on the modes row, and where its key sits under
; the middle of that name.
mode_cols:
    .byte 6, 10, 13, 19, 27, 33
mode_key_cols:
    .byte 7, 10, 15, 22, 29, 35

; The key that picks each LED.  Two of them, because two is every LED this
; program shows.
led_key_names:
    .word str_f1, str_f3
str_f1:         .byte "F1", 0
str_f3:         .byte "F3", 0

mode_names:
    .word str_off, str_on, str_blink, str_breathe, str_cycle, str_beacon

str_off:        .byte "OFF", 0
str_on:         .byte "ON", 0
str_blink:      .byte "BLINK", 0
str_breathe:    .byte "BREATHE", 0
str_cycle:      .byte "CYCLE", 0
str_beacon:     .byte "BEACON", 0
str_mode:       .byte "MODE ", 0

colour_names:
    .word str_c_white, str_c_red, str_c_cyan, str_c_purple
    .word str_c_green, str_c_blue, str_c_yellow, str_c_orange
    .word str_c_brown, str_c_ltred, str_c_dkgrey, str_c_grey
    .word str_c_ltgreen, str_c_ltblue, str_c_ltgrey

str_c_white:    .byte "WHITE", 0
str_c_red:      .byte "RED", 0
str_c_cyan:     .byte "CYAN", 0
str_c_purple:   .byte "PURPLE", 0
str_c_green:    .byte "GREEN", 0
str_c_blue:     .byte "BLUE", 0
str_c_yellow:   .byte "YELLOW", 0
str_c_orange:   .byte "ORANGE", 0
str_c_brown:    .byte "BROWN", 0
str_c_ltred:    .byte "LT RED", 0
str_c_dkgrey:   .byte "DK GREY", 0
str_c_grey:     .byte "GREY", 0
str_c_ltgreen:  .byte "LT GREEN", 0
str_c_ltblue:   .byte "LT BLUE", 0
str_c_ltgrey:   .byte "LT GREY", 0
str_device:     .byte "DEVICE", 0

str_title:      .byte "RBCP LED TESTER", 0
str_brand:      .byte "PIERS.ROCKS", 0
str_led:        .byte "LED ", 0
str_mono:       .byte "MONO", 0
str_rgb:        .byte "RGB", 0
str_modes:      .byte "MODES", 0

; The mode keys are not here: they are on the screen under the modes they set.
str_keys1:      .byte "CRSR L/R  LED       CRSR U/D  COLOUR", 0
str_keys2:      .byte "C COLOURS  B BRIGHT  P PERIOD  H HOLD", 0
str_keys3:      .byte "SPACE PARADE   A ALL   Q QUIT", 0
str_quit_only:  .byte "Q QUITS", 0
str_any_key:    .byte "ANY KEY BACK", 0
str_pick_keys1: .byte "CRSR MOVES    RETURN SETS IT", 0
str_pick_keys2: .byte "Q BACKS OUT", 0

str_sends:      .byte "SENDS", 0
str_colour_for: .byte "THE COLOUR FOR LED", 0
str_wire:       .byte "THE C64 PALETTE IS WHAT GOES ON THE WIRE", 0
str_all_head:   .byte "N TYPE MODE      R   G   B BRI PER MOD", 0
str_max_period: .byte "MAX PERIOD", 0
str_max_hold:   .byte "MAX HOLD", 0
str_truncated:  .byte "THIS DEVICE HAS MORE LEDS THAN ARE SHOWN", 0

; Indexed by the readback code, and coloured by whether it is good news.
read_tab:
    .word str_r_none, str_r_match, str_r_differs, str_r_refused
read_col:
    .byte COL_WHITE, COL_LIGHT_GREEN, COL_LIGHT_RED, COL_LIGHT_RED

str_r_none:     .byte "", 0
str_r_match:    .byte "LAST SET LED  OK   READ BACK AGREES", 0
str_r_differs:  .byte "READ BACK DIFFERS FROM WHAT WAS SENT", 0
str_r_refused:  .byte "THE DEVICE REFUSED THAT SET LED", 0

note_tab:
    .word str_n_blank, str_n_refused, str_n_lost, str_n_nocolour
    .word str_n_noperiod, str_n_nohold, str_n_unsupported, str_n_truncated
    .word str_n_parade, str_n_gone

str_n_blank:        .byte "", 0
str_n_refused:      .byte "THE DEVICE REFUSED THAT", 0
str_n_lost:         .byte "THE DEVICE STOPPED ANSWERING", 0
str_n_nocolour:     .byte "THIS LED'S COLOUR IS NOT OURS TO SET", 0
str_n_noperiod:     .byte "THIS MODE TAKES NO PERIOD ON THIS LED", 0
str_n_nohold:       .byte "THIS DEVICE TIMES NO HOLDS", 0
str_n_unsupported:  .byte "THIS LED DOES NOT HAVE THAT MODE", 0
str_n_truncated:    .byte "MORE LEDS THAN THIS SHOWS  A SEES THEM", 0
str_n_parade:       .byte "WATCH THE DEVICE   ANY KEY STOPS", 0
str_n_gone:         .byte "THE SESSION IS OVER", 0

; Indexed by the refusal code, so the session's own come first, in the order
; app_defs.s numbers them, and this program's follow.
fail_tab:
    .word str_f_nodev           ; SESS_FAIL_NO_DEVICE
    .word str_f_enter           ; SESS_FAIL_ENTER
    .word str_f_version         ; SESS_FAIL_VERSION
    .word str_f_clash           ; SESS_FAIL_CLASH
    .word str_f_slots           ; SESS_FAIL_RAM_SLOTS
    .word str_f_noclean         ; SESS_FAIL_NO_CLEAN
    .word str_f_noleds          ; FAIL_NO_LEDS

str_f_nodev:    .byte "NO DEVICE ANSWERED THE KNOCK", 0
str_f_enter:    .byte "THE DEVICE REFUSED THE SESSION", 0
str_f_version:  .byte "THE DEVICE SPEAKS A VERSION WE DO NOT", 0
str_f_clash:    .byte "THE ROM ALREADY READS AS A REPLY", 0
str_f_slots:    .byte "THE DEVICE NEEDS TWO RAM SLOTS", 0
str_f_noclean:  .byte "NO FLASH SLOT MATCHES THIS ROM", 0
str_f_noleds:   .byte "THIS DEVICE HAS NO LEDS", 0
