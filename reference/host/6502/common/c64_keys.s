; c64_keys.s — scanning the keyboard matrix from a table the application owns
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The kernal's own scan is unavailable: these programs run with interrupts
; masked, so nothing fills the keyboard buffer.  $DC00 drives a column low and
; $DC01 reads rows low, a clear bit meaning the key is down.  The kernal has
; already set CIA1 DDRA to output and DDRB to input, so neither is touched.
;
; The application supplies app_key_table, four bytes an entry:
;
;   .byte column_mask, row_bit, code, shift_code
;
; and ends it with a column mask of zero, which is never a valid one — a valid
; mask has exactly one bit clear.  shift_code is what the entry returns while
; either shift key is held, and is the same as code where shift means nothing.
; Entries are tried in order, so the first match wins.

    .include "app_defs.s"

.import app_key_table

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

shifted:        .res 1          ; 1 while a shift key is held during a scan

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; c64_keys_scan — returns a key code in A, KEY_NONE_CODE if nothing is held.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export c64_keys_scan
c64_keys_scan:
    jsr c64_keys_shift
    lda #0
    rol a                       ; 1 while shift is held, 0 otherwise
    sta shifted

    ldx #0
@entry:
    lda app_key_table, x
    beq @none
    sta CIA1_PRA
    lda app_key_table+1, x
    and CIA1_PRB
    beq @down
    inx
    inx
    inx
    inx
    bne @entry                  ; a table never reaches 64 entries
@none:
    lda #KEY_NONE_CODE
    rts

@down:
    txa
    clc
    adc #2                      ; the code, or the one after it under shift
    adc shifted
    tax
    lda app_key_table, x
    ; fall through

; key_done — the debounce every detected key passes through.  About 200 cycles,
; which is what stops a held key repeating between two scans.
@debounce:
    ldx #DEBOUNCE_COUNT
@dly:
    dex
    bne @dly
    rts

; ---------------------------------------------------------------------------
; c64_keys_shift — carry set if either shift key is down.  Clobbers A.
; ---------------------------------------------------------------------------

.export c64_keys_shift
c64_keys_shift:
    lda #KEY_LSH_COL
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_LSH_ROW_BIT
    beq @yes
    lda #KEY_RSH_COL
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_RSH_ROW_BIT
    beq @yes
    clc
    rts
@yes:
    sec
    rts

; ---------------------------------------------------------------------------
; c64_keys_wait_none — spins until nothing in the table is held.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export c64_keys_wait_none
c64_keys_wait_none:
    jsr c64_keys_scan
    cmp #KEY_NONE_CODE
    bne c64_keys_wait_none
    rts

; ---------------------------------------------------------------------------
; c64_keys_wait_any — until something is pressed, and then released.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export c64_keys_wait_any
c64_keys_wait_any:
    jsr c64_keys_scan
    cmp #KEY_NONE_CODE
    beq c64_keys_wait_any
    jmp c64_keys_wait_none
