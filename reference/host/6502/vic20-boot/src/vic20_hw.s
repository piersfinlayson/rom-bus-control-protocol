; vic20_hw.s — VIC-20 hardware initialisation, keyboard scan, screen output
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; vic20_hw_init is in the BOOT segment (runs from ROM, called pre-relocation).
; All other routines are in the CODE segment (run from RAM post-relocation).
;
; ZP addresses are plain constants exported for importers.  No ZEROPAGE
; segment is used; ZP allocation is managed via the constants defined in
; vic20_defs.s.

    .include "vic20_defs.s"

; Export ZP addresses as plain constants.
.export zp_ptr_lo = ZP_PTR_LO
.export zp_ptr_hi = ZP_PTR_HI
.export zp_tmp0   = ZP_TMP0
.export zp_tmp1   = ZP_TMP1

; ---------------------------------------------------------------------------
; BOOT segment — runs from ROM, called before relocation
; ---------------------------------------------------------------------------

.segment "BOOT"

; vic20_hw_init
; One-time hardware initialisation at reset entry.  Runs from ROM.
; Must not call any subroutine in the CODE segment (not in RAM yet).
; Initialises all VIC registers then configures VIA2 for keyboard scanning.
; Clobbers: A
.export vic20_hw_init
vic20_hw_init:
    ; Pre-clear screen and colour RAM before configuring the VIC.  The VIC
    ; has no display-enable bit, so the moment we write VIC_COL_COUNT_VAL
    ; and VIC_MEM_VAL the chip starts scanning $1E00.  Clearing both regions
    ; first ensures it immediately shows blank content rather than garbage.
    lda #$20                ; space
    ldx #0
@scr_page:
    sta $1E00, x
    inx
    bne @scr_page
    ldx #0
@scr_tail:
    sta $1F00, x
    inx
    cpx #250
    bne @scr_tail

    lda #0                  ; black foreground
    ldx #0
@col_page:
    sta $9600, x
    inx
    bne @col_page
    ldx #0
@col_tail:
    sta $9700, x
    inx
    cpx #250
    bne @col_tail
    
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

    ; VIA2: port B all output (column drive), port A all input (row read)
    lda #VIA2_DDRB_VAL
    sta VIA2_DDRB
    lda #VIA2_DDRA_VAL
    sta VIA2_DDRA

    rts

; ---------------------------------------------------------------------------
; CODE segment — runs from RAM post-relocation
; ---------------------------------------------------------------------------

.code

; ---------------------------------------------------------------------------
; Row-offset tables (RODATA — in code, accessed via absolute RAM addresses)
; ---------------------------------------------------------------------------

.export row_off_lo : absolute
row_off_lo:
    .repeat 23, i
        .byte <(i * 22)
    .endrepeat

.export row_scr_hi : absolute
row_scr_hi:
    .repeat 23, i
        .byte >(SCREEN_BASE + i * 22)
    .endrepeat

.export row_col_hi : absolute
row_col_hi:
    .repeat 23, i
        .byte >(COLOUR_RAM + i * 22)
    .endrepeat

; ---------------------------------------------------------------------------
; vic20_clear_screen
; Screen RAM ($1E00-$1FF9) filled with spaces; colour RAM ($9600-$97F9)
; filled with the colour passed in Y.  506 bytes = 256 + 250.
; Input: Y = colour
; Clobbers: A, X, Y
; ---------------------------------------------------------------------------

.export vic20_clear_screen
vic20_clear_screen:
    sty zp_tmp0             ; save colour argument
    lda #CHAR_SPACE
    ldx #0
@scr_page:
    sta SCREEN_BASE + $000, x
    inx
    bne @scr_page
    ldx #0
@scr_tail:
    sta SCREEN_BASE + $100, x
    inx
    cpx #250
    bne @scr_tail

    lda zp_tmp0             ; restore colour argument
    ldx #0
@col_page:
    sta COLOUR_RAM + $000, x
    inx
    bne @col_page
    ldx #0
@col_tail:
    sta COLOUR_RAM + $100, x
    inx
    cpx #250
    bne @col_tail
    rts

; ---------------------------------------------------------------------------
; vic20_print_at
; Prints null-terminated ASCII string to screen at given row/col.
; Input: zp_ptr_lo/hi = source string, zp_tmp0 = row, zp_tmp1 = col.
; String pointer saved on CPU stack; zp_ptr_lo/hi reused for screen dest;
; zp_tmp0/1 reused for string source (after stack restore).
; ASCII->screen code: A-Z: -$40; a-z: -$60; others: unchanged.
; Clobbers: A, X, Y
; ---------------------------------------------------------------------------

.export vic20_print_at
vic20_print_at:
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
; A = row.  Sets zp_ptr_lo/hi = screen row start, zp_tmp0/1 = colour row start.
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
; vic20_highlight_row
; Sets bit 7 (reverse video) on all 22 screen chars in row; colour = white.
; Input: A = row.  Clobbers: A, X, Y.
; ---------------------------------------------------------------------------

.export vic20_highlight_row
vic20_highlight_row:
    jsr row_to_ptrs
    ldy #21
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
; vic20_unhighlight_row
; Clears bit 7 on all 22 screen chars in row; colour = white.
; Input: A = row.  Clobbers: A, X, Y.
; ---------------------------------------------------------------------------

.export vic20_unhighlight_row
vic20_unhighlight_row:
    jsr row_to_ptrs
    ldy #21
@loop:
    lda (zp_ptr_lo), y
    and #$7F
    sta (zp_ptr_lo), y
    lda #COL_WHITE
    sta (zp_tmp0), y
    dey
    bpl @loop
    rts

; ---------------------------------------------------------------------------
; vic20_scan_key
; Scans VIA2 for RETURN, cursor DOWN, cursor UP (= cursor + either SHIFT).
; Cursor-down and left SHIFT share column 3; after detecting cursor-down the
; column remains selected so left SHIFT is read without a second port write.
; Returns: A = KEY_NONE | KEY_RETURN | KEY_DOWN | KEY_UP.  Clobbers: A, X.
; ---------------------------------------------------------------------------

.export vic20_scan_key
vic20_scan_key:
    lda #KEY_RET_COL
    sta VIA2_PRB
    lda VIA2_PRA
    and #KEY_RET_ROW_BIT
    bne @check_cursor
    lda #KEY_RETURN
    bne @debounce           ; always taken

@check_cursor:
    lda #KEY_CRS_COL        ; column 3 — also selects left SHIFT (row 1)
    sta VIA2_PRB
    lda VIA2_PRA
    and #KEY_CRS_ROW_BIT    ; row 7
    bne @no_key

    ; Cursor-down detected.  Column 3 still selected; check left SHIFT (row 1).
    lda VIA2_PRA
    and #KEY_LSH_ROW_BIT
    bne @check_rsh          ; not held — check right SHIFT
    lda #KEY_UP
    bne @debounce           ; always taken

@check_rsh:
    lda #KEY_RSH_COL
    sta VIA2_PRB
    lda VIA2_PRA
    and #KEY_RSH_ROW_BIT    ; row 6
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