; amiga_stress.s — Amiga RBCP reliability meter
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Purpose
; -------
; The meter sends valid commands as fast as the machine can and counts the
; ones the device does not answer as asked.  Nothing it sends should ever
; fail, so a failure is not a result — it is the measurement.  The headline is
; one number: how many commands the device answers per one it gets wrong.
;
; The figure is for comparison.  The same device gives a different answer in
; an Amiga, a C64 and an Apple IIe, and the useful question is how different
; and why.  Quote the number with the machine it came from.
;
; Chip DMA
; --------
; Two states, on and off, counted apart for the whole run.  `S` asks for the
; other one and the loop makes the change between two commands, so every
; error belongs to a state that held still for the whole of the command that
; failed.  The
; meter never switches by itself.  The Chip DMA section of README.md says what
; Agnus does and why the two are counted apart.
;
; The meter owns the machine
; --------------------------
; The meter is a Kickstart image.  It runs from reset, it never hands the
; machine back, and there is nothing to press but the one key.  A run ends
; when somebody switches off, and that puts the device's RAM slot back the
; way it was.
;
; Nothing retries a command under test.  A retry would hide what this exists
; to count, and CONFIG_RBCP_TIMEOUT_RETRIES is zero for that reason.
;
; ROM image layout, top-aligned — 256 KB from $FC0000 or 512 KB from $F80000:
;
;   ROM SECTION  — executed directly from ROM
;     ROM header, rom_cold_start, JMP rom_entry
;     amiga_hw.s: a500_hw_init, exc_halt, kbd_init, screen_init
;     rom_entry: HW init, screen up, copy RAM section, JMP $28000
;
;   RAM SECTION  — stored in ROM, copied to RAM_CODE_BASE ($28000) at boot
;     ram_entry: the session, then the loop that never returns
;     rbcp.s: RBCP protocol library
;     amiga-common: shared Amiga routines
;
;   ROM DATA SECTION — referenced via absolute long addresses from RAM code
;     copper_template, font_data, strings and tables
;
;   $FFFC00  back-channel region (512 bytes, zeroed)
;   $FFFE00  command page        (512 bytes, zeroed)
;
; The split
;   The knock and command sequences work by triggering specific ROM address
;   reads.  Code fetched from that same ROM puts its own instruction-fetch
;   addresses on the bus and corrupts the sequence the device sees, so it runs
;   from chip RAM.  Once command-response mode is established the device
;   filters on the command page and ROM reads elsewhere are harmless — the
;   screen routines read the font from ROM and are called throughout the run,
;   but never between the knock and the response to ENTER_CMD_RESP.
;
; Addressing note:
;   RAM-section code reaches ROM data through explicit absolute long
;   addressing — LEA (label).L,A0 — never PC-relative, because the code is
;   assembled at its ROM address but executes from $28000.

; The meter draws none of the bootloader's artwork, so the pens that carry it
; are free.  A pen already defined keeps its value, so these go in before the
; palette is included.
PEN06_RGB                   EQU $0999       ; labels, dimmer than the figures
PEN07_RGB                   EQU $0FA0       ; a run with nowhere to report to
PEN08_RGB                   EQU $04D4       ; the state of chip DMA running now
PEN14_RGB                   EQU $0F44       ; errors and the failure record

; Definitions first — the ORG below depends on CONFIG_ROM_BASE.  None of
; these emit any code or data.
        INCLUDE "rbcp_config.s"
        INCLUDE "../rbcp/rbcp_defs.s"
        INCLUDE "../amiga-common/amiga_defs.s"
        INCLUDE "amiga_defs.s"

; The version, shown on screen and in the log.  A macro rather than an EQU
; because it expands to text.
APP_VERSION MACRO
        DC.B    "0.1.0"
        ENDM

        ORG     CONFIG_ROM_BASE

; ============================================================
; ROM SECTION
; ============================================================

; ---------------------------------------------------------------------------
; Kickstart-compatible ROM header
; At reset the 68K reads the SSP from ROM[$0] and the initial PC from ROM[$4]
; (ROM is mapped at $0 via OVL at power-on).
; ---------------------------------------------------------------------------
ROMStart:
        DC.W    $1114                   ; SSP[31:16] — conventional value
        DC.W    $4EF9                   ; SSP[15:0]  — conventional value
        DC.L    rom_cold_start          ; initial PC

        DCB.B   $D0-(*-ROMStart),$00    ; pad to offset $D0

        RESET                           ; +$D0: soft-reset entry
rom_cold_start:                         ; +$D2: CPU jumps here on power-on
        JMP     rom_entry

; ---------------------------------------------------------------------------
; ROM-section hardware routines: a500_hw_init, exc_halt, kbd_init, screen_init
; screen_init contains a forward BSR to screen_clear in the RAM section.  Both
; are in ROM at assembly time, so the PC-relative branch is correct there.
; ---------------------------------------------------------------------------
        INCLUDE "../amiga-common/amiga_hw.s"

; ---------------------------------------------------------------------------
; rom_entry — runs from ROM.  Clears OVL, sets the stack, brings the hardware
; and the display up, copies the RAM section to RAM_CODE_BASE and jumps to it.
;
; The screen is up before the RAM copy, so a machine that fails in the copy
; still shows the boot progress colour.
; ---------------------------------------------------------------------------
rom_entry:
        MOVE.W  #COL_RED,COLOR00
        MOVE.B  #$03,CIAA_DDRA      ; clear OVL — chip RAM now at $0
        MOVE.B  #$02,CIAA_PRA
        MOVEA.L #STACK_TOP,SP       ; SP set AFTER OVL cleared
        BSR     a500_hw_init
        MOVE.W  #COL_YELLOW,COLOR00

        BSR     screen_init
        BSR     kbd_init            ; CIA-A serial port to keyboard input

        LEA     (ram_section_rom_start).L,A0
        MOVEA.L #RAM_CODE_BASE,A1
        MOVE.W  #(ram_section_rom_end-ram_section_rom_start)/2-1,D0
.re_copy:
        MOVE.W  (A0)+,(A1)+
        DBF     D0,.re_copy

        ; ram_entry is at offset 0 from ram_section_rom_start, so
        ; RAM_CODE_BASE is its exact address in chip RAM.
        JMP     (RAM_CODE_BASE).L

; ============================================================
; RAM SECTION
; Stored in the ROM image between ram_section_rom_start and
; ram_section_rom_end, copied word-by-word to RAM_CODE_BASE.
;
; ram_entry is at offset 0 so JMP RAM_CODE_BASE enters it directly.
; BSR/BRA within this section are PC-relative and span the same distance in
; ROM and in the copy.  References out of it use absolute long addressing.
; ============================================================
ram_section_rom_start:

; ---------------------------------------------------------------------------
; ram_entry — the meter proper, running from chip RAM.  The session with the
; device, then the loop.  It does not return.
; ---------------------------------------------------------------------------
ram_entry:
        MOVE.L  #BITPLANE_BASE,VAR_DRAW_BASE
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        CLR.B   VAR_MENU_COL            ; a filled row is the whole row here
        ; The first line off the bottom of the display.
        MOVE.W  #FIELD_TICK_NTSC,VAR_TICK_LINE
        TST.B   VAR_IS_PAL
        BEQ.S   .ae_ntsc
        MOVE.W  #FIELD_TICK_PAL,VAR_TICK_LINE
.ae_ntsc:
        ; report_open names the pipe once it has found one.  err_halt reads
        ; this, and a session that never opened has no pipe to say anything
        ; down.
        CLR.B   VAR_PIPE_PRESENT

        BSR     screen_clear
        BSR     zero_counts
        BSR     draw_title              ; before anything is asked of the device

        BSR     sess_open               ; err_halt on the way out where it fails
        BSR     report_open
        BSR     draw_frame
        BSR     draw_counts

; ---------------------------------------------------------------------------
; meter_loop — send the next command, count what came back, and keep going.
;
; A pass begins with the chip DMA switch `S` asked for, because this is the
; one place in the loop where nothing is in flight.  The command before it was
; answered, refused, or given up on and the device put back together by
; recover, and the next has not gone out.  A write to DMACON anywhere else
; could land between two bytes of a frame and break it, and the error it
; caused would be counted against whichever state the write left behind.
;
; Then the pass wastes nought to three turns of a short delay.  Without
; them the loop takes the same time every time round, so its commands land at
; the same point in the scan line every pass and the whole run measures one
; alignment out of the many the machine has — whichever the build happened to
; assemble to.  Bitplane DMA repeats every scan line and the copper and the
; blitter land on top of it, so a single alignment is not the machine.
;
; The count comes off a shift register stepped once a pass, so it owes nothing
; to the video.  The
; alignment moves a step or two a pass, which covers every one of them long
; before a phase is out.
;
; None of this is a command and none of it is counted.
; ---------------------------------------------------------------------------
meter_loop:
        TST.B   MTR_VARY_PEND
        BEQ.S   .ml_jitter
        BSR     vary_switch
.ml_jitter:
        MOVEQ   #0,D0
        MOVE.B  MTR_JITTER,D0           ; x^8+x^4+x^3+x^2+1, which never
        ADD.B   D0,D0                   ; reaches zero from a seed that is not
        BCC.S   .ml_notap               ; zero
        EORI.B  #$1D,D0
.ml_notap:
        MOVE.B  D0,MTR_JITTER
        ANDI.W  #$0003,D0
        BEQ.S   .ml_send
        SUBQ.W  #1,D0
.ml_pad:
        DBF     D0,.ml_pad

.ml_send:
        BSR     run_test
        BSR     count_sent
        TST.B   D0
        BEQ     .ml_next

        ; Every count this failure touches, first, so that whatever is drawn
        ; afterwards is drawn over counts that are settled.
        BSR     note_failure
        CMPI.B  #RBCP_ERR_RESPONSE,MTR_FAIL_STAGE
        BEQ.S   .ml_answered

        ; It did not answer, so it may have dropped out of command-response
        ; mode and be reading every ROM address as command data.  Drawing
        ; reads the font out of the ROM the device is serving, so the device
        ; goes back together before anything touches the screen.  Saying
        ; anything down the pipe is itself a command and waits too.
        BSR     recover
        TST.B   D0
        BNE.S   .ml_gone
        BSR     draw_counts
        BSR     draw_record
        BSR     report_failure
        MOVEQ   #0,D0
        BSR     report_recovery         ; and that it came back
        BRA.S   .ml_next
.ml_gone:
        BSR     draw_counts
        BSR     draw_record
        BRA     meter_stopped
.ml_answered:
        BSR     draw_counts
        BSR     draw_record
        BSR     report_failure

.ml_next:
        ADDQ.B  #1,MTR_CUR_TEST
        CMPI.B  #TEST_COUNT,MTR_CUR_TEST
        BCS.S   .ml_counted
        CLR.B   MTR_CUR_TEST
.ml_counted:
        BSR     phase_step

        SUBQ.W  #1,MTR_DRAW_LEFT
        BNE.S   .ml_keys
        MOVE.W  #DRAW_COMMANDS,MTR_DRAW_LEFT
        BSR     draw_counts
.ml_keys:
        BSR     amiga_getkey
        TST.B   D0
        BEQ     meter_loop
        BSR     take_key
        BRA     meter_loop

; ---------------------------------------------------------------------------
; meter_stopped — the resting state when there is nothing left to send.
;
; Chip DMA comes back on first.  A run that ends with the screen blank has its
; record where nobody can see it, and that is the run whose record matters
; most.
; ---------------------------------------------------------------------------
meter_stopped:
        MOVEQ   #1,D0
        BSR     dma_set
.ms_wait:
        BRA.S   .ms_wait

; ---------------------------------------------------------------------------
; take_key — D0.B = a key code.  There is one key and it asks for the other
; state of chip DMA.  The ask is all that happens here: meter_loop makes the
; switch where nothing is in flight.
; Clobbers: nothing
; ---------------------------------------------------------------------------
take_key:
        CMPI.B  #KEY_VARY,D0
        BEQ.S   .tk_vary
        CMPI.B  #KEY_VARY_LOWER,D0
        BNE.S   .tk_out
.tk_vary:
        MOVE.B  #1,MTR_VARY_PEND
.tk_out:
        RTS

; ---------------------------------------------------------------------------
; vary_switch — the other state of chip DMA, with the counters that go with it.
; meter_loop is the only caller and the ask is cleared here, where it has been
; met.
; Clobbers (saved/restored): D0-D1
; ---------------------------------------------------------------------------
vary_switch:
        MOVEM.L D0-D1,-(SP)
        CLR.B   MTR_VARY_PEND
        MOVE.B  MTR_VARY_IDX,D0
        EORI.B  #1,D0
        MOVE.B  D0,MTR_VARY_IDX
        MOVE.B  D0,D1
        LSL.B   #2,D1                   ; a long per counter
        MOVE.B  D1,MTR_VARY_OFF
        EORI.B  #1,D0                   ; 1 asks for chip DMA on
        BSR     dma_set
        BSR     draw_vary
        MOVEM.L (SP)+,D0-D1
        RTS

; ---------------------------------------------------------------------------
; dma_set — D0.B = 1 chip DMA on, 0 off.
;
; DMAEN is the master enable, so clearing it stops the bitplanes, the copper
; and the blitter together and leaves the screen blank.  The copper is pointed
; at its list again on the way back on, because it stopped wherever it was.
; Memory refresh is not in DMACON and runs either way.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
dma_set:
        MOVEM.L D0,-(SP)
        TST.B   D0
        BEQ.S   .ds_off
        MOVE.L  #COPPER_BASE,COP1LCH
        MOVE.W  #DMAF_SETCLR|DMAF_MASTER,DMACON
        BRA.S   .ds_done
.ds_off:
        MOVE.W  #DMAF_MASTER,DMACON
.ds_done:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; phase_step — one command nearer the end of this phase.
;
; A phase is only how often the pipe hears from the run.  Every command counts
; against it, answered or not.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
phase_step:
        MOVEM.L D0,-(SP)
        SUBQ.L  #1,MTR_PHASE_LEFT
        BNE.S   .ps_out                 ; the phase ends on the command that
        BSR     report_phase            ; takes the counter to zero
        ADDQ.W  #1,MTR_PHASE_NO
        MOVE.L  #PHASE_COMMANDS,MTR_PHASE_LEFT
.ps_out:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; recover — the device did not answer, so put it back together.
;
; RBCP_RESET flushes a partially received command of up to nine argument bytes
; and two framing bytes, which is exactly what a frame that slipped by a byte
; onto a command taking arguments leaves behind.  Command-response mode is
; entered again rather than the session opened from scratch: the rest of
; opening a session decides whether to talk to the device at all, and that was
; settled before anything called this.
;
; The lost command was counted in note_failure, before the screen was drawn.
;
; Output: D0=0 back in command-response mode, D0=1 gave up
; Clobbers (saved/restored): D1
; ---------------------------------------------------------------------------
recover:
        MOVEM.L D1,-(SP)
        MOVEQ   #RECOVER_TRIES,D1
.rc_try:
        BSR     rbcp_reset
        BSR     rbcp_cmd_enter_cmd_resp
        TST.B   D0
        BEQ.S   .rc_back
        SUBQ.B  #1,D1
        BNE.S   .rc_try
        MOVEQ   #1,D0                   ; it will not go out, but a log that
        BSR     report_recovery         ; stops says where the run stopped
        BRA.S   .rc_out
.rc_back:
        MOVEQ   #0,D0
.rc_out:
        MOVEM.L (SP)+,D1
        RTS

; ---------------------------------------------------------------------------
; run_test — send the command MTR_CUR_TEST names.
;
; Three argument bytes are always staged and only the command's own count goes
; out, so one path sends all four commands and the record reads the same places
; whichever it was.
;
; Output: D0=0 answered, D0=the stage otherwise
; Clobbers (saved/restored): D1/A0
; ---------------------------------------------------------------------------
run_test:
        MOVEM.L D1/A0,-(SP)
        MOVEQ   #0,D1
        MOVE.B  MTR_CUR_TEST,D1
        MULU    #TEST_STRIDE,D1
        LEA     (tests).L,A0
        ADDA.W  D1,A0
        MOVE.B  (A0)+,RBCP_GROUP
        MOVE.B  (A0)+,RBCP_CMD
        MOVEQ   #0,D0
        MOVE.B  (A0)+,D0                ; argument count
        MOVE.B  (A0)+,RBCP_ARG0
        MOVE.B  (A0)+,RBCP_ARG1
        MOVE.B  (A0)+,RBCP_ARG2
        BSR     rbcp_issue_cmd
        MOVEM.L (SP)+,D1/A0
        RTS

; ---------------------------------------------------------------------------
; count_sent — one more command out, against the command and against the state
; of chip DMA it went out under.  Leaves D0 alone, because the caller needs it.
; Clobbers (saved/restored): D1/A0
; ---------------------------------------------------------------------------
count_sent:
        MOVEM.L D1/A0,-(SP)
        MOVEQ   #0,D1
        MOVE.B  MTR_CUR_TEST,D1
        LSL.W   #2,D1
        LEA     (MTR_CMD_SENT).W,A0
        ADDQ.L  #1,(A0,D1.W)
        MOVEQ   #0,D1
        MOVE.B  MTR_VARY_OFF,D1
        LEA     (MTR_VARY_SENT).W,A0
        ADDQ.L  #1,(A0,D1.W)
        MOVEM.L (SP)+,D1/A0
        RTS

; ---------------------------------------------------------------------------
; note_failure — the whole of what just went wrong.
;
; The frame is read back out of the library's own scratch rather than out of
; the table, so what is recorded is what was staged to go on the wire.  The
; response header is copied here rather than read where it is drawn, because
; the device may be gone by then.
;
; A failure the device did not answer is also a lost command, and it is
; counted here rather than where the recovery happens.  The recovery is slow,
; so a screen drawn before it would show the failure as an error and not yet
; as a loss, which is a pair of numbers that contradict each other.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
note_failure:
        MOVEM.L D0-D1/A0,-(SP)
        MOVE.B  RBCP_ERROR_CODE,MTR_FAIL_STAGE
        MOVE.B  MTR_CUR_TEST,MTR_FAIL_TEST

        MOVEQ   #0,D1
        MOVE.B  MTR_CUR_TEST,D1
        LSL.W   #2,D1
        LEA     (MTR_CMD_BAD).W,A0
        ADDQ.L  #1,(A0,D1.W)
        MOVEQ   #0,D1
        MOVE.B  MTR_VARY_OFF,D1
        LEA     (MTR_VARY_BAD).W,A0
        ADDQ.L  #1,(A0,D1.W)
        ; A device that answered and said no lost nothing.
        CMPI.B  #RBCP_ERR_RESPONSE,MTR_FAIL_STAGE
        BEQ.S   .nf_frame
        LEA     (MTR_LOST).W,A0
        ADDQ.L  #1,(A0,D1.W)
.nf_frame:
        MOVE.B  RBCP_GROUP,MTR_FAIL_GROUP
        MOVE.B  RBCP_CMD,MTR_FAIL_CMD
        MOVE.B  RBCP_ARG0,MTR_FAIL_ARGS+0
        MOVE.B  RBCP_ARG1,MTR_FAIL_ARGS+1
        MOVE.B  RBCP_ARG2,MTR_FAIL_ARGS+2
        MOVE.B  RBCP_SAVED_TOK,MTR_FAIL_TOK
        MOVE.B  (RBCP_LASTCMD_GRP_ADDR).L,MTR_FAIL_HDR+0
        MOVE.B  (RBCP_LASTCMD_CMD_ADDR).L,MTR_FAIL_HDR+1
        MOVE.B  (RBCP_TOKEN_LSB_ADDR).L,MTR_FAIL_HDR+2
        MOVE.B  (RBCP_TOKEN_MSB_ADDR).L,MTR_FAIL_HDR+3
        MOVE.B  (RBCP_PROGRESS_ADDR).L,MTR_FAIL_HDR+4
        MOVE.B  (RBCP_RESPONSE_ADDR).L,MTR_FAIL_HDR+5
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; zero_counts — the state of a run that has not started.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
zero_counts:
        MOVEM.L D0/A0,-(SP)
        LEA     (MTR_VARS).W,A0
        MOVE.W  #(MTR_END+3-MTR_VARS)/4-1,D0
.zc_loop:
        CLR.L   (A0)+
        DBF     D0,.zc_loop
        MOVE.W  #DRAW_COMMANDS,MTR_DRAW_LEFT
        MOVE.L  #PHASE_COMMANDS,MTR_PHASE_LEFT
        MOVE.B  #1,MTR_FIRST_DRAW       ; the slots are empty, so the first
                                        ; refresh has nothing to compare with
        MOVE.B  #$5A,MTR_JITTER         ; any seed but zero, which the register
                                        ; cannot leave and cannot reach
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; total_sent, total_bad, total_lost — the run is the two states of chip DMA
; added together.  Keeping the two apart and adding them here means
; they can never disagree with the headline.  Each leaves its answer in
; MTR_NUM_VAL.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
total_sent:
        MOVEM.L D0,-(SP)
        MOVE.L  MTR_VARY_SENT+0,D0
        ADD.L   MTR_VARY_SENT+4,D0
        MOVE.L  D0,MTR_NUM_VAL
        MOVEM.L (SP)+,D0
        RTS

total_bad:
        MOVEM.L D0,-(SP)
        MOVE.L  MTR_VARY_BAD+0,D0
        ADD.L   MTR_VARY_BAD+4,D0
        MOVE.L  D0,MTR_NUM_VAL
        MOVEM.L (SP)+,D0
        RTS

total_lost:
        MOVEM.L D0,-(SP)
        MOVE.L  MTR_LOST+0,D0
        ADD.L   MTR_LOST+4,D0
        MOVE.L  D0,MTR_NUM_VAL
        MOVEM.L (SP)+,D0
        RTS

; ===========================================================================
; The session
; ===========================================================================

; ---------------------------------------------------------------------------
; sess_open — knock, command-response mode, the version check and the three
; strings the device calls itself.
;
; The meter owns the machine from reset and never gives it back, so there is
; no exit to repair and none of the apparatus a bootloader carries for one.
; The device reloads its RAM slot from flash at power-on, so switching off is
; the repair.
;
; A session that will not open goes to err_halt and does not come back.
; ---------------------------------------------------------------------------
sess_open:
        BSR     rbcp_reset
        BSR     rbcp_cmd_enter_cmd_resp
        TST.B   D0
        BEQ.S   .so_entered
        CMPI.B  #RBCP_ERR_TOKEN,RBCP_ERROR_CODE
        BNE.S   .so_refused
        MOVEQ   #ERR_NO_DEVICE,D0       ; the token never moved
        BRA     err_halt
.so_refused:
        MOVEQ   #ERR_ENTER,D0
        BRA     err_halt
.so_entered:
        BSR     rbcp_check_protocol_version
        TST.B   D0
        BEQ.S   .so_ver_ok
        MOVEQ   #ERR_VERSION,D0
        BRA     err_halt
.so_ver_ok:
        BRA     read_identity

; ---------------------------------------------------------------------------
; read_identity — device type, device version and protocol version into the
; buffers the screen is drawn from.  Read once, while the session is opening,
; because a device that has stopped answering will not answer a question about
; its own name either.  A command that fails leaves its buffer empty.
; Clobbers (saved/restored): D0-D1/A0-A1
; ---------------------------------------------------------------------------
read_identity:
        MOVEM.L D0-D1/A0-A1,-(SP)
        BSR     rbcp_cmd_get_device_type
        TST.B   D0
        BNE.S   .ri_ver
        LEA     (MTR_DEV_TYPE).W,A1
        BSR     copy_name
.ri_ver:
        BSR     rbcp_cmd_get_device_version
        TST.B   D0
        BNE.S   .ri_proto
        LEA     (MTR_DEV_VER).W,A1
        BSR     copy_name
.ri_proto:
        BSR     rbcp_cmd_get_proto_version
        TST.B   D0
        BNE.S   .ri_out
        MOVEQ   #4,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        LEA     (MTR_PROTO).W,A1
        MOVE.B  #'R',(A1)+
        MOVE.B  #'B',(A1)+
        MOVE.B  #'C',(A1)+
        MOVE.B  #'P',(A1)+
        MOVE.B  #' ',(A1)+
        MOVEQ   #2,D1                   ; major, minor, patch
.ri_digit:
        MOVE.B  (A0)+,D0
        ADDI.B  #'0',D0
        MOVE.B  D0,(A1)+
        TST.B   D1
        BEQ.S   .ri_last
        MOVE.B  #'.',(A1)+
.ri_last:
        DBF     D1,.ri_digit
        CLR.B   (A1)
.ri_out:
        MOVEM.L (SP)+,D0-D1/A0-A1
        RTS

; ---------------------------------------------------------------------------
; copy_name — A1 = a 25 byte buffer.  The reply's string, cut to 24 characters
; and terminated.  Call it after a command succeeds and before the next one.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
copy_name:
        MOVEM.L D0-D1/A0,-(SP)
        MOVEQ   #24,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        MOVEQ   #24-1,D1
.cn_ch:
        MOVE.B  (A0)+,(A1)+
        BEQ.S   .cn_done
        DBF     D1,.cn_ch
        CLR.B   (A1)
.cn_done:
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ===========================================================================
; The report
;
; The screen is the headline rather than the history, and a machine left
; running overnight has a history worth keeping, so every failure and a line
; every phase go out of the device's pipe as plain text.
;
; A pipe write is itself an RBCP command down the same path as the ones being
; counted, which is why none of it is counted and why it is used sparingly.
; A write only has to work while the session is healthy, which is exactly
; when there is something to say.  Where the session is not healthy the log
; stops, and where it stopped is itself the answer.
;
; Every count belongs to whatever the line named last.  A state word —
; DISPLAY, then ON or OFF — makes the counts after it that state's, and RUN
; makes them the whole run's.  A phase line carries each state separately, since
; pressing the key partway through a phase would otherwise leave a line naming
; one state and counting both.
; ===========================================================================

; ---------------------------------------------------------------------------
; report_open — find a pipe that carries host to device, and say so.
;
; The first pipe reporting OUT is the one.  A device offering more than one has
; no way to say which it would prefer.  A device with no pipes, or one whose
; protocol version predates the group, leaves reporting off and the run is read
; off the screen.
;
; The two commands asked here are as likely to be mangled as any other and
; this runs once, so a single bad one would otherwise cost the whole run its
; log.  Each gets OPEN_TRIES goes.  A mangled command usually comes back as a
; refusal, which is also how a device whose protocol version predates the
; group answers the first of them, so the refusal is not told apart from the
; rest — the count of goes is what stops it.  A device that answers and says
; it has no pipes is taken at its word.
; Clobbers (saved/restored): D0-D4/A0
; ---------------------------------------------------------------------------
report_open:
        MOVEM.L D0-D4/A0,-(SP)
        CLR.B   VAR_PIPE_PRESENT

        MOVEQ   #OPEN_TRIES,D3
.ro_cap:
        BSR     rbcp_cmd_get_pipe_cap
        TST.B   D0
        BEQ.S   .ro_count
        SUBQ.B  #1,D3
        BNE.S   .ro_cap
        BRA     .ro_out
.ro_count:
        MOVEQ   #1,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVEQ   #0,D2
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_CAP_COUNT).W,D2
        BEQ     .ro_out                 ; no pipes at all
        MOVEQ   #0,D4                   ; the pipe being asked about
.ro_try:
        MOVEQ   #OPEN_TRIES,D3
.ro_info:
        MOVE.B  D4,D0
        BSR     rbcp_cmd_get_pipe_info
        TST.B   D0
        BEQ.S   .ro_flags
        SUBQ.B  #1,D3
        BNE.S   .ro_info
        BRA.S   .ro_next
.ro_flags:
        MOVEQ   #2,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_INFO_FLAGS).W,D0
        ANDI.B  #RBCP_PIPE_FLAG_OUT,D0
        BEQ.S   .ro_next
        MOVE.B  D4,D0
        BSR     log_open
        BSR     line_reset
        LEA     (str_start).L,A0
        BSR     line_str
        BSR     line_send
        BRA.S   .ro_out
.ro_next:
        ADDQ.B  #1,D4
        CMP.B   D2,D4
        BCS.S   .ro_try
.ro_out:
        MOVEM.L (SP)+,D0-D4/A0
        RTS

; ---------------------------------------------------------------------------
; report_phase — where the run has got to, every PHASE_COMMANDS commands.
;
; This is the heartbeat and the result both.  A run left alone says one of
; these every phase, and a log that has stopped saying them has stopped.
;
; Each state of chip DMA gets its own sent, errors and ratio.  The run's sent
; and errors are not here: they are the two states added, and one ratio over
; both says how long the run spent in each rather than anything about the
; machine.  Lost is the run's, because a device that stopped answering stopped
; for the run, and RUN in front of it says so.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
report_phase:
        TST.B   VAR_PIPE_PRESENT
        BNE.S   .rp_go
        RTS
.rp_go:
        MOVEM.L D0/A0,-(SP)
        BSR     line_reset
        LEA     (str_phase).L,A0
        BSR     line_str
        MOVE.B  MTR_PHASE_NO,D0
        BSR     line_hex8
        MOVE.B  MTR_PHASE_NO+1,D0
        BSR     line_hex8
        LEA     (str_gap).L,A0
        BSR     line_str
        LEA     (str_vary).L,A0
        BSR     line_str
        LEA     (str_on).L,A0
        BSR     line_str
        MOVEQ   #VARY_ON,D0
        BSR     line_state
        LEA     (str_off).L,A0
        BSR     line_str
        MOVEQ   #VARY_OFF,D0
        BSR     line_state
        LEA     (str_run).L,A0
        BSR     line_str
        LEA     (str_lost).L,A0
        BSR     line_str
        BSR     total_lost
        BSR     line_num
        BSR     line_send
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; report_failure — the whole of the last failure, as one line.
;
; Sent straight away rather than kept, because the session may not survive to
; the next chance.  Where it does not survive, these writes fail too and the
; line is cut short — which the machine reading it can see.
;
; It names the state the machine was in when the command went out, so that it
; can be put against the phase line's figures.  The counts it ends with are
; the run's, and say RUN, so they are not read as that state's.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
report_failure:
        TST.B   VAR_PIPE_PRESENT
        BNE.S   .rf_go
        RTS
.rf_go:
        MOVEM.L D0-D1/A0,-(SP)
        BSR     line_reset
        LEA     (str_fail).L,A0
        BSR     line_str
        MOVE.B  MTR_FAIL_STAGE,D0
        BSR     line_hex8
        LEA     (str_gap).L,A0
        BSR     line_str
        LEA     (str_vary).L,A0
        BSR     line_str
        LEA     (str_on).L,A0
        TST.B   MTR_VARY_IDX
        BEQ.S   .rf_state
        LEA     (str_off).L,A0
.rf_state:
        BSR     line_str
        MOVEQ   #' ',D0
        BSR     line_ch

        MOVEQ   #0,D1
        MOVE.B  MTR_FAIL_TEST,D1
        LSL.W   #2,D1                   ; a long per name
        LEA     (test_names).L,A0
        MOVEA.L (A0,D1.W),A0
        BSR     line_str

        LEA     (str_sent).L,A0
        BSR     line_str
        MOVE.B  MTR_FAIL_GROUP,D0
        BSR     line_field
        MOVE.B  MTR_FAIL_CMD,D0
        BSR     line_field
        MOVE.B  MTR_FAIL_ARGS+0,D0
        BSR     line_field
        MOVE.B  MTR_FAIL_ARGS+1,D0
        BSR     line_field
        MOVE.B  MTR_FAIL_ARGS+2,D0
        BSR     line_field
        LEA     (str_tok).L,A0
        BSR     line_str
        MOVE.B  MTR_FAIL_TOK,D0
        BSR     line_hex8

        LEA     (str_got).L,A0
        BSR     line_str
        MOVE.B  MTR_FAIL_HDR+0,D0
        BSR     line_field
        MOVE.B  MTR_FAIL_HDR+1,D0
        BSR     line_field
        MOVE.B  MTR_FAIL_HDR+2,D0
        BSR     line_field
        MOVE.B  MTR_FAIL_HDR+4,D0
        BSR     line_field
        MOVE.B  MTR_FAIL_HDR+5,D0
        BSR     line_hex8

        LEA     (str_run).L,A0
        BSR     line_str
        LEA     (str_ok).L,A0
        BSR     line_str
        BSR     total_sent
        BSR     line_num
        LEA     (str_bad).L,A0
        BSR     line_str
        BSR     total_bad
        BSR     line_num
        BSR     line_send
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; report_recovery — D0.B = 0 the device came back, anything else it did not.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
report_recovery:
        MOVEM.L D0/A0,-(SP)
        TST.B   VAR_PIPE_PRESENT
        BEQ.S   .rr_out
        BSR     line_reset
        LEA     (str_back).L,A0
        TST.B   D0
        BEQ.S   .rr_say
        LEA     (str_gone).L,A0
.rr_say:
        BSR     line_str
        BSR     line_send
.rr_out:
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; line_state — D0.B = a chip DMA setting.  " SENT n ERR n", and " 1 IN n"
; once that setting has a failure to divide by.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
line_state:
        MOVEM.L D0-D2/A0,-(SP)
        MOVEQ   #0,D2
        MOVE.B  D0,D2
        LSL.W   #2,D2                   ; a long per counter
        LEA     (str_ok).L,A0
        BSR     line_str
        LEA     (MTR_VARY_SENT).W,A0
        MOVE.L  (A0,D2.W),MTR_NUM_VAL
        BSR     line_num
        LEA     (str_bad).L,A0
        BSR     line_str
        LEA     (MTR_VARY_BAD).W,A0
        MOVE.L  (A0,D2.W),MTR_NUM_VAL
        BSR     line_num
        LEA     (MTR_VARY_BAD).W,A0
        MOVE.L  (A0,D2.W),D1
        BEQ.S   .ls_out                 ; no failure is not a measurement
        MOVE.L  D1,MTR_NUM_DEN
        LEA     (str_one_in).L,A0
        BSR     line_str
        LEA     (MTR_VARY_SENT).W,A0
        MOVE.L  (A0,D2.W),MTR_NUM_VAL
        BSR     num_div
        BSR     line_num
.ls_out:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ===========================================================================
; The line buffer
; ===========================================================================

line_reset:
        CLR.B   MTR_LINE_LEN
        RTS

; ---------------------------------------------------------------------------
; line_ch — D0.B = character.  Anything past the buffer is dropped rather than
; written over what is behind it.
; Clobbers (saved/restored): D1/A0
; ---------------------------------------------------------------------------
line_ch:
        MOVEM.L D1/A0,-(SP)
        MOVEQ   #0,D1
        MOVE.B  MTR_LINE_LEN,D1
        CMPI.W  #LINE_MAX,D1
        BCC.S   .lc_full
        LEA     (MTR_LINE).W,A0
        MOVE.B  D0,(A0,D1.W)
        ADDQ.B  #1,MTR_LINE_LEN
.lc_full:
        MOVEM.L (SP)+,D1/A0
        RTS

; line_str — A0 = a null-terminated string.
; Clobbers (saved/restored): D0/A0
line_str:
        MOVEM.L D0/A0,-(SP)
.ls_ch:
        MOVE.B  (A0)+,D0
        BEQ.S   .ls_done
        BSR     line_ch
        BRA.S   .ls_ch
.ls_done:
        MOVEM.L (SP)+,D0/A0
        RTS

; line_hex8 — D0.B = value, as two digits.
; Clobbers (saved/restored): D0/D2
line_hex8:
        MOVEM.L D0/D2,-(SP)
        MOVE.B  D0,D2
        LSR.B   #4,D0
        BSR.S   .lh_conv
        BSR     line_ch
        MOVE.B  D2,D0
        ANDI.B  #$0F,D0
        BSR.S   .lh_conv
        BSR     line_ch
        MOVEM.L (SP)+,D0/D2
        RTS
.lh_conv:
        CMPI.B  #10,D0
        BCS.S   .lh_dig
        ADDI.B  #'A'-10,D0
        RTS
.lh_dig:
        ADDI.B  #'0',D0
        RTS

; line_field — D0.B = value, as a space and two digits.
; Clobbers (saved/restored): D0/D2
line_field:
        MOVEM.L D0/D2,-(SP)
        MOVE.B  D0,D2
        MOVEQ   #' ',D0
        BSR     line_ch
        MOVE.B  D2,D0
        BSR     line_hex8
        MOVEM.L (SP)+,D0/D2
        RTS

; line_num — MTR_NUM_VAL in decimal, no leading zeros.
; Clobbers (saved/restored): D0-D3/A0-A1
line_num:
        MOVEM.L D0-D3/A0-A1,-(SP)
        BSR     num_dec
        LEA     (MTR_NUM_TXT).W,A1
        MOVEQ   #0,D2
        MOVE.B  MTR_NUM_FIRST,D2
        ADDA.W  D2,A1
        MOVEQ   #NUM_DIGITS-1,D3
        SUB.W   D2,D3                   ; the digits left, less one
.ln_ch:
        MOVE.B  (A1)+,D0
        BSR     line_ch
        DBF     D3,.ln_ch
        MOVEM.L (SP)+,D0-D3/A0-A1
        RTS

; ---------------------------------------------------------------------------
; line_send — the buffer down the pipe, with the newline that ends it.
;
; The newline is part of the line rather than something the log adds, because
; a phase line and a failure line are read by a machine a byte at a time.
; pipe_puts takes it from there: it chunks the line, sends each chunk again
; where the device will not take it, and owes a newline where it gave up.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
line_send:
        MOVEM.L D0-D1/A0,-(SP)
        MOVEQ   #$0A,D0
        BSR     line_ch
        MOVEQ   #0,D1
        MOVE.B  MTR_LINE_LEN,D1
        LEA     (MTR_LINE).W,A0
        CLR.B   (A0,D1.W)               ; the end pipe_puts reads up to
        BSR     pipe_puts
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ===========================================================================
; The arithmetic behind the headline
;
; The number a stranger reads off the screen is commands sent divided by
; commands the device got wrong, in decimal, because nobody quotes a
; hexadecimal reliability figure.  Both counts are 32 bits, so the division is
; 32 by 32 and the answer takes the ten digits 4294967295 has.  All of it is
; worked out once per screen refresh and never once per command.
; ===========================================================================

; ---------------------------------------------------------------------------
; num_div — MTR_NUM_VAL = MTR_NUM_VAL / MTR_NUM_DEN, shift and subtract.
;
; Doubling the partial remainder and taking in the next bit can need one bit
; more than the divisor's thirty-two.  That bit falls out of the shift into
; the carry, and a remainder that produced it is certainly at least the
; divisor, which is what keeps a divisor above $80000000 from giving a wrong
; answer.
;
; The caller must not ask for a division by zero.  A ratio taken from no
; failures is not a measurement, and the callers say so rather than divide.
; Clobbers (saved/restored): D0-D4
; ---------------------------------------------------------------------------
num_div:
        MOVEM.L D0-D4,-(SP)
        MOVE.L  MTR_NUM_VAL,D0          ; dividend, shifted out of the top
        MOVE.L  MTR_NUM_DEN,D1
        MOVEQ   #0,D2                   ; remainder
        MOVEQ   #0,D3                   ; quotient
        MOVEQ   #32-1,D4
.nd_bit:
        ADD.L   D3,D3                   ; quotient up, this bit clear
        ADD.L   D0,D0                   ; dividend up, its top bit into X
        ADDX.L  D2,D2                   ; and into the remainder
        BCS.S   .nd_fits                ; the remainder overflowed 32 bits
        CMP.L   D1,D2
        BCS.S   .nd_next
.nd_fits:
        SUB.L   D1,D2
        ADDQ.L  #1,D3
.nd_next:
        DBF     D4,.nd_bit
        MOVE.L  D3,MTR_NUM_VAL
        MOVEM.L (SP)+,D0-D4
        RTS

; ---------------------------------------------------------------------------
; num_dec — MTR_NUM_VAL to ten ASCII digits in MTR_NUM_TXT, right aligned with
; the leading zeros blanked, and MTR_NUM_FIRST pointing at the first of them.
; The last digit is a digit even where the whole number is zero.
;
; Repeated subtraction of a power of ten, at most nine goes a digit.
; Clobbers (saved/restored): D0-D4/A0-A1
; ---------------------------------------------------------------------------
num_dec:
        MOVEM.L D0-D4/A0-A1,-(SP)
        MOVE.L  MTR_NUM_VAL,D0
        LEA     (pow10).L,A0
        LEA     (MTR_NUM_TXT).W,A1
        MOVEQ   #NUM_DIGITS-1,D4
.ndc_digit:
        MOVE.L  (A0)+,D1
        MOVEQ   #'0',D2
.ndc_sub:
        CMP.L   D1,D0
        BCS.S   .ndc_done
        SUB.L   D1,D0
        ADDQ.B  #1,D2
        BRA.S   .ndc_sub
.ndc_done:
        MOVE.B  D2,(A1)+
        DBF     D4,.ndc_digit

        LEA     (MTR_NUM_TXT).W,A1
        MOVEQ   #0,D3
        MOVEQ   #NUM_DIGITS-2,D4              ; the last digit always stands
.ndc_blank:
        CMPI.B  #'0',(A1)
        BNE.S   .ndc_first
        MOVE.B  #' ',(A1)+
        ADDQ.B  #1,D3
        DBF     D4,.ndc_blank
.ndc_first:
        MOVE.B  D3,MTR_NUM_FIRST
        MOVEM.L (SP)+,D0-D4/A0-A1
        RTS

; ===========================================================================
; The screen
;
; The words are drawn once by draw_frame and the numbers over them by
; draw_counts as they change.  A loop that redrew the whole thing every turn
; would spend more time on the screen than on the device, and every command
; not sent is a sample not taken.
; ===========================================================================

; ---------------------------------------------------------------------------
; draw_title — the title bar, before anything has been asked of the device.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_title:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #PEN_GOLD,VAR_PEN
        MOVEQ   #ROW_TITLE,D0
        BSR     screen_fill_row
        MOVE.B  #PEN_BG,VAR_PEN
        MOVE.B  #PEN_GOLD,VAR_PEN_BG
        LEA     (str_title).L,A0
        MOVE.B  #COL_TITLE,D1
        MOVE.B  #ROW_TITLE,D2
        BSR     screen_print
        LEA     (str_brand).L,A0
        MOVE.B  #COL_BRAND,D1
        MOVE.B  #ROW_TITLE,D2
        BSR     screen_print
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_title_at — D2.B = row.  The heading err_halt draws on the error screen.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_title_at:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #PEN_GOLD,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        LEA     (str_title).L,A0
        BSR     screen_print_centred
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_frame — everything on the screen that does not change.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
draw_frame:
        MOVEM.L D0-D3/A0,-(SP)

        MOVE.B  #PEN_TEXT,VAR_PEN
        LEA     (MTR_DEV_TYPE).W,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_DEV,D2
        BSR     screen_print
        LEA     (MTR_DEV_VER).W,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_VER,D2
        BSR     screen_print
        LEA     (MTR_PROTO).W,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_PROTO,D2
        BSR     screen_print

        ; Which pipe the report goes down, or that there is none and the only
        ; record of this run is the screen.
        MOVE.B  #ROW_PIPE,D2
        MOVE.B  #COL_TEXT,D1
        TST.B   VAR_PIPE_PRESENT
        BEQ.S   .df_no_pipe
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_pipe).L,A0
        BSR     screen_print
        ADDI.B  #str_pipe_len,D1
        MOVE.B  VAR_LOG_PIPE,D0
        BSR     print_hex_byte
        BRA.S   .df_band
.df_no_pipe:
        MOVE.B  #PEN_WARN,VAR_PEN
        LEA     (str_no_pipe).L,A0
        BSR     screen_print

        ; The headline gets a band of its own, so the numbers somebody is
        ; meant to read off the screen cannot be missed.
.df_band:
        MOVE.B  #PEN_GOLD,VAR_PEN
        MOVEQ   #ROW_BIG,D0
        BSR     screen_fill_row
        MOVE.B  #PEN_BG,VAR_PEN
        MOVE.B  #PEN_GOLD,VAR_PEN_BG
        LEA     (str_big_on).L,A0
        MOVE.B  #COL_BIG_ON_LBL,D1
        MOVE.B  #ROW_BIG,D2
        BSR     screen_print
        LEA     (str_big_off).L,A0
        MOVE.B  #COL_BIG_OFF_LBL,D1
        MOVE.B  #ROW_BIG,D2
        BSR     screen_print
        MOVE.B  #PEN_BG,VAR_PEN_BG

        ; The run's own counts, and the lost that is part of the errors above
        ; it rather than an addition to them.
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_sent_lbl).L,A0
        MOVE.B  #COL_RAW_SENT_LBL,D1
        MOVE.B  #ROW_RAW,D2
        BSR     screen_print
        LEA     (str_bad_lbl).L,A0
        MOVE.B  #COL_RAW_BAD_LBL,D1
        MOVE.B  #ROW_RAW,D2
        BSR     screen_print
        LEA     (str_lost_lbl).L,A0
        MOVE.B  #COL_RAW_LOST_LBL,D1
        MOVE.B  #ROW_LOST,D2
        BSR     screen_print

        ; The per-command table, which separates a fault reaching every
        ; command from one confined to a single group.
        LEA     (str_head_cmd).L,A0
        MOVE.B  #COL_NAME,D1
        MOVE.B  #ROW_HEAD,D2
        BSR     screen_print
        LEA     (str_head_sent).L,A0
        MOVE.B  #COL_HEAD_SENT,D1
        MOVE.B  #ROW_HEAD,D2
        BSR     screen_print
        LEA     (str_head_bad).L,A0
        MOVE.B  #COL_HEAD_BAD,D1
        MOVE.B  #ROW_HEAD,D2
        BSR     screen_print

        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEQ   #0,D3
.df_name:
        MOVE.W  D3,D0
        LSL.W   #2,D0                   ; a long per name
        LEA     (test_names).L,A0
        MOVEA.L (A0,D0.W),A0
        MOVE.B  #COL_NAME,D1
        MOVE.B  #ROW_FIRST,D2
        ADD.B   D3,D2
        BSR     screen_print
        ADDQ.W  #1,D3
        CMPI.W  #TEST_COUNT,D3
        BCS.S   .df_name

        ; A row for each state of chip DMA, sent as well as errors: without
        ; the sent count a state that has come through half a million commands
        ; untouched reads exactly like one that was never tried.
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVEQ   #0,D3
.df_vary:
        MOVE.W  D3,D0
        LSL.W   #2,D0
        LEA     (vary_names).L,A0
        MOVEA.L (A0,D0.W),A0
        MOVE.B  #COL_VARY_MARK,D1
        MOVE.B  #ROW_VARY,D2
        ADD.B   D3,D2
        BSR     screen_print
        LEA     (str_sent_lbl).L,A0
        MOVE.B  #COL_VARY_SENTLBL,D1
        BSR     screen_print
        LEA     (str_bad_lbl).L,A0
        MOVE.B  #COL_VARY_BADLBL,D1
        BSR     screen_print
        ADDQ.W  #1,D3
        CMPI.W  #VARY_COUNT,D3
        BCS.S   .df_vary

        LEA     (str_keys).L,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_KEYS,D2
        BSR     screen_print
        MOVE.B  #PEN_TEXT,VAR_PEN

        BSR     draw_vary
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; draw_vary — which state of chip DMA is running now, as a marker in the left
; hand column so nothing else has to be redrawn.
; Clobbers (saved/restored): D0-D3
; ---------------------------------------------------------------------------
draw_vary:
        MOVEM.L D0-D3,-(SP)
        MOVE.B  #PEN_MARK,VAR_PEN
        MOVEQ   #0,D3
.dv_row:
        MOVEQ   #' ',D0
        CMP.B   MTR_VARY_IDX,D3
        BNE.S   .dv_put
        MOVEQ   #'>',D0
.dv_put:
        MOVEQ   #0,D1                   ; the left hand column
        MOVE.B  D3,D2
        ADDI.B  #ROW_VARY,D2
        BSR     screen_putchar
        ADDQ.B  #1,D3
        CMPI.B  #VARY_COUNT,D3
        BCS.S   .dv_row
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D3
        RTS

; ---------------------------------------------------------------------------
; draw_counts — the numbers, and only the numbers.
;
; Every number is worked out into its slot first and the slots go on the
; screen afterwards, in one run.  A photograph of the screen has to have the
; totals row as the sum of the rows under it, and drawing each field as soon
; as it is worked out leaves the top of the screen carrying this pass's
; figures and the bottom the last pass's for as long as the arithmetic takes —
; a 32-bit divide and a dozen decimal conversions, which is long enough to
; photograph.
;
; Nothing else runs while this does.  Interrupts are masked from reset, so the
; counts cannot move under it.  What has to be held still is the screen, not
; the counters.
;
; A refresh is time the meter is not sending, so stage_num converts only the
; counts that have moved since the last one.  On a run with nothing going
; wrong six of the seventeen fields move and the other eleven cost a compare.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
draw_counts:
        MOVEM.L D0-D3/A0,-(SP)

        MOVEQ   #VARY_ON,D3
        MOVEQ   #FLD_BIG_ON,D2
        BSR     stage_ratio
        MOVEQ   #VARY_OFF,D3
        MOVEQ   #FLD_BIG_OFF,D2
        BSR     stage_ratio

        BSR     total_sent
        MOVEQ   #FLD_SENT,D0
        BSR     stage_num
        BSR     total_bad
        MOVEQ   #FLD_ERR,D0
        BSR     stage_num
        BSR     total_lost
        MOVEQ   #FLD_LOST,D0
        BSR     stage_num

        MOVEQ   #0,D3
.dc_cmd:
        MOVE.W  D3,D2
        LSL.W   #2,D2
        LEA     (MTR_CMD_SENT).W,A0
        MOVE.L  (A0,D2.W),MTR_NUM_VAL
        MOVE.W  D3,D0
        ADD.W   D0,D0
        ADDI.W  #FLD_CMD,D0
        BSR     stage_num
        LEA     (MTR_CMD_BAD).W,A0
        MOVE.L  (A0,D2.W),MTR_NUM_VAL
        MOVE.W  D3,D0
        ADD.W   D0,D0
        ADDI.W  #FLD_CMD+1,D0
        BSR     stage_num
        ADDQ.W  #1,D3
        CMPI.W  #TEST_COUNT,D3
        BCS.S   .dc_cmd

        MOVEQ   #0,D3
.dc_vary:
        MOVE.W  D3,D2
        LSL.W   #2,D2
        LEA     (MTR_VARY_SENT).W,A0
        MOVE.L  (A0,D2.W),MTR_NUM_VAL
        MOVE.W  D3,D0
        ADD.W   D0,D0
        ADDI.W  #FLD_VARY,D0
        BSR     stage_num
        LEA     (MTR_VARY_BAD).W,A0
        MOVE.L  (A0,D2.W),MTR_NUM_VAL
        MOVE.W  D3,D0
        ADD.W   D0,D0
        ADDI.W  #FLD_VARY+1,D0
        BSR     stage_num
        ADDQ.W  #1,D3
        CMPI.W  #VARY_COUNT,D3
        BCS.S   .dc_vary

        CLR.B   MTR_FIRST_DRAW          ; every slot now holds characters
        BSR     draw_paint
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; stage_ratio — D3.W = a state of chip DMA, D2.W = the field.  One command
; wrong in how many at that state, or dashes where it has not got one wrong
; there yet.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
stage_ratio:
        MOVEM.L D0-D1/A0,-(SP)
        MOVE.W  D3,D0
        LSL.W   #2,D0
        LEA     (MTR_VARY_BAD).W,A0
        MOVE.L  (A0,D0.W),D1
        BEQ.S   .sr_none
        MOVE.L  D1,MTR_NUM_DEN
        LEA     (MTR_VARY_SENT).W,A0
        MOVE.L  (A0,D0.W),MTR_NUM_VAL
        BSR     num_div
        MOVE.W  D2,D0
        BSR     stage_num
        BRA.S   .sr_out
.sr_none:
        MOVE.W  D2,D0
        BSR     stage_dashes
.sr_out:
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; stage_num — D0.W = a field, MTR_NUM_VAL = the value.  Its ten digits, right
; aligned, into the field's slot.
;
; A count that has not moved since this field was last staged already has its
; digits in the slot, and turning a 32-bit count into ten of them is the
; dearest thing a refresh does.  MTR_WAS carries the count each field was made
; from, so the compare stands in for the conversion.  The first refresh
; converts every field, there being nothing behind the slots to compare with.
;
; A field that converts is marked in MTR_DIRTY, which is the only thing
; draw_paint looks at.
; Clobbers (saved/restored): D0-D2/A0-A1
; ---------------------------------------------------------------------------
stage_num:
        MOVEM.L D0-D2/A0-A1,-(SP)
        MOVE.W  D0,D2
        LSL.W   #2,D2                   ; a long a field
        LEA     (MTR_WAS).W,A1
        TST.B   MTR_FIRST_DRAW
        BNE.S   .sn_convert
        MOVE.L  MTR_NUM_VAL,D1
        CMP.L   (A1,D2.W),D1
        BEQ.S   .sn_out
.sn_convert:
        MOVE.L  MTR_NUM_VAL,(A1,D2.W)
        LSR.W   #2,D2                   ; and back to a byte a field
        LEA     (MTR_DIRTY).W,A1
        MOVE.B  #1,(A1,D2.W)
        BSR     num_dec
        MULU    #FLD_WIDTH,D0
        LEA     (MTR_NOW).W,A1
        ADDA.W  D0,A1
        LEA     (MTR_NUM_TXT).W,A0
        MOVEQ   #FLD_WIDTH-1,D1
.sn_copy:
        MOVE.B  (A0)+,(A1)+
        DBF     D1,.sn_copy
.sn_out:
        MOVEM.L (SP)+,D0-D2/A0-A1
        RTS

; ---------------------------------------------------------------------------
; stage_dashes — D0.W = a field.  Dashes into its slot, for a ratio taken from
; no failures, which is not a measurement.
;
; Only a ratio field ever reads dashes, and a ratio is commands sent over
; commands wrong with at least one wrong, so it is never below one.  Zero in
; MTR_WAS is therefore a count no ratio can match, and the first failure at
; this state converts rather than finding the field unchanged.
; Clobbers (saved/restored): D0-D2/A1
; ---------------------------------------------------------------------------
stage_dashes:
        MOVEM.L D0-D2/A1,-(SP)
        MOVE.W  D0,D2
        LSL.W   #2,D2
        LEA     (MTR_WAS).W,A1
        TST.B   MTR_FIRST_DRAW
        BNE.S   .sd_write
        TST.L   (A1,D2.W)
        BEQ.S   .sd_out                 ; the slot already holds dashes
.sd_write:
        CLR.L   (A1,D2.W)
        LSR.W   #2,D2                   ; and back to a byte a field
        LEA     (MTR_DIRTY).W,A1
        MOVE.B  #1,(A1,D2.W)
        MULU    #FLD_WIDTH,D0
        LEA     (MTR_NOW).W,A1
        ADDA.W  D0,A1
        MOVEQ   #FLD_WIDTH-5-1,D1
.sd_pad:
        MOVE.B  #' ',(A1)+
        DBF     D1,.sd_pad
        MOVEQ   #5-1,D1
.sd_dash:
        MOVE.B  #'-',(A1)+
        DBF     D1,.sd_dash
.sd_out:
        MOVEM.L (SP)+,D0-D2/A1
        RTS

; ---------------------------------------------------------------------------
; draw_paint — the characters in each slot the screen does not already have.
;
; A count that has gone up by a few hundred moves its last two or three digits
; and no more, so most of a refresh writes nothing.
;
; A field staging left alone cannot differ from the screen, so only the ones
; MTR_DIRTY marks are walked at all.  The mark is cleared as the field is
; painted, which is what makes the next refresh start from a clean sheet.
; Clobbers (saved/restored): D0-D7/A0-A2
; ---------------------------------------------------------------------------
draw_paint:
        MOVEM.L D0-D7/A0-A2,-(SP)
        MOVEQ   #0,D7
.dp_field:
        MOVE.W  D7,D6
        LEA     (MTR_DIRTY).W,A0
        TST.B   (A0,D6.W)
        BEQ     .dp_next
        CLR.B   (A0,D6.W)
        LEA     (fld_row).L,A0
        MOVE.B  (A0,D6.W),D5
        LEA     (fld_col).L,A0
        MOVE.B  (A0,D6.W),D4
        LEA     (fld_pen).L,A0
        MOVE.B  (A0,D6.W),VAR_PEN
        LEA     (fld_bg).L,A0
        MOVE.B  (A0,D6.W),VAR_PEN_BG
        MULU    #FLD_WIDTH,D6
        LEA     (MTR_NOW).W,A1
        ADDA.W  D6,A1
        LEA     (MTR_SHOWN).W,A2
        ADDA.W  D6,A2
        MOVEQ   #FLD_WIDTH-1,D3
.dp_ch:
        MOVE.B  (A1)+,D0
        CMP.B   (A2),D0
        BEQ.S   .dp_same
        MOVE.B  D0,(A2)
        MOVE.B  D4,D1
        MOVE.B  D5,D2
        BSR     screen_putchar
.dp_same:
        ADDQ.L  #1,A2
        ADDQ.B  #1,D4
        DBF     D3,.dp_ch
.dp_next:
        ADDQ.W  #1,D7
        CMPI.W  #FLD_COUNT,D7
        BCS     .dp_field
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVEM.L (SP)+,D0-D7/A0-A2
        RTS

; ---------------------------------------------------------------------------
; draw_record — what the last failure was, whole.
;
; Three rows: the way it went wrong, the frame that went out, and the
; response header as the device had left it when the host gave up.  Reading
; the last two together is the diagnosis: a GOT row naming a command other
; than the one on the SENT row is a frame the device did not receive as it was
; sent.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
draw_record:
        MOVEM.L D0-D3/A0,-(SP)
        MOVEQ   #ROW_NOTE,D0
        BSR     clear_row
        MOVEQ   #ROW_REC_SENT,D0
        BSR     clear_row
        MOVEQ   #ROW_REC_GOT,D0
        BSR     clear_row

        MOVEQ   #0,D3
        MOVE.B  MTR_FAIL_STAGE,D3
        CMPI.B  #4,D3
        BCS.S   .dr_known
        MOVEQ   #0,D3                   ; a stage the library never reports
.dr_known:
        LSL.W   #2,D3
        LEA     (stage_names).L,A0
        MOVEA.L (A0,D3.W),A0
        MOVE.B  #PEN_BAD,VAR_PEN
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_NOTE,D2
        BSR     screen_print

        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_rec_sent).L,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_REC_SENT,D2
        BSR     screen_print
        ADDI.B  #str_rec_len,D1
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  MTR_FAIL_GROUP,D0
        BSR     print_hex_byte
        ADDQ.B  #1,D1
        MOVE.B  MTR_FAIL_CMD,D0
        BSR     print_hex_byte
        ADDQ.B  #1,D1
        MOVE.B  MTR_FAIL_ARGS+0,D0
        BSR     print_hex_byte
        ADDQ.B  #1,D1
        MOVE.B  MTR_FAIL_ARGS+1,D0
        BSR     print_hex_byte
        ADDQ.B  #1,D1
        MOVE.B  MTR_FAIL_ARGS+2,D0
        BSR     print_hex_byte
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_d_tok).L,A0
        ADDQ.B  #2,D1
        BSR     screen_print
        ADDI.B  #4,D1                   ; "TOK:" is four characters
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  MTR_FAIL_TOK,D0
        BSR     print_hex_byte

        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_rec_got).L,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_REC_GOT,D2
        BSR     screen_print
        ADDI.B  #str_rec_len,D1
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  MTR_FAIL_HDR+0,D0
        BSR     print_hex_byte
        ADDQ.B  #1,D1
        MOVE.B  MTR_FAIL_HDR+1,D0
        BSR     print_hex_byte
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_d_tok).L,A0
        ADDQ.B  #2,D1
        BSR     screen_print
        ADDI.B  #4,D1
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  MTR_FAIL_HDR+2,D0
        BSR     print_hex_byte
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_d_prg).L,A0
        ADDQ.B  #2,D1
        BSR     screen_print
        ADDI.B  #4,D1                   ; "PRG:"
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  MTR_FAIL_HDR+4,D0
        BSR     print_hex_byte
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_d_rsp).L,A0
        ADDQ.B  #2,D1
        BSR     screen_print
        ADDI.B  #4,D1                   ; "RSP:"
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  MTR_FAIL_HDR+5,D0
        BSR     print_hex_byte

        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; clear_row — D0.B = row, back to background.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
clear_row:
        MOVEM.L D0,-(SP)
        MOVE.B  #PEN_BG,VAR_PEN
        BSR     screen_fill_row
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0
        RTS

; ============================================================
; Shared Amiga routines (run from RAM)
; ============================================================
        INCLUDE "../amiga-common/amiga_input.s"
        INCLUDE "../amiga-common/amiga_log.s"
        INCLUDE "../amiga-common/amiga_error.s"
        INCLUDE "../amiga-common/amiga_time.s"

; ============================================================
; RBCP library (runs from RAM)
; ============================================================
        INCLUDE "../rbcp/rbcp.s"

        INCLUDE "../amiga-common/amiga_screen.s"

        EVEN
ram_section_rom_end:

; ============================================================
; ROM DATA SECTION
; Copper template, font, strings and tables.  Reached from RAM code by
; absolute long address, so correct from any PC.
; ============================================================

        INCLUDE "../amiga-common/amiga_screen_data.s"

        EVEN
str_title:
        DC.B    "RBCP METER "
        APP_VERSION
        DC.B    0
        EVEN
str_brand:
        DC.B    "PIERS.ROCKS",0

        INCLUDE "../amiga-common/amiga_error_data.s"
        INCLUDE "../amiga-common/amiga_log_data.s"
        INCLUDE "../amiga-common/amiga_diag_data.s"
        INCLUDE "../amiga-common/amiga_input_data.s"

; ---------------------------------------------------------------------------
; Words on the screen
; ---------------------------------------------------------------------------
        EVEN
str_big_on:
        DC.B    "ON 1 IN",0
        EVEN
str_big_off:
        DC.B    "OFF 1 IN",0
        EVEN
str_sent_lbl:
        DC.B    "SENT",0
        EVEN
str_bad_lbl:
        DC.B    "ERR",0
        EVEN
str_lost_lbl:
        DC.B    "LOST",0
        EVEN
str_head_cmd:
        DC.B    "COMMAND",0
        EVEN
str_head_sent:
        DC.B    "SENT",0
        EVEN
str_head_bad:
        DC.B    "ERROR",0
        EVEN
str_pipe:
        DC.B    "REPORTING ON PIPE ",0
str_pipe_len            EQU 18
        EVEN
str_no_pipe:
        DC.B    "NO OUT PIPE AVAILABLE",0
        EVEN
str_keys:
        DC.B    "PRESS S TO SWITCH THE DISPLAY",0
        EVEN
str_rec_sent:
        DC.B    "SENT ",0
        EVEN
str_rec_got:
        DC.B    "GOT  ",0
str_rec_len             EQU 5

; The marker on each chip DMA row.
        EVEN
vary_names:
        DC.L    str_v_on,str_v_off
        EVEN
str_v_on:
        DC.B    "ON ",0
        EVEN
str_v_off:
        DC.B    "OFF",0

; The stage the library reached before it gave up, in the order rbcp_defs.s
; numbers them.  Entry 0 catches a stage the library never reports.
        EVEN
stage_names:
        DC.L    str_s_unknown,str_s_not_taken
        DC.L    str_s_unfinished,str_s_refused
        EVEN
str_s_unknown:
        DC.B    "THE DEVICE STOPPED ANSWERING",0
        EVEN
str_s_not_taken:
        DC.B    "THE DEVICE DID NOT TAKE THE COMMAND",0
        EVEN
str_s_unfinished:
        DC.B    "THE DEVICE TOOK IT AND NEVER FINISHED",0
        EVEN
str_s_refused:
        DC.B    "THE DEVICE REFUSED THE COMMAND",0

; The reasons a session refuses to start, in the order amiga_defs.s numbers
; them.
        EVEN
err_msgs:
        DC.L    msg_err_0,msg_err_1,msg_err_2
        EVEN
msg_err_0:
        DC.B    "NO DEVICE ANSWERED THE KNOCK",0
        EVEN
msg_err_1:
        DC.B    "THE DEVICE REFUSED THE SESSION",0
        EVEN
msg_err_2:
        DC.B    "DEVICE REPORTS INCOMPATIBLE VERSION",0

; ---------------------------------------------------------------------------
; Words on the wire.  These go down the pipe and never reach a screen.
; ---------------------------------------------------------------------------
        EVEN
str_start:
        DC.B    "RBCP METER START "
        APP_VERSION
        DC.B    0
        EVEN
str_phase:
        DC.B    "PH ",0
        EVEN
str_run:
        DC.B    " RUN",0
        EVEN
str_lost:
        DC.B    " LOST ",0
        EVEN
str_one_in:
        DC.B    " 1 IN ",0
        EVEN
str_gap:
        DC.B    " ",0
        EVEN
str_vary:
        DC.B    "DISPLAY",0
        EVEN
str_on:
        DC.B    " ON",0
        EVEN
str_off:
        DC.B    " OFF",0
        EVEN
str_back:
        DC.B    "RECOVERED",0
        EVEN
str_gone:
        DC.B    "RECOVER FAILED",0
        EVEN
str_fail:
        DC.B    "FAIL ",0
        EVEN
str_sent:
        DC.B    " SENT",0
        EVEN
str_tok:
        DC.B    " TOK ",0
        EVEN
str_got:
        DC.B    " GOT",0
        EVEN
str_ok:
        DC.B    " SENT ",0
        EVEN
str_bad:
        DC.B    " ERR ",0

; ---------------------------------------------------------------------------
; The commands under test: group, command, argument count, three arguments.
;
; NOP and GET_PROTOCOL_VERSION carry no arguments, so their frames are two
; bytes.  The two LED commands carry one and two, so theirs are three and
; four.  LED 0 is the first LED any device with LEDs has, and mode 0 is Off,
; which every LED supports — a device with no LEDs fails both every time.
; ---------------------------------------------------------------------------
        EVEN
tests:
        DC.B    $00,$00,0,$00,$00,$00   ; NOP
        DC.B    $01,$06,0,$00,$00,$00   ; GET_PROTOCOL_VERSION
        DC.B    $06,$01,1,$00,$00,$00   ; GET_LED_INFO, LED 0
        DC.B    $06,$02,2,$00,$00,$00   ; GET_LED_MODE_INFO, mode 0 of LED 0

        EVEN
test_names:
        DC.L    str_t_nop,str_t_proto,str_t_led_info,str_t_led_mode
        EVEN
str_t_nop:
        DC.B    "NOP",0
        EVEN
str_t_proto:
        DC.B    "PROTO VER",0
        EVEN
str_t_led_info:
        DC.B    "LED INFO",0
        EVEN
str_t_led_mode:
        DC.B    "LED MODE",0

; ---------------------------------------------------------------------------
; Where each number field goes, in the order draw_counts fills the slots.
; ---------------------------------------------------------------------------
        EVEN
fld_row:
        DC.B    ROW_BIG,ROW_BIG
        DC.B    ROW_RAW,ROW_RAW,ROW_LOST
        DC.B    ROW_FIRST+0,ROW_FIRST+0,ROW_FIRST+1,ROW_FIRST+1
        DC.B    ROW_FIRST+2,ROW_FIRST+2,ROW_FIRST+3,ROW_FIRST+3
        DC.B    ROW_VARY+0,ROW_VARY+0,ROW_VARY+1,ROW_VARY+1
        EVEN
fld_col:
        DC.B    COL_BIG_ON,COL_BIG_OFF
        DC.B    COL_RAW_SENT,COL_RAW_BAD,COL_RAW_LOST
        DC.B    COL_SENT,COL_BAD,COL_SENT,COL_BAD
        DC.B    COL_SENT,COL_BAD,COL_SENT,COL_BAD
        DC.B    COL_VARY_SENT,COL_VARY_BAD,COL_VARY_SENT,COL_VARY_BAD
        EVEN
fld_pen:
        DC.B    PEN_BG,PEN_BG
        DC.B    PEN_TEXT,PEN_BAD,PEN_BAD
        DC.B    PEN_TEXT,PEN_BAD,PEN_TEXT,PEN_BAD
        DC.B    PEN_TEXT,PEN_BAD,PEN_TEXT,PEN_BAD
        DC.B    PEN_TEXT,PEN_BAD,PEN_TEXT,PEN_BAD
        EVEN
fld_bg:
        DC.B    PEN_GOLD,PEN_GOLD
        DC.B    PEN_BG,PEN_BG,PEN_BG
        DC.B    PEN_BG,PEN_BG,PEN_BG,PEN_BG
        DC.B    PEN_BG,PEN_BG,PEN_BG,PEN_BG
        DC.B    PEN_BG,PEN_BG,PEN_BG,PEN_BG

; The powers of ten, largest first, one long each.
        EVEN
pow10:
        DC.L    1000000000,100000000,10000000,1000000,100000
        DC.L    10000,1000,100,10,1

; The RAM code has to land inside the chip RAM a base A500 has.
    ifgt RAM_CODE_BASE+(ram_section_rom_end-ram_section_rom_start)-CHIP_RAM_MIN
    fail "the RAM code section runs past the chip RAM a base A500 has"
    endc

; ============================================================
; Back-channel region — zeroed, at the CPU address the config derives
; ============================================================
        ORG     CONFIG_RBCP_BCH_ABS
        DCB.B   RBCP_BCH_CPU_SPAN,$00

; ============================================================
; Command page — zeroed, one page of device bus cycles
; ============================================================
        ORG     CONFIG_RBCP_CMD_PAGE_ABS
        DCB.B   RBCP_CMD_PAGE_SPAN,$00
