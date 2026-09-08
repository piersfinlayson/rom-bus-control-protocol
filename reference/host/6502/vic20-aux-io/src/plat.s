; plat.s — the VIC-20 side of the auxiliary I/O tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Reset entry, the copy into RAM, the vectors, the screen and the keys.
;
; Everything after boot_entry runs from RAM.  It has to, because the device is
; serving the kernal socket and the command page is a page of that socket, so a
; host fetching its instructions out of the image would be sending command
; bytes with every pass through a routine that happened to land there.  The
; whole of CODE and RODATA is copied down before the first knock, and after
; that nothing touches the socket except the command page reads the protocol
; makes and the back channel it writes.
;
; The screen has colour, so all three roles draw the same characters and the
; colour says which: green for a pin this machine is driving, white for one
; nobody is driving, and blue for one the ROM is using and we may not touch.

    .include "auxio_defs.s"

.import auxio_run

; Linker-generated symbols for the segments that run from RAM.
.import __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
.import __RODATA_SIZE__

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

shifted:    .res 1              ; 1 while a shift key is held during a scan
last_key:   .res 1              ; what the last scan found, so a held key
                                ; is reported once

; ===========================================================================
; FILL segment — the command page, then the back channel
; ===========================================================================

; This image is the kernal, so the machine boots into it through $FFFC.  The
; command page is the first page of it and the back channel the two after that,
; which is where the tester's own code is not.

.segment "FILL"

    .res 256, $00               ; $E000  the command page
    .res CONFIG_RBCP_BCH_SIZE, $00  ; $E100  the back channel

; ===========================================================================
; BOOT segment — runs from ROM, before the copy
; ===========================================================================

.segment "BOOT"

; ---------------------------------------------------------------------------
; boot_entry — the RESET vector's target.
;
; Interrupts are masked here and never unmasked.  Nothing in this program has
; anything to do in an interrupt, and one landing in the middle of a command
; frame would stretch it in time at best.
;
; RESTORE is not maskable, and it reaches the processor through VIA1, so both
; VIAs have every interrupt enable cleared.  With those clear it raises nothing,
; and the kernal's own handler, which would run kernal code in the middle of a
; command frame, is never entered.
; ---------------------------------------------------------------------------

.export boot_entry
boot_entry:
    sei
    cld
    ldx #$FF
    txs

    lda #VIA_IER_NONE
    sta VIA1_IER
    sta VIA2_IER

    ; The VIC-I has no display-enable bit, so it scans whatever the registers
    ; below point it at from the moment they are written.  Both regions are
    ; cleared first, so what appears is blank rather than what the kernal left.
    lda #$20                    ; space
    ldx #0
@scr:
    sta SCREEN_BASE, x
    sta SCREEN_BASE + $100, x
    inx
    bne @scr
    lda #COL_WHITE
    ldx #0
@col:
    sta COLOUR_RAM, x
    sta COLOUR_RAM + $100, x
    inx
    bne @col

    lda #VIC_H_CENTER_VAL
    sta VIC_H_CENTER
    lda #VIC_V_CENTER_VAL
    sta VIC_V_CENTER
    lda #VIC_COL_COUNT_VAL
    sta VIC_COL_COUNT
    lda #VIC_ROW_COUNT_VAL
    sta VIC_ROW_COUNT
    lda #0
    sta VIC_RASTER
    lda #VIC_MEM_VAL
    sta VIC_MEM
    lda #0
    sta VIC_LIGHTPEN_H
    sta VIC_LIGHTPEN_V
    sta VIC_PADDLE_X
    sta VIC_PADDLE_Y
    sta VIC_OSC1
    sta VIC_OSC2
    sta VIC_OSC3
    sta VIC_NOISE
    sta VIC_AUX_VOL
    lda #VIC_COLOUR_VAL
    sta VIC_COLOUR

    lda #VIA2_DDRB_VAL
    sta VIA2_DDRB
    lda #VIA2_DDRA_VAL
    sta VIA2_DDRA

    ; CODE and RODATA are laid out next to each other in the image and next to
    ; each other in RAM, so one copy moves both.
    lda #<__CODE_LOAD__
    sta ZP_PTR_LO
    lda #>__CODE_LOAD__
    sta ZP_PTR_HI
    lda #<__CODE_RUN__
    sta ZP_TMP0
    lda #>__CODE_RUN__
    sta ZP_TMP1
    lda #<(__CODE_SIZE__ + __RODATA_SIZE__)
    sta ZP_TMP2
    lda #>(__CODE_SIZE__ + __RODATA_SIZE__)
    sta ZP_TMP3

    ldy #0
@copy:
    lda (ZP_PTR_LO), y
    sta (ZP_TMP0), y
    iny
    bne @same_page
    inc ZP_PTR_HI
    inc ZP_TMP1
@same_page:
    lda ZP_TMP2
    bne @dec_lo
    dec ZP_TMP3
@dec_lo:
    dec ZP_TMP2
    lda ZP_TMP2
    ora ZP_TMP3
    bne @copy

    jmp auxio_run               ; its RAM address, the linker having said so

; Both VIAs have every interrupt enable cleared above, so neither vector is
; reached.  They hold an rti because a vector has to point somewhere.
irq_nmi_stub:
    rti

.segment "VECTORS"

    .word irq_nmi_stub          ; $FFFA-$FFFB  NMI
    .word boot_entry            ; $FFFC-$FFFD  RESET
    .word irq_nmi_stub          ; $FFFE-$FFFF  IRQ/BRK

; ===========================================================================
; CODE segment — runs from RAM
; ===========================================================================

.code

; ---------------------------------------------------------------------------
; Row addresses.  Twenty-three rows of twenty-two, one after another.  The
; colour row shares the low byte, so only the high one is worked out again.
; ---------------------------------------------------------------------------

row_off_lo:
    .repeat SCREEN_ROWS, i
        .byte <(i * SCREEN_COLS)
    .endrepeat

row_scr_hi:
    .repeat SCREEN_ROWS, i
        .byte >(SCREEN_BASE + i * SCREEN_COLS)
    .endrepeat

; ---------------------------------------------------------------------------
; plat_init — the display the tester draws on.  Everything it needs was set at
; entry, so all that is left is the key state.  Clobbers A.
; ---------------------------------------------------------------------------

.export plat_init
plat_init:
    lda #0
    sta last_key
    rts

; ---------------------------------------------------------------------------
; plat_cls — a blank screen in the text colour.  Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_cls
plat_cls:
    lda #$20                    ; space
    ldx #0
@scr:
    sta SCREEN_BASE, x
    sta SCREEN_BASE + $100, x
    inx
    bne @scr
    lda #COL_WHITE
    ldx #0
@col:
    sta COLOUR_RAM, x
    sta COLOUR_RAM + $100, x
    inx
    bne @col
    rts

; ---------------------------------------------------------------------------
; plat_row — A = row.  Points the screen writer and the colour writer at it.
; Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_row
plat_row:
    tax
    lda row_off_lo, x
    sta ZP_SCR_LO
    sta ZP_COL_LO
    lda row_scr_hi, x
    sta ZP_SCR_HI
    clc
    adc #COLOUR_OFFSET
    sta ZP_COL_HI
    rts

; ---------------------------------------------------------------------------
; plat_put — A = ASCII, Y = column, X = a COLR_ role.  Y and X come back as
; they went in, because the caller is walking a row with one and holding the
; role in the other.  Clobbers A.
; ---------------------------------------------------------------------------

.export plat_put
plat_put:
    pha
    lda colour_tab, x
    sta (ZP_COL_LO), y
    pla
    jsr to_screen_code
    sta (ZP_SCR_LO), y
    rts

; ---------------------------------------------------------------------------
; to_screen_code — A = ASCII, returns the screen code for it.  This character
; set holds one case, so a lower case letter is drawn as the upper case one.  A
; device that calls itself One ROM is the reason there is a second branch here
; at all.  Clobbers A.
; ---------------------------------------------------------------------------

to_screen_code:
    cmp #'@'
    bcc @done                   ; $20-$3F are their own screen codes
    cmp #'_' + 1
    bcs @lower
    sec
    sbc #$40                    ; $40-$5F, which is @ A-Z [ \ ] ^ _
    rts
@lower:
    cmp #'a'
    bcc @done
    cmp #'z' + 1
    bcs @done
    sec
    sbc #$60
@done:
    rts

; ---------------------------------------------------------------------------
; plat_glyph — A = a GLY_ index, Y = column, X = a COLR_ role.  Y comes back as
; it went in.  Clobbers A, X.
;
; Every role draws the same character and is told apart by its colour, which is
; what having colour buys.  The glyphs are screen codes already, so nothing
; converts them.
; ---------------------------------------------------------------------------

.export plat_glyph
plat_glyph:
    stx ZP_TMP0                 ; role
    tax
    lda glyph_tab, x
    sta (ZP_SCR_LO), y
    ldx ZP_TMP0
    lda colour_tab, x
    sta (ZP_COL_LO), y
    rts

; ---------------------------------------------------------------------------
; plat_fill_row — A = ASCII, X = a COLR_ role.  Fills the selected row.
; Clobbers A, Y.
; ---------------------------------------------------------------------------

.export plat_fill_row
plat_fill_row:
    jsr to_screen_code          ; X survives it, and is still the role
    sta ZP_TMP0
    lda colour_tab, x
    sta ZP_TMP1
    ldy #SCREEN_COLS - 1
@loop:
    lda ZP_TMP0
    sta (ZP_SCR_LO), y
    lda ZP_TMP1
    sta (ZP_COL_LO), y
    dey
    bpl @loop
    rts

; ---------------------------------------------------------------------------
; plat_reverse — A = row, X = column, Y = length.  Sets bit 7 on the screen
; codes already there, which is what reverse video is.  The colours are left
; alone, the run being the title bar and a pin number under the cursor.
; Clobbers A, X, Y and ZP_TMP0/1.
; ---------------------------------------------------------------------------

.export plat_reverse
plat_reverse:
    stx ZP_TMP0                 ; column, before plat_row takes X for the row
    sty ZP_TMP1                 ; length
    jsr plat_row
    ldy ZP_TMP0
    ldx ZP_TMP1
@loop:
    lda (ZP_SCR_LO), y
    ora #$80
    sta (ZP_SCR_LO), y
    iny
    dex
    bne @loop
    rts

; ---------------------------------------------------------------------------
; plat_dark, plat_light — nothing to do.  The VIC-I takes the alternate half of
; every cycle and steals none, so there is nothing to stop.  They are here
; because the shared code calls them.
; ---------------------------------------------------------------------------

.export plat_dark
plat_dark:
.export plat_light
plat_light:
    rts

; ---------------------------------------------------------------------------
; plat_key — a key press, once per press, or KEY_NONE_CODE.
;
; The matrix says what is held, not what has just been pressed, so a scan that
; finds what the last one found reports nothing.  That is what stops a held
; cursor key from running through every pin in the group.
;
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export plat_key
plat_key:
    jsr scan
    cmp last_key
    beq @nothing_new
    sta last_key
    ldx #DEBOUNCE_COUNT
@dly:
    dex
    bne @dly
    rts
@nothing_new:
    lda #KEY_NONE_CODE
    rts

; scan — what the matrix holds this instant, as a KEY_ code, or KEY_NONE_CODE.
scan:
    jsr shift_held
    lda #0
    rol a                       ; 1 while shift is held, 0 otherwise
    sta shifted

    ldx #0
@entry:
    lda key_table, x
    beq @none
    sta VIA2_PRB
    lda key_table + 1, x
    and VIA2_PRA
    beq @down
    inx
    inx
    inx
    inx
    bne @entry                  ; the table never reaches 64 entries
@none:
    lda #KEY_NONE_CODE
    rts

@down:
    txa
    clc
    adc #2                      ; the code, or the one after it under shift
    adc shifted
    tax
    lda key_table, x
    rts

; shift_held — carry set if either shift key is down.  Clobbers A.
shift_held:
    lda #KEY_LSHIFT_COL
    sta VIA2_PRB
    lda VIA2_PRA
    and #KEY_LSHIFT_BIT
    beq @yes
    lda #KEY_RSHIFT_COL
    sta VIA2_PRB
    lda VIA2_PRA
    and #KEY_RSHIFT_BIT
    beq @yes
    clc
    rts
@yes:
    sec
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; The tier tables.  Twenty-two columns, and twelve rows between ROW_RINGS and
; ROW_RINGS_END.
;
; A row of n rings is (n - 1) * pitch + w wide, so perrow is the largest n that
; stays inside twenty-two: big 9 + 7 = 16 for two, mid 14 + 5 = 19 for three,
; small 16 + 3 = 19 for five, dot 20 + 1 = 21 for eleven.
;
; A bank is the ring plus the pin number under it, so bankh is h + 1, and the
; last bank's number row has to land on ROW_RINGS_END or above it.  That is
; (17 - 4 - h) / bankh + 1 banks: two big, three mid, three small, seven dot.
;
; tier_cap is perrow times banks, and never more than MAX_PINS.  The dot tier
; would hold seventy-seven, which is more than MAX_PINS, so it is the one the
; limit rather than the screen decides.
; ---------------------------------------------------------------------------

.export tier_w
.export tier_h
.export tier_pitch
.export tier_perrow
.export tier_bankh
.export tier_cap

; The dot tier is one character wide and its pin number is two, so its pitch
; is three rather than two.  At a pitch of two the numbers of consecutive pins
; run into each other and the row reads as one long figure.  Seven across at a
; pitch of three is nineteen columns of twenty-two.
tier_w:         .byte 7, 5, 3, 1
tier_h:         .byte 5, 3, 3, 1
tier_pitch:     .byte 9, 7, 4, 3
tier_perrow:    .byte 2, 3, 5, 7
tier_bankh:     .byte 6, 4, 4, 2
tier_cap:       .byte 4, 9, 15, 42

; ---------------------------------------------------------------------------
; The glyphs, in GLY_ order: the four corners, the horizontal and vertical
; edges, a ring's inside high and low, and the one character tier high and low.
; Screen codes, checked against the VIC-20 character ROM.
;
; One row, not one per role, because the colour is what says who owns the pin.
; ---------------------------------------------------------------------------

glyph_tab:
    .byte $55                   ; GLY_TL        rounded top left
    .byte $49                   ; GLY_TR        rounded top right
    .byte $4A                   ; GLY_BL        rounded bottom left
    .byte $4B                   ; GLY_BR        rounded bottom right
    .byte $40                   ; GLY_HORIZ
    .byte $5D                   ; GLY_VERT
    .byte $A0                   ; GLY_HIGH      reversed space
    .byte $20                   ; GLY_LOW       space
    .byte $51                   ; GLY_DOT_HIGH  filled circle
    .byte $57                   ; GLY_DOT_LOW   hollow circle

; The colour each role is drawn in, in COLR_ order.  The title bar is white and
; turned over afterwards by plat_reverse.
colour_tab:
    .byte COL_BLUE              ; COLR_THEIRS
    .byte COL_WHITE             ; COLR_FREE
    .byte COL_RED               ; COLR_OURS
    .byte COL_WHITE             ; COLR_TEXT
    .byte COL_WHITE             ; COLR_TITLE

; ---------------------------------------------------------------------------
; The keyboard matrix, four bytes an entry: the column select, the row bit, the
; code, and the code a shift gives instead.  A column mask of zero ends it,
; which is never a valid one — a valid mask has exactly one bit clear.  Entries
; are tried in order and the first match wins.
;
; The cursor keys come first because they are the ones held down.  Both shift
; keys are missing on purpose: they are read by shift_held, and an entry for
; either would match on its own.  So is every key this program has no use for,
; there being no way out of it but the reset screen.
; ---------------------------------------------------------------------------

key_table:
    .byte %11111011, %10000000, KEY_PIN_NEXT, KEY_PIN_PREV  ; CRSR left/right
    .byte %11110111, %10000000, KEY_ROW_NEXT, KEY_ROW_PREV  ; CRSR up/down
    .byte %11111101, %10000000, KEY_RETURN_CODE, KEY_RETURN_CODE ; RETURN

    .byte %11111011, %00100000, KEY_LOW_CODE,  KEY_LOW_CODE     ; L
    .byte %11011111, %00001000, KEY_HIGH_CODE, KEY_HIGH_CODE    ; H
    .byte %11101111, %00000010, KEY_REL_CODE,  KEY_REL_CODE     ; Z
    .byte %11101111, %00001000, KEY_BLINK_CODE, KEY_BLINK_CODE  ; B
    .byte %11011111, %00100000, KEY_PAGE_PREV, KEY_PAGE_PREV    ; : and [
    .byte %11111011, %01000000, KEY_PAGE_NEXT, KEY_PAGE_NEXT    ; ; and ]
    .byte %11111101, %00000100, KEY_RESET_CODE, KEY_RESET_CODE  ; R

    .byte 0
