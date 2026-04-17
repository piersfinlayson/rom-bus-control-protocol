; c64_hw.s — C64 hardware initialisation, keyboard scan, screen output
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; c64_hw_init is in the BOOT segment (runs from ROM, called pre-relocation).
; All other routines are in the CODE segment (run from RAM post-relocation).
;
; ZP addresses (zp_ptr_lo etc.) are plain constants exported for importers.
; No ZEROPAGE segment is used; ZP allocation is managed via the constants
; defined in c64_defs.s.

    .include "c64_defs.s"

; Export ZP addresses as plain constants so c64_boot.s can import them.
; Callers use them as absolute addresses; ca65 will choose ZP addressing
; mode automatically when the resolved value is in $00-$FF.
.export zp_ptr_lo = ZP_PTR_LO
.export zp_ptr_hi = ZP_PTR_HI
.export zp_tmp0   = ZP_TMP0
.export zp_tmp1   = ZP_TMP1

; ---------------------------------------------------------------------------
; Row-offset tables (RODATA — in ROM, accessed via absolute ROM addresses)
; ---------------------------------------------------------------------------

.rodata

.export row_off_lo : absolute
row_off_lo:
    .repeat 25, i
        .byte <(i * 40)
    .endrepeat

.export row_scr_hi : absolute
row_scr_hi:
    .repeat 25, i
        .byte >(SCREEN_BASE + i * 40)
    .endrepeat

.export row_col_hi : absolute
row_col_hi:
    .repeat 25, i
        .byte >(COLOUR_RAM + i * 40)
    .endrepeat

; ---------------------------------------------------------------------------
; BOOT segment — runs from ROM, called before relocation
; ---------------------------------------------------------------------------

.segment "BOOT"

; c64_hw_init
; One-time hardware initialisation at reset entry. Runs from ROM.
; Must not call any subroutine in the CODE segment (not in RAM yet).
; Clobbers: A
.export c64_hw_init
c64_hw_init:
    lda #CPU_DDR_VAL
    sta CPU_DDR
    lda #CPU_PORT_VAL
    sta CPU_PORT

    lda #CIA2_DDRA_VAL
    sta CIA2_DDRA
    lda #CIA2_PRA_VAL
    sta CIA2_PRA

    lda #VIC_CTRL1_VAL
    sta VIC_CTRL1
    lda #VIC_CTRL2_VAL
    sta VIC_CTRL2
    lda #VIC_MEMSETUP_VAL
    sta VIC_MEMSETUP
    lda #COL_BLACK
    sta VIC_BORDER
    sta VIC_BACKGROUND

    lda #$FF
    sta CIA1_DDRA
    lda #$00
    sta CIA1_DDRB
    rts

; ---------------------------------------------------------------------------
; CODE segment — runs from RAM post-relocation
; ---------------------------------------------------------------------------

.code

; ---------------------------------------------------------------------------
; c64_clear_screen
; Screen RAM ($0400-$07E7) filled with spaces, colour RAM ($D800-$DBE7) with
; COL_LIGHT_BLUE. 1000 bytes = 3*256 + 232.
; Clobbers: A, X
; ---------------------------------------------------------------------------

.export c64_clear_screen
c64_clear_screen:
    lda #CHAR_SPACE
    ldx #0
@scr_pages:
    sta SCREEN_BASE + $000, x
    sta SCREEN_BASE + $100, x
    sta SCREEN_BASE + $200, x
    inx
    bne @scr_pages
    ldx #0
@scr_tail:
    sta SCREEN_BASE + $300, x
    inx
    cpx #232
    bne @scr_tail

    lda #COL_LIGHT_BLUE
    ldx #0
@col_pages:
    sta COLOUR_RAM + $000, x
    sta COLOUR_RAM + $100, x
    sta COLOUR_RAM + $200, x
    inx
    bne @col_pages
    ldx #0
@col_tail:
    sta COLOUR_RAM + $300, x
    inx
    cpx #232
    bne @col_tail
    rts

; ---------------------------------------------------------------------------
; c64_print_at
; Prints null-terminated ASCII string to screen at given row/col.
; Input: zp_ptr_lo/hi = source string, zp_tmp0 = row, zp_tmp1 = col.
; String pointer saved on CPU stack; zp_ptr_lo/hi reused for screen dest;
; zp_tmp0/1 reused for string source (after stack restore).
; ASCII->screen code: A-Z: -$40; a-z: -$60; others: unchanged.
; Clobbers: A, X, Y
; ---------------------------------------------------------------------------

.export c64_print_at
c64_print_at:
    lda zp_ptr_hi
    pha
    lda zp_ptr_lo
    pha

    ldx zp_tmp0             ; row
    lda row_off_lo, x
    clc
    adc zp_tmp1             ; + col
    sta zp_ptr_lo
    lda row_scr_hi, x
    adc #0
    sta zp_ptr_hi

    pla
    sta zp_tmp0             ; string ptr lo
    pla
    sta zp_tmp1             ; string ptr hi

    ldy #0
@loop:
    lda (zp_tmp0), y
    beq @done
    cmp #$61
    bcc @not_lower
    cmp #$7B
    bcs @not_lower
    sec
    sbc #$60
    jmp @emit
@not_lower:
    cmp #$41
    bcc @emit
    cmp #$5B
    bcs @emit
    sec
    sbc #$40
@emit:
    sta (zp_ptr_lo), y
    iny
    bne @loop
@done:
    rts

; ---------------------------------------------------------------------------
; row_to_ptrs — internal helper
; A = row. Sets zp_ptr_lo/hi = screen row start, zp_tmp0/1 = colour row start.
; Clobbers: A, X
; ---------------------------------------------------------------------------

row_to_ptrs:
    tax
    lda row_off_lo, x
    sta zp_ptr_lo
    lda row_scr_hi, x
    sta zp_ptr_hi
    lda row_off_lo, x
    sta zp_tmp0
    lda row_col_hi, x
    sta zp_tmp1
    rts

; ---------------------------------------------------------------------------
; c64_highlight_row
; Sets bit 7 (reverse video) on all 40 screen chars in row; colour = white.
; Input: A = row. Clobbers: A, X, Y.
; ---------------------------------------------------------------------------

.export c64_highlight_row
c64_highlight_row:
    jsr row_to_ptrs
    ldy #39
@loop:
    lda (zp_ptr_lo), y
    ora #$80
    sta (zp_ptr_lo), y
    lda #COL_WHITE
    sta (zp_tmp0), y
    dey
    bpl @loop
    rts

; ---------------------------------------------------------------------------
; c64_unhighlight_row
; Clears bit 7 on all 40 screen chars in row; colour = light blue.
; Input: A = row. Clobbers: A, X, Y.
; ---------------------------------------------------------------------------

.export c64_unhighlight_row
c64_unhighlight_row:
    jsr row_to_ptrs
    ldy #39
@loop:
    lda (zp_ptr_lo), y
    and #$7F
    sta (zp_ptr_lo), y
    lda #COL_LIGHT_BLUE
    sta (zp_tmp0), y
    dey
    bpl @loop
    rts

; ---------------------------------------------------------------------------
; c64_scan_key
; Scans CIA1 for RETURN, cursor DOWN, cursor UP (= cursor + left SHIFT).
; Returns: A = KEY_NONE | KEY_RETURN | KEY_DOWN | KEY_UP. Clobbers: A, X.
; ---------------------------------------------------------------------------

.export c64_scan_key
c64_scan_key:
    lda #KEY_RET_COL
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_RET_ROW_BIT
    bne @check_cursor
    lda #KEY_RETURN
    bne @debounce           ; always taken

@check_cursor:
    lda #KEY_CRS_COL
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_CRS_ROW_BIT
    bne @no_key

    lda #KEY_LSH_COL
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_LSH_ROW_BIT
    bne @is_down
    lda #KEY_UP
    bne @debounce           ; always taken

@is_down:
    lda #KEY_DOWN
@debounce:
    ldx #DEBOUNCE_COUNT
@dly:
    dex
    bne @dly
    rts

@no_key:
    lda #KEY_NONE
    rts