; amiga_blit.s — blitter primitives and object drawing
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; RAM section.
;
; Every object is interleaved as the bitmap is, so the whole of it goes down
; in one blit of HEIGHT*PLANES rows.  Each row carries one blank word on the
; right for the pixels the barrel shifter pushes past the edge, so an object
; can land on any pixel column and not only a word boundary.
;
; A mask is spread to four planes before it is used, so it steps at the same
; rate as the object beside it and its modulo is zero too.

; ---------------------------------------------------------------------------
; blit_wait — hold until the blitter has finished.
; Clobbers: nothing
; ---------------------------------------------------------------------------
blit_wait:
        BTST    #6,(DMACONR).L          ; BBUSY, bit 14 of the word
        BNE.S   blit_wait
        RTS

; ---------------------------------------------------------------------------
; obj_dest — D6.W = x, D7.W = y.  Returns A1 = the word the object's top left
; corner lands in, and D3.W = how far into that word.  It follows
; VAR_DRAW_BASE, as the text routines do, so an object goes into the
; foreground object or straight on screen by the same means.
; Clobbers: nothing beyond the two returns
; ---------------------------------------------------------------------------
obj_dest:
        MOVEM.L D0-D1,-(SP)
        MOVE.W  D6,D3
        ANDI.W  #15,D3
        MOVEQ   #0,D0
        MOVE.W  D6,D0
        LSR.W   #4,D0
        ADD.W   D0,D0                   ; two bytes to the word
        MOVEQ   #0,D1
        MOVE.W  D7,D1
        MULU    #SCREEN_ROW_BYTES,D1
        ADD.L   D0,D1
        MOVEA.L VAR_DRAW_BASE,A1
        ADDA.L  D1,A1
        MOVEM.L (SP)+,D0-D1
        RTS

; ---------------------------------------------------------------------------
; draw_object — an object on the screen, cut out by its mask so what is behind
; shows through where the object is transparent.
; A0 = object, A2 = its spread mask, D0.W = words across, D1.W = pixel rows,
; D6.W = x, D7.W = y.
; Clobbers: nothing
; ---------------------------------------------------------------------------
draw_object:
        MOVEM.L D1-D5/A1,-(SP)
        BSR     obj_dest
        MOVE.W  #SCREEN_BPL_W,D2
        SUB.W   D0,D2
        SUB.W   D0,D2                   ; the rest of the plane's row
        LSL.W   #2,D1                   ; four planes to every pixel row
        MOVEQ   #0,D4                   ; the object's rows are contiguous
        MOVEQ   #0,D5                   ; and so are the spread mask's
        BSR     blit_cookie
        MOVEM.L (SP)+,D1-D5/A1
        RTS

; ---------------------------------------------------------------------------
; draw_object_solid — an object on the screen, unmasked.  The object's
; own transparent pixels are written as background, so this is only for an
; object landing on ground that is already clear.
; A0 = object, D0.W = words across, D1.W = pixel rows, D6.W = x, D7.W = y.
; Clobbers: nothing
; ---------------------------------------------------------------------------
draw_object_solid:
        MOVEM.L D1-D4/A1,-(SP)
        BSR     obj_dest
        MOVE.W  #SCREEN_BPL_W,D2
        SUB.W   D0,D2
        SUB.W   D0,D2
        LSL.W   #2,D1
        MOVEQ   #0,D4
        BSR     blit_copy
        MOVEM.L (SP)+,D1-D4/A1
        RTS

; ---------------------------------------------------------------------------
; blit_clear — zero a rectangle.  D alone with a minterm of zero.
; A1 = first word, D0.W = words across, D1.W = blitter rows, D2.W = modulo.
; Clobbers: nothing
; ---------------------------------------------------------------------------
blit_clear:
        MOVEM.L D0-D2,-(SP)
        BSR     blit_wait
        MOVE.W  #$0100,BLTCON0          ; D enabled, every minterm clear
        CLR.W   BLTCON1
        MOVE.W  D2,BLTDMOD
        MOVE.L  A1,BLTDPTH
        LSL.W   #6,D1
        OR.W    D0,D1
        MOVE.W  D1,BLTSIZE
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; blit_copy — A straight into D, shifted.
; A0 = source, A1 = destination, D0.W = words across, D1.W = blitter rows,
; D2.W = destination modulo, D3.W = shift 0 to 15, D4.W = source modulo.
; Clobbers: nothing
; ---------------------------------------------------------------------------
blit_copy:
        MOVEM.L D0-D5,-(SP)
        BSR     blit_wait
        MOVE.W  D3,D5
        ROR.W   #4,D5                   ; the shift lives in bits 15 to 12
        ORI.W   #$09F0,D5               ; A and D enabled, D = A
        MOVE.W  D5,BLTCON0
        CLR.W   BLTCON1
        MOVE.W  #$FFFF,BLTAFWM
        MOVE.W  #$FFFF,BLTALWM
        MOVE.W  D4,BLTAMOD
        MOVE.W  D2,BLTDMOD
        MOVE.L  A0,BLTAPTH
        MOVE.L  A1,BLTDPTH
        LSL.W   #6,D1
        OR.W    D0,D1
        MOVE.W  D1,BLTSIZE
        MOVEM.L (SP)+,D0-D5
        RTS

; ---------------------------------------------------------------------------
; blit_or — A into D over what C already holds, shifted.  Used to fold one
; mask into another.
; A0 = source, A1 = destination, D0.W = words across, D1.W = blitter rows,
; D2.W = destination modulo, D3.W = shift, D4.W = source modulo.
; Clobbers: nothing
; ---------------------------------------------------------------------------
blit_or:
        MOVEM.L D0-D5,-(SP)
        BSR     blit_wait
        MOVE.W  D3,D5
        ROR.W   #4,D5
        ORI.W   #$0BFA,D5               ; A, C and D enabled, D = A OR C
        MOVE.W  D5,BLTCON0
        CLR.W   BLTCON1
        MOVE.W  #$FFFF,BLTAFWM
        MOVE.W  #$FFFF,BLTALWM
        MOVE.W  D4,BLTAMOD
        MOVE.W  D2,BLTCMOD
        MOVE.W  D2,BLTDMOD
        MOVE.L  A0,BLTAPTH
        MOVE.L  A1,BLTCPTH
        MOVE.L  A1,BLTDPTH
        LSL.W   #6,D1
        OR.W    D0,D1
        MOVE.W  D1,BLTSIZE
        MOVEM.L (SP)+,D0-D5
        RTS

; ---------------------------------------------------------------------------
; blit_cookie — the mask decides pixel by pixel whether the object or the
; screen under it comes out.  D = A AND B OR NOT A AND C is minterm $CA, with
; A the mask, B the object and C the screen.  A and B shift together, A's
; amount from BLTCON0 and B's from BLTCON1.
; A0 = object, A2 = mask, A1 = destination, D0.W = words across,
; D1.W = blitter rows, D2.W = destination modulo, D3.W = shift,
; D4.W = object modulo, D5.W = mask modulo.
; Clobbers: nothing
; ---------------------------------------------------------------------------
blit_cookie:
        MOVEM.L D0-D6,-(SP)
        BSR     blit_wait
        MOVE.W  D3,D6
        ROR.W   #4,D6
        MOVE.W  D6,BLTCON1              ; the mask shifts with the object
        ORI.W   #$0FCA,D6               ; A, B, C and D enabled
        MOVE.W  D6,BLTCON0
        MOVE.W  #$FFFF,BLTAFWM
        MOVE.W  #$FFFF,BLTALWM
        MOVE.W  D5,BLTAMOD
        MOVE.W  D4,BLTBMOD
        MOVE.W  D2,BLTCMOD
        MOVE.W  D2,BLTDMOD
        MOVE.L  A2,BLTAPTH
        MOVE.L  A0,BLTBPTH
        MOVE.L  A1,BLTCPTH
        MOVE.L  A1,BLTDPTH
        LSL.W   #6,D1
        OR.W    D0,D1
        MOVE.W  D1,BLTSIZE
        MOVEM.L (SP)+,D0-D6
        RTS
