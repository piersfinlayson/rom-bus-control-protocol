; charset.s — the character set this program draws its discs out of
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The ROM character set has four diagonals and nothing else that curves, so a
; disc built out of it is an octagon.  The VIC can take its characters from RAM
; instead, which is what this builds: the ROM's own text characters, their
; inverses for reverse video, and the disc.
;
; The set lives at $3000, inside the VIC's default bank and above everything
; the linker puts in MAIN — led_test.cfg gives it a memory area of its own so a
; program that grew into it would fail to link rather than fail on screen.
;
; Reading the character ROM means uncovering it at $D000, which is where the
; I/O registers normally are.  Interrupts are already masked by the time this
; runs, and nothing between the two writes to $01 touches I/O.

    .include "led_defs.s"

.import disc_bitmaps

CHARSET_ROM     = $D000         ; the character ROM, once CHAREN is clear

; $D018 selects the video matrix in bits 7-4 and the character base in bits
; 3-1.  Screen stays at $0400, characters move to $3000.
VIC_CHARSET_VAL = %00011100

; ---------------------------------------------------------------------------
; The set itself.  led_test.cfg gives this segment a memory area of its own at
; $3000, so the linker owns the address rather than this file guessing it, and a
; program that grew into it would fail to link.
; ---------------------------------------------------------------------------

.segment "CHARS"

charset_ram:    .res $800

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

saved_memsetup: .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; charset_build — fills the set and points the VIC at it.
;
; Called before anything is drawn, with interrupts already masked.
; Clobbers A, X, Y and ZP_PTR.
; ---------------------------------------------------------------------------

.export charset_build
charset_build:
    .assert charset_ram = $3000, error, "VIC_CHARSET_VAL names $3000"

    lda VIC_MEMSETUP
    sta saved_memsetup

    ; The 64 text characters, straight from the ROM.  $00-$3F is every letter,
    ; digit and piece of punctuation this program prints.
    lda CPU_PORT
    pha
    and #%11111011              ; CHAREN low, so the ROM shows at $D000
    sta CPU_PORT

    lda #<CHARSET_ROM
    sta ZP_PTR_LO
    lda #>CHARSET_ROM
    sta ZP_PTR_HI
    lda #<charset_ram
    sta ZP_TMP0
    lda #>charset_ram
    sta ZP_TMP1
    ldx #2                      ; two pages, 64 characters
    jsr copy_pages

    pla
    sta CPU_PORT

    ; Their inverses, which is all reverse video is once the set is ours.
    ; Character N + $80 sits $400 further on.
    ldx #0
@invert:
    lda charset_ram + $000, x
    eor #$FF
    sta charset_ram + $400, x
    lda charset_ram + $100, x
    eor #$FF
    sta charset_ram + $500, x
    inx
    bne @invert

    ; The disc, in the two runs the text set leaves free.
    lda #<disc_bitmaps
    sta ZP_PTR_LO
    lda #>disc_bitmaps
    sta ZP_PTR_HI
    lda #<(charset_ram + DISC_BLOCK1_CODE * 8)
    sta ZP_TMP0
    lda #>(charset_ram + DISC_BLOCK1_CODE * 8)
    sta ZP_TMP1
    ldx #(DISC_BLOCK1_COUNT * 8 / 256)
    jsr copy_pages

    lda #<(disc_bitmaps + DISC_BLOCK1_COUNT * 8)
    sta ZP_PTR_LO
    lda #>(disc_bitmaps + DISC_BLOCK1_COUNT * 8)
    sta ZP_PTR_HI
    lda #<(charset_ram + DISC_BLOCK2_CODE * 8)
    sta ZP_TMP0
    lda #>(charset_ram + DISC_BLOCK2_CODE * 8)
    sta ZP_TMP1
    ldx #(DISC_BLOCK2_COUNT * 8 / 256)
    beq @tail
    jsr copy_pages
@tail:
    ldy #0
@byte:
    cpy #(DISC_BLOCK2_COUNT * 8 - 256 * (DISC_BLOCK2_COUNT * 8 / 256))
    beq @done
    lda (ZP_PTR_LO), y
    sta (ZP_TMP0), y
    iny
    bne @byte
@done:

    lda #VIC_CHARSET_VAL
    sta VIC_MEMSETUP
    rts

; ---------------------------------------------------------------------------
; charset_restore — puts the VIC back on the ROM set, so BASIC gets the machine
; back able to print.  Clobbers A.
; ---------------------------------------------------------------------------

.export charset_restore
charset_restore:
    lda saved_memsetup
    sta VIC_MEMSETUP
    rts

; ---------------------------------------------------------------------------
; copy_pages — X whole pages from ZP_PTR to ZP_TMP0.  Clobbers A, X, Y and both
; pointers.
; ---------------------------------------------------------------------------

copy_pages:
@page:
    ldy #0
@byte:
    lda (ZP_PTR_LO), y
    sta (ZP_TMP0), y
    iny
    bne @byte
    inc ZP_PTR_HI
    inc ZP_TMP1
    dex
    bne @page
    rts
