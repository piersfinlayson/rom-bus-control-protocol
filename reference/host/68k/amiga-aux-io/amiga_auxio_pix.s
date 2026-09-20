; amiga_auxio_pix.s — the pixel engine the pads are drawn with
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; RAM section.
;
; Every row of a pin's box is built as three masks over a background and
; written to all four planes in one pass, so the ring, the lit centre, the
; selection bracket and the board behind them land in four pens within one
; byte's width.  A box is a whole number of bytes wide and is painted edge to
; edge, so redrawing one covers everything it covered before and no clear is
; needed between refreshes.
;
; The masks are 32 bits with the box's leftmost pixel at bit 31, which is why
; the widest box is four bytes.

; ---------------------------------------------------------------------------
; span_mask — D0.W = the first pixel in the box, D1.W = how many pixels.
; Returns the run in D2.L.
;
; A shift count in a register is taken modulo 64 on a 68000, so a width of
; zero shifts every bit out and gives an empty run with no test for it.
; Clobbers: D2
; ---------------------------------------------------------------------------
span_mask:
        MOVEM.L D3,-(SP)
        MOVEQ   #-1,D2
        MOVEQ   #32,D3
        SUB.W   D1,D3
        LSL.L   D3,D2                   ; the run, at the left of the box
        MOVE.W  D0,D3
        LSR.L   D3,D2                   ; and along to where it starts
        MOVEM.L (SP)+,D3
        RTS

; ---------------------------------------------------------------------------
; cell_row — one row of a box into the bitmap: composed, then written.
;
; A2 = the row's plane 0 address.  The two halves are also called on their
; own, because a pad's rows are composed once for the page and written many
; times after that.
; Clobbers (saved/restored): D0-D7/A0-A1
; ---------------------------------------------------------------------------
cell_row:
        MOVEM.L A0,-(SP)
        BSR     cell_row_mix
        LEA     (AUX_ROWBUF).W,A0
        BSR     cell_row_put
        MOVEM.L (SP)+,A0
        RTS

; ---------------------------------------------------------------------------
; cell_row_mix — one row composed into AUX_ROWBUF, one long a plane.
;
; AUX_MASK_A, AUX_MASK_B and AUX_MASK_C are the three layers and AUX_PEN_A to
; AUX_PEN_D their pens.  A pixel no layer claims takes AUX_PEN_D, so the row
; is written whole and nothing under it shows through.
;
; The three layers must not overlap.  Where two would, the caller takes the
; pixels out of the one underneath.
; Clobbers (saved/restored): D0-D7/A0
; ---------------------------------------------------------------------------
cell_row_mix:
        MOVEM.L D0-D7/A0,-(SP)
        MOVE.L  AUX_MASK_A,D4
        MOVE.L  AUX_MASK_B,D5
        MOVE.L  AUX_MASK_C,D6
        MOVE.L  D4,D7
        OR.L    D5,D7
        OR.L    D6,D7
        NOT.L   D7                      ; everything else is the background
        ; The four pens sit in one long, a byte each, so the plane loop shifts
        ; rather than reading them from memory sixteen times a row.
        MOVE.B  AUX_PEN_A,D3
        LSL.L   #8,D3
        MOVE.B  AUX_PEN_B,D3
        LSL.L   #8,D3
        MOVE.B  AUX_PEN_C,D3
        LSL.L   #8,D3
        MOVE.B  AUX_PEN_D,D3
        LEA     (AUX_ROWBUF).W,A0
        MOVEQ   #0,D0                   ; plane
.crw_plane:
        MOVEQ   #0,D2
        MOVE.L  D3,D1
        ROL.L   #8,D1                   ; pen A
        BTST    D0,D1
        BEQ.S   .crw_b
        OR.L    D4,D2
.crw_b:
        MOVE.L  D3,D1
        SWAP    D1                      ; pen B
        BTST    D0,D1
        BEQ.S   .crw_c
        OR.L    D5,D2
.crw_c:
        MOVE.L  D3,D1
        ROR.L   #8,D1                   ; pen C
        BTST    D0,D1
        BEQ.S   .crw_d
        OR.L    D6,D2
.crw_d:
        BTST    D0,D3
        BEQ.S   .crw_put
        OR.L    D7,D2
.crw_put:
        MOVE.L  D2,(A0)+
        ADDQ.W  #1,D0
        CMPI.W  #SCREEN_PLANES,D0
        BCS.S   .crw_plane
        MOVEM.L (SP)+,D0-D7/A0
        RTS

; ---------------------------------------------------------------------------
; cell_row_put — A0 = four composed longs, one a plane.  A2 = the row's plane
; 0 address and AUX_BOX_BYTES how wide the box is.
;
; A0 comes back where it started, so a caller walking composed rows steps it
; itself.
; Clobbers (saved/restored): D2-D6/A0-A1
; ---------------------------------------------------------------------------
cell_row_put:
        MOVEM.L D2-D6/A0-A1,-(SP)
        MOVEA.L A2,A1
        MOVEQ   #0,D3
        MOVE.B  AUX_BOX_BYTES,D3
        SUBQ.W  #1,D3
        MOVEQ   #SCREEN_PLANES-1,D5
.crp_wplane:
        MOVE.L  (A0)+,D2
        MOVE.W  D3,D4
.crp_wbyte:
        ROL.L   #8,D2                   ; the leftmost byte first
        MOVE.B  D2,(A1)+
        DBF     D4,.crp_wbyte
        MOVE.W  D3,D6
        ADDQ.W  #1,D6
        SUBA.W  D6,A1                   ; the same column, one plane on
        ADDA.W  #SCREEN_BPL_W,A1
        DBF     D5,.crp_wplane
        MOVEM.L (SP)+,D2-D6/A0-A1
        RTS

; ---------------------------------------------------------------------------
; pix_band — D1.W = the first pixel row, D2.W = how many rows, D0.B = the pen.
; The whole width of the screen, one blit a plane.
;
; The blitter is left to finish before the CPU draws over the same rows.
; Clobbers (saved/restored): D0-D5/A0
; ---------------------------------------------------------------------------
pix_band:
        MOVEM.L D0-D5/A0,-(SP)
        MOVEA.L #BITPLANE_BASE,A0
        MOVEQ   #0,D3
        MOVE.W  D1,D3
        MULU    #SCREEN_ROW_BYTES,D3
        ADDA.L  D3,A0
        MOVEQ   #0,D4                   ; plane
.pbd_plane:
        BSR     blit_wait
        MOVE.W  #$0100,D5               ; D enabled, every minterm clear
        BTST    D4,D0
        BEQ.S   .pbd_con
        MOVE.W  #$01FF,D5               ; D enabled, every minterm set
.pbd_con:
        MOVE.W  D5,BLTCON0
        CLR.W   BLTCON1
        MOVE.W  #SCREEN_BPL_MOD,BLTDMOD
        MOVE.L  A0,BLTDPTH
        MOVE.W  D2,D5
        LSL.W   #6,D5                   ; rows in bits 15 to 6
        ORI.W   #SCREEN_BPL_W/2,D5      ; words across in bits 5 to 0
        MOVE.W  D5,BLTSIZE
        ADDA.W  #SCREEN_BPL_W,A0
        ADDQ.W  #1,D4
        CMPI.W  #SCREEN_PLANES,D4
        BCS.S   .pbd_plane
        BSR     blit_wait
        MOVEM.L (SP)+,D0-D5/A0
        RTS

; ---------------------------------------------------------------------------
; pix_rowaddr — D1.W = x, a multiple of eight, D2.W = y.  Returns that pixel's
; plane 0 address in A2.
; Clobbers: A2
; ---------------------------------------------------------------------------
pix_rowaddr:
        MOVEM.L D0/D3,-(SP)
        MOVEQ   #0,D0
        MOVE.W  D2,D0
        MULU    #SCREEN_ROW_BYTES,D0
        MOVEQ   #0,D3
        MOVE.W  D1,D3
        LSR.W   #3,D3
        ADD.L   D3,D0
        MOVEA.L #BITPLANE_BASE,A2
        ADDA.L  D0,A2
        MOVEM.L (SP)+,D0/D3
        RTS

; ---------------------------------------------------------------------------
; label_mask — D0.W = which of the glyph's eight rows.  Returns the label's
; bits for that row in D2.L, from AUX_LABEL, AUX_LAB_LEN and AUX_LAB_X.
; Clobbers: D2
; ---------------------------------------------------------------------------
label_mask:
        MOVEM.L D0-D1/D3-D5/A0-A1,-(SP)
        MOVEQ   #0,D2
        MOVEQ   #0,D5                   ; character
        LEA     (AUX_LABEL).W,A0
        LEA     (font_data).L,A1
.lbm_ch:
        CMP.B   AUX_LAB_LEN,D5
        BCC.S   .lbm_out
        MOVEQ   #0,D1
        MOVE.B  (A0,D5.W),D1
        LSL.W   #3,D1
        ADD.W   D0,D1
        MOVEQ   #0,D3
        MOVE.B  (A1,D1.W),D3            ; the glyph's scan line
        MOVE.W  D5,D4
        LSL.W   #3,D4
        MOVEQ   #0,D1
        MOVE.B  AUX_LAB_X,D1
        ADD.W   D1,D4                   ; the pixel this character starts at
        MOVEQ   #24,D1
        SUB.W   D4,D1
        LSL.L   D1,D3
        OR.L    D3,D2
        ADDQ.W  #1,D5
        BRA.S   .lbm_ch
.lbm_out:
        MOVEM.L (SP)+,D0-D1/D3-D5/A0-A1
        RTS
