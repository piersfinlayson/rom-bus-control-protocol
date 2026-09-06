; timing.s — the one-second window, and the counters it closes over
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The window is exactly one second, so the byte count in it is the rate.  There
; is no division and no multiply anywhere in this file.
;
; A window has closed when the machine's clock has stepped PLAT_TICK_HZ times.
; What the clock is, and how a tick is made to be exactly a
; PLAT_TICK_HZ-th of a second, is the machine's business — see its plat_defs.s.
; One byte of it is read, which stays unambiguous as long as no more than 255
; ticks pass between two reads, and this check runs once a line.

    .include "pipe_defs.s"

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

; The counter block.  The run path writes these, display.s reads them, and
; nothing reads them for control.
.export bytes_win, bytes_total, lines_total
.export refusals, errors
.export rate_now, rate_best, rate_mean, secs

bytes_win:      .res 3      ; bytes sent in the window now open
bytes_total:    .res 4
lines_total:    .res 4
refusals:       .res 2
errors:         .res 2
rate_now:       .res 3      ; bytes in the last closed window, so bytes/sec
rate_best:      .res 3
secs:           .res 2      ; windows closed since the run started
rate_mean:      .res 3      ; total bytes over elapsed seconds, at run end

win_tick:       .res 1      ; the clock when the window opened

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

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
    PLAT_CLOCK_READ
    sta win_tick
    rts

; ---------------------------------------------------------------------------
; timing_window_closed — carry set if a second has passed since the window
; opened.  Six instructions, called once per line.
; Clobbers A.
; ---------------------------------------------------------------------------

.export timing_window_closed
timing_window_closed:
    PLAT_CLOCK_ELAPSED win_tick
    cmp #PLAT_TICK_HZ
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
    jsr timing_mean             ; the window that just closed counts toward it
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
; division in the tester, and it runs once, when a run stops.
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
