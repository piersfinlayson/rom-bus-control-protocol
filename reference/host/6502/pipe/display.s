; display.s — the layout, and every word that goes on a screen
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Every word this tester puts on a screen is here, bar the two rows of key
; names, which are the machine's because the keys are.  Where each part of the
; display sits is the machine's business too and comes from its plat_defs.s,
; and putting a character on the screen is plat_put's.  What is here is the
; layout and the words.
;
; The counter block in timing.s is the interface to the rest of the tester.
; This file reads it and never writes it.  Everything else passes a status code
; in A.
;
; Cost: display_counters runs once per closed window and inside the window, so
; it is inside the measured time.  That is deliberate — it keeps the machine's
; figure and the USB host's figure in agreement.  Eight fields of eight digits
; is a few thousand cycles, well under a percent of a second.  That is the
; number to watch when changing this file.

    .include "pipe_defs.s"

.import plat_cls
.import plat_row
.import plat_put
.import plat_reverse
.import plat_keys_1
.import plat_keys_2

; Written by session.s
.import device_type_buf
.import device_version_buf
.import proto_ver_buf

; The counter block, written by the run path
.import bytes_total, lines_total, refusals, errors
.import rate_now, rate_best, rate_mean, secs

; Run state
.import run_path

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

num:        .res 4          ; what print_num renders
digit_tmp:  .res 4

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

.macro set_ptr addr
    lda #<addr
    sta ZP_PTR_LO
    lda #>addr
    sta ZP_PTR_HI
.endmacro

; ---------------------------------------------------------------------------
; display_init — a blank screen, the title bar, and the keys.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_init
display_init:
    jsr plat_cls

    set_ptr str_title
    lda #ROW_TITLE
    ldx #COL_TITLE
    jsr print_at

    set_ptr str_brand
    lda #ROW_TITLE
    ldx #COL_BRAND
    jsr print_at

    lda #ROW_TITLE              ; the band goes on last, behind both
    ldx #0
    ldy #SCREEN_COLS
    jsr plat_reverse

    set_ptr plat_keys_1
    lda #ROW_KEYS
    ldx #COL_KEYS
    jsr print_at

    set_ptr plat_keys_2
    lda #ROW_KEYS + 1
    ldx #COL_KEYS
    jmp print_at

; ---------------------------------------------------------------------------
; display_device — what the device calls itself.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_device
display_device:
    set_ptr device_type_buf
    lda #ROW_DEVICE
    ldx #COL_DEV
    jsr print_at

    set_ptr device_version_buf
    lda #ROW_VERSION
    ldx #COL_VER
    jsr print_at

    set_ptr proto_ver_buf
    lda #ROW_PROTO
    ldx #COL_PROTO
    jmp print_at

; ---------------------------------------------------------------------------
; display_labels — the fixed left-hand text of every counter row.  Drawn once.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

LABEL_COUNT = 8

.export display_labels
display_labels:
    lda #0
    sta ZP_APP6
@loop:
    ldx ZP_APP6
    lda label_ptr_tab_lo, x
    sta ZP_PTR_LO
    lda label_ptr_tab_hi, x
    sta ZP_PTR_HI
    lda label_row_tab, x
    ldx #COL_LABEL
    jsr print_at
    inc ZP_APP6
    lda ZP_APP6
    cmp #LABEL_COUNT
    bne @loop
    rts

; ---------------------------------------------------------------------------
; display_paths — the three send path names, the selected one in reverse video.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_paths
display_paths:
    set_ptr str_paths
    lda #ROW_PATHS
    ldx #0
    jsr print_at

    ldx run_path
    cpx #PATH_COUNT
    bcc @ok
    ldx #0
@ok:
    ldy path_len_tab, x
    lda path_col_tab, x
    tax
    lda #ROW_PATHS
    jmp plat_reverse

; ---------------------------------------------------------------------------
; display_counters — every number on the screen.  Called once per closed
; window and once when a run stops.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_counters
display_counters:
    lda #ROW_RATE
    ldx #<rate_now
    ldy #>rate_now
    jsr num24_at

    lda #ROW_BEST
    ldx #<rate_best
    ldy #>rate_best
    jsr num24_at

    lda #ROW_MEAN
    ldx #<rate_mean
    ldy #>rate_mean
    jsr num24_at

    lda #ROW_TOTAL
    ldx #<bytes_total
    ldy #>bytes_total
    jsr num32_at

    lda #ROW_LINES
    ldx #<lines_total
    ldy #>lines_total
    jsr num32_at

    lda #ROW_SECS
    ldx #<secs
    ldy #>secs
    jsr num16_at

    lda #ROW_REFUSALS
    ldx #<refusals
    ldy #>refusals
    jsr num16_at

    lda #ROW_ERRORS
    ldx #<errors
    ldy #>errors
    jmp num16_at

; ---------------------------------------------------------------------------
; display_status — A = status code.  The row is blanked first, so a short
; message never leaves the tail of a longer one behind it.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

.export display_status
display_status:
    cmp #STAT_COUNT
    bcc @in_range
    lda #STAT_BLANK
@in_range:
    asl a
    tax
    lda str_status_tab, x
    sta ZP_APP0
    lda str_status_tab + 1, x
    sta ZP_APP1

    lda #ROW_STATUS
    jsr blank_row

    lda ZP_APP0
    sta ZP_PTR_LO
    lda ZP_APP1
    sta ZP_PTR_HI
    lda #ROW_STATUS
    ldx #1
    jmp print_at

; ---------------------------------------------------------------------------
; num16_at / num24_at / num32_at — A = row, X/Y = pointer to the value.
; Widens into the 32-bit scratch and renders it.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

num16_at:
    pha
    jsr load_num
    lda #0
    sta num + 2
    sta num + 3
    jmp numv_go

; num24_at is only used for the three rates, which are counted in bytes a
; second and shown in bits, so it shifts by three on the way.
num24_at:
    pha
    jsr load_num
    ldy #2
    lda (ZP_APP0), y
    sta num + 2
    lda #0
    sta num + 3
    ldx #3
@bits:
    asl num + 0
    rol num + 1
    rol num + 2
    rol num + 3
    dex
    bne @bits
    jmp numv_go

num32_at:
    pha
    jsr load_num
    ldy #2
    lda (ZP_APP0), y
    sta num + 2
    iny
    lda (ZP_APP0), y
    sta num + 3

numv_go:
    lda #NUM_COL
    sta ZP_APP2
    pla                         ; row
    ; fall through

; ---------------------------------------------------------------------------
; print_num — renders num as NUM_WIDTH digits right-aligned in the field
; starting at column ZP_APP2 on the row in A, leading zeros as spaces.
; Repeated subtraction, which is slow and short, and runs once a second per
; field.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

print_num:
    jsr plat_row
    lda #0
    sta ZP_APP6                 ; non-zero once a digit has been emitted
    sta ZP_APP7                 ; digit position, 0 to NUM_WIDTH-1
    ldy ZP_APP2                 ; column, and Y stays the column throughout

@digit:
    lda ZP_APP7
    asl a
    asl a
    tax                         ; four bytes per pow10 entry
    lda #0
    sta ZP_APP4                 ; value of this digit
@sub:
    sec
    lda num + 0
    sbc pow10 + 0, x
    sta digit_tmp + 0
    lda num + 1
    sbc pow10 + 1, x
    sta digit_tmp + 1
    lda num + 2
    sbc pow10 + 2, x
    sta digit_tmp + 2
    lda num + 3
    sbc pow10 + 3, x
    sta digit_tmp + 3
    bcc @emit
    lda digit_tmp + 0
    sta num + 0
    lda digit_tmp + 1
    sta num + 1
    lda digit_tmp + 2
    sta num + 2
    lda digit_tmp + 3
    sta num + 3
    inc ZP_APP4
    jmp @sub

@emit:
    lda ZP_APP4
    bne @show
    lda ZP_APP6
    bne @show                   ; past the leading zeros, so zeros count
    lda ZP_APP7
    cmp #(NUM_WIDTH - 1)
    beq @show                   ; the units digit always shows
    lda #' '
    jmp @put
@show:
    lda #1
    sta ZP_APP6
    lda ZP_APP4
    clc
    adc #'0'
@put:
    jsr plat_put                ; Y comes back as the column it went in as
    iny
    inc ZP_APP7
    lda ZP_APP7
    cmp #NUM_WIDTH
    bne @digit
    rts

; Leaves the caller's pointer in ZP_APP0/1 so the wider variants can reach the
; bytes above the low two.
load_num:
    stx ZP_APP0
    sty ZP_APP1
    ldy #0
    lda (ZP_APP0), y
    sta num + 0
    iny
    lda (ZP_APP0), y
    sta num + 1
    rts

; ---------------------------------------------------------------------------
; print_at — A = row, X = column, ZP_PTR_LO/HI = a null-terminated ASCII
; string.  Stops at the right-hand edge, so a device name longer than the
; screen cannot wrap onto the row below.
; Clobbers A, X, Y and the app zero page above ZP_APP3.
; ---------------------------------------------------------------------------

print_at:
    stx ZP_APP4                 ; column
    jsr plat_row
    lda #0
    sta ZP_APP5                 ; index into the string
@loop:
    ldy ZP_APP5
    lda (ZP_PTR_LO), y
    beq @done
    ldy ZP_APP4
    cpy #SCREEN_COLS
    bcs @done
    jsr plat_put
    inc ZP_APP4
    inc ZP_APP5
    bne @loop
@done:
    rts

; ---------------------------------------------------------------------------
; blank_row — A = row.  Spaces from edge to edge.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

blank_row:
    jsr plat_row
    ldy #0
@loop:
    lda #' '
    jsr plat_put
    iny
    cpy #SCREEN_COLS
    bne @loop
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

pow10:
    .dword 10000000, 1000000, 100000, 10000
    .dword 1000, 100, 10, 1

label_row_tab:
    .byte ROW_RATE, ROW_BEST, ROW_TOTAL, ROW_LINES
    .byte ROW_SECS, ROW_REFUSALS, ROW_ERRORS, ROW_MEAN
label_ptr_tab_lo:
    .byte <str_rate, <str_best, <str_total, <str_lines
    .byte <str_secs, <str_refusals, <str_errors, <str_mean
label_ptr_tab_hi:
    .byte >str_rate, >str_best, >str_total, >str_lines
    .byte >str_secs, >str_refusals, >str_errors, >str_mean

; Where each name starts on the paths row, and how long it is.  Both come off
; the string in the same branch below, so the three move together.

str_status_tab:
    .word str_blank
    .word str_opening
    .word str_armed
    .word str_no_device
    .word str_enter_fail
    .word str_version
    .word str_no_pipe
    .word str_pipe_dir
    .word str_running
    .word str_stopped
    .word str_no_answer
    .word str_not_armed
    .word str_no_complete
    .word str_bad_refusal
    .word str_pipe_stuck
    .word str_no_recover

str_brand:
    .byte "PIERS.ROCKS", 0
str_blank:
    .byte 0

.if SCREEN_COLS >= 32

path_col_tab:
    .byte 3, 15, 27
path_len_tab:
    .byte 6, 6, 8

str_title:
    .byte "RBCP PIPE THROUGHPUT TEST", 0
str_paths:
    .byte "   1 LIB4      2 LIB1      3 TUNED4", 0

str_rate:
    .byte "BPS", 0
str_best:
    .byte "BEST", 0
str_total:
    .byte "TOTAL BYTES", 0
str_lines:
    .byte "LINES", 0
str_secs:
    .byte "SECONDS", 0
str_refusals:
    .byte "REFUSALS", 0
str_errors:
    .byte "ERRORS", 0
str_mean:
    .byte "MEAN THIS RUN", 0

str_opening:
    .byte "OPENING RBCP SESSION", 0
str_armed:
    .byte "READY", 0
str_no_device:
    .byte "NO DEVICE ANSWERED THE KNOCK", 0
str_enter_fail:
    .byte "DEVICE REFUSED COMMAND-RESPONSE MODE", 0
str_version:
    .byte "PROTOCOL VERSION NOT SUPPORTED", 0
str_no_pipe:
    .byte "DEVICE HAS NO PIPE", 0
str_pipe_dir:
    .byte "PIPE 0 WILL NOT TAKE HOST BYTES", 0
str_running:
    .byte "RUNNING", 0
str_stopped:
    .byte "STOPPED", 0
str_no_answer:
    .byte "DEVICE DID NOT TAKE THE COMMAND", 0
str_not_armed:
    .byte "NO SESSION - NOTHING TO RUN", 0
str_no_complete:
    .byte "DEVICE NEVER FINISHED THE COMMAND", 0
str_bad_refusal:
    .byte "WRITE REFUSED WITH THE PIPE NOT FULL", 0
str_pipe_stuck:
    .byte "PIPE STAYED FULL - RUN ENDED", 0
str_no_recover:
    .byte "DEVICE DID NOT COME BACK - NO SESSION", 0

.else

path_col_tab:
    .byte 0, 6, 12
path_len_tab:
    .byte 5, 5, 5

str_title:
    .byte "RBCP PIPE", 0
str_paths:
    .byte "1LIB4 2LIB1 3TUN4", 0

str_rate:
    .byte "BPS", 0
str_best:
    .byte "BEST", 0
str_total:
    .byte "BYTES", 0
str_lines:
    .byte "LINES", 0
str_secs:
    .byte "SECS", 0
str_refusals:
    .byte "REFUSED", 0
str_errors:
    .byte "ERRORS", 0
str_mean:
    .byte "MEAN", 0

str_opening:
    .byte "OPENING SESSION", 0
str_armed:
    .byte "READY", 0
str_no_device:
    .byte "NO DEVICE", 0
str_enter_fail:
    .byte "NO CMD-RESP MODE", 0
str_version:
    .byte "BAD PROTOCOL VER", 0
str_no_pipe:
    .byte "NO PIPE", 0
str_pipe_dir:
    .byte "PIPE WILL NOT TAKE", 0
str_running:
    .byte "RUNNING", 0
str_stopped:
    .byte "STOPPED", 0
str_no_answer:
    .byte "COMMAND NOT TAKEN", 0
str_not_armed:
    .byte "NO SESSION", 0
str_no_complete:
    .byte "NEVER FINISHED", 0
str_bad_refusal:
    .byte "REFUSED NOT FULL", 0
str_pipe_stuck:
    .byte "PIPE STAYED FULL", 0
str_no_recover:
    .byte "DEVICE GONE", 0

.endif
