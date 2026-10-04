; charset.s — the character set this program draws its discs out of
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The ROM character set has four diagonals and nothing else that curves, so a
; disc built out of it is an octagon.  The VIC can take its characters from RAM
; instead, which is what this builds: the ROM's own text characters, their
; inverses for reverse video, and the disc.
;
; The set is in the VIC's default bank, above everything else in RAM.
;
; Reading the character ROM means uncovering it at $D000, which is where the
; I/O registers normally are.  Interrupts are already masked by the time this
; runs, and nothing between the two writes to $01 touches I/O.
;
; The disc's characters are built here to save image space.  Each cell shape
; is a disc_gen shape, mirrored by its disc_shape bits.

    .include "led_defs.s"

.import disc_gen
.import disc_shape
.import disc_shape_end
.import disc_level_lo
.import disc_level_hi
.import disc_dither

DISC_LEVELS     = 3             ; len(LEVELS) in tools/gen_disc.py

CHARSET_ROM     = $D000         ; the character ROM, once CHAREN is clear

; $D018 selects the video matrix in bits 7-4 and the character base in bits
; 3-1.  Screen stays at $0400, characters move to $3800.
VIC_CHARSET_VAL = %00011110

; ---------------------------------------------------------------------------
; The set itself, in a memory area of its own in each linker configuration so
; a program that grew into it fails to link.
; ---------------------------------------------------------------------------

.segment "CHARS"

charset_ram:    .res $800

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

glyph_cls:      .res 1          ; the class being built, less one
glyph_lv:       .res 1          ; its brightness level
glyph_tf:       .res 1          ; its disc_shape byte
glyph_shape:    .res 8          ; its eight rows, undithered

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
    .assert charset_ram = $3800, error, "VIC_CHARSET_VAL names $3800"

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

    jsr disc_build

    lda #VIC_CHARSET_VAL
    sta VIC_MEMSETUP
    rts

; ---------------------------------------------------------------------------
; disc_build — the disc's characters, into the runs the text set leaves free.
;
; Each class's generator is mirrored into glyph_shape, then ANDed with each
; brightness mask into the class's code for that level.  A code two levels
; share is written twice with the same bytes.
;
; Clobbers A, X, Y, ZP_PTR, ZP_TMP0, ZP_TMP1 and ZP_TMP2.
; ---------------------------------------------------------------------------

disc_build:
    lda #0
    sta glyph_cls

@class:
    ldx glyph_cls
    lda disc_shape, x
    sta glyph_tf
    and #$FC
    asl a                       ; bits 7-2 are the generator, eight rows each
    tay
    ldx #0
@copy:
    lda disc_gen, y
    sta glyph_shape, x
    iny
    inx
    cpx #8
    bne @copy

    lda glyph_tf
    and #$01
    beq @no_mirror_x
    ldx #7                      ; left to right reverses the bits of each row
@row:
    lda glyph_shape, x
    sta ZP_TMP2
    lda #0
    ldy #8
@bit:
    lsr ZP_TMP2
    rol a
    dey
    bne @bit
    sta glyph_shape, x
    dex
    bpl @row
@no_mirror_x:

    lda glyph_tf
    and #$02
    beq @no_mirror_y
    ldx #0                      ; top to bottom reverses the order of the rows
    ldy #7
@swap:
    lda glyph_shape, x
    pha
    lda glyph_shape, y
    sta glyph_shape, x
    pla
    sta glyph_shape, y
    inx
    dey
    cpx #4
    bne @swap
@no_mirror_y:

    lda #0
    sta glyph_lv
@level:
    ldx glyph_lv
    lda disc_level_lo, x
    sta ZP_PTR_LO
    lda disc_level_hi, x
    sta ZP_PTR_HI
    ldy glyph_cls
    iny                         ; the level tables start at class 0
    lda (ZP_PTR_LO), y

    sta ZP_TMP0                 ; the code's eight bytes start at code * 8
    lda #0
    sta ZP_TMP1
    asl ZP_TMP0
    rol ZP_TMP1
    asl ZP_TMP0
    rol ZP_TMP1
    asl ZP_TMP0
    rol ZP_TMP1
    lda ZP_TMP1
    clc
    adc #>charset_ram           ; the set is page aligned
    sta ZP_TMP1

    lda glyph_lv
    asl a
    asl a
    asl a
    tax                         ; offset of this level's mask
    ldy #0
@byte:
    lda glyph_shape, y
    and disc_dither, x
    sta (ZP_TMP0), y
    inx
    iny
    cpy #8
    bne @byte

    inc glyph_lv
    lda glyph_lv
    cmp #DISC_LEVELS
    bne @level

    inc glyph_cls
    lda glyph_cls
    cmp #<(disc_shape_end - disc_shape)
    beq @all_done
    jmp @class                  ; out of branch range
@all_done:
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
