; amiga_hw.s — A500 ROM-section hardware routines
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; ROM-only routines executed before the RAM section is copied.
; All custom chip registers are accessed via absolute long addressing
; (e.g. MOVE.W #$7FFF,INTENA) rather than indexed from A0, because the
; register equates are absolute 24-bit addresses that exceed the 16-bit
; signed displacement range of d(An) addressing.

; ---------------------------------------------------------------------------
; a500_hw_init — one-time hardware setup at cold start
; Clobbers: D0/A0/A1 (startup — no meaningful register state yet)
; ---------------------------------------------------------------------------
a500_hw_init:
        ORI.W   #$2700,SR
        MOVE.W  #COL_WHITE,COLOR00  ; WHITE — CPU is alive, a500_hw_init entered

        ; Silence custom chips via absolute register addresses
        MOVE.W  #$7FFF,INTENA       ; disable all interrupt enables
        MOVE.W  #$7FFF,INTREQ       ; acknowledge all pending requests
        MOVE.W  #$03FF,DMACON       ; disable all DMA channels
        MOVE.W  #$7FFF,ADKCON       ; clear audio/disk control
        CLR.L   COP1LCH             ; stop the copper

        ; Clear OVL: CIA-A PRA bit 0 = 0 (chip RAM at $0); bit 1 = 1 (LED off)
        MOVE.B  #$03,CIAA_DDRA
        MOVE.B  #$02,CIAA_PRA

        MOVE.W  #COL_GREEN,COLOR00  ; GREEN — stack is set up

        ; Install exc_halt in all exception vectors $8-$3FF (vectors 2-255)
        LEA.L   exc_halt,A0
        MOVEA.L #$00000008,A1
        MOVE.W  #(256-2)-1,D0
.iv_loop:
        MOVE.L  A0,(A1)+
        DBF     D0,.iv_loop

        MOVE.W  #COL_BLUE,COLOR00   ; BLUE — a500_hw_init done
        RTS

; ---------------------------------------------------------------------------
; exc_halt — minimal exception handler: red border, halt CPU
; ---------------------------------------------------------------------------
exc_halt:
        MOVE.W  #COL_PURPLE,COLOR00      ; Purple
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
; screen_init — copy copper template to chip RAM, patch BPL1PT, enable DMA
; copper_template, font_data, and screen_clear are forward references
; resolved in the second pass; all are within BSR.W range for our image size.
; Clobbers (saved/restored): D0/A0-A2
; ---------------------------------------------------------------------------
screen_init:
        MOVEM.L D0/A0-A2,-(SP)

        ; Copy copper template from ROM to chip RAM
        LEA.L   copper_template,A0
        LEA.L   COPPER_BASE,A1
        MOVE.W  #(copper_template_end-copper_template)/2-1,D0
.si_copy:
        MOVE.W  (A0)+,(A1)+
        DBF     D0,.si_copy

        ; Patch BPL1PTH and BPL1PTL in the chip RAM copper list
        MOVE.L  #BITPLANE_BASE,D0
        LEA.L   COPPER_BASE,A1
        SWAP    D0
        MOVE.W  D0,2(A1)            ; BPL1PTH data word
        SWAP    D0
        MOVE.W  D0,6(A1)            ; BPL1PTL data word

        ; Point Agnus at copper list and strobe
        MOVE.L  #COPPER_BASE,COP1LCH
        TST.W   COPJMP1

        ; Clear bitplane (forward BSR to screen_clear in RAM section)
        BSR     screen_clear

        ; Enable DMA: MASTER + COPEN + BPLEN
        MOVE.W  #$8380,DMACON

        MOVEM.L (SP)+,D0/A0-A2
        RTS