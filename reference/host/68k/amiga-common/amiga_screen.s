; amiga_screen.s — the screen engine
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; RAM section.  Text into the interleaved bitmap.  font_data lives in the ROM
; data section and is reached by absolute long address, correct from any
; execution address.

; ---------------------------------------------------------------------------
; The bitmap is interleaved, so one character row is 1280 contiguous bytes —
; eight pixel rows, each holding planes 0 to 3 in turn, 40 bytes each.  A
; character cell is a column within it, and stepping down one pixel row is
; +160.
;
; A character cell takes two pens: VAR_PEN for the glyph and VAR_PEN_BG for
; the rest of the cell.  Both are written, so a character covers whatever was
; there, and text on the highlight bar is black on gold rather than black on
; a hole punched through it.
;
; They are variables rather than arguments because screen_print, diag_field
; and print_hex_byte all sit between a caller and screen_putchar, and so do an
; application's own drawing routines.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; screen_clear — zero every plane of the bitmap being drawn to
; screen_init calls it from the ROM section, before the RAM copy, and sets
; VAR_DRAW_BASE first.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
screen_clear:
        MOVEM.L D0/A0,-(SP)
        MOVEA.L VAR_DRAW_BASE,A0
        MOVE.W  #SCREEN_BPL_SZ/4-1,D0
.sc_loop:
        CLR.L   (A0)+
        DBF     D0,.sc_loop
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; screen_fill_row — fill one character row with VAR_PEN, from VAR_MENU_COL to
; the right edge.  An application that fills whole rows leaves VAR_MENU_COL at
; zero.
; Input : D0.B = row
; Clobbers (saved/restored): D0-D6/A0
; ---------------------------------------------------------------------------
screen_fill_row:
        MOVEM.L D0-D6/A0,-(SP)
        MOVEQ   #0,D1
        MOVE.B  D0,D1
        MULU    #ROW_STRIDE,D1
        MOVEA.L VAR_DRAW_BASE,A0
        ADDA.L  D1,A0
        MOVEQ   #0,D3
        MOVE.B  VAR_MENU_COL,D3
        ADDA.W  D3,A0                   ; the bar's first column
        NEG.W   D3
        ADDI.W  #SCREEN_COLS-1,D3       ; columns it covers, less one
        MOVEQ   #0,D1
        MOVE.B  VAR_PEN,D1
        MOVEQ   #7,D5                   ; eight pixel rows
.fr_line:
        MOVEQ   #0,D4                   ; plane number
.fr_plane:
        MOVEQ   #0,D2
        BTST    D4,D1
        BEQ.S   .fr_mask
        MOVEQ   #-1,D2                  ; this plane is set right across
.fr_mask:
        MOVE.W  D3,D6
.fr_byte:
        MOVE.B  D2,(A0)+
        DBF     D6,.fr_byte
        ADDA.W  #SCREEN_BPL_W-1,A0      ; the same column, one plane on
        SUBA.W  D3,A0
        ADDQ.B  #1,D4
        CMPI.B  #SCREEN_PLANES,D4
        BCS.S   .fr_plane
        DBF     D5,.fr_line
        MOVEM.L (SP)+,D0-D6/A0
        RTS

; ---------------------------------------------------------------------------
; screen_putchar — render one ASCII character into the bitmap
; Input : D0.B = character code, D1.B = column (0-39), D2.B = row (0-31)
;         VAR_PEN = glyph pen, VAR_PEN_BG = pen for the rest of the cell
;
; Within a plane the byte is the background mask with the glyph's bits
; switched to the foreground mask.  That is background EOR (select AND glyph).
; Clobbers (saved/restored): D0-D7/A0-A2
; ---------------------------------------------------------------------------
screen_putchar:
        MOVEM.L D0-D7/A0-A2,-(SP)

        ; Cell address in plane 0 = VAR_DRAW_BASE + row*1280 + col.  The offset
        ; runs past $7FFF at the bottom of the screen, so it is kept long.
        MOVEQ   #0,D3
        MOVE.B  D2,D3
        MULU    #ROW_STRIDE,D3
        MOVEQ   #0,D7
        MOVE.B  D1,D7
        ADD.L   D7,D3
        MOVEA.L VAR_DRAW_BASE,A1
        ADDA.L  D3,A1

        ; Glyph address = font_data + char_code * 8
        MOVEQ   #0,D3
        MOVE.B  D0,D3
        ASL.W   #3,D3
        LEA     (font_data).L,A0
        ADDA.W  D3,A0

        MOVEQ   #0,D4
        MOVE.B  VAR_PEN,D4
        MOVEQ   #0,D5
        MOVE.B  VAR_PEN_BG,D5

        MOVEQ   #0,D6                   ; plane number
.pc_plane:
        MOVEQ   #0,D2                   ; D2 = this plane's background bits
        BTST    D6,D5
        BEQ.S   .pc_fg
        MOVEQ   #-1,D2
.pc_fg:
        MOVEQ   #0,D3                   ; D3 = this plane's foreground bits
        BTST    D6,D4
        BEQ.S   .pc_sel
        MOVEQ   #-1,D3
.pc_sel:
        EOR.B   D2,D3                   ; the bits the glyph switches
        MOVEA.L A0,A2                   ; the glyph, from its first line
        MOVEQ   #7,D7                   ; eight scan lines
.pc_line:
        MOVE.B  (A2)+,D0
        AND.B   D3,D0
        EOR.B   D2,D0
        MOVE.B  D0,(A1)
        ADDA.W  #SCREEN_ROW_BYTES,A1
        DBF     D7,.pc_line
        ; back up to line 0, one plane further in
        SUBA.W  #SCREEN_ROW_BYTES*8-SCREEN_BPL_W,A1
        ADDQ.B  #1,D6
        CMPI.B  #SCREEN_PLANES,D6
        BCS.S   .pc_plane

        MOVEM.L (SP)+,D0-D7/A0-A2
        RTS

; ---------------------------------------------------------------------------
; screen_print — print a null-terminated ASCII string in VAR_PEN
; Input : A0 = string pointer, D1.B = column, D2.B = row
; Characters at or beyond VAR_COL_MAX are dropped, so a name too wide for the
; space it has is cut short rather than running into the text beside it.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
screen_print:
        MOVEM.L D0-D2/A0,-(SP)
.sp_loop:
        MOVE.B  (A0)+,D0
        BEQ.S   .sp_done
        CMP.B   VAR_COL_MAX,D1
        BCC.S   .sp_done
        BSR     screen_putchar
        ADDQ.B  #1,D1
        BRA.S   .sp_loop
.sp_done:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; screen_print_centred — centre a null-terminated ASCII string on one row
; Input : A0 = string, D2.B = row
; A string wider than the screen starts at column 0.
; Clobbers (saved/restored): D0-D1/A0-A1
; ---------------------------------------------------------------------------
screen_print_centred:
        MOVEM.L D0-D1/A0-A1,-(SP)
        MOVEA.L A0,A1                   ; keep the start
        MOVEQ   #0,D0
.spc_len:
        TST.B   (A0)+
        BEQ.S   .spc_got
        ADDQ.W  #1,D0
        BRA.S   .spc_len
.spc_got:
        MOVEQ   #SCREEN_COLS,D1
        SUB.W   D0,D1
        BPL.S   .spc_col
        MOVEQ   #0,D1
.spc_col:
        LSR.W   #1,D1
        MOVEA.L A1,A0
        BSR     screen_print
        MOVEM.L (SP)+,D0-D1/A0-A1
        RTS
