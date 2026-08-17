; timing.s — the one-second window, and the counters it closes over
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The window is exactly one second, so the byte count in it is the rate.  There
; is no division and no multiply anywhere in this file.
;
; That falls out of an arithmetic fact.  The PAL clock is 985248 Hz and
; 985248 = 32 * 30789, so a Timer A period of 30789 cycles underflowing 32
; times is one second to the cycle.  NTSC is 1022727 Hz, which is not an integer
; multiple of anything useful — the real figure is 14318181/14 — so 32 periods
; of 31960 gives 1022720 cycles, 6.8 parts per million short of a second.  At
; the rates being measured that is well under a single byte.
;
; A CIA reloads from its latch and counts down through zero, so the latch value
; written is the period minus one.
;
; Timer B counts Timer A underflows.  A window has closed when Timer B has
; stepped 32 times, which is one read of its low byte: the byte alone only
; becomes ambiguous after 256 underflows, and the check runs once per line.
;
; CIA2 rather than CIA1, which carries the keyboard matrix and the kernal's own
; timer, and is left as found.  The interrupt mask at $DD0D is not touched, so
; neither timer can raise an NMI.

    .include "pipe_defs.s"

WINDOW_UNDERFLOWS = 32
PAL_TA_LATCH      = 30789 - 1
NTSC_TA_LATCH     = 31960 - 1

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

; The counter block.  The run path writes these, display.s reads them, and
; nothing reads them for control.
.export bytes_win, bytes_total, lines_total
.export refusals, errors
.export rate_now, rate_best, rate_mean, secs
.export video_pal

bytes_win:      .res 3      ; bytes sent in the window now open
bytes_total:    .res 4
lines_total:    .res 4
refusals:       .res 2
errors:         .res 2
rate_now:       .res 3      ; bytes in the last closed window, so bytes/sec
rate_best:      .res 3
secs:           .res 2      ; windows closed since the run started
rate_mean:      .res 3      ; total bytes over elapsed seconds, at run end

video_pal:      .res 1      ; non-zero PAL, from the kernal's own flag

.export armed_flag
armed_flag:     .res 1      ; non-zero once the session is open and checked

saved_cia2:     .res 6      ; TA lo/hi, TB lo/hi, CRA, CRB
win_tb_lo:      .res 1      ; Timer B low byte when the window opened

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; timing_start — takes CIA2 and programs it.  Clobbers A.
; ---------------------------------------------------------------------------

.export timing_start
timing_start:
    lda CIA2_TA_LO
    sta saved_cia2 + 0
    lda CIA2_TA_HI
    sta saved_cia2 + 1
    lda CIA2_TB_LO
    sta saved_cia2 + 2
    lda CIA2_TB_HI
    sta saved_cia2 + 3
    lda CIA2_CRA
    sta saved_cia2 + 4
    lda CIA2_CRB
    sta saved_cia2 + 5

    lda PALNTSC                 ; the kernal set this at reset and it is right
    sta video_pal

    lda #0                      ; stop both before loading the latches
    sta CIA2_CRA
    sta CIA2_CRB

    lda video_pal
    beq @ntsc
    lda #<PAL_TA_LATCH
    sta CIA2_TA_LO
    lda #>PAL_TA_LATCH
    sta CIA2_TA_HI
    jmp @latched
@ntsc:
    lda #<NTSC_TA_LATCH
    sta CIA2_TA_LO
    lda #>NTSC_TA_LATCH
    sta CIA2_TA_HI
@latched:
    lda #$FF                    ; Timer B just counts, so it free-runs
    sta CIA2_TB_LO
    sta CIA2_TB_HI

    lda #CIA2_CRB_RUN
    sta CIA2_CRB
    lda #CIA2_CRA_RUN
    sta CIA2_CRA
    rts

; ---------------------------------------------------------------------------
; timing_stop — gives CIA2 back.  Clobbers A.
; ---------------------------------------------------------------------------

.export timing_stop
timing_stop:
    lda #0
    sta CIA2_CRA
    sta CIA2_CRB
    lda saved_cia2 + 0
    sta CIA2_TA_LO
    lda saved_cia2 + 1
    sta CIA2_TA_HI
    lda saved_cia2 + 2
    sta CIA2_TB_LO
    lda saved_cia2 + 3
    sta CIA2_TB_HI
    lda saved_cia2 + 4
    sta CIA2_CRA
    lda saved_cia2 + 5
    sta CIA2_CRB
    rts

; ---------------------------------------------------------------------------
; timing_reset_run — zeroes every counter and opens the first window.
; Clobbers A, X.
; ---------------------------------------------------------------------------

.export timing_reset_run
timing_reset_run:
    ldx #0
    lda #0
@zero:
    sta bytes_win, x
    inx
    cpx #(3 + 4 + 4 + 2 + 2 + 3 + 3 + 2 + 3)
    bne @zero
    ; fall through

; ---------------------------------------------------------------------------
; timing_open_window — marks now as the start of a window.  Clobbers A.
; ---------------------------------------------------------------------------

.export timing_open_window
timing_open_window:
    lda CIA2_TB_LO
    sta win_tb_lo
    rts

; ---------------------------------------------------------------------------
; timing_window_closed — carry set if a second has passed since the window
; opened.  Fourteen cycles, called once per line.
;
; Timer B counts down, so elapsed underflows are start minus now.
;
; Clobbers A.
; ---------------------------------------------------------------------------

.export timing_window_closed
timing_window_closed:
    lda win_tb_lo
    sec
    sbc CIA2_TB_LO
    cmp #WINDOW_UNDERFLOWS
    rts

; ---------------------------------------------------------------------------
; timing_close_window — the window's byte count becomes the rate, because the
; window is a second.  Folds it into the totals and opens the next one.
; Clobbers A, X.
; ---------------------------------------------------------------------------

.export timing_close_window
timing_close_window:
    lda bytes_win + 0
    sta rate_now + 0
    lda bytes_win + 1
    sta rate_now + 1
    lda bytes_win + 2
    sta rate_now + 2

    ; best so far, compared from the top down
    lda rate_now + 2
    cmp rate_best + 2
    bcc @not_best
    bne @is_best
    lda rate_now + 1
    cmp rate_best + 1
    bcc @not_best
    bne @is_best
    lda rate_now + 0
    cmp rate_best + 0
    bcc @not_best
@is_best:
    lda rate_now + 0
    sta rate_best + 0
    lda rate_now + 1
    sta rate_best + 1
    lda rate_now + 2
    sta rate_best + 2
@not_best:

    lda #0
    sta bytes_win + 0
    sta bytes_win + 1
    sta bytes_win + 2

    inc secs
    bne @opened
    inc secs + 1
@opened:
    jmp timing_open_window

; ---------------------------------------------------------------------------
; timing_add_line — one 64-byte line has gone out.  Fifteen cycles of counter
; work per 64 bytes, which is where the design's overhead budget is spent.
; Clobbers A.
; ---------------------------------------------------------------------------

.export timing_add_line
timing_add_line:
    lda bytes_win + 0
    clc
    adc #64
    sta bytes_win + 0
    bcc @win_done
    inc bytes_win + 1
    bne @win_done
    inc bytes_win + 2
@win_done:

    lda bytes_total + 0
    clc
    adc #64
    sta bytes_total + 0
    bcc @total_done
    inc bytes_total + 1
    bne @total_done
    inc bytes_total + 2
    bne @total_done
    inc bytes_total + 3
@total_done:

    inc lines_total + 0
    bne @lines_done
    inc lines_total + 1
    bne @lines_done
    inc lines_total + 2
    bne @lines_done
    inc lines_total + 3
@lines_done:
    rts

; ---------------------------------------------------------------------------
; timing_mean — total bytes over elapsed seconds, into rate_mean.  The only
; division in the program, and it runs once, when a run stops.
;
; Shift and subtract: the dividend shifts left out of the top and the quotient
; bit shifts in at the bottom, so the two share one 32-bit word.
;
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export timing_mean
timing_mean:
    lda secs
    ora secs + 1
    bne @divide
    lda #0                      ; a run shorter than a window has no mean
    sta rate_mean + 0
    sta rate_mean + 1
    sta rate_mean + 2
    rts

@divide:
    lda bytes_total + 0
    sta ZP_APP0
    lda bytes_total + 1
    sta ZP_APP1
    lda bytes_total + 2
    sta ZP_APP2
    lda bytes_total + 3
    sta ZP_APP3
    lda #0
    sta ZP_APP4                 ; remainder lo
    sta ZP_APP5                 ; remainder hi
    ldx #32
@loop:
    asl ZP_APP0
    rol ZP_APP1
    rol ZP_APP2
    rol ZP_APP3
    rol ZP_APP4
    rol ZP_APP5

    sec
    lda ZP_APP4
    sbc secs + 0
    tay
    lda ZP_APP5
    sbc secs + 1
    bcc @next
    sty ZP_APP4
    sta ZP_APP5
    inc ZP_APP0                 ; the bit the shift vacated
@next:
    dex
    bne @loop

    lda ZP_APP0
    sta rate_mean + 0
    lda ZP_APP1
    sta rate_mean + 1
    lda ZP_APP2
    sta rate_mean + 2
    rts
