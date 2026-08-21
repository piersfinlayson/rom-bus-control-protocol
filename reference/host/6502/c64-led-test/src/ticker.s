; ticker.s — how long it has been, in the units the protocol counts periods in
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The animation on screen has to run at the rate the device says its LED is
; running at, and the main loop's own rate is whatever the device's answers
; cost.  So the loop asks this how much time has passed rather than counting
; its own turns.
;
; CIA2 Timer B, free running on phi2, is a 16-bit counter nothing else here
; uses.  CIA1 is the kernal's and is left alone.  The counter counts down and
; wraps every 66ms, which is far shorter than any period and far longer than a
; turn of the loop, so the difference between two reads is the time between
; them.
;
; PAL phi2.  On an NTSC machine every tick is about 1.7% short, which nothing
; here measures and no eye can see.

    .include "led_defs.s"

TICK_CYCLES = 9852              ; 10ms of PAL phi2

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

last_lo:        .res 1
last_hi:        .res 1
acc_lo:         .res 1          ; phi2 cycles not yet worth a tick
acc_hi:         .res 1
saved_crb:      .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; ticker_start — Clobbers A.
; ---------------------------------------------------------------------------

.export ticker_start
ticker_start:
    lda CIA2_CRB
    sta saved_crb
    lda #$FF
    sta CIA2_TB_LO
    sta CIA2_TB_HI
    lda #%00010001              ; load the latch, then run continuously on phi2
    sta CIA2_CRB
    lda #0
    sta acc_lo
    sta acc_hi
    jsr read_timer
    sta last_lo
    stx last_hi
    rts

; ---------------------------------------------------------------------------
; ticker_stop — puts the timer back as it was found.  Clobbers A.
; ---------------------------------------------------------------------------

.export ticker_stop
ticker_stop:
    lda saved_crb
    sta CIA2_CRB
    rts

; ---------------------------------------------------------------------------
; ticker_poll — returns in A how many whole 10ms ticks have passed since the
; last call, saturating at 255.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export ticker_poll
ticker_poll:
    jsr read_timer
    sta ZP_APP0                 ; now, low
    stx ZP_APP1                 ; now, high

    ; The timer counts down, so elapsed = last - now.
    lda last_lo
    sec
    sbc ZP_APP0
    sta ZP_APP2
    lda last_hi
    sbc ZP_APP1
    sta ZP_APP3

    lda ZP_APP0
    sta last_lo
    lda ZP_APP1
    sta last_hi

    ; Add it to whatever was left over from last time.
    lda acc_lo
    clc
    adc ZP_APP2
    sta acc_lo
    lda acc_hi
    adc ZP_APP3
    sta acc_hi

    ldy #0
@count:
    lda acc_hi
    cmp #>TICK_CYCLES
    bcc @done
    bne @take
    lda acc_lo
    cmp #<TICK_CYCLES
    bcc @done
@take:
    lda acc_lo
    sec
    sbc #<TICK_CYCLES
    sta acc_lo
    lda acc_hi
    sbc #>TICK_CYCLES
    sta acc_hi
    iny
    bne @count
    dey                         ; 255 ticks is longer than anything here needs
@done:
    tya
    rts

; ---------------------------------------------------------------------------
; read_timer — the 16-bit counter, low in A and high in X.  Read high, low,
; high again, because it is running underneath.  Clobbers A, X.
; ---------------------------------------------------------------------------

read_timer:
    ldx CIA2_TB_HI
@retry:
    lda CIA2_TB_LO
    cpx CIA2_TB_HI
    beq @done
    ldx CIA2_TB_HI
    jmp @retry
@done:
    rts
