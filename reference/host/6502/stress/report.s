; report.s — sending the run's history to whatever is on the other end of a pipe
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen is the headline.  It is not the history, and a machine left
; running overnight has a history worth keeping.  So every failure and a
; periodic heartbeat go out of the device over a pipe, as plain text, and the
; machine on the other end keeps it.
;
; A pipe write is itself an RBCP command down the same path as the ones being
; counted, which is why it is used sparingly and why nothing it does is
; counted.  It only has to work while the session is healthy, which is exactly
; when there is something to say.  When the session is not, the log simply
; stops, and where it stopped is itself the answer.
;
; The strings here go on the wire and never on the screen, so they are ASCII
; and are not display.s's.
;
; What a number on a line counts
; ------------------------------
; Every count belongs to whatever the line named last.  A setting word — the
; machine's own variable, then ON or OFF — makes the counts after it that
; setting's, and RUN makes them the whole run's.  Without that a phase line and
; a failure line both said SENT and meant different things.
;
; The phase line's figures are per setting because somebody who presses the key
; mid-phase would otherwise leave a line naming one setting and counting both.
; The failure line's are the run's, because the run is the headline and the line
; has already said which setting the command went out under.

    .include "stress_defs.s"

.import rbcp_cmd_get_pipe_capability
.import rbcp_cmd_get_pipe_info
.import rbcp_cmd_pipe_write

.import num_val
.import num_den
.import num_div
.import num_txt
.import num_first
.import num_dec

.import total_sent
.import total_bad
.import tot_bad
.import vary_sent
.import vary_bad
.import lost
.import vary_idx
.import phase_lo
.import phase_hi

.import fail_stage
.import fail_test
.import fail_group
.import fail_cmd
.import fail_args
.import fail_tok
.import fail_hdr

.import test_names
.if PLAT_VARY
.import plat_vary_word
.endif

; The longest line is a phase line on a machine with two settings.  A setting's
; three numbers cannot all be ten digits at once.  A ten digit count over a
; divisor of d digits leaves a quotient of at most eleven less d, so the error
; count and the ratio together are eleven digits however the two fall.  Twenty
; one digits and the words around them is as much as one setting can take, and
; the run's lost count and the newline come after the second of them.
LINE_MAX = 128

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export report_pipe
.export report_have_pipe

report_pipe:      .res 1        ; the pipe the report goes down
report_have_pipe: .res 1        ; and whether there is one at all

line:       .res LINE_MAX
line_len:   .res 1
scan_pipe:  .res 1
send_idx:   .res 1
chunk_len:  .res 1
send_tries: .res 1
open_tries: .res 1
line_cut:   .res 1        ; the last line ran out of tries part way through
hold_y:     .res 1
vary_at:    .res 1        ; which setting line_setting is writing

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

.macro line_set addr
    lda #<addr
    sta ZP_PTR_LO
    lda #>addr
    sta ZP_PTR_HI
.endmacro

; ---------------------------------------------------------------------------
; report_open — finds a pipe that carries host to device, and says so.
;
; The first pipe reporting OUT is the one, because a device offering more than
; one has no way to tell this program which it would prefer.  A device with no
; pipes, or one whose protocol version predates the group, leaves reporting off
; and the run is read off the screen instead.
;
; The two commands asked here are as likely to be mangled as any other, and
; this runs once, so a single bad one would otherwise cost the whole run its
; log.  Each gets OPEN_TRIES goes.  A mangled command usually comes back as a
; refusal, which is also how an old device answers the first of them, so the
; refusal is not told apart from the rest — the count is what stops this.  A
; device that answers and says it has no pipes is taken at its word.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export report_open
report_open:
    lda #0
    sta report_have_pipe
    sta report_pipe
    sta line_cut

    lda #OPEN_TRIES
    sta open_tries
@ask_cap:
    jsr rbcp_cmd_get_pipe_capability
    bcc @count
    dec open_tries
    bne @ask_cap
    rts
@count:
    lda RBCP_DATA_ADDR + RBCP_PIPE_CAP_COUNT
    beq @none
    sta scan_pipe               ; how many there are, counted back down

    lda #0
@try:
    pha
    lda #OPEN_TRIES
    sta open_tries
@ask_info:
    pla                         ; the pipe number, back on the stack for the
    pha                         ; next go and for @next
    jsr rbcp_cmd_get_pipe_info
    bcc @flags
    dec open_tries
    bne @ask_info
    beq @next                   ; always taken
@flags:
    lda RBCP_DATA_ADDR + RBCP_PIPE_INFO_FLAGS
    and #RBCP_PIPE_FLAG_OUT
    beq @next
    pla
    sta report_pipe
    lda #1
    sta report_have_pipe
    jmp @hello
@next:
    pla
    clc
    adc #1
    cmp scan_pipe
    bne @try
@none:
    rts

@hello:
    jsr line_reset
    line_set str_start
    jsr line_str
    jmp line_send

; ---------------------------------------------------------------------------
; report_phase — where the run has got to, every PHASE_COMMANDS commands.
;
; This is the heartbeat and the result both.  A run left alone says one of
; these every phase, and a log that has stopped saying them has stopped.
;
; Each setting of whatever the machine varies gets its own sent, error and
; ratio.  The run's sent and errors are not here.  They are the two settings
; added, and one ratio over both says how long the run spent in each rather
; than anything about the machine.  Lost is the run's, because a device that
; stopped answering stopped for the run, and RUN in front of it says so.  A
; machine that varies nothing prints one set, unnamed.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export report_phase
report_phase:
    lda report_have_pipe
    bne @go
    rts
@go:
    jsr line_reset
    line_set str_phase
    jsr line_str
    lda phase_hi
    jsr line_hex8
    lda phase_lo
    jsr line_hex8
.if PLAT_VARY
    line_set str_gap
    jsr line_str
    line_set plat_vary_word
    jsr line_str
    line_set str_on
    jsr line_str
    lda #VARY_ON
    jsr line_setting
    line_set str_off
    jsr line_str
    lda #VARY_OFF
    jsr line_setting
.else
    lda #VARY_ON
    jsr line_setting
.endif
    line_set str_run
    jsr line_str
    line_set str_lost
    jsr line_str
    jsr load_lost
    jsr line_num
    jmp line_send

; ---------------------------------------------------------------------------
; report_recovery — A = 0 the device came back, anything else it did not.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export report_recovery
report_recovery:
    tax
    lda report_have_pipe
    beq @out
    jsr line_reset
    cpx #0
    bne @lost
    line_set str_back
    bne @say                    ; always taken
@lost:
    line_set str_gone
@say:
    jsr line_str
    jmp line_send
@out:
    rts

; ---------------------------------------------------------------------------
; report_failure — the whole of the last failure, as one line.
;
; Sent straight away rather than kept, because the session may not survive to
; the next chance.  Where it does not survive, these writes fail too and the
; line is cut short — which the machine reading it can see.
;
; It names the setting the machine was in when the command went out.  The
; phase line's figures are split by setting, and a failure that did not say
; which one could not be put against them.  The counts it ends with are the
; run's, and say RUN, so they are not read as the named setting's.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export report_failure
report_failure:
    lda report_have_pipe
    bne @go
    rts
@go:
    jsr line_reset
    line_set str_fail
    jsr line_str
    lda fail_stage
    jsr line_hex8
.if PLAT_VARY
    line_set str_gap
    jsr line_str
    line_set plat_vary_word
    jsr line_str
    lda vary_idx
    beq @on
    line_set str_off
    jmp @word
@on:
    line_set str_on
@word:
    jsr line_str
.endif
    lda #' '
    jsr line_ch

    lda fail_test
    asl a
    tax
    lda test_names, x
    sta ZP_PTR_LO
    lda test_names + 1, x
    sta ZP_PTR_HI
    jsr line_str

    line_set str_sent
    jsr line_str
    lda fail_group
    jsr line_field
    lda fail_cmd
    jsr line_field
    lda fail_args + 0
    jsr line_field
    lda fail_args + 1
    jsr line_field
    lda fail_args + 2
    jsr line_field
    line_set str_tok
    jsr line_str
    lda fail_tok
    jsr line_hex8

    line_set str_got
    jsr line_str
    lda fail_hdr + 0
    jsr line_field
    lda fail_hdr + 1
    jsr line_field
    lda fail_hdr + 2
    jsr line_field
    lda fail_hdr + 4
    jsr line_field
    lda fail_hdr + 5
    jsr line_hex8

    jsr line_counts
    jmp line_send

; ---------------------------------------------------------------------------
; The line buffer
; ---------------------------------------------------------------------------

line_reset:
    lda #0
    sta line_len
    rts

; line_ch — A = character.  Anything past the buffer is dropped rather than
; written over what is behind it.  Clobbers X.
line_ch:
    ldx line_len
    cpx #LINE_MAX
    bcs @full
    sta line, x
    inc line_len
@full:
    rts

; line_str — the null-terminated string at ZP_PTR.  Clobbers A, X, Y.
line_str:
    ldy #0
@ch:
    lda (ZP_PTR_LO), y
    beq @done
    sty hold_y
    jsr line_ch
    ldy hold_y
    iny
    bne @ch
@done:
    rts

; line_hex8 — A = value, as two digits.  Clobbers A, X, Y.
line_hex8:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr @nybble
    pla
    and #$0F
@nybble:
    cmp #10
    bcc @digit
    clc
    adc #'A' - 10
    bne @put                    ; always taken
@digit:
    clc
    adc #'0'
@put:
    jmp line_ch

; line_field — A = value, as a space and two digits.  Clobbers A, X, Y.
line_field:
    pha
    lda #' '
    jsr line_ch
    pla
    jmp line_hex8

; line_num — num_val in decimal, no leading zeros.  Clobbers A, X, Y.
line_num:
    jsr num_dec
    ldy num_first
@ch:
    lda num_txt, y
    sty hold_y
    jsr line_ch
    ldy hold_y
    iny
    cpy #10
    bne @ch
    rts

; load_lost — num_val = the failures the device never answered, both settings
; added together.  Clobbers A.
load_lost:
    lda lost + 0
    sta num_val + 0
    lda lost + 1
    sta num_val + 1
    lda lost + 2
    sta num_val + 2
    lda lost + 3
    sta num_val + 3
.if VARY_COUNT > 1
    clc
    lda num_val + 0
    adc lost + 4
    sta num_val + 0
    lda num_val + 1
    adc lost + 5
    sta num_val + 1
    lda num_val + 2
    adc lost + 6
    sta num_val + 2
    lda num_val + 3
    adc lost + 7
    sta num_val + 3
.endif
    rts

; line_counts — " RUN SENT n ERR n", both settings added.  Clobbers A, X, Y.
line_counts:
    line_set str_run
    jsr line_str
    line_set str_ok
    jsr line_str
    jsr total_sent
    jsr line_num
    line_set str_bad
    jsr line_str
    jsr total_bad
    lda tot_bad + 0
    sta num_val + 0
    lda tot_bad + 1
    sta num_val + 1
    lda tot_bad + 2
    sta num_val + 2
    lda tot_bad + 3
    sta num_val + 3
    jmp line_num

; line_setting — A = a vary index.  " SENT n ERR n", and " 1 IN n" once that
; setting has a failure to divide by.  Clobbers A, X, Y.
line_setting:
    sta vary_at
    line_set str_ok
    jsr line_str
    jsr load_vary_sent
    jsr line_num
    line_set str_bad
    jsr line_str
    jsr load_vary_bad
    jsr line_num

    lda vary_at
    asl a
    asl a
    tax
    lda vary_bad + 0, x
    sta num_den + 0
    lda vary_bad + 1, x
    sta num_den + 1
    lda vary_bad + 2, x
    sta num_den + 2
    lda vary_bad + 3, x
    sta num_den + 3
    ora num_den + 0
    ora num_den + 1
    ora num_den + 2
    bne @have
    rts
@have:
    line_set str_one_in
    jsr line_str
    jsr load_vary_sent
    jsr num_div
    jmp line_num

; load_vary_sent, load_vary_bad — num_val = what the setting in vary_at has
; sent, or got wrong.  Both clobber A, X.
load_vary_sent:
    lda vary_at
    asl a
    asl a
    tax
    lda vary_sent + 0, x
    sta num_val + 0
    lda vary_sent + 1, x
    sta num_val + 1
    lda vary_sent + 2, x
    sta num_val + 2
    lda vary_sent + 3, x
    sta num_val + 3
    rts

load_vary_bad:
    lda vary_at
    asl a
    asl a
    tax
    lda vary_bad + 0, x
    sta num_val + 0
    lda vary_bad + 1, x
    sta num_val + 1
    lda vary_bad + 2, x
    sta num_val + 2
    lda vary_bad + 3, x
    sta num_val + 3
    rts

; ---------------------------------------------------------------------------
; line_send — the buffer and a newline, four bytes to a PIPE_WRITE.
;
; A write that fails is sent again, up to PIPE_TRIES times.  Retrying a command
; under test would hide what this program counts, but a report is not under
; test, and a line cut off in the middle is a record lost.  PIPE_WRITE is all
; or nothing — a device that refused took none of the bytes — so the same four
; go out again rather than some part of them.
;
; A chunk that will not go at all abandons the rest of the line, and the
; newline goes with it.  That newline is the only thing separating what did go
; out from the next line, so the stump and the line after it arrived joined
; together and neither could be read.  The give-up is remembered instead, and
; the next line begins by sending a newline of its own.  The stump then stands
; as a short line, which is what it is.
;
; A pipe that will not take even that newline is a session that has stopped,
; and the log stops with it.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

line_send:
    lda #$0A                    ; the newline is part of the line
    jsr line_ch
    lda line_cut
    beq @whole
    jsr send_break
    bcs @stop
@whole:
    lda #0
    sta send_idx
@chunk:
    ldy send_idx
    cpy line_len
    bcs @done

    ldx #0
@fill:
    lda line, y
    sta rbcp_arg0, x
    iny
    inx
    cpx #RBCP_PIPE_WRITE_MAX
    beq @full
    cpy line_len
    bne @fill
@full:
    sty send_idx
    stx chunk_len               ; how many went in
    lda #PIPE_TRIES
    sta send_tries
@again:
    lda chunk_len
    ldx report_pipe
    jsr rbcp_cmd_pipe_write
    bcc @chunk
    dec send_tries
    bne @again
    lda #1                      ; the rest of this line, newline and all
    sta line_cut
@stop:
    rts
@done:
    lda #0
    sta line_cut
    rts

; ---------------------------------------------------------------------------
; send_break — one newline, to end the line the last send could not finish.
;
; Carry clear it went, carry set the pipe still will not take anything.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

send_break:
    lda #$0A
    sta rbcp_arg0
    lda #PIPE_TRIES
    sta send_tries
@again:
    lda #1
    ldx report_pipe
    jsr rbcp_cmd_pipe_write
    bcc @went
    dec send_tries
    bne @again
    sec
    rts
@went:
    lda #0
    sta line_cut
    clc
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

str_start:  .byte "RBCP METER START", 0
str_phase:  .byte "PH ", 0
str_run:    .byte " RUN", 0
str_lost:   .byte " LOST ", 0
str_one_in: .byte " 1 IN ", 0
str_gap:    .byte " ", 0
str_on:     .byte " ON", 0
str_off:    .byte " OFF", 0
str_back:   .byte "RECOVERED", 0
str_gone:   .byte "RECOVER FAILED", 0
str_fail:   .byte "FAIL ", 0
str_sent:   .byte " SENT", 0
str_tok:    .byte " TOK ", 0
str_got:    .byte " GOT", 0
str_ok:     .byte " SENT ", 0
str_bad:    .byte " ERR ", 0
