; plat.s — the VIC-20 side of the pipe throughput test
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Entry, the copy into RAM, the screen, the keys and the clock.
;
; Everything after boot_entry runs from RAM.  It has to, because the device is
; serving one of the machine's ROM sockets and the command page is a page of
; that socket, so a host fetching its instructions out of the image would be
; sending command bytes with every pass through a routine that happened to land
; there.  The whole of CODE and RODATA is copied down before the first knock,
; and after that nothing touches the socket except the command page reads the
; protocol makes and the back channel it writes.

    .include "pipe_defs.s"

.import pipe_run

; Linker-generated symbols for the segments that run from RAM.
.import __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
.import __RODATA_SIZE__

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export plat_abort_flag
plat_abort_flag: .res 1         ; nothing here raises it, so RETURN stops a run

; ===========================================================================
; FILL segment — the command page, then the back channel
; ===========================================================================

; The machine's own kernal runs at reset and enters BASIC through the word at
; $C000, which is where this image is entered.  The command page is the page
; above, because the kernal reads $C000 itself and reads $C002 when RESTORE
; arrives with RUN/STOP held, and a command page under either would take those
; reads as command bytes.

.segment "FILL"

    .res 256, $00               ; $E000  the command page
    .res CONFIG_RBCP_BCH_SIZE, $00  ; $E100  the back channel

; ===========================================================================
; BOOT segment — runs from ROM, before the copy
; ===========================================================================

.segment "BOOT"

; ---------------------------------------------------------------------------
; boot_entry — the RESET vector's target.
;
; Interrupts are masked here and never unmasked.  Nothing in this tester has
; anything to do in an interrupt, and one landing in the middle of a command
; frame would stretch it in time at best.
;
; RESTORE is not maskable, and it reaches the processor through VIA1, so both
; VIAs have every interrupt enable cleared.  With those clear it raises nothing,
; and the kernal's own handler, which would run kernal code in the middle of a
; command frame, is never entered.
; ---------------------------------------------------------------------------

.export boot_entry
boot_entry:
    sei
    cld
    ldx #$FF
    txs

    lda #VIA_IER_NONE
    sta VIA1_IER
    sta VIA2_IER

    lda #0
    sta plat_abort_flag

    ; The VIC-I has no display-enable bit, so it scans whatever the registers
    ; below point it at from the moment they are written.  Both regions are
    ; cleared first, so what appears is blank rather than what the kernal left.
    lda #$20                    ; space
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

    jmp pipe_run                ; its RAM address, the linker having said so

; Both VIAs have every interrupt enable cleared above, so neither vector is
; reached.  They hold an rti because a vector has to point somewhere.
irq_nmi_stub:
    rti

.segment "VECTORS"

    .word irq_nmi_stub          ; $FFFA-$FFFB  NMI
    .word boot_entry            ; $FFFC-$FFFD  RESET
    .word irq_nmi_stub          ; $FFFE-$FFFF  IRQ/BRK

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

; ---------------------------------------------------------------------------
; plat_init — the display the tester draws on.  Everything it needs was set at
; entry, so there is nothing left to do.
; ---------------------------------------------------------------------------

.export plat_init
plat_init:
    rts

; ---------------------------------------------------------------------------
; plat_cls — a blank screen in the tester's own colour.  Clobbers A, X.
;
; Colour RAM is written here and never again, every character on this screen
; being the same colour, so plat_put has a screen pointer to keep up to date
; and nothing else.
; ---------------------------------------------------------------------------

.export plat_cls
plat_cls:
    lda #$20                    ; space
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
    lda row_scr_hi, x
    sta ZP_SCR_HI
    rts

; ---------------------------------------------------------------------------
; plat_put — A = ASCII, Y = column.  Y comes back as it went in, because the
; caller is walking a row with it.  Clobbers A.
; ---------------------------------------------------------------------------

.export plat_put
plat_put:
    cmp #'A'
    bcc @write
    cmp #'Z' + 1
    bcs @lower
    sec
    sbc #$40
    bcs @write                  ; always taken
@lower:
    cmp #'a'
    bcc @write
    cmp #'z' + 1
    bcs @write
    sec
    sbc #$60
@write:
    sta (ZP_SCR_LO), y
    rts

; ---------------------------------------------------------------------------
; plat_reverse — A = row, X = column, Y = length.  Sets bit 7 on the screen
; codes already there, which is what reverse video is.
; Clobbers A, X, Y and ZP_TMP0/1.
; ---------------------------------------------------------------------------

.export plat_reverse
plat_reverse:
    stx ZP_TMP0                 ; column
    sty ZP_TMP1                 ; length
    jsr plat_row
    ldy ZP_TMP0
    ldx ZP_TMP1
@loop:
    lda (ZP_SCR_LO), y
    ora #$80
    sta (ZP_SCR_LO), y
    iny
    dex
    bne @loop
    rts

; ---------------------------------------------------------------------------
; plat_key — a key code, or KEY_NONE_CODE if nothing is held.
;
; Four column selects cover the five keys.  A run does not call this — it
; calls plat_key_stop, which is one column.
;
; Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_key
plat_key:
    lda #KEY_COL_0
    sta VIA2_PRB
    lda VIA2_PRA
    tax
    and #KEY_1_BIT
    bne @c0_3
    lda #KEY_1_CODE
    bne @debounce               ; always taken
@c0_3:
    txa
    and #KEY_3_BIT
    bne @col_7
    lda #KEY_3_CODE
    bne @debounce               ; always taken

@col_7:
    lda #KEY_COL_7
    sta VIA2_PRB
    lda VIA2_PRA
    and #KEY_2_BIT
    bne @col_6
    lda #KEY_2_CODE
    bne @debounce               ; always taken

@col_6:
    lda #KEY_COL_6
    sta VIA2_PRB
    lda VIA2_PRA
    and #KEY_T_BIT
    bne @col_1
    lda #KEY_T_CODE
    bne @debounce               ; always taken

@col_1:
    jsr plat_key_stop
    bne @none
    lda #KEY_RET_CODE
@debounce:
    ldx #DEBOUNCE_COUNT
@dly:
    dex
    bne @dly
    rts
@none:
    lda #KEY_NONE_CODE
    rts

; ---------------------------------------------------------------------------
; plat_key_stop — one column, about 13 cycles.  Z set means RETURN is held.
; A run calls this one line in sixteen, so a stop is seen within about 24 ms.
; Clobbers A.
; ---------------------------------------------------------------------------

.export plat_key_stop
plat_key_stop:
    lda #KEY_COL_1
    sta VIA2_PRB
    lda VIA2_PRA
    and #KEY_RETURN_BIT
    rts

; ---------------------------------------------------------------------------
; plat_key_wait_none — spins until nothing is held.  Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_key_wait_none
plat_key_wait_none:
    jsr plat_key
    cmp #KEY_NONE_CODE
    bne plat_key_wait_none
    rts

; ---------------------------------------------------------------------------
; plat_clock_start — VIA1 timer 1, free-running on the latch plat_defs.s works
; out for the video standard this image is built for.
;
; VIA1 rather than VIA2, which carries the keyboard matrix and the kernal's
; jiffy timer.  VIA1's interrupt enables were cleared at entry, so a timeout
; sets the flag and raises nothing.
;
; Writing the high counter is what loads the counter from the latch, starts it
; and clears the flag, so the low latch goes first.
;
; Clobbers A.
; ---------------------------------------------------------------------------

.export plat_clock_start
plat_clock_start:
    lda #0
    sta ZP_TICK
    lda #VIA1_ACR_T1FREE
    sta VIA1_ACR
    lda #<T1_LATCH
    sta VIA1_T1LL
    lda #>T1_LATCH
    sta VIA1_T1CH
    rts

; ---------------------------------------------------------------------------
; plat_clock_poll — one timer 1 period counted, if one has elapsed.  The send
; paths call this because PLAT_SW_TICK is set.  Clobbers A.
; ---------------------------------------------------------------------------

.export plat_clock_poll
plat_clock_poll:
    PLAT_CLOCK_TICK
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

.export plat_keys_1
plat_keys_1:
    .byte "RET STARTS AND STOPS", 0

.export plat_keys_2
plat_keys_2:
    .byte "T RUNS TEN SECONDS", 0
