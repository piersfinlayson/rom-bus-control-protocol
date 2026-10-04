; c64_menu.s — highlighting a screen row and reading the keys that move it
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Only the bootloader uses these, so they are not in c64_hw.s.

    .include "c64_defs.s"

.import row_off_lo
.import row_scr_hi
.import row_col_hi

.code

; ---------------------------------------------------------------------------
; row_to_ptrs
; Input: A = row. Output: ZP_PTR = screen row, ZP_TMP0/1 = colour row.
; Clobbers: A, X.
; ---------------------------------------------------------------------------

row_to_ptrs:
    tax
    lda row_off_lo, x
    sta ZP_PTR_LO
    lda row_scr_hi, x
    sta ZP_PTR_HI
    lda row_off_lo, x
    sta ZP_TMP0
    lda row_col_hi, x
    sta ZP_TMP1
    rts

; ---------------------------------------------------------------------------
; c64_highlight_row
; Sets a screen row to reverse video.
; Input: A = row. Clobbers: A, X, Y.
; ---------------------------------------------------------------------------

.export c64_highlight_row
c64_highlight_row:
    jsr row_to_ptrs
    ldy #39
@loop:
    lda (ZP_PTR_LO), y
    ora #$80
    sta (ZP_PTR_LO), y
    lda #COL_WHITE
    sta (ZP_TMP0), y
    dey
    bpl @loop
    rts

; ---------------------------------------------------------------------------
; c64_unhighlight_row
; Sets a screen row back to normal video.
; Input: A = row. Clobbers: A, X, Y.
; ---------------------------------------------------------------------------

.export c64_unhighlight_row
c64_unhighlight_row:
    jsr row_to_ptrs
    ldy #39
@loop:
    lda (ZP_PTR_LO), y
    and #$7F
    sta (ZP_PTR_LO), y
    lda #COL_WHITE
    sta (ZP_TMP0), y
    dey
    bpl @loop
    rts

; ---------------------------------------------------------------------------
; c64_scan_key
; Reads RETURN and cursor down. Cursor up is cursor down with either SHIFT.
; Output: A = KEY_NONE, KEY_RETURN, KEY_DOWN or KEY_UP. Clobbers: A, X.
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
    bne @check_rsh
    lda #KEY_UP
    bne @debounce           ; always taken

@check_rsh:
    lda #KEY_RSH_COL
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_RSH_ROW_BIT
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
