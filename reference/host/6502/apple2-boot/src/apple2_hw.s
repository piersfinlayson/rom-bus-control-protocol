; apple2_hw.s — Apple II hardware initialisation, keyboard, screen output
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; a2_hw_init is in the BOOT segment (runs from ROM, called pre-relocation).
; All other routines are in the CODE segment (run from RAM post-relocation).
;
; ZP addresses are plain constants exported for importers.  No ZEROPAGE
; segment is used — ZP allocation is managed via the constants defined in
; apple2_defs.s.

    .include "apple2_defs.s"

; Export ZP addresses as plain constants.
.export zp_ptr_lo = ZP_PTR_LO
.export zp_ptr_hi = ZP_PTR_HI
.export zp_tmp0   = ZP_TMP0
.export zp_tmp1   = ZP_TMP1

; ---------------------------------------------------------------------------
; BOOT segment — runs from ROM, called before relocation
; ---------------------------------------------------------------------------

.segment "BOOT"

; a2_hw_init
; One-time hardware setup at reset entry.  Runs from ROM, so it must not call
; any subroutine in the CODE segment.  Puts the display into 40-column text,
; page 1, and clears the strobe left by whatever key was last pressed.
; Clobbers: A
.export a2_hw_init
a2_hw_init:
    sta TXTSET
    sta MIXCLR
    sta TXTPAGE1
    sta LORES
    sta CLR80COL
    sta CLRALTCHAR
    sta KBDSTRB
    rts

; ---------------------------------------------------------------------------
; CODE segment — runs from RAM post-relocation
; ---------------------------------------------------------------------------

.code

; ---------------------------------------------------------------------------
; Row address tables.  Screen rows are interleaved, so a table is cheaper
; than working the address out each time.
; ---------------------------------------------------------------------------

.export row_off_lo : absolute
row_off_lo:
    .repeat SCREEN_ROWS, i
        .byte <(SCREEN_BASE + (i .mod 8) * $80 + (i / 8) * $28)
    .endrepeat

.export row_scr_hi : absolute
row_scr_hi:
    .repeat SCREEN_ROWS, i
        .byte >(SCREEN_BASE + (i .mod 8) * $80 + (i / 8) * $28)
    .endrepeat

; ---------------------------------------------------------------------------
; a2_clear_screen
; Fills the whole of text page 1 with spaces, the holes included.  1024 bytes
; means four whole pages and no tail to count.
; Clobbers: A, X
; ---------------------------------------------------------------------------

.export a2_clear_screen
a2_clear_screen:
    lda #CHAR_SPACE
    ldx #0
@pages:
    sta SCREEN_BASE + $000, x
    sta SCREEN_BASE + $100, x
    sta SCREEN_BASE + $200, x
    sta SCREEN_BASE + $300, x
    inx
    bne @pages
    rts

; ---------------------------------------------------------------------------
; a2_print_at
; Prints a null-terminated ASCII string at a given row and column.
; Input: zp_ptr_lo/hi = string, zp_tmp0 = row, zp_tmp1 = column.
; Lower case is folded to upper case, as a II and II+ cannot display it.
; Leaves zp_tmp2 and above alone, so callers can keep a loop counter there.
; Clobbers: A, X, Y, zp_ptr_lo/hi, zp_tmp0/1
; ---------------------------------------------------------------------------

.export a2_print_at
a2_print_at:
    lda zp_ptr_hi
    pha
    lda zp_ptr_lo
    pha

    ldx zp_tmp0             ; row
    lda row_off_lo, x
    clc
    adc zp_tmp1             ; + column
    sta zp_ptr_lo
    lda row_scr_hi, x
    adc #0
    sta zp_ptr_hi

    pla
    sta zp_tmp0             ; string pointer lo
    pla
    sta zp_tmp1             ; string pointer hi

    ldy #0
@loop:
    lda (zp_tmp0), y
    beq @done
    cmp #'a'
    bcc @emit
    cmp #'z' + 1
    bcs @emit
    sec
    sbc #$20                ; fold to upper case
@emit:
    ora #$80                ; normal video
    sta (zp_ptr_lo), y
    iny
    bne @loop
@done:
    rts

; ---------------------------------------------------------------------------
; row_to_ptr — internal helper.  A = row, sets zp_ptr_lo/hi to its start.
; Clobbers: A, X
; ---------------------------------------------------------------------------

row_to_ptr:
    tax
    lda row_off_lo, x
    sta zp_ptr_lo
    lda row_scr_hi, x
    sta zp_ptr_hi
    rts

; ---------------------------------------------------------------------------
; a2_invert_row / a2_normal_row
; Turns a whole row inverse or back again.
; Input: A = row.  Clobbers: A, X, Y.
; ---------------------------------------------------------------------------

.export a2_invert_row
a2_invert_row:
    jsr row_to_ptr
    ldy #SCREEN_COLS - 1
@loop:
    lda (zp_ptr_lo), y
    and #$3F
    sta (zp_ptr_lo), y
    dey
    bpl @loop
    rts

.export a2_normal_row
a2_normal_row:
    jsr row_to_ptr
    ldy #SCREEN_COLS - 1
@loop:
    lda (zp_ptr_lo), y
    ora #$80
    sta (zp_ptr_lo), y
    dey
    bpl @loop
    rts

; ---------------------------------------------------------------------------
; a2_getkey
; Returns the waiting key in A with bit 7 set, or KEY_NONE if none is waiting,
; and clears the strobe so the next press is seen.
; Clobbers: A
; ---------------------------------------------------------------------------

.export a2_getkey
a2_getkey:
    lda KBD
    bpl @none
    sta KBDSTRB             ; any access clears the strobe, and A survives
    rts
@none:
    lda #KEY_NONE
    rts
