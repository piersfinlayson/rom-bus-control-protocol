; amiga_hw.s — A500 ROM-section hardware routines
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; ROM-only routines executed before the RAM section is copied.
; Custom chip registers are reached by absolute long addressing rather than
; indexed from A0, because the register equates are 24-bit addresses and
; d(An) has only a 16-bit signed displacement.

; ---------------------------------------------------------------------------
; a500_hw_init — one-time hardware setup at cold start
; Clobbers: D0/A0/A1 (startup — no meaningful register state yet)
; ---------------------------------------------------------------------------
a500_hw_init:
        ORI.W   #$2700,SR
        MOVE.W  #COL_WHITE,COLOR00  ; WHITE — the CPU is alive

        ; A cold start can find the blitter already busy, and every later
        ; blit waits on it.  Giving it a blit of its own — one word, into
        ; scratch — puts it into a state we set rather than one we found.
        ; Nothing of ours is in chip RAM yet, so the write can do no harm.
        ; The count is a bound, not a unit, so a blitter that never goes idle
        ; does not hang the machine.
        MOVE.W  #$8240,DMACON       ; master and blitter DMA on
        CLR.W   BLTCON1
        MOVE.W  #$0100,BLTCON0      ; D only, every minterm clear
        CLR.W   BLTAMOD
        CLR.W   BLTBMOD
        CLR.W   BLTCMOD
        CLR.W   BLTDMOD
        MOVE.L  #$00007000,BLTDPTH  ; scratch, nothing of ours is here yet
        MOVE.W  #$0041,BLTSIZE      ; one row of one word
        MOVE.L  #$00040000,D0
.ahi_blt:
        BTST    #6,(DMACONR).L      ; BBUSY, bit 14 of the word
        BEQ.S   .ahi_blt_done
        SUBQ.L  #1,D0
        BNE.S   .ahi_blt
.ahi_blt_done:

        ; These registers take bit 15 as set-or-clear, so a value with it
        ; clear clears every bit named.  The chipset goes quiet.
        MOVE.W  #$7FFF,INTENA
        MOVE.W  #$7FFF,INTREQ
        MOVE.W  #$03FF,DMACON
        MOVE.W  #$7FFF,ADKCON
        MOVE.W  #$FF00,POTGO        ; drive pot pins weak-high so a mouse button
                                    ; reads low when pressed, high when released
        CLR.L   COP1LCH             ; stop the copper

        ; Clear OVL: PRA bit 0 = 0 (chip RAM at $0), bit 1 = 1 (LED off)
        MOVE.B  #$03,CIAA_DDRA
        MOVE.B  #$02,CIAA_PRA

        MOVE.W  #COL_GREEN,COLOR00  ; GREEN

        ; exc_halt into every exception vector, $8-$3FF
        LEA.L   exc_halt,A0
        MOVEA.L #$00000008,A1
        MOVE.W  #(256-2)-1,D0
.iv_loop:
        MOVE.L  A0,(A1)+
        DBF     D0,.iv_loop

        BSR     tod_start           ; the one clock that runs on its own

        MOVE.W  #COL_BLUE,COLOR00   ; BLUE — a500_hw_init done
        RTS

; ---------------------------------------------------------------------------
; exc_halt — every exception lands here.  Purple screen, and stop.
; ---------------------------------------------------------------------------
exc_halt:
        MOVE.W  #COL_PURPLE,COLOR00
.eh_spin:
        STOP    #$2700
        BRA.S   .eh_spin

; ---------------------------------------------------------------------------
; kbd_init — configure CIA-A SP for keyboard input
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
kbd_init:
        MOVEM.L D0,-(SP)
        MOVE.B  CIAA_CRA,D0
        ANDI.B  #$BF,D0             ; SPMODE = 0 = SP input
        MOVE.B  D0,CIAA_CRA
        MOVE.B  CIAA_ICR,D0         ; read-to-clear pending ICR events
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; screen_init — copy the copper template to chip RAM, point the four bitplane
; pointers into the interleaved bitmap, set the display height from the Agnus
; fitted, and enable DMA.
;
; copper_template, font_data and screen_clear are forward references, all
; within BSR.W range for our image size.
; Clobbers (saved/restored): D0-D2/A0-A2
; ---------------------------------------------------------------------------
screen_init:
        MOVEM.L D0-D2/A0-A2,-(SP)

        LEA.L   copper_template,A0
        LEA.L   COPPER_BASE,A1
        MOVE.W  #(copper_template_end-copper_template)/2-1,D0
.si_copy:
        MOVE.W  (A0)+,(A1)+
        DBF     D0,.si_copy

        ; Each plane starts at its own 40 bytes within the bitmap's first pixel
        ; row, and BPL1MOD/BPL2MOD in the template skip the other three.
        LEA.L   COPPER_BASE+COP_OFF_BPL1PTH,A1
        MOVE.L  #BITPLANE_BASE,D1
        MOVEQ   #SCREEN_PLANES-1,D0
.si_ptr:
        MOVE.L  D1,D2
        SWAP    D2
        MOVE.W  D2,(A1)             ; BPLnPTH data word
        MOVE.W  D1,4(A1)            ; BPLnPTL data word
        ADDA.W  #8,A1
        ADD.L   #SCREEN_BPL_W,D1
        DBF     D0,.si_ptr

        ; The template holds the NTSC stop, so only a PAL Agnus needs writing.
        ; Which one is fitted is kept, because the chime's sample period and
        ; the ball's bottom limit both follow from it.
        MOVE.W  (VPOSR).L,D0
        ANDI.W  #VPOSR_PAL,D0
        BEQ.S   .si_ntsc
        MOVE.W  #DIW_STOP_PAL,(COPPER_BASE+COP_OFF_DIWSTOP).W
        MOVE.B  #1,VAR_IS_PAL
        BRA.S   .si_height
.si_ntsc:
        CLR.B   VAR_IS_PAL
.si_height:

        MOVE.L  #COPPER_BASE,COP1LCH
        TST.W   COPJMP1

        BSR     screen_clear

        ; MASTER + COPEN + BPLEN + BLTEN.  Audio DMA goes on only while the
        ; chime is playing.
        MOVE.W  #$83C0,DMACON

        MOVEM.L (SP)+,D0-D2/A0-A2
        RTS