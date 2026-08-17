; pipe_test.s — entry, exit, interrupts and key scanning
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Entered from BASIC by SYS 2061 and returns to BASIC by rts, so the machine
; must be handed back exactly as it was found.  What this file takes and gives
; back, in order: the stack pointer, interrupts, zero page $D0-$FF, the border
; and background colours, the CIA2 timers, and the NMI vector.
;
; sei comes second, before the zero page save and before anything reads
; $A000-$BFFF.  The kernal's raster IRQ scans the keyboard through KEYLOG at
; $F5/$F6 on every frame, which is inside the block this program is about to
; take, so leaving interrupts on for even the save would have the two fighting.

    .include "pipe_defs.s"

.import display_init
.import display_status
.import display_labels
.import display_paths
.import display_counters
.import session_start
.import session_end
.import session_open
.import timing_start
.import timing_stop
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
.import armed_flag

; ---------------------------------------------------------------------------
; PRG header and BASIC stub
; ---------------------------------------------------------------------------

.segment "LOADADDR"
    .word $0801

; 10 SYS 2061
.segment "BASICSTUB"
    .byte $0B, $08          ; link to the end-of-program marker at $080B
    .byte $0A, $00          ; line number 10
    .byte $9E               ; SYS token
    .byte "2061"
    .byte $00               ; end of line
    .byte $00, $00          ; end of program

; The entry point has a segment of its own so that SYS 2061 lands on it
; whatever order the linker puts the CODE segment's contributors in.
.segment "ENTRY"
    jmp main

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

saved_sp:       .res 1
saved_zp:       .res ZP_SAVE_COUNT
saved_border:   .res 1
saved_bg:       .res 1
saved_nmi:      .res 2

.export nmi_flag
nmi_flag:       .res 1

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
; main — SYS 2061 arrives here with interrupts on and the kernal live.
; ---------------------------------------------------------------------------

main:
    tsx
    stx saved_sp
    sei                         ; before the first use of $D0-$FF

    ldx #0
@save_zp:
    lda ZP_SAVE_BASE, x
    sta saved_zp, x
    inx
    cpx #ZP_SAVE_COUNT
    bne @save_zp

    lda VIC_BORDER
    sta saved_border
    lda VIC_BACKGROUND
    sta saved_bg

    lda #0
    sta armed_flag
    sta run_number
    lda #PATH_TUNED4
    sta run_path

    jsr nmi_install
    jsr timing_start
    jsr display_init
    jsr display_labels
    jsr display_paths
    jsr timing_reset_run
    jsr display_counters

    jsr session_start
    bcs menu                    ; the reason is already on the status row
    lda #1
    sta armed_flag
    ; fall through

; ---------------------------------------------------------------------------
; menu — the program's resting state, inside the open session.
;
; Selections are taken on release rather than on press.  scan_key's debounce is
; about 200 cycles, so a held key would otherwise repeat.
;
; Nothing here reads $A000-$BFFF.  The keyboard is CIA1 and the screen is RAM,
; so the session is undisturbed for as long as this loop runs.
; ---------------------------------------------------------------------------

menu:
    jsr scan_key
    cmp #KEY_NONE_CODE
    beq menu
    sta key_held
    jsr wait_no_key

    lda key_held
    cmp #KEY_Q_CODE
    bne @not_q
    jmp quit
@not_q:

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
    bne @not_3_j
    lda #PATH_TUNED4
    jmp @select
@not_3_j:
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
; The banner goes out through the library path whatever is selected: it is one
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
    inc run_number

    lda #0
    sta tuned_mode              ; the banner is never mirrored
    jsr build_banner
    lda #RBCP_PIPE_WRITE_MAX
    sta chunk_count
    jsr send_lib_line
    bcc @banner_ok
    jmp run_lost
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
    sta nmi_flag
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
    jmp run_lost
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
    lda nmi_flag
    bne run_stop

    inc line_tick
    lda line_tick
    and #15
    bne @continue
    jsr scan_return
    beq run_stop
@continue:
    jmp run_loop

run_stop:
    lda #STAT_STOPPED
    jmp run_finish

; A poll that never completed.  tuned_poll jumps straight here, so the stack is
; unwound to where the run loop started rather than returned through.
.export run_abort
run_abort:
    ldx run_sp
    txs
run_lost:
    lda #STAT_LOST

run_finish:
    pha
    lda #0
    sta tuned_mode
    jsr timing_mean
    jsr display_counters
    pla
    jsr display_status
    jsr wait_no_key
    jmp menu

; ---------------------------------------------------------------------------
; build_banner — "#### RUN nn PATH" padded to 62 characters and terminated.
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

@number:
    lda run_number
    ldy #'0' - 1
@tens:
    iny
    sec
    sbc #10
    bcs @tens
    adc #10
    sty line_buf + 9
    clc
    adc #'0'
    sta line_buf + 10

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
    sta line_buf + 12, y
    iny
    bne @name
@done:
    rts

; ---------------------------------------------------------------------------
; scan_return — one column, about 13 cycles.  Z set means RETURN is held.
; A run calls this one line in sixteen, so a stop is seen within about 24 ms.
; Clobbers A.
; ---------------------------------------------------------------------------

scan_return:
    lda #KEY_COL_0
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_RETURN_BIT
    rts

quit:
    jsr session_end
    ; fall through

; ---------------------------------------------------------------------------
; leave — hands the machine back and returns to BASIC.
;
; Order is the reverse of main's.  The kernal clear-screen call comes after the
; zero page restore because the screen editor works through LDTB1 at $D9-$F2,
; which this program has been using.
;
; The release wait comes first.  Without it the key that asked to quit is still
; held when cli runs, the kernal's IRQ scan puts it in the keyboard buffer, and
; BASIC echoes it after READY.  Zeroing NDX afterwards catches anything the IRQ
; managed to buffer between cli and here.
; ---------------------------------------------------------------------------

leave:
    jsr wait_no_key

    jsr timing_stop
    jsr nmi_restore

    lda saved_border
    sta VIC_BORDER
    lda saved_bg
    sta VIC_BACKGROUND

    ldx #0
@restore_zp:
    lda saved_zp, x
    sta ZP_SAVE_BASE, x
    inx
    cpx #ZP_SAVE_COUNT
    bne @restore_zp

    ldx saved_sp
    txs
    cli
    lda #0
    sta KEY_NDX
    jsr KERNAL_CLRSCR
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

.code

; ---------------------------------------------------------------------------
; NMI
;
; RESTORE is edge-triggered through its own monostable rather than through a
; CIA, so nothing needs acknowledging.  The kernal's NMI entry does sei then
; jmp ($0318) without saving registers, so the stub saves the one it uses.
;
; Without this the default handler reaches jmp ($A002) when RUN/STOP is held
; with RESTORE — a read of the command page in the middle of a session, which
; would inject a command byte.  The stub touches nothing else, so an NMI
; arriving mid-command stretches the frame in time but does not corrupt it.
; ---------------------------------------------------------------------------

nmi_stub:
    pha
    lda #1
    sta nmi_flag
    pla
    rti

nmi_install:
    lda #0
    sta nmi_flag
    lda NMINV
    sta saved_nmi
    lda NMINV+1
    sta saved_nmi+1
    lda #<nmi_stub
    sta NMINV
    lda #>nmi_stub
    sta NMINV+1
    rts

nmi_restore:
    lda saved_nmi
    sta NMINV
    lda saved_nmi+1
    sta NMINV+1
    rts

; ---------------------------------------------------------------------------
; scan_key — returns a key code in A, KEY_NONE_CODE if nothing is held.
;
; Four column selects cover all six keys this program uses.  A run does not
; call this: it scans RETURN alone, one line in sixteen, which is one column.
;
; Clobbers A, X.
; ---------------------------------------------------------------------------

.export scan_key
scan_key:
    lda #KEY_COL_7
    sta CIA1_PRA
    lda CIA1_PRB
    tax
    and #KEY_1_BIT
    bne @c7_2
    lda #KEY_1_CODE
    bne @debounce               ; always taken
@c7_2:
    txa
    and #KEY_2_BIT
    bne @c7_q
    lda #KEY_2_CODE
    bne @debounce               ; always taken
@c7_q:
    txa
    and #KEY_Q_BIT
    bne @col_1
    lda #KEY_Q_CODE
    bne @debounce               ; always taken

@col_1:
    lda #KEY_COL_1
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_3_BIT
    bne @col_2
    lda #KEY_3_CODE
    bne @debounce               ; always taken

@col_2:
    lda #KEY_COL_2
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_T_BIT
    bne @col_0
    lda #KEY_T_CODE
    bne @debounce               ; always taken

@col_0:
    lda #KEY_COL_0
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_RETURN_BIT
    bne @none
    lda #KEY_RET_CODE
@debounce:
    ldx #DEBOUNCE_COUNT
@dly:
    dex
    bne @dly
    rts
@none:
    lda #KEY_NONE_CODE
    rts

; ---------------------------------------------------------------------------
; wait_no_key — spins until nothing is held.  Clobbers A, X.
; ---------------------------------------------------------------------------

.export wait_no_key
wait_no_key:
    jsr scan_key
    cmp #KEY_NONE_CODE
    bne wait_no_key
    rts
