; vic20_3k.s — stops with a message when the 3K expansion is missing
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Every VIC-20 image here that runs from $0400 calls vic20_3k_check from its
; BOOT segment, after the screen is set up and before anything is copied to
; RAM.

RAM_3K_BASE         = $0400
RAM_3K_BLOCKS       = 3         ; 1KB each, $0400-$0FFF

; The middle row of the 22 by 23 screen at $1E00.
MSG_3K_SCREEN       = $1E00 + 11 * 22
MSG_3K_COLOUR       = $9600 + 11 * 22
MSG_3K_COL_WHITE    = 1

.define MSG_3K_TEXT "3K EXPANSION NOT FOUND"

.segment "BOOT"

; ---------------------------------------------------------------------------
; vic20_3k_check
; Returns if every 1KB block of the 3K expansion holds RAM.  Otherwise prints
; MSG_3K_TEXT and stops.
;
; Each byte tested keeps its value.  With no RAM there a read returns whatever
; was last on the bus, which doesn't match both the byte and its inverse.
; Clobbers: A
; ---------------------------------------------------------------------------

.export vic20_3k_check
vic20_3k_check:
.repeat RAM_3K_BLOCKS, i
    lda RAM_3K_BASE + i * $400
    eor #$FF
    sta RAM_3K_BASE + i * $400
    cmp RAM_3K_BASE + i * $400
    bne @missing
    eor #$FF
    sta RAM_3K_BASE + i * $400
    cmp RAM_3K_BASE + i * $400
    bne @missing
.endrepeat
    rts

@missing:
    ldx #.strlen(MSG_3K_TEXT) - 1
@print:
    lda msg_3k, x
    sta MSG_3K_SCREEN, x
    lda #MSG_3K_COL_WHITE
    sta MSG_3K_COLOUR, x
    dex
    bpl @print
@stop:
    jmp @stop

; Screen codes, which for capitals, digits and space are ASCII with bits 6
; and 7 clear.
msg_3k:
.repeat .strlen(MSG_3K_TEXT), i
    .byte .strat(MSG_3K_TEXT, i) & $3F
.endrepeat
