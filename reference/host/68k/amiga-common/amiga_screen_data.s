; amiga_screen_data.s — the copper list template and the font
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; ROM data section.  Reached from RAM code by absolute long address.

; ---------------------------------------------------------------------------
; Copper list template
;
; screen_init copies this to chip RAM, patches the four bitplane pointers, and
; patches DIWSTOP where the Agnus is PAL.  The three offsets below index the
; copied list, so the order here and those equates go together.
; ---------------------------------------------------------------------------
        EVEN
copper_template:
cop_bplpt:
        DC.W    COP_BPL1PTH,$0000       ; the four pointers, patched by
        DC.W    COP_BPL1PTL,$0000       ; screen_init to plane 0..3 within
        DC.W    COP_BPL1PTH+4,$0000     ; the bitmap's first pixel row
        DC.W    COP_BPL1PTL+4,$0000
        DC.W    COP_BPL1PTH+8,$0000
        DC.W    COP_BPL1PTL+8,$0000
        DC.W    COP_BPL1PTH+12,$0000
        DC.W    COP_BPL1PTL+12,$0000
        DC.W    COP_BPLCON0,BPLCON0_4PL
        DC.W    COP_BPLCON1,$0000
        DC.W    COP_BPLCON2,$0024
        DC.W    COP_BPL1MOD,SCREEN_BPL_MOD
        DC.W    COP_BPL2MOD,SCREEN_BPL_MOD
        DC.W    COP_DDFSTRT,DDF_START
        DC.W    COP_DDFSTOP,DDF_STOP
        DC.W    COP_DIWSTRT,DIW_START
cop_diwstop:
        DC.W    COP_DIWSTOP,DIW_STOP_NTSC   ; PAL height patched in
cop_colours:
        DC.W    COP_COLOR00+0,PEN00_RGB
        DC.W    COP_COLOR00+2,PEN01_RGB
        DC.W    COP_COLOR00+4,PEN02_RGB
        DC.W    COP_COLOR00+6,PEN03_RGB
        DC.W    COP_COLOR00+8,PEN04_RGB
        DC.W    COP_COLOR00+10,PEN05_RGB
        DC.W    COP_COLOR00+12,PEN06_RGB
        DC.W    COP_COLOR00+14,PEN07_RGB
        DC.W    COP_COLOR00+16,PEN08_RGB
        DC.W    COP_COLOR00+18,PEN09_RGB
        DC.W    COP_COLOR00+20,PEN10_RGB
        DC.W    COP_COLOR00+22,PEN11_RGB
        DC.W    COP_COLOR00+24,PEN12_RGB
        DC.W    COP_COLOR00+26,PEN13_RGB
        DC.W    COP_COLOR00+28,PEN14_RGB
        DC.W    COP_COLOR00+30,PEN15_RGB
        DC.W    $FFFF,$FFFE             ; END
copper_template_end:

; Byte offsets into the copied list of the data words the code writes.
COP_OFF_BPL1PTH     EQU cop_bplpt-copper_template+2
COP_OFF_DIWSTOP     EQU cop_diwstop-copper_template+2
COP_OFF_COLOR00     EQU cop_colours-copper_template+2

; font_8x8.bin: 256 glyphs * 8 bytes = 2048 bytes, no header.
; One byte per scan line, MSB = leftmost pixel.
        EVEN
font_data:
        INCBIN  "font_8x8.bin"
font_data_end:
