; diag.s — the record of the RBCP session and the report made from it
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; diag_begin and diag_end wrap every command the bootloader sends, recording
; its frame, the header that came back and how long it took.  On a failed boot
; the record is drawn on the screen and sent out of pipe 0.
;
; Times are milliseconds from CIA2.  A PAL-N C64 is taken for PAL, so its times
; are 4% long.

    .include "boot_defs.s"
    .include "rbcp_stage.s"

.import c64_clear_screen
.import c64_print_at
.import buf_putc
.import buf_puts
.import byte_to_hex
.import buf_dec16
.import pipe_log
.import str_app

.import rbcp_recover
.import rbcp_cmd_get_pipe_capability
.import rbcp_cmd_get_device_type
.import rbcp_cmd_get_device_version
.import rbcp_cmd_get_flash_slot_info_all

; Milliseconds diag_late waits, from when the command went out.
LATE_LIMIT      = 10000

LATE_NONE           = 0
LATE_COMPLETED      = 1
LATE_NOT_RECEIVED   = 2
LATE_NOT_COMPLETED  = 3

REPORT_LOST     = 0             ; the device didn't respond after a reset
REPORT_NO_PIPE  = 1
REPORT_CUT      = 2             ; a write to the pipe failed partway
REPORT_SENT     = 3

; Flash slot records that fit in the back channel after its header and the
; 4 byte preamble.
SLOT_FIT        = (CONFIG_RBCP_BCH_SIZE - 8 - 4) / 32
SLOTS_LEN       = 4 + SLOT_FIT * 32
.assert SLOTS_LEN > $100 .and SLOTS_LEN <= $200, error, "fetch_device copies one page and part of another"

DEV_STR_MAX     = 23            ; characters kept of the device's type or version
SLOT_NAME_MAX   = 31

ROW_STAGE       = 2
ROW_SENT        = 3
ROW_HEADER      = 4
ROW_LATE        = 5
ROW_LATE_HEADER = 6
ROW_HEAD        = 8
ROW_LIST        = 9
ROW_RESULT      = 22
ROW_DEVICE      = 23
ROW_APP         = 24
COL_RESULT      = 20
COL_TIME        = 34

; Arguments shown on a row of the list.
LIST_ARGS       = 4

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

diag_rec:       .res ENT_MAX * ENT_SIZE
diag_count:     .res 1
diag_start:     .res 2          ; when the last command went out
.export diag_ms
diag_ms:        .res 2          ; how long the last command took
diag_save_a:    .res 1
diag_save_x:    .res 1
diag_stage:     .res 1
diag_pal:       .res 1          ; 1 on PAL
diag_msg:       .res 2          ; the error message
diag_tmp:       .res 1

late_state:     .res 1
late_ms:        .res 2
late_hdr:       .res HDR_LEN

report:         .res 1
put_i:          .res 1
put_n:          .res 1
loop_i:         .res 1
list_row:       .res 1
at_col:         .res 1

dev_type:       .res DEV_STR_MAX + 1
dev_ver:        .res DEV_STR_MAX + 1
slots:          .res SLOTS_LEN
slots_ok:       .res 1

; A screen row or pipe line being built.
text:           .res 96

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

.macro set_ptr addr
    lda #<(addr)
    sta ZP_PTR_LO
    lda #>(addr)
    sta ZP_PTR_HI
.endmacro

.macro put_str addr
    set_ptr addr
    jsr buf_puts
.endmacro

; ---------------------------------------------------------------------------
; diag_init — empties the record, works out PAL or NTSC and starts the clock.
; Takes up to a frame.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export diag_init
diag_init:
    lda #0
    sta diag_count
    sta late_state
    sta diag_pal
    sta dev_type
    sta dev_ver
    sta slots_ok

    ; The last raster line is $137 on PAL and $106 or $107 on NTSC.  Wait for
    ; line $100, then keep the highest low byte seen until the count wraps.
@high:
    bit VIC_CTRL1
    bpl @high
    lda #0
    sta diag_tmp
@track:
    lda VIC_RASTER
    bit VIC_CTRL1
    bpl @tracked                ; wrapped, so this sample may be line 0
    cmp diag_tmp
    bcc @track
    sta diag_tmp
    bcs @track                  ; always
@tracked:
    lda diag_tmp
    cmp #$20                    ; carry set on PAL
    rol diag_pal

    lda #CIA_ICR_NONE
    sta CIA2_ICR
    lda #0
    sta CIA2_CRA
    sta CIA2_CRB
    lda #$FF
    sta CIA2_TBLO
    sta CIA2_TBHI
    ldx #<MS_LATCH_NTSC
    ldy #>MS_LATCH_NTSC
    lda diag_pal
    beq @latch
    ldx #<MS_LATCH_PAL
    ldy #>MS_LATCH_PAL
@latch:
    stx CIA2_TALO
    sty CIA2_TAHI
    lda #CIA_CRB_RUN
    sta CIA2_CRB
    lda #CIA_CRA_RUN
    sta CIA2_CRA
    rts

; ---------------------------------------------------------------------------
; timer_now — milliseconds since diag_init, A low and X high.  Timer B counts
; down from $FFFF, so this is its complement.  Clobbers A, X.
; ---------------------------------------------------------------------------

timer_now:
    ldx CIA2_TBHI
    lda CIA2_TBLO
    cpx CIA2_TBHI
    bne timer_now               ; timer B moved on between the reads
    eor #$FF
    pha
    txa
    eor #$FF
    tax
    pla
    rts

; ---------------------------------------------------------------------------
; diag_begin — records when a command goes out.  Preserves A and X.
; ---------------------------------------------------------------------------

.export diag_begin
diag_begin:
    sta diag_save_a
    stx diag_save_x
    jsr timer_now
    sta diag_start
    stx diag_start + 1
    lda diag_save_a
    ldx diag_save_x
    rts

; ---------------------------------------------------------------------------
; diag_end — records the command that has just returned and sets diag_ms to
; how long it took.  Nothing is added to a full record.
;
; Carry set without a stage is a protocol version the bootloader doesn't
; support.  The command itself completed, so it is recorded as OK.
;
; Preserves A and carry.  Clobbers X, Y.
; ---------------------------------------------------------------------------

.export diag_end
diag_end:
    php
    pha
    lda #0
    bcc @stage
    lda rbcp_zp_5
    cmp #STAGE_COUNT
    bcc @stage
    lda #0
@stage:
    sta diag_stage

    jsr timer_now
    sec
    sbc diag_start
    sta diag_ms
    txa
    sbc diag_start + 1
    sta diag_ms + 1

    ldx diag_count
    cpx #ENT_MAX
    bcs @out
    inc diag_count
    jsr ent_point

    ldy #ENT_GROUP
    lda rbcp_zp_0
    sta (ZP_ENT_LO), y
    ldy #ENT_CMD
    lda rbcp_zp_1
    sta (ZP_ENT_LO), y
    ldy #ENT_ARGS
    ldx #0
@arg:
    lda rbcp_arg0, x
    sta (ZP_ENT_LO), y
    iny
    inx
    cpx #ENT_COUNT - ENT_ARGS
    bne @arg
    ldy #ENT_COUNT
    lda rbcp_zp_4               ; rbcp_send_cmd leaves the count here
    sta (ZP_ENT_LO), y
    ldy #ENT_TOK
    lda rbcp_zp_2
    sta (ZP_ENT_LO), y
    ldy #ENT_STAGE
    lda diag_stage
    sta (ZP_ENT_LO), y
    ldy #ENT_MS
    lda diag_ms
    sta (ZP_ENT_LO), y
    iny
    lda diag_ms + 1
    sta (ZP_ENT_LO), y
    ldy #ENT_HDR
    ldx #0
@hdr:
    lda CONFIG_RBCP_BCH_BASE, x
    sta (ZP_ENT_LO), y
    iny
    inx
    cpx #HDR_LEN
    bne @hdr
@out:
    pla
    plp
    rts

; ---------------------------------------------------------------------------
; ent_point — points ZP_ENT at entry X.  Clobbers A.
; ---------------------------------------------------------------------------

ent_point:
    txa
    lsr a
    lsr a
    lsr a
    clc
    adc #>diag_rec
    sta ZP_ENT_HI
    txa
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc #<diag_rec
    sta ZP_ENT_LO
    bcc @done
    inc ZP_ENT_HI
@done:
    rts

; ---------------------------------------------------------------------------
; diag_late — keeps polling the last command if it timed out.
;
; The library's timeouts are short, so a slow device and a stuck one fail the
; same way.  This polls for up to LATE_LIMIT milliseconds from when the command
; went out, first for the token to change and then for progress to be complete.
; It records the time and the header when it stops.  The border is yellow while
; it polls.
;
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export diag_late
diag_late:
    ldx diag_count
    beq @out
    dex
    jsr ent_point
    ldy #ENT_STAGE
    lda (ZP_ENT_LO), y
    cmp #STAGE_NOT_TAKEN
    beq @wait
    cmp #STAGE_UNFINISHED
    bne @out
@wait:
    lda #COL_YELLOW
    sta VIC_BORDER
    ldy #ENT_TOK
@token:
    lda RBCP_TOKEN_LSB_ADDR
    cmp (ZP_ENT_LO), y
    bne @progress
    jsr late_time
    bcc @token
    lda #LATE_NOT_RECEIVED
    bne @keep                   ; always
@progress:
    lda RBCP_PROGRESS_ADDR
    cmp #RBCP_COMPLETE
    beq @completed
    jsr late_time
    bcc @progress
    lda #LATE_NOT_COMPLETED
    bne @keep                   ; always
@completed:
    jsr late_time
    lda #LATE_COMPLETED
@keep:
    sta late_state
    ldx #0
@hdr:
    lda CONFIG_RBCP_BCH_BASE, x
    sta late_hdr, x
    inx
    cpx #HDR_LEN
    bne @hdr
@out:
    rts

; late_time — sets late_ms to the time since the command went out.  Carry set
; once it reaches LATE_LIMIT.  Clobbers A, X.
late_time:
    jsr timer_now
    sec
    sbc diag_start
    sta late_ms
    txa
    sbc diag_start + 1
    sta late_ms + 1
    lda late_ms
    cmp #<LATE_LIMIT
    lda late_ms + 1
    sbc #>LATE_LIMIT
    rts

; ---------------------------------------------------------------------------
; diag_screen — draws the error message in ZP_PTR, the record and the prompt
; to capture diagnostics.  The display stays as it was.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export diag_screen
diag_screen:
    lda ZP_PTR_LO
    sta diag_msg
    lda ZP_PTR_HI
    sta diag_msg + 1
    ldy #COL_WHITE
    jsr c64_clear_screen

    ldx #0
    ldy #0
    jsr print_at
    jsr screen_failed
    jsr screen_list

    set_ptr str_prompt
    ldx #ROW_RESULT
    ldy #0
    jsr print_at

    jsr text_start
    jsr put_app
    ldx #ROW_APP
    jmp text_row

; screen_failed — draws the command that failed.  A failure that isn't a
; command's, for example no kernals to boot, draws nothing.  Clobbers A, X, Y.
screen_failed:
    ldx diag_count
    bne @some
@none:
    rts
@some:
    dex
    jsr ent_point
    ldy #ENT_STAGE
    lda (ZP_ENT_LO), y
    beq @none
    jsr text_start
    put_str str_command
    jsr put_stage
    ldx #ROW_STAGE
    jsr text_row

    jsr text_start
    put_str str_sent
    lda #ENT_COUNT - ENT_ARGS
    jsr put_frame
    ldx #ROW_SENT
    jsr text_row

    jsr text_start
    put_str str_token + 1       ; without its leading space
    lda #ENT_TOK
    jsr put_sp_hex
    put_str str_header
    jsr put_hdr
    ldx #ROW_HEADER
    jsr text_row

    lda late_state
    beq @out
    jsr text_start
    jsr put_late
    ldx #ROW_LATE
    jsr text_row
    jsr text_start
    put_str str_header + 1
    jsr put_late_hdr
    ldx #ROW_LATE_HEADER
    jmp text_row
@out:
    rts

; screen_list — draws a row for each command in the record.  Clobbers A, X, Y.
screen_list:
    set_ptr str_head
    ldx #ROW_HEAD
    ldy #0
    jsr print_at

    lda #0
    sta loop_i
@entry:
    ldx loop_i
    cpx diag_count
    beq @out
    jsr ent_point
    txa
    clc
    adc #ROW_LIST
    sta list_row

    jsr text_start
    lda #LIST_ARGS
    jsr put_frame
    ldx list_row
    jsr text_row

    jsr text_start
    jsr put_stage
    ldx list_row
    ldy #COL_RESULT
    jsr text_row_at

    jsr text_start
    jsr put_ms
    ldx list_row
    ldy #COL_TIME
    jsr text_row_at

    inc loop_i
    bne @entry                  ; always
@out:
    rts

; ---------------------------------------------------------------------------
; diag_send — puts the device back into command-response mode and sends the
; record out of pipe 0.  Reads the device's type, version and flash slots
; first, for this and for diag_result.
;
; The display has to be off, as for any other exchange with the device.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export diag_send
diag_send:
    lda #REPORT_LOST
    sta report
    jsr rbcp_recover
    bcs @out
    lda #REPORT_NO_PIPE
    sta report
    jsr fetch_device
    jsr rbcp_cmd_get_pipe_capability
    bcs @out
    lda RBCP_DATA_ADDR + RBCP_PIPE_CAP_COUNT
    beq @out
    lda #REPORT_CUT
    sta report
    jsr send_head
    bcs @out
    jsr send_entries
    bcs @out
    jsr send_late
    bcs @out
    jsr send_slots
    bcs @out
    jsr text_start
    put_str str_end
    jsr text_send
    bcs @out
    lda #REPORT_SENT
    sta report
@out:
    rts

; Each send_ routine below returns carry set if a write to the pipe failed and
; clobbers A, X, Y.

; send_head — this bootloader, the error message and the device.
send_head:
    jsr text_start
    jsr put_app
    jsr text_send
    bcs @out
    jsr text_start
    lda diag_msg
    sta ZP_PTR_LO
    lda diag_msg + 1
    sta ZP_PTR_HI
    jsr buf_puts
    jsr text_send
    bcs @out
    jsr text_start
    jsr put_device
    jmp text_send
@out:
    rts

; send_entries — a line for each command in the record.
send_entries:
    lda #0
    sta loop_i
@entry:
    ldx loop_i
    cpx diag_count
    beq @done
    jsr ent_point
    jsr send_entry
    bcs @out
    inc loop_i
    bne @entry                  ; always
@done:
    clc
@out:
    rts

; send_late — diag_late's result, where it polled.
send_late:
    lda late_state
    beq @none
    jsr text_start
    jsr put_late
    put_str str_header
    jsr put_late_hdr
    jmp text_send
@none:
    clc
    rts

; send_entry — the entry at ZP_ENT as one line.
send_entry:
    jsr text_start
    put_str str_sent
    lda #ENT_COUNT - ENT_ARGS
    jsr put_frame
    put_str str_token
    lda #ENT_TOK
    jsr put_sp_hex
    put_str str_header
    jsr put_hdr
    lda #' '
    jsr buf_putc
    jsr put_stage
    lda #' '
    jsr buf_putc
    jsr put_ms
    jmp text_send

; send_slots — the flash slot list, a line for the count and one a slot.  The
; count is how many slots are listed, of how many the device has.
send_slots:
    jsr text_start
    lda slots_ok
    bne @count
    put_str str_slots_failed
    jmp text_send
@count:
    lda slots + 1
    ldx #0
    jsr buf_dec16
    put_str str_of
    lda slots + 0
    ldx #0
    jsr buf_dec16
    put_str str_listed
    jsr text_send
    bcs @out

    lda #0
    sta loop_i
@slot:
    lda loop_i
    cmp slots + 1
    beq @done
    cmp #SLOT_FIT
    beq @done
    jsr text_start
    put_str str_slot
    lda loop_i
    jsr byte_to_hex
    put_str str_type
    ldx loop_i
    jsr slot_point
    ldy #0
    lda (ZP_PTR_LO), y          ; ROM type
    jsr byte_to_hex
    lda #' '
    jsr buf_putc
    ldx loop_i
    jsr slot_point
    inc ZP_PTR_LO               ; the name follows the type byte
    bne @name
    inc ZP_PTR_HI
@name:
    ldx #SLOT_NAME_MAX
    jsr put_bounded
    jsr text_send
    bcs @out
    inc loop_i
    bne @slot                   ; always
@done:
    clc
@out:
    rts

; slot_point — points ZP_PTR at the record of flash slot X.  Clobbers A.
slot_point:
    txa
    lsr a
    lsr a
    lsr a
    clc
    adc #>(slots + 4)
    sta ZP_PTR_HI
    txa
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc #<(slots + 4)
    sta ZP_PTR_LO
    bcc @done
    inc ZP_PTR_HI
@done:
    rts

; ---------------------------------------------------------------------------
; fetch_device — keeps the device's type, version and flash slot list.  The
; pipe writes that follow overwrite the back channel.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

fetch_device:
    jsr rbcp_cmd_get_device_type
    bcs @version
    lda #<dev_type
    ldx #>dev_type
    jsr keep_string
@version:
    jsr rbcp_cmd_get_device_version
    bcs @slots
    lda #<dev_ver
    ldx #>dev_ver
    jsr keep_string
@slots:
    jsr rbcp_cmd_get_flash_slot_info_all
    bcs @out
    ldx #0
@page0:
    lda RBCP_DATA_ADDR, x
    sta slots, x
    inx
    bne @page0
@page1:
    lda RBCP_DATA_ADDR + $100, x
    sta slots + $100, x
    inx
    cpx #<SLOTS_LEN
    bne @page1
    lda #1
    sta slots_ok
@out:
    rts

; keep_string — copies the string in the back channel's data to the buffer at
; A (low) and X (high).
; Clobbers A, X, Y.
keep_string:
    sta ZP_TMP0
    stx ZP_TMP1
    set_ptr RBCP_DATA_ADDR
    ldx #DEV_STR_MAX
    jsr put_bounded
    lda #0
    jmp buf_putc

; ---------------------------------------------------------------------------
; diag_result — draws the report's outcome over the prompt, and the device's
; type and version.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export diag_result
diag_result:
    jsr text_start
    ldx #SCREEN_COLS
@space:
    lda #' '
    jsr buf_putc
    dex
    bne @space
    ldx #ROW_RESULT
    jsr text_row

    lda report
    asl a
    tax
    lda report_says, x
    sta ZP_PTR_LO
    lda report_says + 1, x
    sta ZP_PTR_HI
    ldx #ROW_RESULT
    ldy #0
    jsr print_at

    lda dev_type
    beq @out
    jsr text_start
    jsr put_device
    ldx #ROW_DEVICE
    jmp text_row
@out:
    rts

; ---------------------------------------------------------------------------
; Building text.  buf_putc and c64_print_at both use ZP_TMP0/1, so a row is
; built in full before it is printed.
; ---------------------------------------------------------------------------

; text_start — points buf_putc at the start of the buffer.  Clobbers A.
text_start:
    lda #<text
    sta ZP_TMP0
    lda #>text
    sta ZP_TMP1
    rts

; text_row — prints the buffer at row X, column 0.  text_row_at takes the
; column in Y.  Clobbers A, X, Y.
text_row:
    ldy #0
text_row_at:
    sty at_col                  ; buf_putc clobbers only Y
    lda #0
    jsr buf_putc
    set_ptr text
    ldy at_col
    ; fall through

; print_at — prints the string at ZP_PTR at row X, column Y.  Clobbers A, X, Y.
print_at:
    stx ZP_TMP0
    sty ZP_TMP1
    jmp c64_print_at

; text_send — ends the buffer with CR LF and sends it.  Carry set if a write to
; the pipe failed.  Clobbers A, X, Y.
text_send:
    lda #13
    jsr buf_putc
    lda #10
    jsr buf_putc
    lda #0
    jsr buf_putc
    set_ptr text
    jmp pipe_log

; put_bounded — the string at ZP_PTR, stopping at its terminator or after X
; characters.  Clobbers A, X, Y.
put_bounded:
    ldy #0
    lda (ZP_PTR_LO), y
    beq @done
    jsr buf_putc
    inc ZP_PTR_LO
    bne @next
    inc ZP_PTR_HI
@next:
    dex
    bne put_bounded
@done:
    rts

; put_sp_hex — a space, then the byte at offset A of the entry at ZP_ENT in
; hex.  Clobbers A, X, Y.
put_sp_hex:
    tay
    lda (ZP_ENT_LO), y
    pha
    lda #' '
    jsr buf_putc
    pla
    jmp byte_to_hex

; put_bytes — A bytes of the entry at ZP_ENT from offset X, each as
; put_sp_hex writes it.  Clobbers A, X, Y.
put_bytes:
    sta put_n
    stx put_i
@next:
    lda put_i
    jsr put_sp_hex
    inc put_i
    dec put_n
    bne @next
    rts

; put_frame — the group, the command and at most A of the arguments, with a +
; where there were more.  Clobbers A, X, Y.
put_frame:
    sta diag_tmp
    ldy #ENT_COUNT
    lda (ZP_ENT_LO), y
    cmp diag_tmp
    bcc @fits
    lda diag_tmp
@fits:
    clc
    adc #ENT_ARGS               ; plus the group and command
    ldx #ENT_GROUP
    jsr put_bytes
    ldy #ENT_COUNT
    lda (ZP_ENT_LO), y
    cmp diag_tmp
    beq @done
    bcc @done
    lda #'+'
    jmp buf_putc
@done:
    rts

; put_hdr — the header the entry at ZP_ENT recorded.  Clobbers A, X, Y.
put_hdr:
    lda #HDR_LEN
    ldx #ENT_HDR
    jmp put_bytes

; put_late_hdr — the header diag_late read last.  ZP_ENT is pointed so that
; late_hdr is where an entry's header would be.  Clobbers A, X, Y.
put_late_hdr:
    lda #<(late_hdr - ENT_HDR)
    sta ZP_ENT_LO
    lda #>(late_hdr - ENT_HDR)
    sta ZP_ENT_HI
    jmp put_hdr

; put_stage — the entry's result.  Clobbers A, X, Y.
put_stage:
    ldy #ENT_STAGE
    lda (ZP_ENT_LO), y
    asl a
    tax
    lda stage_word, x
    sta ZP_PTR_LO
    lda stage_word + 1, x
    sta ZP_PTR_HI
    jmp buf_puts

; put_ms — the entry's time.  Clobbers A, X, Y.
put_ms:
    ldy #ENT_MS + 1
    lda (ZP_ENT_LO), y
    tax
    dey
    lda (ZP_ENT_LO), y
    jsr buf_dec16
    put_str str_ms
    rts

; put_late — diag_late's result and when it stopped polling.  Clobbers A,
; X, Y.
put_late:
    lda late_state
    asl a
    tax
    lda late_word, x
    sta ZP_PTR_LO
    lda late_word + 1, x
    sta ZP_PTR_HI
    jsr buf_puts
    lda late_ms
    ldx late_ms + 1
    jsr buf_dec16
    put_str str_ms
    rts

; put_device — the device's type and version.  Clobbers A, Y.
put_device:
    put_str str_device
    put_str dev_type
    lda #' '
    jsr buf_putc
    put_str dev_ver
    rts

; put_app — this bootloader, the video standard and the image.  Clobbers A,
; Y.
put_app:
    put_str str_app
    set_ptr str_ntsc
    lda diag_pal
    beq @std
    set_ptr str_pal
@std:
    jsr buf_puts
    put_str str_image
    rts

; ---------------------------------------------------------------------------
; Strings
; ---------------------------------------------------------------------------

; Indexed by stage, as rbcp_stage.s numbers them.
stage_word:
    .word str_ok, str_not_received, str_not_completed, str_failed

; Indexed by late_state.  Entry 0 is never drawn.
late_word:
    .word 0, str_completed_in, str_not_received_in, str_not_completed_in

; Indexed by report.
report_says:
    .word str_lost, str_no_pipe, str_cut, str_reported

str_command:          .byte "COMMAND ", 0
str_ok:               .byte "OK", 0
str_not_received:     .byte "NOT RECEIVED", 0
str_not_completed:    .byte "NOT COMPLETED", 0
str_failed:           .byte "FAILED", 0

str_completed_in:     .byte "COMPLETED IN ", 0
str_not_received_in:  .byte "NOT RECEIVED IN ", 0
str_not_completed_in: .byte "NOT COMPLETED IN ", 0

str_prompt:           .byte "CAPTURE DIAGS THEN PRESS RETURN", 0
str_lost:             .byte "DEVICE NOT RESPONDING. REPORT NOT SENT", 0
str_no_pipe:          .byte "PIPE 0 UNAVAILABLE. REPORT NOT SENT", 0
str_cut:              .byte "REPORT PARTLY SENT TO PIPE 0", 0
str_reported:         .byte "REPORT SENT TO PIPE 0", 0

str_head:             .byte " COMMAND            RESULT        TIME", 0
str_sent:             .byte "SENT", 0
str_token:            .byte " TOKEN", 0
str_header:           .byte " HEADER", 0
str_ms:               .byte "MS", 0
str_device:           .byte "DEVICE ", 0
str_of:               .byte " OF ", 0
str_listed:           .byte " FLASH SLOTS LISTED", 0
str_slots_failed:     .byte "FLASH SLOT LIST FAILED", 0
str_slot:             .byte "SLOT ", 0
str_type:             .byte " TYPE ", 0
str_end:              .byte "END", 0
str_pal:              .byte " PAL", 0
str_ntsc:             .byte " NTSC", 0
.ifdef COMBINED
str_image:            .byte " COMBINED", 0
.else
str_image:            .byte " KERNAL", 0
.endif
