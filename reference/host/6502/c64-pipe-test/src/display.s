; display.s — everything this program puts on the screen
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The seam
; --------
; The counter block in timing.s is the interface.  This file reads it and never
; writes it.  The rest of the program passes a status code in A and never holds
; a string, a row, a column or a colour.
;
; Two rules a rewrite of this file has to keep, neither of them visible in the
; code:
;
;   - Write $0400 and $D800 directly.  No kernal screen calls.  CHROUT and the
;     rest of the editor work through $D0-$F2, which this program has taken for
;     its own zero page, so the screen memory is safe and the editor is not.
;
;   - Do not read $A000-$BFFF.  A stray read of the command page injects a
;     command byte into an open session.
;
; Cost: display_counters runs once per closed window and inside the window, so
; it is inside the measured time.  That is deliberate — it keeps the C64's
; figure and the USB host's figure in agreement.  Eight fields of eight digits
; is about 3500 cycles, 0.36% of a second.  That is the number to watch when
; changing this file.

    .include "pipe_defs.s"

.import c64_clear_screen
.import c64_print_at
.import row_off_lo
.import row_scr_hi

; Written by session.s
.import device_type_buf
.import device_version_buf
.import proto_ver_buf
.import ram_slot_active
.import exit_slot
.import exit_flash

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
; display_init — black border and background, white text.  White on black
; rather than anything prettier: it is what reads on video.
; Clobbers A, X, Y and the c64_hw.s scratch.
; ---------------------------------------------------------------------------

.export display_init
display_init:
    lda #COL_BLACK
    sta VIC_BORDER
    sta VIC_BACKGROUND
    ldy #COL_WHITE
    jsr c64_clear_screen

    set_ptr str_title
    lda #ROW_TITLE
    ldx #5
    jsr print_at

    set_ptr str_keys
    lda #ROW_KEYS
    ldx #1
    jmp print_at

; ---------------------------------------------------------------------------
; display_device — device identity and RAM slot counts.
; Clobbers A, X, Y and the c64_hw.s scratch.
; ---------------------------------------------------------------------------

.export display_device
display_device:
    set_ptr device_type_buf
    lda #ROW_DEVICE
    ldx #1
    jsr print_at

    set_ptr device_version_buf
    lda #ROW_DEVICE
    ldx #17
    jsr print_at

    set_ptr proto_ver_buf
    lda #ROW_DEVICE
    ldx #28
    jsr print_at

    set_ptr str_ram_slots
    lda #ROW_SLOTS
    ldx #1
    jsr print_at

    lda ram_slot_active
    ldx #5
    ldy #ROW_SLOTS
    jmp digit_at

; ---------------------------------------------------------------------------
; display_exit_slot — fills in where the clean exit points, once verification
; has found it.
; Clobbers A, X, Y and the c64_hw.s scratch.
; ---------------------------------------------------------------------------

.export display_exit_slot
display_exit_slot:
    lda exit_slot
    ldx #24
    ldy #ROW_SLOTS
    jsr digit_at
    lda exit_flash
    ldx #37
    ldy #ROW_SLOTS
    jmp digit_at

; ---------------------------------------------------------------------------
; display_labels — the fixed left-hand text of every counter row.  Drawn once.
; Clobbers A, X, Y and the c64_hw.s scratch.
; ---------------------------------------------------------------------------

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
    ldx #1
    jsr print_at
    inc ZP_APP6
    lda ZP_APP6
    cmp #8
    bne @loop
    rts

; ---------------------------------------------------------------------------
; display_paths — the three send path names, the selected one in reverse video.
;
; c64_highlight_row is no use here: it reverses all forty columns, and this row
; needs one name out of three.
;
; Clobbers A, X, Y and the c64_hw.s scratch.
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
    jmp reverse_span

; ---------------------------------------------------------------------------
; display_counters — every number on the screen.  Called once per closed
; window and once when a run stops.
; Clobbers A, X, Y and the c64_hw.s scratch.
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
; Clobbers A, X, Y and the c64_hw.s scratch.
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
    lda str_status_tab+1, x
    sta ZP_APP1

    set_ptr str_blank_row
    lda #ROW_STATUS
    ldx #0
    jsr print_at

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
; Clobbers A, X, Y and the c64_hw.s scratch.
; ---------------------------------------------------------------------------

num16_at:
    pha
    jsr load_num
    lda #0
    sta num + 2
    sta num + 3
    jmp numv_go

num24_at:
    pha
    jsr load_num
    ldy #2
    lda (ZP_APP0), y
    sta num + 2
    lda #0
    sta num + 3
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
    pla
    tay                         ; row
    ldx #NUM_COL
    ; fall through

; ---------------------------------------------------------------------------
; print_num — renders num as eight digits right-aligned in the field starting
; at column X on row Y, leading zeros as spaces.  Repeated subtraction, which
; is slow and short, and runs once per second per field.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

print_num:
    stx ZP_APP2                 ; leftmost column of the field
    sty ZP_APP3                 ; row
    lda #0
    sta ZP_APP6                 ; non-zero once a digit has been emitted
    sta ZP_APP7                 ; digit position, 0 to NUM_WIDTH-1

@digit:
    lda ZP_APP7
    asl a
    asl a
    tax                         ; four bytes per pow10 entry
    ldy #0                      ; value of this digit
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
    iny
    jmp @sub

@emit:
    sty ZP_APP4                 ; digit value
    cpy #0
    bne @show
    lda ZP_APP6
    bne @show                   ; past the leading zeros, so zeros count
    lda ZP_APP7
    cmp #(NUM_WIDTH - 1)
    beq @show                   ; the units digit always shows
    lda #CHAR_SPACE
    jmp @put
@show:
    lda #1
    sta ZP_APP6
    lda ZP_APP4
    clc
    adc #$30                    ; screen codes $30-$39 are the digits
@put:
    pha
    lda ZP_APP2
    clc
    adc ZP_APP7
    tax
    ldy ZP_APP3
    pla
    jsr poke_char
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
; poke_char — A = screen code, X = column, Y = row.
; Clobbers A, Y.  Preserves X.
; ---------------------------------------------------------------------------

poke_char:
    sta ZP_APP5
    stx ZP_APP4
    lda row_off_lo, y
    clc
    adc ZP_APP4
    sta ZP_PTR_LO
    lda row_scr_hi, y
    adc #0
    sta ZP_PTR_HI
    lda ZP_APP5
    ldy #0
    sta (ZP_PTR_LO), y
    rts

; ---------------------------------------------------------------------------
; reverse_span — A = row, X = column, Y = length.  Sets bit 7 on the screen
; codes, which is what reverse video is.
; Clobbers A, X, Y and the c64_hw.s scratch.
; ---------------------------------------------------------------------------

reverse_span:
    sty ZP_APP7
    stx ZP_APP4
    tay
    lda row_off_lo, y
    clc
    adc ZP_APP4
    sta ZP_PTR_LO
    lda row_scr_hi, y
    adc #0
    sta ZP_PTR_HI
    ldy #0
@loop:
    lda (ZP_PTR_LO), y
    ora #$80
    sta (ZP_PTR_LO), y
    iny
    cpy ZP_APP7
    bne @loop
    rts

; ---------------------------------------------------------------------------
; digit_at — A = value 0-9, X = column, Y = row.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

digit_at:
    clc
    adc #$30
    jmp poke_char

; ---------------------------------------------------------------------------
; print_at — A = row, X = col, ZP_PTR_LO/HI = null-terminated ASCII.
; ---------------------------------------------------------------------------

print_at:
    sta ZP_TMP0
    stx ZP_TMP1
    jmp c64_print_at

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

; Where each name starts on the paths row, and how long it is.  From the
; string below: "1 LIB4" at 3, "2 LIB1" at 15, "3 TUNED4" at 27.
path_col_tab:
    .byte 3, 15, 27
path_len_tab:
    .byte 6, 6, 8

str_title:
    .byte "RBCP PIPE THROUGHPUT TEST", 0
str_keys:
    .byte "1 2 3 SELECT  RET RUN  T 10 SEC  Q QUIT", 0
; Digits are poked in at columns 5, 24 and 37, which is where the zeros sit.
str_ram_slots:
    .byte "RAM 0 ACTIVE  EXIT RAM 0 FROM FLASH 0", 0
str_paths:
    .byte "   1 LIB4      2 LIB1      3 TUNED4", 0
str_blank_row:
    .byte "                                        ", 0

str_rate:
    .byte "BYTES/SEC", 0
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

str_status_tab:
    .word str_blank
    .word str_checking
    .word str_opening
    .word str_armed
    .word str_clash
    .word str_no_device
    .word str_enter_fail
    .word str_version
    .word str_no_pipe
    .word str_pipe_dir
    .word str_ram_slot_count
    .word str_dirty_exit
    .word str_running
    .word str_stopped
    .word str_lost
    .word str_not_armed
    .word str_verifying
    .word str_no_clean

str_blank:
    .byte 0
str_checking:
    .byte "READING BASIC IMAGE", 0
str_opening:
    .byte "OPENING RBCP SESSION", 0
str_armed:
    .byte "READY", 0
str_clash:
    .byte "BACK CHANNEL CLASHES WITH IMAGE - STOPPED", 0
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
str_ram_slot_count:
    .byte "DEVICE NEEDS TWO RAM SLOTS", 0
str_dirty_exit:
    .byte "LEFT SESSION - BASIC IMAGE IS DIRTY", 0
str_running:
    .byte "RUNNING", 0
str_stopped:
    .byte "STOPPED", 0
str_lost:
    .byte "DEVICE STOPPED ANSWERING - RUN ENDED", 0
str_not_armed:
    .byte "NO SESSION - NOTHING TO RUN", 0
str_verifying:
    .byte "LOOKING FOR A CLEAN IMAGE IN FLASH", 0
str_no_clean:
    .byte "NO FLASH SLOT MATCHES - NO CLEAN EXIT", 0
