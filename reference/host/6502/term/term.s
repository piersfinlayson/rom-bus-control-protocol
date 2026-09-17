; term.s — the line being typed, and what happens to it at RETURN
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; term_run is where the machine arrives once its own code has put the terminal
; in RAM, and it does not return.  There is no exit: the terminal is a ROM
; image the device serves, so the only way out is to switch the machine off,
; which reloads the device's RAM slot from flash and leaves the served image as
; it was built.
;
; A line goes down the outbound pipe with a carriage return and a line feed
; behind it, and only reaches the text area once the device has taken all of
; it.  So a line still on the input row is a line that has not gone.
;
; Bytes come the other way on a second pipe, which is read once a second while
; nobody is typing.  There is no clock here to count, so the wait is counted in
; passes of the main loop and PLAT_POLL_LOOPS says how many a machine takes.

    .include "term_defs.s"

.import plat_init
.import plat_key
.if PLAT_DARK
.import plat_dark
.import plat_light
.endif

.import display_init
.import display_input
.import display_typed
.import display_deleted
.import display_status
.import display_sent
.import display_device
.import display_rx_byte
.import display_rx_close

.import session_start
.import session_open
.import pipe_out
.import pipe_in

.import rbcp_cmd_pipe_write
.import rbcp_cmd_pipe_read
.import rbcp_recover

.ifdef SELFTEST
.import selftest_key
.import selftest_start
.endif

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export line_buf
.export line_len

line_buf:   .res LINE_BUF_SIZE  ; the line, and the two bytes that end it
line_len:   .res 1              ; how much of it has been typed

armed_flag: .res 1              ; non-zero while there is a session to send down
send_len:   .res 1              ; the line plus its carriage return and line feed
send_pos:   .res 1
chunk_len:  .res 1
tries_left: .res 1          ; refusals left on this chunk
fault_stat: .res 1              ; the status a failed line ended with

rx_armed:   .res 1              ; non-zero while a pipe brings bytes back
poll_lo:    .res 1              ; main loop passes left before the next read
poll_hi:    .res 1
burst_left: .res 1              ; back to back reads left in this poll
rx_len:     .res 1              ; bytes the last read returned
rx_pos:     .res 1              ; how far through them the screen has got
rx_wait:    .res 1              ; what the device said was still waiting

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; term_run — entered from the machine's reset code, running from RAM.
; ---------------------------------------------------------------------------

.export term_run
term_run:
    lda #0
    sta armed_flag
    sta line_len

    jsr plat_init
.ifdef SELFTEST
    jsr selftest_start
.endif
    jsr display_init

.if PLAT_DARK
    jsr plat_dark
.endif
    jsr session_start
.if PLAT_DARK
    jsr plat_light
.endif
    bcs main                    ; the reason is already on the status bar

    lda #1
    sta armed_flag

    ; A device with no inbound pipe is one this terminal can only talk at.
    ; That is every device built before the firmware that added the second
    ; pipe, so the terminal runs send-only on one rather than refusing to open.
    lda #0
    sta rx_armed
    lda pipe_in
    cmp #PIPE_NONE
    beq @no_rx
    inc rx_armed
@no_rx:
    jsr poll_reload

    jsr display_device
    jsr show_ready

; ---------------------------------------------------------------------------
; main — a key at a time.  Nothing here reads the served image: the keyboard
; and the screen are the machine's own, so the session is undisturbed for as
; long as nobody presses RETURN.
; ---------------------------------------------------------------------------

main:
    jsr key_get
    cmp #KEY_NONE_CODE
    beq idle
    cmp #KEY_RET_CODE
    beq send_line
    cmp #KEY_DEL_CODE
    beq delete_char

    cmp #CHAR_FIRST
    bcc main
    cmp #CHAR_PUNCT_END
    bcc @take
    cmp #CHAR_ALPHA
    bcc main
    cmp #CHAR_ALPHA_END
    bcs main
@take:
    ldx line_len
    cpx #LINE_MAX
    bcs main                    ; the line is full, so the key does nothing
    sta line_buf, x
    inc line_len
    jsr display_typed
    jmp main

delete_char:
    lda line_len
    beq main
    dec line_len
    jsr display_deleted
    jmp main

; ---------------------------------------------------------------------------
; idle — no key this pass, so the receive pipe gets a pass of the counter.
; ---------------------------------------------------------------------------

idle:
    jsr poll_tick
    jmp main

; ---------------------------------------------------------------------------
; key_get — a key press, once per press, in ASCII, or KEY_NONE_CODE.
;
; The self-typing build reads a table instead of the keyboard, so that a
; machine with nobody at it sends known lines and the far end can be checked
; against them.
; ---------------------------------------------------------------------------

key_get:
.ifdef SELFTEST
    jmp selftest_key
.else
    jmp plat_key
.endif

; ---------------------------------------------------------------------------
; send_line — RETURN.  The line goes out with a carriage return and a line feed
; behind it, four bytes to a PIPE_WRITE.
; ---------------------------------------------------------------------------

send_line:
    lda armed_flag
    bne @armed
    lda #STAT_NOT_ARMED
    jsr display_status
    jmp main
@armed:
    ldx line_len
    lda #13
    sta line_buf, x
    inx
    lda #10
    sta line_buf, x
    inx
    stx send_len

.if PLAT_DARK
    jsr plat_dark
.endif
    jsr write_line
.if PLAT_DARK
    jsr plat_light
.endif
    bcs @failed

    jsr display_sent
    lda #0
    sta line_len
    jsr display_input
    jsr show_ready
    jmp main

; A line that did not go stays on the input row, so RETURN sends it again.  A
; device that stopped answering is put back together first, and one that does
; not come back leaves the terminal with nothing to send down.
@failed:
    lda fault_stat
    jsr display_status
    lda fault_stat
    cmp #STAT_PIPE_FULL
    beq @back
    jsr recover
@back:
    jmp main

; ---------------------------------------------------------------------------
; write_line — the whole of send_len, four bytes at a time.
;
; PIPE_WRITE takes all the bytes it is offered or none, so a refusal resends
; the same ones.  A refusal is the pipe being full, which is the far end not
; reading, and it is given FULL_TRIES goes before the line is given up on.
; The gather runs again on each go because it costs nothing here and puts the
; question of what the library leaves in the arguments beyond reach.
;
; Returns carry clear sent, carry set with the reason in fault_stat.
; Clobbers A, X, Y and the RBCP arguments.
; ---------------------------------------------------------------------------

write_line:
    lda #0
    sta send_pos

@chunk:
    lda #<FULL_TRIES
    sta tries_left

    lda send_len
    sec
    sbc send_pos
    beq @done
    cmp #RBCP_PIPE_WRITE_MAX
    bcc @have
    lda #RBCP_PIPE_WRITE_MAX
@have:
    sta chunk_len

@gather:
    ldy send_pos
    ldx #0
@byte:
    lda line_buf, y
    sta rbcp_arg0, x
    iny
    inx
    cpx chunk_len
    bne @byte

    lda chunk_len
    ldx pipe_out
    jsr rbcp_cmd_pipe_write
    bcc @taken

    lda rbcp_zp_5
    cmp #STAGE_REFUSED
    bne @stage
    dec tries_left
    bne @gather
    lda #STAT_PIPE_FULL
    sta fault_stat
    sec
    rts

@stage:
    cmp #STAGE_NOT_TAKEN
    bne @unfinished
    lda #STAT_NO_ANSWER
    sta fault_stat
    sec
    rts
@unfinished:
    lda #STAT_NO_COMPLETE
    sta fault_stat
    sec
    rts

@taken:
    lda send_pos
    clc
    adc chunk_len
    sta send_pos
    jmp @chunk

@done:
    clc
    rts

; ---------------------------------------------------------------------------
; show_ready — the bar, saying whether this device talks back.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

show_ready:
    lda rx_armed
    bne @both
    lda #STAT_SEND_ONLY
    bne @show                   ; always, the code not being zero
@both:
    lda #STAT_READY
@show:
    jmp display_status

; ---------------------------------------------------------------------------
; poll_tick — one pass of the main loop off the counter, and a read of the
; receive pipe when it runs out.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

poll_tick:
    lda poll_lo
    sec
    sbc #1
    sta poll_lo
    lda poll_hi
    sbc #0
    sta poll_hi
    ora poll_lo
    bne @waiting
    jsr poll_reload
    jmp read_pipe
@waiting:
    rts

poll_reload:
    lda #<PLAT_POLL_LOOPS
    sta poll_lo
    lda #>PLAT_POLL_LOOPS
    sta poll_hi
    rts

; ---------------------------------------------------------------------------
; read_pipe — what the far end has sent, on the screen.
;
; Reads run back to back while the device says more is waiting, up to
; RX_BURST_MAX, so a burst arrives at the speed the back channel allows rather
; than a read a second.  The keyboard is unread for the whole of it.
;
; Clobbers A, X, Y, the app zero page and the RBCP arguments.
; ---------------------------------------------------------------------------

read_pipe:
    lda armed_flag
    beq @out
    lda rx_armed
    beq @out

    lda #RX_BURST_MAX
    sta burst_left

@read:
.if PLAT_DARK
    jsr plat_dark
.endif
    jsr read_once
.if PLAT_DARK
    jsr plat_light
.endif
    bcs @failed

    lda rx_wait
    beq @out                    ; nothing waiting, so back to the keyboard
    dec burst_left
    bne @read
@out:
    rts

; A read that did not happen leaves any row it was filling closed, so what
; arrives next starts a fresh one rather than running on from a gap.
;
; A device that did not answer is put back together, as a line that would not
; go is.  One that answered and said no is refusing the pipe number or the room
; for the answer, which a second later will be just as wrong, so reading stops
; and the bar says so.
@failed:
    jsr display_rx_close
    lda rbcp_zp_5
    cmp #STAGE_REFUSED
    beq @refused
    jmp recover
@refused:
    lda #0
    sta rx_armed
    lda #STAT_RX_FAIL
    jmp display_status

; ---------------------------------------------------------------------------
; read_once — one read, and what it returned on the screen.
;
; The reading and the drawing are one piece of work because the bytes are in
; the served image, so both belong inside whatever window the machine needs to
; read it safely - on the C64, the display being off.
;
; Returns carry clear read, with what is still waiting in rx_wait, carry set
; with the stage in rbcp_zp_5.
; Clobbers A, X, Y, the app zero page and the RBCP arguments.
; ---------------------------------------------------------------------------

read_once:
    lda #RX_MAX
    ldx pipe_in
    jsr rbcp_cmd_pipe_read
    bcs @failed
    jsr show_bytes
    sta rx_wait
    clc
    rts
@failed:
    sec
    rts

; ---------------------------------------------------------------------------
; show_bytes — the bytes the read returned, on the screen.
;
; Returns the device's count of what is still waiting in A, with the flags set
; from it, so a caller knows whether to go round again.
;
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

show_bytes:
    lda RBCP_DATA_ADDR + RBCP_PIPE_READ_FLAGS
    and #RBCP_PIPE_READ_FLAG_FULL
    beq @counted
    lda #RX_MAX                 ; the count asked for is the count that came
    bne @have                   ; always, RX_MAX not being zero
@counted:
    lda RBCP_DATA_ADDR + RBCP_PIPE_READ_COUNT
@have:
    sta rx_len
    beq @done                   ; the pipe was empty, which is not a failure

    ldy #0
@byte:
    lda RBCP_DATA_ADDR + RBCP_PIPE_READ_DATA, y
    sty rx_pos
    jsr display_rx_byte
    ldy rx_pos
    iny
    cpy rx_len
    bne @byte

@done:
    lda RBCP_DATA_ADDR + RBCP_PIPE_READ_WAITING
    rts

; ---------------------------------------------------------------------------
; recover — the device stopped answering, so put it back together.
;
; The sequence is common/rbcp_recover.s, which every host that has to do this
; shares.  What belongs to this program is the flag, and it follows the device.
; Clobbers A, X, Y and the RBCP arguments.
; ---------------------------------------------------------------------------

recover:
.if PLAT_DARK
    jsr plat_dark
.endif
    jsr rbcp_recover
.if PLAT_DARK
    jsr plat_light
.endif
    bcs @gone
    lda #1
    sta session_open
    rts
@gone:
    lda #0
    sta session_open
    sta armed_flag
    sta rx_armed
    lda #STAT_NO_RECOVER
    jmp display_status
