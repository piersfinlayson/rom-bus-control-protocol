; ratio.s — the arithmetic behind the headline
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The number a stranger reads off the screen is commands sent divided by
; commands the device got wrong, and it has to be shown in decimal, because
; nobody sends back a hexadecimal reliability figure.  Neither the division
; nor the conversion exists on a 6502, so both are here.
;
; Ten digits, because commands sent is a 32-bit count and 4294967295 has ten
; of them.  Everything is worked out once per screen refresh and not once per
; command.

    .include "stress_defs.s"

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export num_val
.export num_den
.export num_txt
.export num_first

num_val:    .res 4          ; the value, little endian.  Both routines eat it.
num_den:    .res 4          ; what num_div divides by
num_txt:    .res 10         ; what num_dec wrote, right aligned, space padded
num_first:  .res 1          ; the first digit in it, so a caller can left align

num_rem:    .res 4
num_sub:    .res 4
num_top:    .res 1
num_tmp:    .res 1
num_bits:   .res 1
num_digit:  .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; num_div — num_val = num_val / num_den, shift and subtract, 32 bits by 32.
;
; Both counts the meter divides are four bytes, so the divisor is four bytes
; as well.  The partial remainder is always smaller than the divisor, but
; doubling it and taking in the next bit can need one bit more than the
; divisor's thirty-two.  That bit falls out of the shift into num_top and the
; subtraction is done across all five bytes, which is what keeps a divisor
; over 65535 from giving a wrong answer.
;
; The caller must not ask for a division by zero.  A ratio taken from no
; failures is not a measurement, and the display says so rather than dividing.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export num_div
num_div:
    lda #0
    sta num_rem + 0
    sta num_rem + 1
    sta num_rem + 2
    sta num_rem + 3
    ldx #32
@bit:
    asl num_val + 0
    rol num_val + 1
    rol num_val + 2
    rol num_val + 3
    rol num_rem + 0
    rol num_rem + 1
    rol num_rem + 2
    rol num_rem + 3
    lda #0
    rol a                       ; the bit that came off the top of it
    sta num_top

    sec
    lda num_rem + 0
    sbc num_den + 0
    sta num_sub + 0
    lda num_rem + 1
    sbc num_den + 1
    sta num_sub + 1
    lda num_rem + 2
    sbc num_den + 2
    sta num_sub + 2
    lda num_rem + 3
    sbc num_den + 3
    sta num_sub + 3
    lda num_top
    sbc #0
    bcc @next                   ; it did not go
    lda num_sub + 0
    sta num_rem + 0
    lda num_sub + 1
    sta num_rem + 1
    lda num_sub + 2
    sta num_rem + 2
    lda num_sub + 3
    sta num_rem + 3
    inc num_val + 0             ; the bit just shifted in was a zero
@next:
    dex
    bne @bit
    rts

; ---------------------------------------------------------------------------
; num_dec — num_val to ten ASCII digits in num_txt, leading zeros blanked and
; num_first left pointing at the first of them.  num_val is left as rubbish,
; and so are all three registers.
;
; Repeated subtraction of a power of ten, at most nine goes a digit, rather
; than ten divisions.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export num_dec
num_dec:
    ldx #0                      ; which power of ten
@digit:
    lda #'0'
    sta num_digit
@sub:
    sec
    lda num_val + 0
    sbc pow_b0, x
    sta num_bits                ; the low byte of the difference, held back
    lda num_val + 1
    sbc pow_b1, x
    tay
    lda num_val + 2
    sbc pow_b2, x
    sta num_tmp
    lda num_val + 3
    sbc pow_b3, x
    bcc @done                   ; it did not go, so the digit is what it is
    sta num_val + 3
    lda num_tmp
    sta num_val + 2
    sty num_val + 1
    lda num_bits
    sta num_val + 0
    inc num_digit
    bne @sub                    ; always taken
@done:
    lda num_digit
    sta num_txt, x
    inx
    cpx #10
    bne @digit

    ; Leading zeros are spaces, but the last digit is a digit even when the
    ; whole number is zero.
    ldx #0
@blank:
    lda num_txt, x
    cmp #'0'
    bne @found
    lda #' '
    sta num_txt, x
    inx
    cpx #9
    bne @blank
@found:
    stx num_first
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; The powers of ten, largest first, a table to a byte of the value.
pow_b0: .byte $00, $00, $80, $40, $A0, $10, $E8, $64, $0A, $01
pow_b1: .byte $CA, $E1, $96, $42, $86, $27, $03, $00, $00, $00
pow_b2: .byte $9A, $F5, $98, $0F, $01, $00, $00, $00, $00, $00
pow_b3: .byte $3B, $05, $00, $00, $00, $00, $00, $00, $00, $00
