; amiga_auxio_pins.s — the pins on the screen
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; RAM section.
;
; A pin is a pad on a board.  The ring is in the pen of whoever owns it and the
; centre is lit where the level is high and dark where it is low.  The cursor's
; pad sits in a gold bracket.  A pad is drawn pixel by pixel, so it is round,
; sits at whatever pitch its size asks for, and carries four pens in one byte's
; width.
;
; The pins are read again and drawn again every field.  A pad is only redrawn
; where what it shows has changed, and then only the rows the pad itself
; covers unless the cursor or the pin's flags moved too, which is what makes
; a refresh every field affordable.  A slice of the sweep runs for whatever
; the field has left when the drawing is done, so a board with more pins than
; fit in a field refreshes over several fields instead of the screen dropping
; to a slower rate.

; ---------------------------------------------------------------------------
; pin_label_text — D0.B = pin, the group in AUX_CELL_GROUP.  The characters
; the pad is labelled with into AUX_LABEL, and how many in D1.W.
;
; Named as put_pin_label names it, into AUX_LABEL rather than onto the screen.
; Clobbers: D1
; ---------------------------------------------------------------------------
pin_label_text:
        MOVEM.L D0/D2-D3/A0,-(SP)
        MOVE.B  D0,D3
        MOVE.B  AUX_CELL_GROUP,D0
        BSR     group_type
        LEA     (AUX_LABEL).W,A0
        CMPI.B  #RBCP_AUX_TYPE_IMGSEL,D0
        BEQ.S   .plt_letter
        CMPI.B  #RBCP_AUX_TYPE_XPADS,D0
        BNE.S   .plt_num
        ADDQ.B  #1,D3
.plt_num:
        MOVEQ   #1,D1
        CMPI.B  #10,D3
        BCS.S   .plt_units
        MOVEQ   #0,D2
.plt_tens:
        CMPI.B  #10,D3
        BCS.S   .plt_tens_out
        SUBI.B  #10,D3
        ADDQ.B  #1,D2
        BRA.S   .plt_tens
.plt_tens_out:
        ADDI.B  #'0',D2
        MOVE.B  D2,(A0)+
        MOVEQ   #2,D1
.plt_units:
        ADDI.B  #'0',D3
        MOVE.B  D3,(A0)+
        BRA.S   .plt_out
.plt_letter:
        ADDI.B  #'A',D3
        MOVE.B  D3,(A0)+
        MOVEQ   #1,D1
.plt_out:
        MOVEM.L (SP)+,D0/D2-D3/A0
        RTS

; ---------------------------------------------------------------------------
; pad_masks — D0.W = the row within the pad, D7.W = the tier.  The ring into
; one mask and the lit centre into another.
;
; The two do not overlap: the centre comes out of the disc, because cell_row
; paints whatever no mask claims as background.
; Clobbers (saved/restored): D0-D2/D4/A0-A1
; ---------------------------------------------------------------------------
pad_masks:
        MOVEM.L D0-D2/D4/A0-A1,-(SP)
        LEA     (tier_span).L,A0
        MOVE.W  D7,D1
        LSL.W   #2,D1
        MOVEA.L (A0,D1.W),A1
        MOVE.W  D0,D1
        LSL.W   #2,D1
        ADDA.W  D1,A1                   ; this row: ox0, ow, ix0, iw
        MOVEQ   #0,D4
        MOVE.B  AUX_CELL_PADX,D4        ; where the pad sits in the box

        MOVEQ   #0,D0
        MOVE.B  (A1),D0
        ADD.W   D4,D0
        MOVEQ   #0,D1
        MOVE.B  1(A1),D1
        BSR     span_mask
        MOVE.L  D2,AUX_MASK_A           ; the whole disc, until the centre goes

        MOVEQ   #0,D0
        MOVE.B  2(A1),D0
        ADD.W   D4,D0
        MOVEQ   #0,D1
        MOVE.B  3(A1),D1
        BSR     span_mask
        MOVE.L  D2,AUX_MASK_B
        NOT.L   D2
        AND.L   AUX_MASK_A,D2
        MOVE.L  D2,AUX_MASK_A           ; the ring is the disc less the centre
        MOVEM.L (SP)+,D0-D2/D4/A0-A1
        RTS

; ---------------------------------------------------------------------------
; label_row — D3.W = the row within the box, D7.W = the tier.  The pin's
; number under its pad, where this row is one the label covers.  The cursor's
; pin reads over.  Nothing else on the page does.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
label_row:
        MOVEM.L D0-D2/A0,-(SP)
        LEA     (tier_laby).L,A0
        MOVEQ   #0,D0
        MOVE.B  (A0,D7.W),D0
        CMPI.W  #TIER_NO_LABEL,D0
        BEQ.S   .lrw_out                ; this size carries no label
        MOVE.W  D3,D1
        SUB.W   D0,D1
        BCS.S   .lrw_out
        CMPI.W  #8,D1
        BCC.S   .lrw_out
        MOVE.W  D1,D0
        BSR     label_mask
        MOVE.L  D2,AUX_MASK_A
        TST.B   AUX_CELL_SEL
        BEQ.S   .lrw_out
        MOVEQ   #0,D0
        MOVE.B  AUX_LAB_X,D0
        MOVEQ   #0,D1
        MOVE.B  AUX_LAB_LEN,D1
        LSL.W   #3,D1
        BSR     span_mask
        MOVE.L  AUX_MASK_A,D1
        NOT.L   D1
        AND.L   D1,D2
        MOVE.L  D2,AUX_MASK_B           ; gold behind the figures
        MOVE.B  #PEN_BG,AUX_PEN_A
        MOVE.B  #PEN_GOLD,AUX_PEN_B
.lrw_out:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; bracket_row — D3.W = the row within the box, D5.W = the pad's top row,
; D6.W = the pad's height, D7.W = the tier.  The gold bracket around the
; cursor's pad: an arm and a stem two rows above the pad and two below, so it
; never lands on the pad or on the label.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
bracket_row:
        MOVEM.L D0-D2/A0,-(SP)
        TST.B   AUX_CELL_SEL
        BEQ     .brw_out
        MOVE.W  D5,D0
        SUBQ.W  #2,D0
        CMP.W   D3,D0
        BEQ.S   .brw_arm
        MOVE.W  D5,D0
        ADD.W   D6,D0
        ADDQ.W  #1,D0
        CMP.W   D3,D0
        BEQ.S   .brw_arm
        MOVE.W  D5,D0
        SUBQ.W  #1,D0
        CMP.W   D3,D0
        BEQ.S   .brw_stem
        MOVE.W  D5,D0
        ADD.W   D6,D0
        CMP.W   D3,D0
        BNE     .brw_out
.brw_stem:
        MOVEQ   #1,D1
        BRA.S   .brw_put
.brw_arm:
        MOVEQ   #3,D1
.brw_put:
        MOVE.B  D1,AUX_BR_RUN
        LEA     (tier_brx).L,A0
        MOVEQ   #0,D0
        MOVE.B  (A0,D7.W),D0
        BSR     span_mask
        MOVE.L  D2,AUX_MASK_C
        LEA     (tier_brx).L,A0
        MOVEQ   #0,D0
        MOVE.B  (A0,D7.W),D0
        LEA     (tier_brw).L,A0
        MOVEQ   #0,D1
        MOVE.B  (A0,D7.W),D1
        ADD.W   D1,D0
        MOVEQ   #0,D1
        MOVE.B  AUX_BR_RUN,D1
        SUB.W   D1,D0                   ; the same run at the far side
        BSR     span_mask
        OR.L    AUX_MASK_C,D2
        MOVE.L  D2,AUX_MASK_C
        MOVE.B  #PEN_GOLD,AUX_PEN_C
        NOT.L   D2
        AND.L   AUX_MASK_A,D2
        MOVE.L  D2,AUX_MASK_A
.brw_out:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; cell_masks — D3.W = the row within the box, D5.W = the pad's top row,
; D6.W = the pad's height, D7.W = the tier.  Everything cell_row needs for one
; row.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
cell_masks:
        MOVEM.L D0-D2/A0,-(SP)
        CLR.L   AUX_MASK_A
        CLR.L   AUX_MASK_B
        CLR.L   AUX_MASK_C
        MOVE.B  AUX_CELL_BG,AUX_PEN_D
        MOVEQ   #0,D0
        MOVE.B  AUX_CELL_ROLE,D0
        LEA     (role_pens).L,A0
        MOVE.B  (A0,D0.W),AUX_PEN_A
        LEA     (role_pens_low).L,A0
        MOVE.B  (A0,D0.W),D1
        TST.B   AUX_CELL_HIGH
        BEQ.S   .cms_low
        MOVE.B  AUX_PEN_A,D1
.cms_low:
        MOVE.B  D1,AUX_PEN_B

        MOVE.W  D3,D0
        SUB.W   D5,D0
        BCS.S   .cms_off
        CMP.W   D6,D0
        BCC.S   .cms_off
        BSR     pad_masks
        BRA.S   .cms_bracket
.cms_off:
        BSR     label_row
.cms_bracket:
        BSR     bracket_row
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; pad_cache_build — every pad this page can show, composed once.
;
; A pad's own rows hold the ring and the centre and nothing else: the label
; sits under the pad and the selection bracket outside it, so what those rows
; hold depends only on the size, the background, who owns the pin and whether
; it is high.  Three owners at two levels is six pads, and building them here
; means a level that changes is four longs a row copied rather than three
; masks and four pens worked out again.
;
; AUX_CELL_TIER and AUX_CELL_BG are what it builds for.
; Clobbers (saved/restored): D0-D7/A0-A2
; ---------------------------------------------------------------------------
pad_cache_build:
        MOVEM.L D0-D7/A0-A2,-(SP)
        CLR.B   AUX_PAD_OK
        MOVEQ   #0,D7
        MOVE.B  AUX_CELL_TIER,D7
        LEA     (tier_bytes).L,A0
        MOVE.B  (A0,D7.W),AUX_BOX_BYTES
        LEA     (tier_padx).L,A0
        MOVE.B  (A0,D7.W),AUX_CELL_PADX
        LEA     (tier_pady).L,A0
        MOVEQ   #0,D5
        MOVE.B  (A0,D7.W),D5            ; the pad's top row in the box
        LEA     (tier_d).L,A0
        MOVEQ   #0,D6
        MOVE.B  (A0,D7.W),D6            ; and how deep the pad is
        CLR.B   AUX_CELL_SEL
        LEA     (AUX_PAD_CACHE).W,A2
        MOVEQ   #0,D0                   ; role
.pcb_role:
        MOVEQ   #0,D1                   ; level
.pcb_level:
        MOVE.B  D0,AUX_CELL_ROLE
        MOVE.B  D1,AUX_CELL_HIGH
        MOVE.W  D5,D3                   ; the first row of the pad
        MOVEQ   #0,D4
.pcb_row:
        BSR     cell_masks
        BSR     cell_row_mix
        LEA     (AUX_ROWBUF).W,A0
        MOVEQ   #SCREEN_PLANES-1,D2
.pcb_plane:
        MOVE.L  (A0)+,(A2)+
        DBF     D2,.pcb_plane
        ADDQ.W  #1,D3
        ADDQ.W  #1,D4
        CMP.W   D6,D4
        BCS.S   .pcb_row
        MOVE.W  #PAD_ROWS_MAX,D2
        SUB.W   D6,D2
        MULU    #PAD_ROW_BYTES,D2
        ADDA.W  D2,A2                   ; on to the next pad's room
        ADDQ.W  #1,D1
        CMPI.W  #2,D1
        BCS.S   .pcb_level
        ADDQ.W  #1,D0
        CMPI.W  #3,D0
        BCS     .pcb_role
        MOVE.B  AUX_CELL_TIER,AUX_PAD_TIER
        MOVE.B  AUX_CELL_BG,AUX_PAD_BG
        MOVE.B  #1,AUX_PAD_OK
        MOVEM.L (SP)+,D0-D7/A0-A2
        RTS

; ---------------------------------------------------------------------------
; pad_cache_want — the composed pads built again where the page has changed
; size or background under them, and left alone where it has not.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
pad_cache_want:
        MOVEM.L D0,-(SP)
        TST.B   AUX_PAD_OK
        BEQ.S   .pcw_build
        MOVE.B  AUX_CELL_TIER,D0
        CMP.B   AUX_PAD_TIER,D0
        BNE.S   .pcw_build
        MOVE.B  AUX_CELL_BG,D0
        CMP.B   AUX_PAD_BG,D0
        BEQ.S   .pcw_out
.pcw_build:
        BSR     pad_cache_build
.pcw_out:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; pin_cell — one pin's box, edge to edge.
;
; AUX_CELL_X and AUX_CELL_Y are its top left, AUX_CELL_TIER its size,
; AUX_CELL_ROLE who owns the pin, AUX_CELL_HIGH its level, AUX_CELL_SEL
; whether the cursor is on it, and AUX_CELL_PIN with AUX_CELL_GROUP name it.
; AUX_CELL_PART = 1 covers the pad's rows alone, which is all that moves when
; a level changes.
; Clobbers (saved/restored): D0-D7/A0-A2
; ---------------------------------------------------------------------------
pin_cell:
        MOVEM.L D0-D7/A0-A2,-(SP)
        MOVEQ   #0,D7
        MOVE.B  AUX_CELL_TIER,D7
        LEA     (tier_bytes).L,A0
        MOVE.B  (A0,D7.W),AUX_BOX_BYTES
        LEA     (tier_padx).L,A0
        MOVE.B  (A0,D7.W),AUX_CELL_PADX

        MOVE.B  AUX_CELL_PIN,D0
        BSR     pin_label_text
        MOVE.B  D1,AUX_LAB_LEN
        LEA     (tier_pitch).L,A0
        MOVEQ   #0,D2
        MOVE.B  (A0,D7.W),D2
        LSL.W   #3,D1
        SUB.W   D1,D2
        LSR.W   #1,D2                   ; the label, centred in the box
        MOVE.B  D2,AUX_LAB_X

        LEA     (tier_pady).L,A0
        MOVEQ   #0,D5
        MOVE.B  (A0,D7.W),D5
        LEA     (tier_d).L,A0
        MOVEQ   #0,D6
        MOVE.B  (A0,D7.W),D6

        MOVEQ   #0,D3                   ; the first row to cover
        LEA     (tier_boxh).L,A0
        MOVEQ   #0,D4
        MOVE.B  (A0,D7.W),D4            ; and one past the last
        TST.B   AUX_CELL_PART
        BEQ.S   .pcl_rows
        MOVE.W  D5,D3
        MOVE.W  D5,D4
        ADD.W   D6,D4
.pcl_rows:
        MOVE.W  AUX_CELL_X,D1
        MOVE.W  AUX_CELL_Y,D2
        ADD.W   D3,D2
        BSR     pix_rowaddr

        ; The pad's own rows are already composed, unless what is on screen is
        ; not what they were composed for.
        TST.B   AUX_CELL_PART
        BEQ.S   .pcl_row
        TST.B   AUX_PAD_OK
        BEQ.S   .pcl_row
        MOVE.B  AUX_CELL_TIER,D0
        CMP.B   AUX_PAD_TIER,D0
        BNE.S   .pcl_row
        MOVE.B  AUX_CELL_BG,D0
        CMP.B   AUX_PAD_BG,D0
        BNE.S   .pcl_row
        MOVEQ   #0,D0
        MOVE.B  AUX_CELL_ROLE,D0
        ADD.W   D0,D0
        TST.B   AUX_CELL_HIGH
        BEQ.S   .pcl_var
        ADDQ.W  #1,D0
.pcl_var:
        MULU    #PAD_VAR_BYTES,D0
        LEA     (AUX_PAD_CACHE).W,A0
        ADDA.L  D0,A0
.pcl_fast:
        BSR     cell_row_put
        ADDA.W  #PAD_ROW_BYTES,A0
        ADDA.W  #SCREEN_ROW_BYTES,A2
        ADDQ.W  #1,D3
        CMP.W   D4,D3
        BCS.S   .pcl_fast
        BRA.S   .pcl_done
.pcl_row:
        BSR     cell_masks
        BSR     cell_row
        ADDA.W  #SCREEN_ROW_BYTES,A2
        ADDQ.W  #1,D3
        CMP.W   D4,D3
        BCS.S   .pcl_row
.pcl_done:
        MOVEM.L (SP)+,D0-D7/A0-A2
        RTS

; ---------------------------------------------------------------------------
; cell_put — D0.B = pin, D1.B = group.  Draws the pad where what it shows has
; changed since it was last drawn, and does nothing where it has not.
;
; A level that changes on its own touches neither the label nor the bracket,
; so that redraw covers the pad's rows alone.  A repaint, a cursor that moved,
; a pin whose flags changed and a pin changing hands each take the whole box.
;
; A page of fifty pins runs this fifty times a field and most of those pads
; have not moved, so everything up to the comparison is here rather than in
; routines of its own.  That is the place in the tables, the two bytes the
; device reported and the descriptor built from them.  Nothing is written
; anywhere until the pad turns out to need drawing.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
cell_put:
        MOVEM.L D0-D2/A0,-(SP)
        ANDI.W  #$00FF,D0
        ANDI.W  #$00FF,D1
        MOVE.W  D1,D2
        LSL.W   #MAX_PINS_SHIFT,D2
        ADD.W   D0,D2                   ; the pin's place in the tables
        LEA     (AUX_PIN_DIRTY).W,A0
        TST.B   AUX_FORCE
        BNE.S   .cpt_look
        TST.B   (A0,D2.W)
        BEQ     .cpt_out                ; the device has reported nothing new
.cpt_look:
        CLR.B   (A0,D2.W)
        LEA     (AUX_PIN_FLAGS).W,A0
        MOVEQ   #ROLE_THEIRS,D1
        BTST    #0,(A0,D2.W)            ; RBCP_AUX_FLAG_DRIVABLE
        BEQ.S   .cpt_role
        LEA     (AUX_PIN_STATE).W,A0
        MOVEQ   #ROLE_FREE,D1
        BTST    #1,(A0,D2.W)            ; PIN_DRIVEN_BIT
        BEQ.S   .cpt_role
        MOVEQ   #ROLE_OURS,D1
.cpt_role:
        LEA     (AUX_PIN_STATE).W,A0
        MOVE.B  (A0,D2.W),D0
        ANDI.B  #PIN_LEVEL_BIT|PIN_DRIVEN_BIT,D0
        LSL.B   #2,D1
        OR.B    D1,D0                   ; the role, above the level
        TST.B   AUX_CELL_SEL
        BEQ.S   .cpt_desc
        ORI.B   #DESC_SEL,D0
.cpt_desc:
        ORI.B   #DESC_DRAWN,D0          ; what the pad should show
        LEA     (AUX_PIN_DRAWN).W,A0
        MOVE.B  (A0,D2.W),D1            ; and what it does show
        CMP.B   D0,D1
        BNE.S   .cpt_move
        TST.B   AUX_REPAINT
        BEQ.S   .cpt_out                ; nothing about this pad has moved
.cpt_move:
        MOVE.B  D0,(A0,D2.W)
        CLR.B   AUX_CELL_PART
        TST.B   AUX_REPAINT
        BNE.S   .cpt_whole
        EOR.B   D0,D1
        ANDI.B  #DESC_SETTLED,D1
        BNE.S   .cpt_whole              ; the cursor or the flags moved
        MOVE.B  #1,AUX_CELL_PART
.cpt_whole:
        MOVE.W  D2,D1
        ANDI.W  #MAX_PINS-1,D1
        MOVE.B  D1,AUX_CELL_PIN
        LSR.W   #MAX_PINS_SHIFT,D2
        MOVE.B  D2,AUX_CELL_GROUP
        MOVE.B  D0,D1
        LSR.B   #2,D1
        ANDI.B  #3,D1
        MOVE.B  D1,AUX_CELL_ROLE
        MOVE.B  D0,D1
        ANDI.B  #PIN_LEVEL_BIT,D1
        MOVE.B  D1,AUX_CELL_HIGH
        BSR     pin_cell
.cpt_out:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; board_place — D0.W = how deep the page's pads and headings come to, D1.B = 1
; where the board's top must land on a character row.  AUX_BOARD_H and
; AUX_BOARD_Y, the board in the middle of the space rather than at the top of
; it.
;
; Every page works out its own depth, so a page of four pads and a page of
; fifty are each centred on what they hold.  The page with every pin on it
; writes headings with the text routines and so needs its top on a character
; row.
; Clobbers (saved/restored): D0-D2
; ---------------------------------------------------------------------------
board_place:
        MOVEM.L D0-D2,-(SP)
        CMPI.W  #PIN_H,D0
        BLS.S   .bpl_fits
        MOVE.W  #PIN_H,D0
.bpl_fits:
        MOVE.W  D0,AUX_BOARD_H
        MOVE.W  #PIN_H,D2
        SUB.W   D0,D2
        LSR.W   #1,D2
        TST.B   D1
        BEQ.S   .bpl_put
        ANDI.W  #$FFF8,D2
.bpl_put:
        ADDI.W  #PIN_Y0,D2
        MOVE.W  D2,AUX_BOARD_Y
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; draw_board — the board the pads sit on, where board_place put it: a strip
; with a lighter line along each edge, and background above and below it.
;
; A group with nothing on it gets no board.  The note row says why in words
; and a bare strip of board with no pads on it says nothing.
; Clobbers (saved/restored): D0-D2
; ---------------------------------------------------------------------------
draw_board:
        MOVEM.L D0-D2,-(SP)
        MOVE.B  #PEN_BG,D0
        MOVE.W  #PIN_Y0,D1
        MOVE.W  #PIN_H,D2
        BSR     pix_band
        MOVE.W  AUX_BOARD_H,D2
        BEQ.S   .dbd_out
        MOVE.B  #PEN_BOARD,D0
        MOVE.W  AUX_BOARD_Y,D1
        BSR     pix_band
        MOVE.B  #PEN_EDGE,D0
        MOVE.W  AUX_BOARD_Y,D1
        MOVEQ   #1,D2
        BSR     pix_band
        MOVE.B  #PEN_EDGE,D0
        MOVE.W  AUX_BOARD_Y,D1
        ADD.W   AUX_BOARD_H,D1
        SUBQ.W  #1,D1
        MOVEQ   #1,D2
        BSR     pix_band
.dbd_out:
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; pins_view — the pad size the current group's drivable pins get, how many
; rows of them there are, and where that puts the board.  The largest pad that
; holds them all.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
pins_view:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_drv
        MOVE.B  D0,AUX_VIEW_N
        BSR     pins_tier
        MOVE.B  D0,AUX_VIEW_TIER
        MOVEQ   #0,D1
        MOVE.B  D0,D1
        LEA     (tier_perrow).L,A0
        MOVEQ   #0,D2
        MOVE.B  (A0,D1.W),D2
        MOVEQ   #0,D0
        MOVE.B  AUX_VIEW_N,D0
        ADD.W   D2,D0
        SUBQ.W  #1,D0
        MOVEQ   #0,D1                   ; rows, rounded up
.pvw_div:
        CMP.W   D2,D0
        BCS.S   .pvw_out
        SUB.W   D2,D0
        ADDQ.W  #1,D1
        BRA.S   .pvw_div
.pvw_out:
        MOVE.B  D1,AUX_VIEW_ROWS
        MOVEQ   #0,D0
        MOVE.B  AUX_VIEW_TIER,D0
        LEA     (tier_boxh).L,A0
        MOVE.B  (A0,D0.W),D0
        ANDI.W  #$00FF,D0
        MULU    D1,D0
        BEQ.S   .pvw_place              ; no pads, so no board to stand them on
        ADDI.W  #PIN_TOP_PAD*2,D0       ; a margin above the pads and below
.pvw_place:
        MOVEQ   #0,D1
        BSR     board_place
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; row_left — D0.W = how many pads the row holds, D1.W = the tier.  The first
; pad's pixel column in D0.W, so a part-filled row sits under the full ones
; rather than at one end.
; Clobbers: D0
; ---------------------------------------------------------------------------
row_left:
        MOVEM.L D1-D2/A0,-(SP)
        LEA     (tier_pitch).L,A0
        MOVEQ   #0,D2
        MOVE.B  (A0,D1.W),D2
        MULU    D2,D0
        NEG.W   D0
        ADDI.W  #SCREEN_COLS*8,D0
        LSR.W   #1,D0
        ANDI.W  #$FFF8,D0
        MOVEM.L (SP)+,D1-D2/A0
        RTS

; ---------------------------------------------------------------------------
; slot_xy — D0.B = which of the group's drivable pins.  Its box's top left
; into AUX_CELL_X and AUX_CELL_Y, and AUX_CELL_TIER with it.
; Clobbers (saved/restored): D0-D4/A0
; ---------------------------------------------------------------------------
slot_xy:
        MOVEM.L D0-D4/A0,-(SP)
        MOVEQ   #0,D4
        MOVE.B  AUX_VIEW_TIER,D4
        MOVE.B  D4,AUX_CELL_TIER
        LEA     (tier_perrow).L,A0
        MOVEQ   #0,D1
        MOVE.B  (A0,D4.W),D1
        ANDI.W  #$00FF,D0
        MOVEQ   #0,D2                   ; the row this pad is on
.sxy_div:
        CMP.W   D1,D0
        BCS.S   .sxy_got
        SUB.W   D1,D0
        ADDQ.W  #1,D2
        BRA.S   .sxy_div
.sxy_got:
        MOVEQ   #0,D3
        MOVE.B  AUX_VIEW_N,D3
        MOVE.W  D2,-(SP)
        MULU    D1,D2
        SUB.W   D2,D3                   ; pads left from this row on
        MOVE.W  (SP)+,D2
        CMP.W   D1,D3
        BLS.S   .sxy_row
        MOVE.W  D1,D3
.sxy_row:
        MOVE.W  D0,-(SP)
        MOVE.W  D3,D0
        MOVE.W  D4,D1
        BSR     row_left
        MOVE.W  D0,D3                   ; the row's left edge
        MOVE.W  (SP)+,D0

        LEA     (tier_pitch).L,A0
        MOVEQ   #0,D1
        MOVE.B  (A0,D4.W),D1
        MULU    D1,D0
        ADD.W   D3,D0
        MOVE.W  D0,AUX_CELL_X

        LEA     (tier_boxh).L,A0
        MOVEQ   #0,D1
        MOVE.B  (A0,D4.W),D1
        MULU    D1,D2
        ADD.W   AUX_BOARD_Y,D2
        ADDQ.W  #PIN_TOP_PAD,D2
        MOVE.W  D2,AUX_CELL_Y
        MOVEM.L (SP)+,D0-D4/A0
        RTS

; ---------------------------------------------------------------------------
; draw_rings — the current group's drivable pins, as pads on a board.
;
; Nothing is drawn for a group with no drivable pins: there is no pad to draw
; and the note row says so in words.  AUX_REPAINT says whether the board goes
; down first and every pad with it, or only the pads that have moved.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
draw_rings:
        MOVEM.L D0-D3/A0,-(SP)
        MOVE.B  AUX_CUR_PAGE,D0
        CMP.B   AUX_GROUP_COUNT,D0
        BCC     .drg_out                ; the all-pins page draws its own
        MOVE.B  #PEN_BOARD,AUX_CELL_BG
        BSR     pins_view
        MOVE.B  AUX_VIEW_TIER,AUX_CELL_TIER
        BSR     pad_cache_want
        TST.B   AUX_REPAINT
        BEQ.S   .drg_pads
        BSR     draw_board
.drg_pads:
        MOVEQ   #0,D3                   ; the drivable pin being drawn
.drg_slot:
        CMP.B   AUX_VIEW_N,D3
        BCC.S   .drg_done
        MOVE.B  D3,D0
        BSR     slot_xy
        MOVEQ   #0,D2
        CMP.B   AUX_CUR_SLOT,D3
        BNE.S   .drg_nosel
        MOVEQ   #1,D2
.drg_nosel:
        MOVE.B  D2,AUX_CELL_SEL
        MOVE.B  D3,D0
        MOVE.B  AUX_CUR_GROUP,D1
        BSR     pins_drv_at
        MOVE.B  AUX_CUR_GROUP,D1
        BSR     cell_put
        ADDQ.B  #1,D3
        BRA.S   .drg_slot
.drg_done:
        CLR.B   AUX_REPAINT
.drg_out:
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; all_height — D0.B = a tier.  How deep the page holding every pin comes to at
; that size, in D1.W.  A group takes a heading on a character row and then its
; pads, and the next group's heading starts on a character row too.
; Clobbers: D1
; ---------------------------------------------------------------------------
all_height:
        MOVEM.L D0/D2-D5/A0,-(SP)
        MOVEQ   #0,D5
        MOVE.B  D0,D5
        LEA     (tier_perrow).L,A0
        MOVEQ   #0,D3
        MOVE.B  (A0,D5.W),D3
        LEA     (tier_boxh).L,A0
        MOVEQ   #0,D4
        MOVE.B  (A0,D5.W),D4
        MOVEQ   #0,D1                   ; the depth so far
        MOVEQ   #0,D5                   ; group
.ahg_group:
        CMP.B   AUX_GROUP_COUNT,D5
        BCC.S   .ahg_out
        ADDQ.W  #8,D1                   ; the heading
        MOVE.B  D5,D0
        BSR     group_pins
        ANDI.W  #$00FF,D0
        ADD.W   D3,D0
        SUBQ.W  #1,D0
        MOVEQ   #0,D2
.ahg_div:
        CMP.W   D3,D0
        BCS.S   .ahg_rows
        SUB.W   D3,D0
        ADDQ.W  #1,D2
        BRA.S   .ahg_div
.ahg_rows:
        MULU    D4,D2
        ADD.W   D2,D1
        ADDQ.W  #7,D1
        ANDI.W  #$FFF8,D1               ; the next heading, on a character row
        ADDQ.B  #1,D5
        BRA.S   .ahg_group
.ahg_out:
        MOVEM.L (SP)+,D0/D2-D5/A0
        RTS

; ---------------------------------------------------------------------------
; all_tier — the pad size the page holding every pin gets: the larger one
; where every group fits on the board with its heading, the smaller otherwise.
; Output: D0.B = the tier, D1.W = how deep the page comes to at it
; Clobbers: D0/D1
; ---------------------------------------------------------------------------
all_tier:
        MOVEQ   #ALL_TIER_BIG,D0
        BSR     all_height
        CMPI.W  #PIN_H,D1
        BLS.S   .atr_out
        MOVEQ   #ALL_TIER_SMALL,D0
        BSR     all_height
.atr_out:
        RTS

; ---------------------------------------------------------------------------
; all_bank — one row of group D5.B's pads at row D6.W, starting at pin D4.W.
; Moves D6 past the row.
; Output: D0.B = 1 where the row does not fit on the board
; Clobbers: D0/D6
; ---------------------------------------------------------------------------
all_bank:
        MOVEM.L D1-D5/A0,-(SP)
        MOVE.B  D5,AUX_ALL_GROUP
        MOVE.W  D4,AUX_ALL_BASE
        MOVEQ   #0,D3
        MOVE.B  AUX_VIEW_TIER,D3
        LEA     (tier_boxh).L,A0
        MOVEQ   #0,D2
        MOVE.B  (A0,D3.W),D2
        MOVE.W  D6,D0
        ADD.W   D2,D0
        SUB.W   AUX_BOARD_Y,D0
        CMP.W   AUX_BOARD_H,D0
        BHI     .abk_full
        MOVE.W  D2,AUX_ALL_BOXH

        LEA     (tier_perrow).L,A0
        MOVEQ   #0,D1
        MOVE.B  (A0,D3.W),D1
        MOVE.W  D1,AUX_ALL_PER

        MOVE.B  D5,D0
        BSR     group_pins
        ANDI.W  #$00FF,D0
        SUB.W   D4,D0
        CMP.W   D1,D0
        BLS.S   .abk_count
        MOVE.W  D1,D0
.abk_count:
        MOVE.W  D0,AUX_ALL_CNT
        MOVE.W  D3,D1
        BSR     row_left
        MOVE.W  D0,AUX_ALL_LEFT

        ; A group whose pins read as a number runs right to left, so the pad
        ; at the left of the row is the highest-numbered one on it.
        MOVE.B  D5,D0
        BSR     group_type
        BSR     pins_reversed
        MOVE.B  D0,AUX_ALL_REV

        MOVE.W  D6,AUX_CELL_Y
        MOVE.B  AUX_VIEW_TIER,AUX_CELL_TIER
        CLR.B   AUX_CELL_SEL
        ; The pitch is the same for every pad on the row and the row's first
        ; pin is in AUX_ALL_BASE, so the column walks along by one pitch a pad
        ; rather than being multiplied out again for each.
        MOVEQ   #0,D3
        MOVE.B  AUX_VIEW_TIER,D3
        LEA     (tier_pitch).L,A0
        MOVEQ   #0,D4
        MOVE.B  (A0,D3.W),D4
        MOVE.W  AUX_ALL_LEFT,D3
        MOVEQ   #0,D2                   ; the column being drawn
.abk_cell:
        CMP.W   AUX_ALL_CNT,D2
        BCC.S   .abk_done
        MOVE.W  D3,AUX_CELL_X
        MOVE.W  AUX_ALL_BASE,D0
        TST.B   AUX_ALL_REV
        BEQ.S   .abk_up
        ADD.W   AUX_ALL_CNT,D0
        SUBQ.W  #1,D0
        SUB.W   D2,D0
        BRA.S   .abk_put
.abk_up:
        ADD.W   D2,D0
.abk_put:
        MOVE.B  AUX_ALL_GROUP,D1
        BSR     cell_put
        ADD.W   D4,D3
        ADDQ.W  #1,D2
        BRA.S   .abk_cell
.abk_done:
        ADD.W   AUX_ALL_BOXH,D6
        MOVEQ   #0,D0
        BRA.S   .abk_out
.abk_full:
        MOVEQ   #1,D0
.abk_out:
        MOVEM.L (SP)+,D1-D5/A0
        RTS

; ---------------------------------------------------------------------------
; all_group_head — the group's name and its pin count, on the character row
; D6.W sits on, over the board.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
all_group_head:
        MOVEM.L D0-D2/A0,-(SP)
        TST.B   AUX_REPAINT
        BEQ.S   .agh_out
        MOVE.W  D6,D2
        LSR.W   #3,D2
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BOARD,VAR_PEN_BG
        MOVE.B  AUX_ALL_GROUP,D0
        BSR     group_type
        BSR     type_name
        MOVE.B  #COL_GROUP,D1
        BSR     screen_print
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #COL_OF,D1
        MOVE.B  AUX_ALL_GROUP,D0
        BSR     group_pins
        BSR     print_dec
        ADDQ.B  #1,D1
        LEA     (str_pins).L,A0
        BSR     screen_print
        BSR     plain_pens
.agh_out:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_all — every pin of every group, group by group, on one board.
;
; The group pages show only the pins this program can drive.  This page shows
; the rest, the lines the device serves the ROM on included, read as often as
; everything else.
;
; A device with more groups or rows than the board holds is cut off at the
; bottom and the note row says so.
; Clobbers (saved/restored): D0-D6/A0
; ---------------------------------------------------------------------------
draw_all:
        MOVEM.L D0-D6/A0,-(SP)
        MOVE.B  #PEN_BOARD,AUX_CELL_BG
        BSR     all_tier
        MOVE.B  D0,AUX_VIEW_TIER
        MOVE.B  D0,AUX_CELL_TIER
        BSR     pad_cache_want
        MOVE.W  D1,D0
        MOVEQ   #1,D1                   ; the headings land on character rows
        BSR     board_place
        TST.B   AUX_REPAINT
        BEQ.S   .dal_groups
        BSR     draw_board
.dal_groups:
        MOVE.W  AUX_BOARD_Y,D6          ; the row being written
        MOVEQ   #0,D5                   ; group
.dal_group:
        CMP.B   AUX_GROUP_COUNT,D5
        BCC     .dal_out
        MOVE.B  D5,AUX_ALL_GROUP
        BSR     all_group_head
        ADDQ.W  #8,D6
        MOVEQ   #0,D4                   ; the first pin of the row
.dal_bank:
        MOVE.B  D5,D0
        BSR     group_pins
        ANDI.W  #$00FF,D0
        CMP.W   D4,D0
        BLS.S   .dal_next
        BSR     all_bank
        TST.B   D0
        BNE.S   .dal_cut
        ADD.W   AUX_ALL_PER,D4
        BRA.S   .dal_bank
.dal_next:
        ADDQ.W  #7,D6
        ANDI.W  #$FFF8,D6
        ADDQ.B  #1,D5
        BRA     .dal_group
.dal_cut:
        MOVE.B  #1,AUX_TRUNCATED
.dal_out:
        CLR.B   AUX_REPAINT
        MOVEM.L (SP)+,D0-D6/A0
        RTS

; ---------------------------------------------------------------------------
; clear_rings — the legend and the board area, back to background.  The reset
; screen draws over them.
; Clobbers (saved/restored): D0-D2
; ---------------------------------------------------------------------------
clear_rings:
        MOVEM.L D0-D2,-(SP)
        MOVE.B  #PEN_BG,D0
        MOVE.W  #ROW_LEGEND*8,D1
        MOVE.W  #(ROW_RINGS_END+1-ROW_LEGEND)*8,D2
        BSR     pix_band
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; legend_pad — D0.B = the role, D1.W = x, D2.W = y, D3.B = the level.  One
; small pad on the legend row, with nothing around it.
; Clobbers (saved/restored): D0-D3
; ---------------------------------------------------------------------------
legend_pad:
        MOVEM.L D0-D3,-(SP)
        MOVE.B  D0,AUX_CELL_ROLE
        MOVE.B  D3,AUX_CELL_HIGH
        MOVE.W  D1,AUX_CELL_X
        MOVEQ   #0,D0
        MOVE.B  (tier_pady+ALL_TIER_SMALL).L,D0
        SUB.W   D0,D2
        MOVE.W  D2,AUX_CELL_Y
        MOVE.B  #ALL_TIER_SMALL,AUX_CELL_TIER
        MOVE.B  #PEN_BG,AUX_CELL_BG
        CLR.B   AUX_CELL_SEL
        MOVE.B  #1,AUX_CELL_PART
        CLR.B   AUX_CELL_PIN
        CLR.B   AUX_CELL_GROUP
        BSR     pin_cell
        MOVE.B  #PEN_BOARD,AUX_CELL_BG
        MOVEM.L (SP)+,D0-D3
        RTS

; ---------------------------------------------------------------------------
; draw_legend — what a pad's pen and its fill stand for, in one row under the
; count.  It is the only place the colours are named.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
draw_legend:
        MOVEM.L D0-D3/A0,-(SP)
        MOVEQ   #ROW_LEGEND,D0
        BSR     clear_row
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG

        MOVEQ   #ROLE_OURS,D0
        MOVE.W  #LEG_X_OURS,D1
        MOVE.W  #ROW_LEGEND*8+1,D2
        MOVEQ   #0,D3
        BSR     legend_pad
        LEA     (str_leg_ours).L,A0
        MOVE.B  #LEG_X_OURS/8+1,D1
        MOVE.B  #ROW_LEGEND,D2
        BSR     screen_print

        MOVEQ   #ROLE_FREE,D0
        MOVE.W  #LEG_X_FREE,D1
        MOVE.W  #ROW_LEGEND*8+1,D2
        MOVEQ   #0,D3
        BSR     legend_pad
        LEA     (str_leg_free).L,A0
        MOVE.B  #LEG_X_FREE/8+1,D1
        MOVE.B  #ROW_LEGEND,D2
        BSR     screen_print

        MOVEQ   #ROLE_THEIRS,D0
        MOVE.W  #LEG_X_THEIRS,D1
        MOVE.W  #ROW_LEGEND*8+1,D2
        MOVEQ   #0,D3
        BSR     legend_pad
        LEA     (str_leg_theirs).L,A0
        MOVE.B  #LEG_X_THEIRS/8+1,D1
        MOVE.B  #ROW_LEGEND,D2
        BSR     screen_print

        MOVEQ   #ROLE_FREE,D0
        MOVE.W  #LEG_X_HIGH,D1
        MOVE.W  #ROW_LEGEND*8+1,D2
        MOVEQ   #1,D3
        BSR     legend_pad
        LEA     (str_leg_high).L,A0
        MOVE.B  #LEG_X_HIGH/8+1,D1
        MOVE.B  #ROW_LEGEND,D2
        BSR     screen_print

        MOVEQ   #ROLE_FREE,D0
        MOVE.W  #LEG_X_LOW,D1
        MOVE.W  #ROW_LEGEND*8+1,D2
        MOVEQ   #0,D3
        BSR     legend_pad
        LEA     (str_leg_low).L,A0
        MOVE.B  #LEG_X_LOW/8+1,D1
        MOVE.B  #ROW_LEGEND,D2
        BSR     screen_print

        BSR     plain_pens
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; draw_rate — how many times a second every pin on the page was read, at the
; right of the count row.  A live display that says its own rate is one a
; reader can tell from a frozen one.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_rate:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        LEA     (str_blank).L,A0
        MOVE.B  #COL_RATE,D1
        MOVE.B  #ROW_COUNT,D2
        BSR     screen_print
        MOVE.B  #COL_RATE,D1
        MOVE.B  AUX_FPS,D0
        BSR     print_dec
        ADDQ.B  #1,D1
        LEA     (str_hz).L,A0
        BSR     screen_print
        BSR     plain_pens
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; rate_tick — once a second, the sweeps counted since the last time put on
; screen.
;
; The CIA-B counter is clocked by horizontal sync, so a second is a fixed
; number of scan lines and the Agnus fitted decides which number.
; Clobbers (saved/restored): D0-D1
; ---------------------------------------------------------------------------
rate_tick:
        MOVEM.L D0-D1,-(SP)
        BSR     tod_now
        MOVE.L  D0,D1
        SUB.L   AUX_RATE_TOD,D1
        MOVE.L  #TOD_SEC_NTSC,D0
        TST.B   VAR_IS_PAL
        BEQ.S   .rtk_have
        MOVE.L  #TOD_SEC_PAL,D0
.rtk_have:
        CMP.L   D0,D1
        BCS.S   .rtk_out
        BSR     tod_now
        MOVE.L  D0,AUX_RATE_TOD
        MOVE.B  AUX_SWEEPS,AUX_FPS
        CLR.B   AUX_SWEEPS
        BSR     draw_rate
.rtk_out:
        MOVEM.L (SP)+,D0-D1
        RTS

; ---------------------------------------------------------------------------
; pins_read_one — D0.B = pin, D1.B = group.  One GET_AUX_PIN_INFO into
; AUX_PIN_FLAGS and AUX_PIN_STATE.
;
; Level and driven mean nothing unless the device says they do, so a pin that
; cannot be read is recorded low and undriven rather than believed.
; Output: D0=0 read, D0=1 the device stopped answering
; Clobbers: D0
; ---------------------------------------------------------------------------
pins_read_one:
        MOVEM.L D1-D3/A0-A1,-(SP)
        MOVE.B  D0,D2                   ; pin
        MOVE.B  D1,D3                   ; group
        BSR     rbcp_cmd_get_aux_pin_info
        TST.B   D0
        BNE.S   .pro_fail
        MOVEQ   #3,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  D2,D0
        MOVE.B  D3,D1
        BSR     pins_index
        LEA     (AUX_PIN_FLAGS).W,A0
        LEA     (AUX_PIN_STATE).W,A1
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_AUX_PIN_FLAGS).W,D2
        MOVEQ   #0,D1
        MOVE.B  D2,D3
        ANDI.B  #RBCP_AUX_FLAG_READABLE,D3
        BEQ.S   .pro_have               ; a pin the device will not read is low
        TST.B   (CONFIG_RBCP_DATA_BUF+RBCP_AUX_PIN_LEVEL).W
        BEQ.S   .pro_low
        MOVEQ   #PIN_LEVEL_BIT,D1
.pro_low:
        TST.B   (CONFIG_RBCP_DATA_BUF+RBCP_AUX_PIN_DRIVEN).W
        BEQ.S   .pro_have
        ORI.B   #PIN_DRIVEN_BIT,D1
.pro_have:
        ; The pad is drawn again only where the answer differs from the last
        ; one, so a pin the device reports the same costs the drawer nothing.
        CMP.B   (A0,D0.W),D2
        BNE.S   .pro_moved
        CMP.B   (A1,D0.W),D1
        BEQ.S   .pro_ok
.pro_moved:
        MOVE.B  D2,(A0,D0.W)
        MOVE.B  D1,(A1,D0.W)
        LEA     (AUX_PIN_DIRTY).W,A0
        MOVE.B  #1,(A0,D0.W)
        MOVE.B  #1,AUX_MOVED
.pro_ok:
        MOVEQ   #0,D0
        BRA.S   .pro_out
.pro_fail:
        MOVEQ   #1,D0
.pro_out:
        MOVEM.L (SP)+,D1-D3/A0-A1
        RTS

; ---------------------------------------------------------------------------
; scan_count — how many pins the page on screen holds.  A group page shows
; only the pins it can drive, so those are the only ones worth asking about.
; Output: D0.W
; Clobbers: D0
; ---------------------------------------------------------------------------
scan_count:
        MOVEM.L D1-D2,-(SP)
        MOVE.B  AUX_CUR_PAGE,D0
        CMP.B   AUX_GROUP_COUNT,D0
        BCC.S   .scn_all
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_drv
        ANDI.W  #$00FF,D0
        BRA.S   .scn_out
.scn_all:
        MOVEQ   #0,D2
        MOVEQ   #0,D1
.scn_group:
        CMP.B   AUX_GROUP_COUNT,D1
        BCC.S   .scn_total
        MOVE.B  D1,D0
        BSR     group_pins
        ANDI.W  #$00FF,D0
        ADD.W   D0,D2
        ADDQ.B  #1,D1
        BRA.S   .scn_group
.scn_total:
        MOVE.W  D2,D0
.scn_out:
        MOVEM.L (SP)+,D1-D2
        RTS

; ---------------------------------------------------------------------------
; scan_at — D0.W = a position in the page's list of pins.  Reads that one pin.
; Output: D0=0 read, D0=1 the device stopped answering
; Clobbers: D0
; ---------------------------------------------------------------------------
scan_at:
        MOVEM.L D1-D3/A0,-(SP)
        MOVE.W  D0,D3
        MOVE.B  AUX_CUR_PAGE,D0
        CMP.B   AUX_GROUP_COUNT,D0
        BCC.S   .sat_all
        MOVE.B  D3,D0
        MOVE.B  AUX_CUR_GROUP,D1
        BSR     pins_drv_at
        MOVE.B  AUX_CUR_GROUP,D1
        BRA.S   .sat_read
.sat_all:
        ; The counts are read straight out of the table here.  This runs for
        ; every pin of every sweep and a call a group is a call too many.
        LEA     (AUX_GROUP_PINS).W,A0
        MOVEQ   #0,D1                   ; group
.sat_group:
        CMP.B   AUX_GROUP_COUNT,D1
        BCC.S   .sat_gone
        MOVEQ   #0,D0
        MOVE.B  (A0,D1.W),D0
        CMP.W   D0,D3
        BCS.S   .sat_found
        SUB.W   D0,D3
        ADDQ.B  #1,D1
        BRA.S   .sat_group
.sat_found:
        MOVE.B  D3,D0
.sat_read:
        BSR     pins_read_one
        BRA.S   .sat_out
.sat_gone:
        MOVEQ   #0,D0                   ; past the end, nothing to read
.sat_out:
        MOVEM.L (SP)+,D1-D3/A0
        RTS

; ---------------------------------------------------------------------------
; scan_slice — the page's pins read again, for the rest of the field.
;
; A page whose pins all fit is read right through, and the field ends there:
; the screen changes once a field and nothing is gained by asking the device
; the same question twice between two pictures.  A page with more pins
; than that reads what it can and carries on where it left off next field, so
; the rest of the screen keeps its rate instead of the whole page dropping to
; the slowest pin's.
;
; The sweep gets whatever the field has left once the draw has had its share.
; The sweep stops when another read the length of the last one would run into
; the next field, so a page that takes most of a field to draw still reads
; every field rather than losing one to the wait.
;
; The pin under the cursor is read first, so the one being driven answers
; every field whatever the sweep reaches.
;
; The keyboard is polled between pins, because a press left unread for the
; length of a sweep does not appear until the sweep ends.
; Clobbers (saved/restored): D0-D6
; ---------------------------------------------------------------------------
scan_slice:
        MOVEM.L D0-D6,-(SP)
        MOVE.L  AUX_FIELD_TOD,D3        ; when the field began
        MOVE.L  #FIELD_LINES_NTSC-SCAN_SPARE,D6
        TST.B   VAR_IS_PAL
        BEQ.S   .ssl_field
        MOVE.L  #FIELD_LINES_PAL-SCAN_SPARE,D6
.ssl_field:
        BSR     scan_cursor
        BSR     scan_count
        MOVE.W  D0,D1                   ; pins on the page, fixed for the field
        BEQ.S   .ssl_out                ; a page with no pins on it
        MOVEQ   #0,D4                   ; pins read this field
        BSR     tod_now
        MOVE.L  D0,D2                   ; when the next read starts
.ssl_one:
        CMP.W   D1,D4
        BCC.S   .ssl_out                ; the whole page, read this field
        MOVE.W  AUX_SCAN_NEXT,D0
        CMP.W   D1,D0
        BCS.S   .ssl_go
        MOVEQ   #0,D0
        MOVE.W  D0,AUX_SCAN_NEXT
        ADDQ.B  #1,AUX_SWEEPS           ; a whole pass of the page
.ssl_go:
        MOVE.W  AUX_SCAN_NEXT,D0
        BSR     scan_at
        TST.B   D0
        BNE.S   .ssl_lost
        ADDQ.W  #1,AUX_SCAN_NEXT
        ADDQ.W  #1,D4
        BSR     key_poll
        BSR     tod_now
        MOVE.L  D0,D5
        SUB.L   D2,D5                   ; what that read cost
        MOVE.L  D0,D2                   ; and when the next one starts
        SUB.L   D3,D0                   ; how far into the field it leaves us
        ADD.L   D5,D0                   ; with room for another the same
        CMP.L   D6,D0
        BCS.S   .ssl_one
.ssl_out:
        MOVEM.L (SP)+,D0-D6
        RTS
.ssl_lost:
        MOVEQ   #ERR_LOST,D0
        BRA     err_halt

; ---------------------------------------------------------------------------
; scan_cursor — the pin under the cursor, read again.  The group pages are the
; only ones with a cursor on them.
; Clobbers (saved/restored): D0-D1
; ---------------------------------------------------------------------------
scan_cursor:
        MOVEM.L D0-D1,-(SP)
        MOVE.B  AUX_CUR_PAGE,D0
        CMP.B   AUX_GROUP_COUNT,D0
        BCC.S   .scu_out
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_drv
        BEQ.S   .scu_out                ; no drivable pin to point at
        MOVE.B  AUX_CUR_SLOT,D0
        MOVE.B  AUX_CUR_GROUP,D1
        BSR     pins_drv_at
        MOVE.B  AUX_CUR_GROUP,D1
        BSR     pins_read_one
        TST.B   D0
        BNE.S   .scu_lost
.scu_out:
        MOVEM.L (SP)+,D0-D1
        RTS
.scu_lost:
        MOVEQ   #ERR_LOST,D0
        BRA     err_halt

; ---------------------------------------------------------------------------
; key_poll — one poll of the keyboard, held until the caller is ready for it.
; A key already waiting is not thrown away.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
key_poll:
        MOVEM.L D0,-(SP)
        TST.B   AUX_KEY_STASH
        BNE.S   .kpl_out
        BSR     amiga_getkey
        MOVE.B  D0,AUX_KEY_STASH
.kpl_out:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; draw_page_pins — whichever page is up, drawn again.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
draw_page_pins:
        MOVEM.L D0,-(SP)
        TST.B   AUX_REPAINT
        BNE.S   .dpp_force
        MOVE.B  AUX_CUR_PAGE,D0
        CMP.B   AUX_LAST_PAGE,D0
        BNE.S   .dpp_force
        MOVE.B  AUX_CUR_GROUP,D0
        CMP.B   AUX_LAST_GROUP,D0
        BNE.S   .dpp_force
        MOVE.B  AUX_CUR_SLOT,D0
        CMP.B   AUX_LAST_SLOT,D0
        BNE.S   .dpp_force
        TST.B   AUX_MOVED
        BEQ.S   .dpp_out                ; no pin has come back different
        BRA.S   .dpp_go
.dpp_force:
        MOVE.B  #1,AUX_FORCE            ; the cursor moved, or the page did
.dpp_go:
        MOVE.B  AUX_CUR_PAGE,AUX_LAST_PAGE
        MOVE.B  AUX_CUR_GROUP,AUX_LAST_GROUP
        MOVE.B  AUX_CUR_SLOT,AUX_LAST_SLOT
        CLR.B   AUX_MOVED
        MOVE.B  AUX_CUR_PAGE,D0
        CMP.B   AUX_GROUP_COUNT,D0
        BCC.S   .dpp_all
        BSR     draw_rings
        BRA.S   .dpp_done
.dpp_all:
        BSR     draw_all
.dpp_done:
        CLR.B   AUX_FORCE
.dpp_out:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; pins_repaint — the next draw puts the board down and every pad on it.  The
; screen no longer holds this page, so nothing may be skipped as already
; drawn.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
pins_repaint:
        MOVEM.L D0/A0,-(SP)
        MOVE.B  #1,AUX_REPAINT
        MOVE.B  #1,AUX_FORCE
        CLR.W   AUX_SCAN_NEXT
        LEA     (AUX_PIN_DRAWN).W,A0
        MOVE.W  #MAX_GROUPS*MAX_PINS/2-1,D0
.prp_clr:
        CLR.W   (A0)+
        DBF     D0,.prp_clr
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; live_tick — one field: the pins read again as far as the field allows, the
; pads that moved drawn again, and whatever was pressed.
;
; The draw goes in at the field boundary, so a pad changes on screen at the
; top of a frame rather than half way down one.
;
; The counter reading at the top is scan_slice's, which measures its budget
; from where the field started.
; Output: D0.B = a key, or 0
; Clobbers: D0
; ---------------------------------------------------------------------------
live_tick:
        BSR     wait_field
        BSR     tod_now
        MOVE.L  D0,AUX_FIELD_TOD
        BSR     key_poll
        BSR     draw_page_pins
        BSR     scan_slice
        BSR     rate_tick
        BSR     key_poll
        MOVE.B  AUX_KEY_STASH,D0
        CLR.B   AUX_KEY_STASH
        RTS
