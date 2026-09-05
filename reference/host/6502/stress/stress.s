; stress.s — the loop that sends, the counts it keeps, and the record of what
; went wrong
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; What this program is for
; ------------------------
; It sends valid commands as fast as the machine can and counts the ones the
; device does not answer as asked.  Nothing it sends should ever fail, so a
; failure is not a result, it is the measurement.  The headline is one number:
; how many commands the device answers per one it gets wrong.
;
; Four commands rather than one, of different lengths and made of different
; bytes.  A fault in how the device takes bytes off the bus reaches all four
; and mangles each into something different.  One that only ever touches a
; single group is something else, and the per-command counts are how the two
; are told apart.
;
; It owns the machine
; -------------------
; The meter is a ROM.  It runs from reset, it never hands the machine back,
; and there is nothing to press.  A run ends when somebody switches off, which
; is also what puts the device's RAM slot back the way it was.
;
; Nothing retries a command.  A retry would hide what this exists to count.

    .include "stress_defs.s"

.import num_val

.import rbcp_issue_cmd
.import rbcp_recover

.import plat_init
.import plat_key
.if PLAT_VARY
.import plat_vary_set
.endif

.import sess_open

.import display_init
.import display_frame
.import display_counts
.import display_record
.import display_fail
.if PLAT_VARY
.import display_vary
.endif

.import report_open
.import report_phase
.import report_failure
.import report_recovery

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export cmd_sent
.export cmd_bad
.export vary_sent
.export vary_bad
.export lost
.export tot_bad
.export phase_lo
.export phase_hi
.export vary_idx

.export fail_stage
.export fail_test
.export fail_group
.export fail_cmd
.export fail_args
.export fail_tok
.export fail_hdr

; What each command has been asked to do and how often it went wrong.  These
; run for the whole run, because the headline is the run.
cmd_sent:   .res TEST_COUNT * 4
cmd_bad:    .res TEST_COUNT * 4

; The same again, split by the setting of whatever the machine varies.  A
; machine that varies nothing has one of each and the two are the same thing.
; The headline comes off these two, so failures is four bytes like sent.
vary_sent:  .res VARY_COUNT * 4
vary_bad:   .res VARY_COUNT * 4

; The failures the device did not answer at all, against the setting they
; happened under.  Every one of these is also counted in vary_bad.
lost:       .res VARY_COUNT * 4

tot_bad:    .res 4          ; where total_bad leaves its answer

phase_lo:   .res 1
phase_hi:   .res 1
phase_left_lo: .res 1
phase_left_hi: .res 1

vary_idx:   .res 1          ; 0 the machine's own variable is on, 1 off
vary_off4:  .res 1          ; and where that puts the counters

; The last failure, whole.  Taken from the library's own state and from the
; response header, at the moment it happened.  A device that has stopped
; answering will not answer a question about it later either.
fail_stage: .res 1          ; 1 not taken, 2 never finished, 3 refused
fail_test:  .res 1          ; which of the four
fail_group: .res 1          ; and the frame that went out
fail_cmd:   .res 1
fail_args:  .res 3
fail_tok:   .res 1          ; the token as the host saw it before sending
fail_hdr:   .res 6          ; the response header as it stood at the failure

cur_test:   .res 1
draw_left:  .res 1
jitter:     .res 1          ; the shift register the loop's padding comes off

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; stress_run — reached from the machine's reset entry, once the code is in RAM.
; It does not return.
; ---------------------------------------------------------------------------

.export stress_run
stress_run:
    jsr plat_init
    jsr zero_counts
    jsr display_init

    jsr sess_open
    bcs @refused
    jsr report_open
    jsr display_frame
    jsr display_counts
    jmp loop

@refused:
    jsr display_fail            ; the reason is already in A
    jmp stopped

; ---------------------------------------------------------------------------
; loop — send the next command, count what came back, and keep going.
;
; Every pass begins by wasting a few cycles, and how many varies.  Without
; them the loop takes the same time every time round, so its commands land at
; the same points against whatever else the machine's video is doing to the
; bus, and the whole run measures one of the many alignments the machine has.
; Which one is settled by whatever the build happened to compile to, and it is
; worth a factor of two.  Lengthening a line of the log moved a C64 from one
; wrong in 431 to one in 910 and changed nothing else.  Once the period stops
; being constant the alignment wanders, and a short run samples the machine
; rather than one corner of it.
;
; The number of cycles comes off a shift register stepped once a pass, because
; it has to be something the video is not.  Taking it from the raster would
; tie the padding to the very thing the padding is there to break away from.
;
; Nought to three turns of a five cycle loop is as much as this needs.  The
; alignment moves a step or two each pass, which has covered every one of them
; long before a phase is out.  A wider spread would cover them sooner and cost
; commands, and commands are what the tester is made of.
;
; None of this is a command and none of it is counted.
; ---------------------------------------------------------------------------

loop:
    lda jitter                  ; x^8 + x^4 + x^3 + x^2 + 1, which never
    asl a                       ; reaches zero from a seed that is not zero
    bcc @pad_count
    eor #$1D
@pad_count:
    sta jitter
    and #$03
    beq @send
    tax
@pad:
    dex
    bne @pad

@send:
    lda cur_test
    jsr run_test
    bcs @failed
    jsr count_sent
    jmp @next

@failed:
    jsr count_sent
    jsr note_failure            ; every count this failure touches, first
    jsr display_counts          ; then the screen, over counts that are settled
    jsr display_record
    lda fail_stage
    cmp #STAGE_REFUSED
    beq @tell                   ; it answered, so the pipe will hear about it

    ; It did not answer.  Put the device back together before saying anything,
    ; because saying anything is itself a command.
    jsr recover
    bcs stopped
    jsr report_failure
    lda #0
    jsr report_recovery         ; and that it came back
    jmp @next

@tell:
    jsr report_failure

@next:
    inc cur_test
    lda cur_test
    cmp #TEST_COUNT
    bcc @counted
    lda #0
    sta cur_test
@counted:
    jsr phase_step

    dec draw_left
    bne @keys
    lda #DRAW_COMMANDS
    sta draw_left
    jsr display_counts

@keys:
    jsr plat_key
    cmp #KEY_NONE_CODE
    beq loop
    jsr take_key
    jmp loop

; ---------------------------------------------------------------------------
; stopped — the resting state when there is nothing left to send.
;
; Whatever the machine varies comes back on first.  A run that ends while the
; display is off has its record on a screen nobody can see, and that is the run
; whose record matters most.
; ---------------------------------------------------------------------------

stopped:
.if PLAT_VARY
    lda #1
    jsr plat_vary_set
.endif
@wait:
    jmp @wait

; ---------------------------------------------------------------------------
; take_key — A = a key code.  There is one, and only where the machine has
; something to vary.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

take_key:
.if PLAT_VARY
    cmp #KEY_VARY
    bne @out
    lda vary_idx
    eor #1
    sta vary_idx
    asl a
    asl a
    sta vary_off4
    lda vary_idx
    eor #1                      ; 1 asks for it on
    jsr plat_vary_set
    jmp display_vary
@out:
.endif
    rts

; ---------------------------------------------------------------------------
; phase_step — one command nearer the end of this phase.
;
; A phase is only how often the pipe hears from the run.  Every command counts
; against it, answered or not.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

phase_step:
    lda phase_left_lo
    bne @dec_lo
    dec phase_left_hi
@dec_lo:
    dec phase_left_lo
    bne @out                    ; the phase ends on the command that takes the
    lda phase_left_hi           ; counter to zero, not on the one after
    bne @out
    jsr report_phase
    inc phase_lo
    bne @reload
    inc phase_hi
@reload:
    lda #<PHASE_COMMANDS
    sta phase_left_lo
    lda #>PHASE_COMMANDS
    sta phase_left_hi
@out:
    rts

; ---------------------------------------------------------------------------
; recover — the device did not answer, so put it back together.
;
; The sequence is common/rbcp_recover.s, which every host that has to do this
; shares.  What belongs to the meter is what it says when the device does not
; come back.  The lost command was counted in note_failure, before the screen
; was drawn.
;
; Carry clear back in command-response mode, carry set gave up.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

recover:
    jsr rbcp_recover
    bcc @out
    lda #1
    jsr report_recovery         ; it will not go out, but the screen has it
    sec
@out:
    rts

; ---------------------------------------------------------------------------
; zero_counts — the state of a run that has not started.  Clobbers A, X.
; ---------------------------------------------------------------------------

zero_counts:
    lda #0
    ldx #(TEST_COUNT * 4) - 1
@sent:
    sta cmd_sent, x
    dex
    bpl @sent
    ldx #(TEST_COUNT * 4) - 1
@bad:
    sta cmd_bad, x
    dex
    bpl @bad
    ldx #(VARY_COUNT * 4) - 1
@vsent:
    sta vary_sent, x
    dex
    bpl @vsent
    ldx #(VARY_COUNT * 4) - 1
@vbad:
    sta vary_bad, x
    dex
    bpl @vbad
    ldx #(VARY_COUNT * 4) - 1
@vlost:
    sta lost, x
    dex
    bpl @vlost

    lda #0
    sta phase_lo
    sta phase_hi
    sta cur_test
    sta vary_idx
    sta vary_off4
    sta fail_stage
    lda #<PHASE_COMMANDS
    sta phase_left_lo
    lda #>PHASE_COMMANDS
    sta phase_left_hi
    lda #DRAW_COMMANDS
    sta draw_left
    lda #$5A                    ; any seed but zero, which the register cannot
    sta jitter                  ; leave and cannot reach
    rts

; ---------------------------------------------------------------------------
; total_sent, total_bad — the run is the sum of what happened under each
; setting of whatever the machine varies.  Keeping the two apart and adding
; them here means they can never disagree with the headline.
;
; total_sent leaves every command sent in num_val, total_bad leaves every
; failure in tot_bad.  Both clobber A, X.
; ---------------------------------------------------------------------------

.export total_sent
total_sent:
    lda vary_sent + 0
    sta num_val + 0
    lda vary_sent + 1
    sta num_val + 1
    lda vary_sent + 2
    sta num_val + 2
    lda vary_sent + 3
    sta num_val + 3
.if VARY_COUNT > 1
    clc
    lda num_val + 0
    adc vary_sent + 4
    sta num_val + 0
    lda num_val + 1
    adc vary_sent + 5
    sta num_val + 1
    lda num_val + 2
    adc vary_sent + 6
    sta num_val + 2
    lda num_val + 3
    adc vary_sent + 7
    sta num_val + 3
.endif
    rts

.export total_bad
total_bad:
    lda vary_bad + 0
    sta tot_bad + 0
    lda vary_bad + 1
    sta tot_bad + 1
    lda vary_bad + 2
    sta tot_bad + 2
    lda vary_bad + 3
    sta tot_bad + 3
.if VARY_COUNT > 1
    clc
    lda tot_bad + 0
    adc vary_bad + 4
    sta tot_bad + 0
    lda tot_bad + 1
    adc vary_bad + 5
    sta tot_bad + 1
    lda tot_bad + 2
    adc vary_bad + 6
    sta tot_bad + 2
    lda tot_bad + 3
    adc vary_bad + 7
    sta tot_bad + 3
.endif
    rts

; ---------------------------------------------------------------------------
; run_test — A = which command.  Sends it.
;
; Three argument bytes are always staged and only the command's own count goes
; out, so one path sends all four shapes and the record reads the same
; locations whichever it was.
;
; Carry clear answered, carry set not, with the stage in rbcp_zp_5.
; ---------------------------------------------------------------------------

run_test:
    tax
    lda test_off, x
    tax
    lda tests + 0, x
    sta rbcp_zp_0
    lda tests + 1, x
    sta rbcp_zp_1
    lda tests + 3, x
    sta rbcp_arg0
    lda tests + 4, x
    sta rbcp_arg1
    lda tests + 5, x
    sta rbcp_arg2
    lda tests + 2, x
    jmp rbcp_issue_cmd

; ---------------------------------------------------------------------------
; count_sent — one more command out, against the command and against whatever
; the machine is doing while it went.  Clobbers A, X.
; ---------------------------------------------------------------------------

count_sent:
    lda cur_test
    asl a
    asl a
    tax
    INC32 cmd_sent
    ldx vary_off4
    INC32 vary_sent
    rts

; ---------------------------------------------------------------------------
; note_failure — the whole of what just went wrong.
;
; The frame is read back out of the library's own zero page rather than out of
; the table, so what is recorded is what was staged to go on the wire.  The
; response header is copied here rather than read where it is drawn, because a
; device that has stopped answering has stopped.
;
; A failure the device did not answer is also a lost command, and it is counted
; here rather than where the recovery happens.  The recovery is slow, so a
; screen drawn before it would show the failure as an error and not yet as a
; loss, which is a pair of numbers that contradict each other.
; Clobbers A, X.
; ---------------------------------------------------------------------------

note_failure:
    lda rbcp_zp_5
    sta fail_stage
    lda cur_test
    sta fail_test
    asl a
    asl a
    tax
    INC32 cmd_bad
    ldx vary_off4
    INC32 vary_bad
    jsr note_lost

    lda rbcp_zp_0
    sta fail_group
    lda rbcp_zp_1
    sta fail_cmd
    lda rbcp_arg0
    sta fail_args + 0
    lda rbcp_arg1
    sta fail_args + 1
    lda rbcp_arg2
    sta fail_args + 2
    lda rbcp_zp_2
    sta fail_tok
    ldx #0
@byte:
    lda CONFIG_RBCP_BCH_BASE, x
    sta fail_hdr, x
    inx
    cpx #6
    bne @byte
    rts

; ---------------------------------------------------------------------------
; note_lost — a failure the device never answered is a lost command, against
; the setting it happened under.  A device that answered and said no lost
; nothing.  Clobbers A, X.
; ---------------------------------------------------------------------------

note_lost:
    lda fail_stage
    cmp #STAGE_REFUSED
    bne @count
    rts
@count:
    ldx vary_off4
    INC32 lost
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; The commands under test: group, command, argument count, three arguments.
;
; Every one of these is valid on any device that answers the group at all, and
; the arguments are chosen so the device has nothing to disagree with.  NOP and
; GET_PROTOCOL_VERSION carry no arguments, so their frames are two bytes.  The
; two LED commands carry one and two, so theirs are three and four.  LED 0 is
; the first LED any device with LEDs has, and mode 0 is Off, which every LED
; supports.
.export tests
.export test_off
tests:
    .byte $00, $00, 0, $00, $00, $00    ; NOP
    .byte $01, $06, 0, $00, $00, $00    ; GET_PROTOCOL_VERSION
    .byte $06, $01, 1, $00, $00, $00    ; GET_LED_INFO, LED 0
    .byte $06, $02, 2, $00, $00, $00    ; GET_LED_MODE_INFO, mode 0 of LED 0

; Where each command's row starts.  A table rather than a multiply, because
; four entries of six is not worth one.
test_off:
    .byte 0 * TEST_STRIDE, 1 * TEST_STRIDE, 2 * TEST_STRIDE, 3 * TEST_STRIDE
