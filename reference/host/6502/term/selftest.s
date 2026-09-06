; selftest.s — the keys the self-typing build presses
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; A ROM cannot be typed at by a test harness, so this build types for itself
; and the far end is read to see what arrived.  The keys are the only thing
; made up: every byte after them takes the path an operator's would.
;
; The fourth line is longer than any of these screens will hold, so what comes
; out of the pipe says where each machine capped it.  The numbered lines after
; it are more than any of these text areas holds, so the screen at the end says
; whether it scrolled.

    .include "term_defs.s"

FILL_LINES  = 24

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

; The script outgrows a single index, so it is walked through a pointer.  Two
; of the shared code's zero page bytes are free: display.s uses ZP_APP4 and
; ZP_APP5 and nothing else in the terminal touches the block.
at_lo   = ZP_APP7
at_hi   = ZP_APP8

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; selftest_start — back to the first key.  Called where a keyboard would be
; initialised.  Clobbers A.
; ---------------------------------------------------------------------------

.export selftest_start
selftest_start:
    lda #<script
    sta at_lo
    lda #>script
    sta at_hi
    rts

; ---------------------------------------------------------------------------
; selftest_key — the next key in the script, and KEY_NONE_CODE once it has run
; out.  Clobbers A, Y.
; ---------------------------------------------------------------------------

.export selftest_key
selftest_key:
    ldy #0
    lda (at_lo), y
    beq @end                    ; the terminator, and every call after it
    inc at_lo
    bne @end
    inc at_hi
@end:
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

script:
    .byte "RBCP TERMINAL TEST", KEY_RET_CODE
    .byte "ONE ROM USB LOGGING", KEY_RET_CODE
    .byte "DELETE TEST XX", KEY_DEL_CODE, KEY_DEL_CODE, "OK", KEY_RET_CODE
    .byte "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHI", KEY_RET_CODE
    .repeat FILL_LINES, i
        .byte "LINE ", '0' + ((i + 5) / 10), '0' + ((i + 5) .mod 10)
        .byte KEY_RET_CODE
    .endrepeat
    .byte KEY_NONE_CODE
