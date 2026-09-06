; plat.s — the VIC-20 side of the RBCP terminal
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Entry, the copy into RAM, the screen and the keys.
;
; Everything after boot_entry runs from RAM.  It has to, because the device is
; serving one of the machine's ROM sockets and the command page is a page of
; that socket, so a host fetching its instructions out of the image would be
; sending command bytes with every pass through a routine that happened to land
; there.  The whole of CODE and RODATA is copied down before the first knock,
; and after that nothing touches the socket except the command page reads the
; protocol makes and the back channel it writes.

    .include "term_defs.s"

.import term_run

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
; which is where the terminal's own code is not.

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
; Interrupts are masked here and never unmasked.  Nothing in this terminal has
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

    jmp term_run                ; its RAM address, the linker having said so

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
; Row addresses.  Twenty-three rows of twenty-two, one after another.
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
; plat_init — the display the terminal draws on.  Everything it needs was set
; at entry, so all that is left is the key state.  Clobbers A.
; ---------------------------------------------------------------------------

.export plat_init
plat_init:
    lda #0
    sta last_key
    rts

; ---------------------------------------------------------------------------
; plat_cls — a blank screen in the terminal's own colour.  Clobbers A, X.
;
; Colour RAM is written here and never again, every character on this screen
; being the same colour, so plat_put has a screen pointer to keep up to date
; and nothing else.
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
; plat_row — A = row.  Points the screen writer at it.  Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_row
plat_row:
    tax
    lda row_off_lo, x
    sta ZP_SCR_LO
    lda row_scr_hi, x
    sta ZP_SCR_HI
    rts

; ---------------------------------------------------------------------------
; plat_put — A = ASCII, Y = column.  Y comes back as it went in, because the
; caller is walking a row with it.  Clobbers A.
;
; This character set holds one case, so a lower case letter is drawn as the
; upper case one.  A device that calls itself One ROM is the reason there is a
; second branch here at all.
; ---------------------------------------------------------------------------

.export plat_put
plat_put:
    cmp #'A'
    bcc @write
    cmp #'Z' + 1
    bcs @lower
    sec
    sbc #$40
    bcs @write                  ; always taken
@lower:
    cmp #'a'
    bcc @write
    cmp #'z' + 1
    bcs @write
    sec
    sbc #$60
@write:
    sta (ZP_SCR_LO), y
    rts

; ---------------------------------------------------------------------------
; plat_reverse — A = row, X = column, Y = length.  Sets bit 7 on the screen
; codes already there, which is what reverse video is.
; Clobbers A, X, Y and ZP_TMP0/1.
; ---------------------------------------------------------------------------

.export plat_reverse
plat_reverse:
    stx ZP_TMP0                 ; column
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
; plat_scroll — the text area up one row, and the bottom row blanked.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export plat_scroll
plat_scroll:
    ldx #ROW_TEXT_TOP
@row:
    lda row_off_lo, x
    sta ZP_SCR_LO
    lda row_scr_hi, x
    sta ZP_SCR_HI
    inx
    lda row_off_lo, x
    sta ZP_SRC_LO
    lda row_scr_hi, x
    sta ZP_SRC_HI
    ldy #0
@byte:
    lda (ZP_SRC_LO), y
    sta (ZP_SCR_LO), y
    iny
    cpy #SCREEN_COLS
    bne @byte
    cpx #ROW_TEXT_BOT
    bne @row

    ldy #0                      ; ZP_SRC is the bottom row, now copied up
    lda #' '
@blank:
    sta (ZP_SRC_LO), y
    iny
    cpy #SCREEN_COLS
    bne @blank
    rts

; ---------------------------------------------------------------------------
; plat_key — a key press in ASCII, once per press, or KEY_NONE_CODE.
;
; The matrix says what is held, not what has just been pressed, so a scan that
; finds what the last one found reports nothing.  That is what stops a held key
; from filling the line.
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

; scan — what the matrix holds this instant, in ASCII, or KEY_NONE_CODE.
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

; The keyboard matrix, four bytes an entry: the column select, the row bit, the
; code, and the code a shift gives instead.  A column mask of zero ends it,
; which is never a valid one — a valid mask has exactly one bit clear.  Entries
; are tried in order and the first match wins.
;
; Both shift keys are missing on purpose: they are read by shift_held, and an
; entry for either would match on its own.  So are the keys with nothing to
; send — the function keys, the cursor keys, RUN/STOP, CTRL, the Commodore key,
; HOME, and the three whose characters this screen does not draw as itself.

key_table:
    .byte %11111110, %10000000, KEY_DEL_CODE, KEY_DEL_CODE  ; DEL
    .byte %11111101, %10000000, KEY_RET_CODE, KEY_RET_CODE  ; RETURN

    .byte %11101111, %00000001, ' ', ' '                    ; SPACE
    .byte %11111110, %00000001, '1', '!'
    .byte %01111111, %00000001, '2', '"'
    .byte %11111110, %00000010, '3', '#'
    .byte %01111111, %00000010, '4', '$'
    .byte %11111110, %00000100, '5', '%'
    .byte %01111111, %00000100, '6', '&'
    .byte %11111110, %00001000, '7', $27                    ; apostrophe
    .byte %01111111, %00001000, '8', '('
    .byte %11111110, %00010000, '9', ')'
    .byte %01111111, %00010000, '0', '0'

    .byte %11111011, %00000010, 'A', 'A'
    .byte %11101111, %00001000, 'B', 'B'
    .byte %11101111, %00000100, 'C', 'C'
    .byte %11111011, %00000100, 'D', 'D'
    .byte %10111111, %00000010, 'E', 'E'
    .byte %11011111, %00000100, 'F', 'F'
    .byte %11111011, %00001000, 'G', 'G'
    .byte %11011111, %00001000, 'H', 'H'
    .byte %11111101, %00010000, 'I', 'I'
    .byte %11111011, %00010000, 'J', 'J'
    .byte %11011111, %00010000, 'K', 'K'
    .byte %11111011, %00100000, 'L', 'L'
    .byte %11101111, %00010000, 'M', 'M'
    .byte %11110111, %00010000, 'N', 'N'
    .byte %10111111, %00010000, 'O', 'O'
    .byte %11111101, %00100000, 'P', 'P'
    .byte %10111111, %00000001, 'Q', 'Q'
    .byte %11111101, %00000100, 'R', 'R'
    .byte %11011111, %00000010, 'S', 'S'
    .byte %10111111, %00000100, 'T', 'T'
    .byte %10111111, %00001000, 'U', 'U'
    .byte %11110111, %00001000, 'V', 'V'
    .byte %11111101, %00000010, 'W', 'W'
    .byte %11110111, %00000100, 'X', 'X'
    .byte %11111101, %00001000, 'Y', 'Y'
    .byte %11101111, %00000010, 'Z', 'Z'

    .byte %11111110, %00100000, '+', '+'
    .byte %01111111, %00100000, '-', '-'
    .byte %11111101, %01000000, '*', '*'
    .byte %11110111, %01000000, '/', '?'
    .byte %11011111, %01000000, '=', '='
    .byte %11101111, %00100000, '.', '>'
    .byte %11110111, %00100000, ',', '<'
    .byte %11011111, %00100000, ':', ':'
    .byte %11111011, %01000000, ';', ';'

    .byte 0
