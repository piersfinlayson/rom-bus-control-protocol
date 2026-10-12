; vic20_tv.s — PAL or NTSC, from the VIC-I fitted
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Every VIC-20 image here runs on either TV standard and calls vic20_tv_init
; from its BOOT segment, before anything is copied to RAM.

VIC_H_CENTER        = $9000
VIC_V_CENTER        = $9001
VIC_RASTER          = $9004

VIC_H_CENTER_PAL    = $0C
VIC_V_CENTER_PAL    = $26
VIC_H_CENTER_NTSC   = $05
VIC_V_CENTER_NTSC   = $19

; A 6561 (PAL) draws 312 lines and a 6560 (NTSC) 261.  VIC_RASTER holds the
; line number halved, so only a 6561 reaches this value.
VIC_RASTER_PAL_MIN  = $90

; Passes of 256 raster reads at 13 cycles each.  Eight outlast a PAL frame of
; 22,152 cycles.
TV_DETECT_PASSES    = 8

.segment "BOOT"

; ---------------------------------------------------------------------------
; vic20_tv_init
; Detects the TV standard from the VIC-I fitted and centres the screen for it.
; Takes up to 26 ms.
; Returns: carry set for PAL, clear for NTSC.
; Clobbers: A, X, Y
; ---------------------------------------------------------------------------

.export vic20_tv_init
vic20_tv_init:
    ldy #TV_DETECT_PASSES
    ldx #0
@detect:
    lda VIC_RASTER
    cmp #VIC_RASTER_PAL_MIN
    bcs @pal
    dex
    bne @detect
    dey
    bne @detect
    lda #VIC_H_CENTER_NTSC
    sta VIC_H_CENTER
    lda #VIC_V_CENTER_NTSC
    sta VIC_V_CENTER
    clc
    rts
@pal:
    lda #VIC_H_CENTER_PAL
    sta VIC_H_CENTER
    lda #VIC_V_CENTER_PAL
    sta VIC_V_CENTER
    rts                         ; carry still set by the compare
