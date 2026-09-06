; fault.s — what happens when a write does not go through
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; A send path calls in here whenever rbcp_cmd_pipe_write, or the hand-written
; poll that stands in for it, comes back with anything other than success.
; What comes out is one of two answers: send the same bytes again, or end the
; run, with the reason in fault_stat.
;
; The three ways a command can fail are the three the library reports in
; rbcp_zp_5, named in common/rbcp_stage.s, and they are different faults with
; different repairs:
;
;   not taken   the token never moved — nothing received the command
;   unfinished  it moved and the command never completed — the device is stuck
;   refused     the device answered and said failure
;
; The first two mean the device is not in a state to be talked to, so the run
; ends and the device is put back together.  A refusal is the interesting one — a
; PIPE_WRITE answer is one byte, so a refusal alone does not say whether the
; pipe was full — the legitimate case, and worth retrying — or whether the
; device is answering about a command this program never sent.  GET_PIPE_INFO
; is what tells the two apart, and the retry is bounded either way.  A loop
; that can hang the machine is worse than the condition it guards.

    .include "pipe_defs.s"

.import rbcp_cmd_get_pipe_info
.import rbcp_recover

.import errors
.import refusals
.import armed_flag
.import session_open

.import plat_abort_flag
.import plat_key_stop

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export fault_stat
.export fault_lost
.export fault_stall

fault_stat:     .res 1      ; the status code that ended the run
fault_lost:     .res 1      ; non-zero when the device needs putting together

; Non-zero while a stall is open.  A send path clears this at the top of each
; line — five cycles a line — which is what makes the stall timeout a bound on
; one line rather than on the whole run.
fault_stall:    .res 1

stall_tb:       .res 1      ; the clock when the stall opened
burst_left:     .res 1      ; immediate retries left before asking the pipe
saw_room:       .res 1      ; the pipe reported room for the refused bytes

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; fault_note — A = the status that ended the run.  The device is marked as
; needing a recovery, and the error count moves.
; Clobbers A.
; ---------------------------------------------------------------------------

.export fault_note
fault_note:
    sta fault_stat
    lda #1
    sta fault_lost
    ; fall through

fault_count:
    inc errors
    bne @done
    inc errors + 1
@done:
    rts

; ---------------------------------------------------------------------------
; fault_stage — A = the stage in rbcp_zp_5, one of the two the device did not
; answer.  Ends the run naming which.
; Clobbers A.
; ---------------------------------------------------------------------------

.export fault_stage
fault_stage:
    cmp #STAGE_NOT_TAKEN
    bne @unfinished
    lda #STAT_NO_ANSWER
    jmp fault_note
@unfinished:
    lda #STAT_NO_COMPLETE
    jmp fault_note

; ---------------------------------------------------------------------------
; fault_write_refused — the device answered a PIPE_WRITE with failure.
;
; A = the number of bytes it was offered.
;
; A burst of immediate retries comes first, because a pipe that is momentarily
; full is the case the retry exists for and it costs one branch.  When the
; burst runs out GET_PIPE_INFO says how much room the pipe has now.  Room for
; the bytes that were just refused, twice over, is not fullness — it is a
; device answering about something else — so the run ends and says so.
;
; Where the pipe really is full the wait continues, but the stop key and the
; machine's own abort are read on every round and the whole stall is bounded at
; STALL_SECS.
;
; Returns carry clear to send the same bytes again, carry set to end the run
; with fault_stat holding the reason.
; Clobbers A, X, Y and ZP_APP7.
; ---------------------------------------------------------------------------

.export fault_write_refused
fault_write_refused:
    sta ZP_APP7                     ; bytes offered

    inc refusals
    bne @counted
    inc refusals + 1
@counted:

    lda fault_stall
    bne @burst
    inc fault_stall                 ; a stall has begun
    PLAT_CLOCK_READ
    sta stall_tb
    lda #0
    sta saw_room
    lda #FAULT_BURST
    sta burst_left

@burst:
    dec burst_left
    beq @ask
    clc                             ; the same bytes, at once
    rts

@ask:
    lda #FAULT_BURST
    sta burst_left

    lda #0                          ; pipe 0
    jsr rbcp_cmd_get_pipe_info
    bcc @have_info
    lda rbcp_zp_5
    cmp #STAGE_REFUSED
    beq @not_full                   ; it refused a question that always answers
    jsr fault_stage                 ; it did not answer at all
    sec
    rts

@have_info:
    lda RBCP_DATA_ADDR + RBCP_PIPE_INFO_FREE
    cmp ZP_APP7
    bcc @full                       ; less room than was offered, so full

    ; Room for them.  A far end that drained between the refusal and this
    ; question would look the same, so the answer has to come twice.
    lda saw_room
    bne @not_full
    inc saw_room
    lda #1
    sta burst_left                  ; ask again on the very next refusal
    clc
    rts

; A refusal that fullness does not explain: either the pipe had room for the
; bytes twice over, or the device refused to say how much room it has.  Both
; are a device answering about a command this program did not send.
@not_full:
    lda #STAT_BAD_REFUSAL
    jsr fault_note
    sec
    rts

@full:
    lda #0
    sta saw_room

    lda plat_abort_flag
    bne @stopped
    jsr plat_key_stop
    beq @stopped

    PLAT_CLOCK_ELAPSED stall_tb
    cmp #STALL_TICKS
    bcc @wait
    lda #STAT_PIPE_STUCK
    sta fault_stat
    jsr fault_count                 ; the device is answering, so nothing to fix
    sec
    rts

@stopped:
    lda #STAT_STOPPED
    sta fault_stat
    sec
    rts

@wait:
    clc
    rts

; ---------------------------------------------------------------------------
; fault_recover — the device is not answering, so put it back together.
;
; The sequence is common/rbcp_recover.s, which every host that has to do this
; shares.  What belongs to this program is the flags, and they follow the
; device.  Where it does not come back the program is not armed, and says so at
; the next attempt to run rather than failing at the first write with READY on
; the screen.
;
; Returns carry clear back in command-response mode, carry set gave up.
; Clobbers A, X, Y and the RBCP arguments.
; ---------------------------------------------------------------------------

.export fault_recover
fault_recover:
    jsr rbcp_recover
    bcs @gone

    lda #1
    sta session_open
    lda #0
    sta fault_lost
    clc
    rts

@gone:
    lda #0
    sta session_open
    sta armed_flag
    sec
    rts
