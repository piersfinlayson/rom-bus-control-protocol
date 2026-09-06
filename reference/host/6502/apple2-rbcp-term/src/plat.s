; plat.s — the Apple IIe side of the RBCP terminal
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Reset entry, the copy into RAM, the vectors, the screen and the keys.
;
; Everything after boot_entry runs from RAM.  It has to, because the device is
; serving the EF socket and the command page is a page of that socket, so a
; host fetching its instructions out of the image would be sending command
; bytes with every pass through a routine that happened to land there.  The
; whole of CODE and RODATA is copied down before the first knock, and after
; that nothing touches the socket except the command page reads the protocol
; makes and the back channel it writes.

    .include "term_defs.s"

.import term_run

; Linker-generated symbols for the segments that run from RAM.
.import __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
.import __RODATA_SIZE__

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
; ---------------------------------------------------------------------------

.export boot_entry
boot_entry:
    sei
    cld
    ldx #$FF
    txs

    ; 40 column text, page 1, the primary character set.  Done here rather
    ; than after the copy so that a machine which cannot get that far still
    ; shows a text screen rather than whatever the graphics mode held.
    sta TXTSET
    sta MIXCLR
    sta TXTPAGE1
    sta LORES
    sta CLR80COL
    sta CLRALTCHAR
    sta KBDSTRB

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

; ---------------------------------------------------------------------------
; irq_nmi_stub — both vectors point here.  Interrupts are masked and never
; unmasked, and an Apple II motherboard raises no NMI, but a card can.
;
; It stays in ROM so that it is valid from the first cycle after reset, before
; the copy has run.  These two bytes are the only instructions ever fetched out
; of the served image once a session is open, and they are not on the command
; page, which is the page the device filters command bytes on.  So the device
; sees an ordinary ROM read and ignores it.
; ---------------------------------------------------------------------------

irq_nmi_stub:
    rti

; ===========================================================================
; CODE segment — runs from RAM
; ===========================================================================

.code

; ---------------------------------------------------------------------------
; Row addresses.  Screen rows are interleaved, so a table is cheaper than
; working the address out each time.
; ---------------------------------------------------------------------------

row_off_lo:
    .repeat SCREEN_ROWS, i
        .byte <(SCREEN_BASE + (i .mod 8) * $80 + (i / 8) * $28)
    .endrepeat

row_scr_hi:
    .repeat SCREEN_ROWS, i
        .byte >(SCREEN_BASE + (i .mod 8) * $80 + (i / 8) * $28)
    .endrepeat

; ---------------------------------------------------------------------------
; plat_init — the display the terminal draws on.  Everything it needs was set
; at reset, so there is nothing left to do.  Clobbers nothing.
; ---------------------------------------------------------------------------

.export plat_init
plat_init:
    rts

; ---------------------------------------------------------------------------
; plat_cls — a blank screen.  The whole of text page 1, the holes included,
; which is four pages and no tail to count.  Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_cls
plat_cls:
    lda #$A0                    ; a space, in normal video
    ldx #0
@page:
    sta SCREEN_BASE + $000, x
    sta SCREEN_BASE + $100, x
    sta SCREEN_BASE + $200, x
    sta SCREEN_BASE + $300, x
    inx
    bne @page
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
; The screen has no colour, and a character with bit 7 set is normal video, so
; a write is one ora.  Both bars are put down this way and turned over
; afterwards by plat_reverse.
; ---------------------------------------------------------------------------

.export plat_put
plat_put:
    ora #$80
    sta (ZP_SCR_LO), y
    rts

; ---------------------------------------------------------------------------
; plat_reverse — A = row, X = column, Y = length.  Clears bits 7 and 6 of the
; characters already there, which is what inverse video is.
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
    and #$3F
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
    lda #$A0
@blank:
    sta (ZP_SRC_LO), y
    iny
    cpy #SCREEN_COLS
    bne @blank
    rts

; ---------------------------------------------------------------------------
; plat_key — a key press in ASCII, once per press, or KEY_NONE_CODE.
;
; The keyboard latches the last key pressed and holds it until the strobe is
; cleared, so this reads and clears and a held key cannot arrive twice.  A key
; the terminal has no use for is cleared too, rather than left to be read as
; the next one.
;
; Clobbers A.
; ---------------------------------------------------------------------------

.export plat_key
plat_key:
    lda KBD
    bpl @none
    sta KBDSTRB
    and #$7F
    cmp #KEY_RET_CODE
    beq @out
    cmp #KEY_LEFT_ARROW
    beq @delete
    cmp #KEY_DEL_ASCII
    beq @delete
    cmp #'a'
    bcc @out
    cmp #'z' + 1
    bcs @out
    sec
    sbc #$20                    ; these screens hold one case, and it is upper
@out:
    rts
@delete:
    lda #KEY_DEL_CODE
    rts
@none:
    lda #KEY_NONE_CODE
    rts

; ===========================================================================
; CMD — the command page, which the device reads and the image never does
; ===========================================================================

.segment "CMD"
    .res 256, $00

; ===========================================================================
; BCH — the back-channel region, which the device writes and the image does not
; ===========================================================================

.segment "BCH"
    .res 64, $00

; ===========================================================================
; The 6502 vectors, read at reset and never again
; ===========================================================================

.segment "VECTORS"
    .word irq_nmi_stub          ; $FFFA-$FFFB  NMI
    .word boot_entry            ; $FFFC-$FFFD  RESET
    .word irq_nmi_stub          ; $FFFE-$FFFF  IRQ/BRK
