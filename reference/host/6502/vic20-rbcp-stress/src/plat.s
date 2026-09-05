; plat.s — the VIC-20 side of the reliability meter
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Reset entry, the copy into RAM, the screen, and the vectors.
;
; Everything after boot_entry runs from RAM.  It has to, because the device is serving
; the kernal socket, and a host that fetches instructions out of the image it
; is talking to is reading it, which the protocol does not allow between the
; knock and the exit.  So the whole of CODE and RODATA is copied down before
; the first knock and nothing touches the socket again except the command page
; reads and the back channel.

    .include "stress_defs.s"

.import stress_run

.import __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
.import __RODATA_SIZE__

; ===========================================================================
; FILL — the command page and the back-channel region, at the bottom of the
; image, where the device writes and the meter's own bytes are not.
; ===========================================================================

.segment "FILL"
    .res $100 + CONFIG_RBCP_BCH_SIZE, $00

; ===========================================================================
; BOOT segment — runs from ROM, before the copy
; ===========================================================================

.segment "BOOT"

; ---------------------------------------------------------------------------
; boot_entry — the RESET vector's target.
;
; Interrupts are masked here and never unmasked.  Nothing in this program has
; anything to do in an interrupt, and an interrupt landing in the middle of a
; command frame would stretch it in time at best.
; ---------------------------------------------------------------------------

.export boot_entry
boot_entry:
    sei
    cld
    ldx #$FF
    txs

    ; The VIC-I has no display-enable bit, so it starts scanning $1E00 the
    ; moment the registers are written.  Both regions are cleared first, so
    ; what appears is blank rather than whatever the RAM powered up holding.
    lda #$20                    ; space
    ldx #0
@scr_page:
    sta SCREEN_BASE, x
    inx
    bne @scr_page
    ldx #0
@scr_tail:
    sta SCREEN_BASE + $100, x
    inx
    cpx #250
    bne @scr_tail

    lda #COL_BLACK
    ldx #0
@col_page:
    sta COLOUR_RAM, x
    inx
    bne @col_page
    ldx #0
@col_tail:
    sta COLOUR_RAM + $100, x
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

    lda #VIA2_DDRB_VAL
    sta VIA2_DDRB
    lda #VIA2_DDRA_VAL
    sta VIA2_DDRA

    ; CODE and RODATA are laid out next to each other in the image and next to
    ; each other in RAM, so one copy moves both.
    lda #<__CODE_LOAD__
    sta ZP_PTR_LO
    lda #>__CODE_LOAD__
    sta ZP_PTR_HI
    lda #<__CODE_RUN__
    sta ZP_TMP0
    lda #>__CODE_RUN__
    sta ZP_TMP1
    lda #<(__CODE_SIZE__ + __RODATA_SIZE__)
    sta ZP_TMP2
    lda #>(__CODE_SIZE__ + __RODATA_SIZE__)
    sta ZP_TMP3

    ldy #0
@copy:
    lda (ZP_PTR_LO), y
    sta (ZP_TMP0), y
    iny
    bne @same_page
    inc ZP_PTR_HI
    inc ZP_TMP1
@same_page:
    lda ZP_TMP2
    bne @dec_lo
    dec ZP_TMP3
@dec_lo:
    dec ZP_TMP2
    lda ZP_TMP2
    ora ZP_TMP3
    bne @copy

    jmp stress_run              ; its RAM address, the linker having said so

; ---------------------------------------------------------------------------
; irq_nmi_stub — both vectors point here.  Interrupts are masked and never
; unmasked, and RESTORE cannot be masked, so this is what it reaches.
; ---------------------------------------------------------------------------

irq_nmi_stub:
    rti

; ===========================================================================
; CODE segment — runs from RAM
; ===========================================================================

.code

; ---------------------------------------------------------------------------
; Row addresses.  Twenty-three rows of twenty-two, one after another.
; ---------------------------------------------------------------------------

row_off_lo:
    .repeat SCREEN_ROWS, i
        .byte <(i * SCREEN_COLS)
    .endrepeat

row_scr_hi:
    .repeat SCREEN_ROWS, i
        .byte >(SCREEN_BASE + i * SCREEN_COLS)
    .endrepeat

row_col_hi:
    .repeat SCREEN_ROWS, i
        .byte >(COLOUR_RAM + i * SCREEN_COLS)
    .endrepeat

; ---------------------------------------------------------------------------
; plat_init — the display the meter draws on.  Everything it needs was set at
; reset, so there is nothing left to do.
; ---------------------------------------------------------------------------

.export plat_init
plat_init:
    rts

; ---------------------------------------------------------------------------
; plat_cls — a blank screen in the meter's own colour.  Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_cls
plat_cls:
    lda #$20
    ldx #0
@scr:
    sta SCREEN_BASE, x
    sta SCREEN_BASE + $100, x
    inx
    bne @scr
    lda #COL_WHITE
    ldx #0
@col:
    sta COLOUR_RAM, x
    sta COLOUR_RAM + $100, x
    inx
    bne @col
    rts

; ---------------------------------------------------------------------------
; plat_row — A = row.  Points the screen writer at it.  Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_row
plat_row:
    tax
    lda row_off_lo, x
    sta ZP_SCR_LO
    sta ZP_COL_LO
    lda row_scr_hi, x
    sta ZP_SCR_HI
    lda row_col_hi, x
    sta ZP_COL_HI
    rts

; ---------------------------------------------------------------------------
; plat_put — A = ASCII, Y = column, X = a COLR_ role.  Y comes back as it went
; in, because the caller is walking a row with it.  Clobbers A.
;
; The title bar and the headline band are reverse video, which on a VIC-20 is
; the screen code with bit 7 set.  Every other role is a colour and nothing
; more.
; ---------------------------------------------------------------------------

.export plat_put
plat_put:
    cmp #'A'
    bcc @coded
    cmp #'Z' + 1
    bcs @lower
    sec
    sbc #$40
    bcs @coded                  ; always taken
@lower:
    cmp #'a'
    bcc @coded
    cmp #'z' + 1
    bcs @coded
    sec
    sbc #$60
@coded:
    cpx #COLR_TITLE
    bcc @write
    ora #$80
@write:
    sta (ZP_SCR_LO), y
    lda colr_map, x
    sta (ZP_COL_LO), y
    rts

; ---------------------------------------------------------------------------
; plat_key — nothing on this machine does anything, so nothing is read.
; ---------------------------------------------------------------------------

.export plat_key
plat_key:
    lda #KEY_NONE_CODE
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; A colour for each of the meter's roles, in the order stress_defs.s lists
; them: plain, dim, head, big, ok, bad, warn, title, band.  A VIC-20's colour
; RAM holds four bits, so only the first eight colours are reachable.
colr_map:
    .byte COL_WHITE, COL_GREEN, COL_YELLOW, COL_GREEN
    .byte COL_WHITE, COL_YELLOW, COL_YELLOW, COL_CYAN
    .byte COL_GREEN

; ===========================================================================
; The 6502 vectors, read at reset and never again
; ===========================================================================

.segment "VECTORS"
    .word irq_nmi_stub          ; $FFFA-$FFFB  NMI
    .word boot_entry            ; $FFFC-$FFFD  RESET
    .word irq_nmi_stub          ; $FFFE-$FFFF  IRQ/BRK
