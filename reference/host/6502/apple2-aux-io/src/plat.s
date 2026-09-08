; plat.s — the Apple IIe side of the auxiliary I/O tester
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
;
; The screen has no colour, so the three roles are three different characters.
; A ring the ROM is using is drawn in dots, one nobody is driving in the box
; characters, and one this machine is driving in hashes, which is the heaviest
; of the three and the one that has been changed.

    .include "auxio_defs.s"

.import auxio_run

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
; Interrupts are masked here and never unmasked.  Nothing in this program has
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

    jmp auxio_run               ; its RAM address, the linker having said so

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
; plat_init — nothing beyond what boot_entry already did.  The screen mode is
; set from ROM so that a machine which never reaches RAM still shows text.
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
; plat_put — A = ASCII, Y = column, X = a COLR_ role.  Y comes back as it went
; in, because the caller is walking a row with it.  Clobbers A.
;
; The screen has no colour, and a character with bit 7 set is normal video, so
; a write is one ora.  The role says nothing about text — the title bar is put
; down this way and turned over afterwards by plat_reverse.
; ---------------------------------------------------------------------------

.export plat_put
plat_put:
    ora #$80
    sta (ZP_SCR_LO), y
    rts

; ---------------------------------------------------------------------------
; plat_glyph — A = a GLY_ index, Y = column, X = a COLR_ role.  Y comes back
; as it went in.  Clobbers A.
;
; With no colour to say who owns a pin, the character does.  glyph_tab holds
; one row of ten per role, and the two glyphs that mean a high level are drawn
; inverse, which is the same thing the filled ring means on a machine that has
; colour.
; ---------------------------------------------------------------------------

.export plat_glyph
plat_glyph:
    sta ZP_TMP0                 ; the glyph index
    txa
    asl a                       ; role * 10
    asl a
    asl a
    sta ZP_TMP1
    txa
    asl a
    clc
    adc ZP_TMP1
    adc ZP_TMP0
    tax
    lda glyph_tab, x
    ldx ZP_TMP0
    cpx #GLY_HIGH
    beq @inverse
    cpx #GLY_DOT_HIGH
    beq @inverse
    ora #$80                    ; normal video
    sta (ZP_SCR_LO), y
    ldx ZP_TMP0
    rts
@inverse:
    and #$3F
    sta (ZP_SCR_LO), y
    ldx ZP_TMP0
    rts

; ---------------------------------------------------------------------------
; plat_fill_row — A = ASCII, X = a COLR_ role.  Fills the selected row.
; Clobbers A, Y.
; ---------------------------------------------------------------------------

.export plat_fill_row
plat_fill_row:
    ora #$80
    ldy #SCREEN_COLS - 1
@loop:
    sta (ZP_SCR_LO), y
    dey
    bpl @loop
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
; plat_dark, plat_light — nothing to do.  The video takes the alternate half
; of every cycle and steals none, so there is nothing to stop.  They are here
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
; The keyboard latches the last key pressed and holds it until the strobe is
; cleared, so this reads and clears and a held key cannot arrive twice.  A key
; this program has no use for is cleared too, rather than left to be read as
; the next one.
;
; Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_key
plat_key:
    lda KBD
    bpl @none
    sta KBDSTRB
    and #$7F
    cmp #'a'
    bcc @have
    cmp #'z' + 1
    bcs @have
    sec
    sbc #$20                    ; this screen holds one case, and it is upper
@have:
    ldx #0
@look:
    cmp key_tab, x
    beq @found
    inx
    inx
    cpx #key_tab_end - key_tab
    bne @look
@none:
    lda #KEY_NONE_CODE
    rts
@found:
    lda key_tab + 1, x
    rts

; ===========================================================================
; CMD — the command page, which the device reads and the image never does
; ===========================================================================

.segment "CMD"
    .res 256, $00

; ===========================================================================
; BCH — the back-channel region the device writes its replies into
; ===========================================================================

.segment "BCH"
    .res CONFIG_RBCP_BCH_SIZE, $00

; ===========================================================================
; VECTORS
; ===========================================================================

.segment "VECTORS"
    .word irq_nmi_stub          ; NMI
    .word boot_entry            ; RESET
    .word irq_nmi_stub          ; IRQ/BRK

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; The tier tables.  Forty columns, and fourteen rows between ROW_RINGS and
; ROW_RINGS_END.  tier_cap is what each size holds: rings across, times banks
; down, and never more than MAX_PINS.
; ---------------------------------------------------------------------------

.export tier_w
.export tier_h
.export tier_pitch
.export tier_perrow
.export tier_bankh
.export tier_cap

; The dot tier is one character wide and its pin number is two, so its pitch
; is three rather than two.  At a pitch of two the numbers of consecutive pins
; run into each other and the row reads as one long figure.
tier_w:         .byte 7, 5, 3, 1
tier_h:         .byte 5, 3, 3, 1
tier_pitch:     .byte 9, 7, 4, 3
tier_perrow:    .byte 4, 5, 9, 13
tier_bankh:     .byte 6, 4, 4, 2
tier_cap:       .byte 8, 15, 27, MAX_PINS

; ---------------------------------------------------------------------------
; The glyphs, ten per role in GLY_ order: the four corners, the horizontal and
; vertical edges, a ring's inside high and low, and the one character tier high
; and low.
;
; The inside of a ring is a space whatever the role, because the level is said
; by inverse video rather than by the character.
; ---------------------------------------------------------------------------

glyph_tab:
    ; COLR_THEIRS — the ROM is using this pin
    .byte '.', '.', '.', '.', '.', '.', ' ', ' ', '.', '.'
    ; COLR_FREE — nobody is driving it
    .byte '+', '+', '+', '+', '-', '|', ' ', ' ', '-', '-'
    ; COLR_OURS — this machine is driving it
    .byte '#', '#', '#', '#', '#', '#', ' ', ' ', '#', '#'

; ---------------------------------------------------------------------------
; The keys, in pairs: the ASCII the keyboard gives, and the code this program
; knows it by.
; ---------------------------------------------------------------------------

key_tab:
    .byte KEY_RIGHT_ARROW, KEY_PIN_NEXT
    .byte KEY_LEFT_ARROW,  KEY_PIN_PREV
    .byte KEY_DOWN_ARROW,  KEY_ROW_NEXT
    .byte KEY_UP_ARROW,    KEY_ROW_PREV
    .byte 'L',             KEY_LOW_CODE
    .byte 'H',             KEY_HIGH_CODE
    .byte 'Z',             KEY_REL_CODE
    .byte 'B',             KEY_BLINK_CODE
    .byte ']',             KEY_PAGE_NEXT
    .byte '[',             KEY_PAGE_PREV
    .byte 'R',             KEY_RESET_CODE
    .byte $0D,             KEY_RETURN_CODE
key_tab_end:
