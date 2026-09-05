; plat.s — the Apple IIe side of the reliability meter
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Reset entry, the copy into RAM, the screen, and the vectors.
;
; Everything after boot_entry runs from RAM.  It has to, because the device is serving
; the EF socket, and a host that fetches instructions out of the image it is
; talking to is reading it, which the protocol does not allow between the
; knock and the exit.  So the whole of CODE and RODATA is copied down before
; the first knock and nothing touches the socket again except the command page
; reads and the back channel.

    .include "stress_defs.s"

.import stress_run

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
; anything to do in an interrupt, and an interrupt landing in the middle of a
; command frame would stretch it in time at best.
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

    jmp stress_run              ; its RAM address, the linker having said so

; ---------------------------------------------------------------------------
; irq_nmi_stub — both vectors point here.  Interrupts are masked and never
; unmasked, and an Apple II motherboard raises no NMI, but a card can.
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
; plat_init — the display the meter draws on.  Everything it needs was set at
; reset, so there is nothing left to do.  Clobbers nothing.
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
; The screen has no colour, so a role means one of two things here: normal
; video, which is the character with bit 7 set, or inverse, which is the
; character with bits 7 and 6 clear.  The title bar and the headline band are
; inverse and everything else is normal.
; ---------------------------------------------------------------------------

.export plat_put
plat_put:
    cpx #COLR_TITLE
    bcs @inverse
    ora #$80
    bne @write                  ; always taken, bit 7 having just been set
@inverse:
    and #$3F
@write:
    sta (ZP_SCR_LO), y
    rts

; ---------------------------------------------------------------------------
; plat_key — nothing on this machine does anything, so nothing is read.  The
; strobe is cleared so that a key pressed out of curiosity does not sit in the
; hardware for the rest of the run.
; Clobbers A.
; ---------------------------------------------------------------------------

.export plat_key
plat_key:
    lda KBD
    bpl @none
    sta KBDSTRB
@none:
    lda #KEY_NONE_CODE
    rts

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
