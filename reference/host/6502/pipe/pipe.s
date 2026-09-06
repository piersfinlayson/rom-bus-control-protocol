; pipe.s — the menu, the run loop, and the line that marks a run
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; pipe_run is where the machine arrives once its own code has put the tester in
; RAM, and it does not return.  There is no exit: the tester is a ROM image the
; device serves, so the only way out is to switch the machine off, which
; reloads the device's RAM slot from flash and leaves the served image as it
; was built.

    .include "pipe_defs.s"

.import plat_init
.import plat_key
.import plat_key_stop
.import plat_key_wait_none
.import plat_abort_flag
.import plat_clock_start
.if PLAT_DARK
.import plat_dark
.import plat_light
.endif

.import display_init
.import display_status
.import display_labels
.import display_paths
.import display_counters
.import session_start
.import timing_reset_run
.import timing_mean
.import timing_open_window
.import timing_window_closed
.import timing_close_window
.import timing_add_line
.import secs
.import line_buf
.import line_reset
.import line_next
.import line_to_tuned
.import tuned_mode
.import send_lib_line
.import send_tuned_line
.import chunk_count
.import fault_stat
.import fault_lost
.import fault_recover

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export armed_flag
armed_flag:     .res 1      ; non-zero once the session is open and checked

.export run_path
run_path:       .res 1      ; PATH_LIB4, PATH_LIB1 or PATH_TUNED4
key_held:       .res 1
run_timed:      .res 1      ; non-zero for a fixed length run
run_number:     .res 1
line_tick:      .res 1
run_sp:         .res 1      ; stack pointer at the top of the run loop

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; pipe_run — entered from the machine's reset code, running from RAM.
; ---------------------------------------------------------------------------

.export pipe_run
pipe_run:
    lda #0
    sta armed_flag
    sta run_number
    lda #PATH_TUNED4
    sta run_path

    jsr plat_init
    jsr plat_clock_start
    jsr display_init
    jsr display_labels
    jsr display_paths
    jsr timing_reset_run
    jsr display_counters

.if PLAT_DARK
    jsr plat_dark
.endif
    jsr session_start
.if PLAT_DARK
    jsr plat_light
.endif
    bcs menu                    ; the reason is already on the status row
    lda #1
    sta armed_flag
    ; fall through

; ---------------------------------------------------------------------------
; menu — the tester's resting state, inside the open session.
;
; Selections are taken on release rather than on press, so a held key does not
; repeat.
;
; Nothing here reads the served image.  The keyboard and the screen are the
; machine's own, so the session is undisturbed for as long as this loop runs.
; ---------------------------------------------------------------------------

menu:
    jsr plat_key
    cmp #KEY_NONE_CODE
    beq menu
    sta key_held
    jsr plat_key_wait_none

    lda key_held
    cmp #KEY_1_CODE
    bne @not_1
    lda #PATH_LIB4
    jmp @select
@not_1:
    cmp #KEY_2_CODE
    bne @not_2
    lda #PATH_LIB1
    jmp @select
@not_2:
    cmp #KEY_3_CODE
    bne @not_3
    lda #PATH_TUNED4
    jmp @select
@not_3:
    cmp #KEY_RET_CODE
    bne @not_ret
    lda #0
    jmp start_run
@not_ret:
    cmp #KEY_T_CODE
    beq @timed
    jmp menu
@timed:
    lda #1
    jmp start_run

@select:
    sta run_path
    jsr display_paths
    jmp menu

; ---------------------------------------------------------------------------
; start_run — A = 0 continuous, non-zero for a fixed ten seconds.
;
; The banner goes out through the library path whatever is selected — it is one
; line, once, and it is what marks a run boundary for the reader and for the
; checking tool.
; ---------------------------------------------------------------------------

TIMED_SECS = 10

start_run:
    sta run_timed
    ldx armed_flag
    bne @armed
    lda #STAT_NOT_ARMED
    jsr display_status
    jmp menu
@armed:
.if PLAT_DARK
    jsr plat_dark               ; until run_finish, however the run ends
.endif
    inc run_number

    lda #STAT_STOPPED           ; how a run ends unless something says otherwise
    sta fault_stat
    lda #0
    sta fault_lost
    sta tuned_mode              ; the banner is never mirrored
    jsr build_banner
    lda #RBCP_PIPE_WRITE_MAX
    sta chunk_count
    jsr send_lib_line
    bcc @banner_ok
    jmp run_finish
@banner_ok:

    jsr line_reset
    lda run_path
    cmp #PATH_TUNED4
    bne @lib
    jsr line_to_tuned
    jmp @counters
@lib:
    lda #RBCP_PIPE_WRITE_MAX
    ldx run_path
    cpx #PATH_LIB1
    bne @chunked
    lda #1
@chunked:
    sta chunk_count

@counters:
    jsr timing_reset_run
    lda #0
    sta line_tick
    sta plat_abort_flag
    lda #STAT_RUNNING
    jsr display_status
    jsr display_counters
    jsr timing_open_window

    tsx
    stx run_sp                  ; where run_abort unwinds to

run_loop:
    lda tuned_mode
    beq @via_lib
    jsr send_tuned_line
    jmp @sent
@via_lib:
    jsr send_lib_line
    bcc @sent
    jmp run_finish
@sent:
    jsr timing_add_line
    jsr line_next

    jsr timing_window_closed
    bcc @no_window
    jsr timing_close_window
    jsr display_counters
    lda run_timed
    beq @no_window
    lda secs + 1
    bne run_stop
    lda secs
    cmp #TIMED_SECS
    bcs run_stop

@no_window:
    lda plat_abort_flag
    bne run_stop

    inc line_tick
    lda line_tick
    and #15
    bne @continue
    jsr plat_key_stop
    beq run_stop
@continue:
    jmp run_loop

run_stop:
    lda #STAT_STOPPED
    sta fault_stat
    jmp run_finish

; A device that stopped answering.  tuned_poll jumps straight here, so the
; stack is unwound to where the run loop started rather than returned through.
.export run_abort
run_abort:
    ldx run_sp
    txs
    ; fall through

; ---------------------------------------------------------------------------
; run_finish — every way out of a run, with fault_stat holding which.
;
; The reason a run ended stays on the status row afterwards, including where
; the device was brought back, because that is the thing worth reading.  Only a
; device that did not come back replaces it, and then the tester is no longer
; armed and the next attempt to run says so.
; ---------------------------------------------------------------------------

run_finish:
    lda #0
    sta tuned_mode
    jsr timing_mean
    jsr display_counters
    lda fault_stat
    jsr display_status

    lda fault_lost
    beq @done
    jsr fault_recover
    bcc @done
    lda #STAT_NO_RECOVER
    jsr display_status
@done:
.if PLAT_DARK
    jsr plat_light
.endif
    jsr plat_key_wait_none
    jmp menu

; ---------------------------------------------------------------------------
; build_banner — "#### RUN nnn PATH" padded to 62 characters and terminated.
; Written straight into line_buf, not through line_store, because the banner is
; never mirrored into the block.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

build_banner:
    ldx #0
    lda #' '
@blank:
    sta line_buf, x
    inx
    cpx #62
    bne @blank
    lda #13
    sta line_buf + 62
    lda #10
    sta line_buf + 63

    ldx #0
@hash:
    lda #'#'
    sta line_buf, x
    inx
    cpx #4
    bne @hash

    ldy #0
@run_word:
    lda str_run_word, y
    beq @number
    sta line_buf + 5, y
    iny
    bne @run_word

    ; Three digits, because run_number is a byte and two of them walk past '9'
    ; at a hundred runs.
@number:
    lda run_number
    ldx #'0' - 1
@hundreds:
    inx
    sec
    sbc #100
    bcs @hundreds
    adc #100
    stx line_buf + 9
    ldy #'0' - 1
@tens:
    iny
    sec
    sbc #10
    bcs @tens
    adc #10
    sty line_buf + 10
    clc
    adc #'0'
    sta line_buf + 11

    lda run_path
    asl a
    tax
    lda path_name_tab, x
    sta ZP_APP0
    lda path_name_tab + 1, x
    sta ZP_APP1
    ldy #0
@name:
    lda (ZP_APP0), y
    beq @done
    sta line_buf + 13, y
    iny
    bne @name
@done:
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

str_run_word:
    .byte "RUN", 0

path_name_tab:
    .word str_lib4, str_lib1, str_tuned4
str_lib4:
    .byte "LIB4", 0
str_lib1:
    .byte "LIB1", 0
str_tuned4:
    .byte "TUNED4", 0
