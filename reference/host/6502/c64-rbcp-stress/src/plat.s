; plat.s — the C64 side of the reliability meter
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Reset entry, the copy into RAM, the screen, the key, and blanking the VIC.
;
; Everything after boot_entry runs from RAM.  It has to, because the device is serving
; one of the machine's ROM sockets, and a host that fetches instructions out of
; the image it is talking to is reading it, which the protocol does not allow
; between the knock and the exit.  So the whole of CODE and RODATA is copied
; down before the first knock and nothing touches the socket again except the
; command page reads and the back channel.

    .include "stress_defs.s"

.import c64_hw_init
.import c64_clear_screen
.import row_off_lo
.import row_scr_hi
.import row_col_hi

.import stress_run

; Linker-generated symbols for the segments that run from RAM.
.import __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
.import __RODATA_SIZE__

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

    jsr c64_hw_init             ; also in BOOT, so safe to call from ROM

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

; ===========================================================================
; CODE segment — runs from RAM
; ===========================================================================

.code

; ---------------------------------------------------------------------------
; plat_init — the display the meter draws on.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export plat_init
plat_init:
    lda #COL_BLACK
    sta VIC_BORDER
    sta VIC_BACKGROUND
    lda #VIC_CTRL1_VAL
    sta VIC_CTRL1               ; display on, which is where a run starts
    rts

; ---------------------------------------------------------------------------
; plat_cls — a blank screen in the meter's own colour.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export plat_cls
plat_cls:
    ldy #COL_WHITE
    jmp c64_clear_screen

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
; in, because the caller is walking a row with it.  Clobbers A, X.
;
; The title bar is reverse video, which on a C64 is the screen code with bit 7
; set.  Every other role is a colour and nothing more.
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
    cpx #COLR_TITLE             ; the title bar and the headline band, and
    bcc @write                  ; nothing else, are reverse video
    ora #$80
@write:
    sta (ZP_SCR_LO), y
    lda colr_map, x
    sta (ZP_COL_LO), y
    rts

; ---------------------------------------------------------------------------
; plat_key — the one key this machine has.  KEY_VARY once per press, because
; it waits for the release before it says so.
; Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_key
plat_key:
    lda #KEY_S_COL
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_S_ROW_BIT
    bne @none
    ldx #DEBOUNCE_COUNT
@settle:
    dex
    bne @settle
@held:
    lda #KEY_S_COL
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_S_ROW_BIT
    beq @held
    lda #KEY_VARY
    rts
@none:
    lda #KEY_NONE_CODE
    rts

; ---------------------------------------------------------------------------
; plat_vary_set — A non-zero puts the display back on, zero stops it.
;
; Stopping the display stops every badline and every other cycle the VIC takes
; off the processor.  Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_vary_set
plat_vary_set:
    tax
    lda VIC_CTRL1
    and #<(~VIC_CTRL1_DEN)
    cpx #0
    beq @put
    ora #VIC_CTRL1_DEN
@put:
    sta VIC_CTRL1
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; A colour for each of the meter's roles, in the order stress_defs.s lists
; them: plain, dim, head, big, ok, bad, warn, title, band.
colr_map:
    .byte COL_WHITE, COL_LIGHT_GREY, COL_MED_GREY, COL_LIGHT_GREEN
    .byte COL_WHITE, COL_LIGHT_RED, COL_YELLOW, COL_BLUE
    .byte COL_LIGHT_GREEN

.export plat_vary_word
plat_vary_word: .byte "SCREEN", 0

.export plat_key_word
plat_key_word:  .byte "S", 0
