; amiga_pipe.s — Amiga RBCP pipe throughput test
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Purpose
; -------
; The tester pushes a numbered stream down an RBCP pipe as fast as the machine
; will carry it and counts the bytes that went.  The headline is how many go in
; a second.
;
; The window
; ----------
; A window is exactly one second, so the byte count in it is the rate and
; nothing divides.  The CIA-B time of day counter is clocked by horizontal
; sync, which is 15625 lines a second on a PAL machine and 15734 on an NTSC
; one, so the count that makes a second is the machine's and amiga_defs.s holds
; both.  screen_init says which Agnus is fitted.
;
; The tester owns the machine
; ---------------------------
; It is a Kickstart image.  It runs from reset, it never hands the machine
; back, and switching off is what ends a session.  That puts the device's RAM
; slot back the way it was.
;
; ROM image layout, top-aligned — 256 KB from $FC0000 or 512 KB from $F80000:
;
;   ROM SECTION  — executed directly from ROM
;     ROM header, rom_cold_start, JMP rom_entry
;     amiga_hw.s: a500_hw_init, exc_halt, kbd_init, screen_init
;     rom_entry: HW init, screen up, copy RAM section, JMP $28000
;
;   RAM SECTION  — stored in ROM, copied to RAM_CODE_BASE ($28000) at boot
;     ram_entry: the session, then the menu and the run loop
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
;   screen routines read the font from ROM and are called throughout a run, but
;   never between the knock and the response to ENTER_CMD_RESP.
;
; Addressing note:
;   RAM-section code reaches ROM data through explicit absolute long
;   addressing — LEA (label).L,A0 — never PC-relative, because the code is
;   assembled at its ROM address but executes from $28000.

; The tester draws none of the bootloader's artwork, so the pens that carry it
; are free.  A pen already defined keeps its value, so these go in before the
; palette is included.
PEN06_RGB                   EQU $0999       ; labels, dimmer than the figures
PEN07_RGB                   EQU $0FA0       ; nothing to send down
PEN08_RGB                   EQU $04D4       ; the send path in hand
PEN14_RGB                   EQU $0F44       ; refusals and errors

; Definitions first — the ORG below depends on CONFIG_ROM_BASE.  None of
; these emit any code or data.
        INCLUDE "rbcp_config.s"
        INCLUDE "../rbcp/rbcp_defs.s"
        INCLUDE "../amiga-common/amiga_defs.s"
        INCLUDE "amiga_defs.s"

; The version, shown in the heading.  A macro rather than an EQU because it
; expands to text.
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
; ram_entry — the tester proper, running from chip RAM.  The session with the
; device, then the menu.  It does not return.
; ---------------------------------------------------------------------------
ram_entry:
        MOVE.L  #BITPLANE_BASE,VAR_DRAW_BASE
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        CLR.B   VAR_MENU_COL            ; a filled row is the whole row here
        MOVE.W  #FIELD_TICK_NTSC,VAR_TICK_LINE
        TST.B   VAR_IS_PAL
        BEQ.S   .ae_ntsc
        MOVE.W  #FIELD_TICK_PAL,VAR_TICK_LINE
.ae_ntsc:
        ; Nothing here logs.  The pipe is what is being measured, and a log
        ; line down it would be bytes the stream did not send.
        CLR.B   VAR_PIPE_PRESENT

        BSR     screen_clear
        BSR     zero_all
        BSR     clock_pick
        BSR     draw_title              ; before anything is asked of the device

        BSR     sess_open               ; err_halt on the way out where it fails
        BSR     find_pipe
        BSR     tod_start
        BSR     draw_frame
        BSR     draw_counts

        TST.B   PT_HAVE_PIPE
        BEQ.S   .ae_no_pipe
        MOVE.B  #1,PT_ARMED
        MOVEQ   #STAT_ARMED,D0
        BSR     draw_status
        BRA     menu
.ae_no_pipe:
        MOVEQ   #0,D0                   ; find_pipe left which kind of nothing
        MOVE.B  PT_STAT,D0
        BSR     draw_status
        ; fall through

; ---------------------------------------------------------------------------
; menu — the resting state, inside the open session.
;
; Nothing here reads the served image.  The keyboard and the screen are the
; machine's own, so the session is undisturbed for as long as this loop runs.
; ---------------------------------------------------------------------------
menu:
        BSR     amiga_getkey
        TST.B   D0
        BEQ.S   menu
        CMPI.B  #'1',D0
        BNE.S   .mn_not_1
        MOVEQ   #PATH_LIB4,D0
        BRA.S   .mn_path
.mn_not_1:
        CMPI.B  #'2',D0
        BNE.S   .mn_not_2
        MOVEQ   #PATH_LIB1,D0
        BRA.S   .mn_path
.mn_not_2:
        CMPI.B  #'3',D0
        BNE.S   .mn_not_3
        MOVEQ   #PATH_TUNED4,D0
        BRA.S   .mn_path
.mn_not_3:
        CMPI.B  #KEY_RETURN,D0
        BNE.S   .mn_not_ret
        MOVEQ   #0,D0
        BRA     start_run
.mn_not_ret:
        CMPI.B  #KEY_TIMED,D0
        BEQ.S   .mn_timed
        CMPI.B  #KEY_TIMED_LOWER,D0
        BNE.S   menu
.mn_timed:
        MOVEQ   #1,D0
        BRA     start_run
.mn_path:
        MOVE.B  D0,PT_PATH
        BSR     draw_paths
        BRA.S   menu

; ---------------------------------------------------------------------------
; start_run — D0.B = 0 until a key stops it, non-zero for TIMED_SECS windows.
;
; The banner marks the boundary between one run and the next, for whoever is
; reading the stream and for the tool checking it.  It goes out ahead of the
; counters, so the bytes it costs belong to no window.
; ---------------------------------------------------------------------------
start_run:
        MOVE.B  D0,PT_TIMED
        TST.B   PT_ARMED
        BNE.S   .sr_armed
        MOVEQ   #STAT_NOT_ARMED,D0
        BSR     draw_status
        BRA     menu
.sr_armed:
        ADDQ.B  #1,PT_RUN_NO
        ; How a run ends unless something else says otherwise.
        MOVE.B  #STAT_STOPPED,PT_STAT
        CLR.B   PT_LOST
        CLR.B   PT_LINE_TICK

        ; Whatever the path, the banner goes out four bytes at a time.  It is
        ; one line, once.
        MOVE.B  #RBCP_PIPE_WRITE_MAX,PT_CHUNK
        BSR     build_banner
        BSR     send_line
        TST.B   D0
        BNE     run_finish

        MOVE.B  #RBCP_PIPE_WRITE_MAX,PT_CHUNK
        CMPI.B  #PATH_LIB1,PT_PATH
        BNE.S   .sr_chunked
        MOVE.B  #1,PT_CHUNK
.sr_chunked:
        BSR     line_reset
        BSR     zero_run
        MOVEQ   #STAT_RUNNING,D0
        BSR     draw_status
        BSR     draw_counts
        BSR     win_open
        ; fall through

; ---------------------------------------------------------------------------
; run_loop — one line out, then the counters, then the window.
;
; The window is checked once a line, which is once every 64 bytes.  Three CIA
; reads is a few microseconds against a line that costs far more, and the check
; is inside the second it is timing, where it belongs: the figure has to be
; what the machine achieved with its own bookkeeping in the way.
;
; Which send path carries the line is read every pass rather than branched to
; once before the loop, at one compare and one branch against a line that
; costs thousands of cycles.
;
; TUNED4 builds the next line itself, while the device is still working on the
; line's last command.  The other two paths have no wait to put it in.
;
; The keyboard is read every KEY_LINES lines, which is where the cost of
; reading it and the wait before a stop is noticed are both small.
; ---------------------------------------------------------------------------
run_loop:
        CMPI.B  #PATH_TUNED4,PT_PATH
        BEQ.S   .rl_tuned
        BSR     send_line
        TST.B   D0
        BNE     run_finish
        BSR     line_next
        BRA.S   .rl_sent
.rl_tuned:
        BSR     send_tuned_line
        TST.B   D0
        BNE     run_finish
.rl_sent:
        BSR     count_line

        BSR     win_step
        TST.B   D0
        BEQ.S   .rl_keys
        BSR     draw_counts
        TST.B   PT_TIMED
        BEQ.S   .rl_keys
        MOVE.L  PT_SECS,D0
        CMPI.L  #TIMED_SECS,D0
        BCC.S   run_stop

.rl_keys:
        ADDQ.B  #1,PT_LINE_TICK
        MOVE.B  PT_LINE_TICK,D0
        ANDI.B  #KEY_LINES-1,D0
        BNE     run_loop
        BSR     amiga_getkey
        CMPI.B  #KEY_RETURN,D0
        BNE     run_loop

run_stop:
        MOVE.B  #STAT_STOPPED,PT_STAT
        ; fall through

; ---------------------------------------------------------------------------
; run_finish — every way out of a run, with PT_STAT holding which.
;
; The reason a run ended stays on the status row afterwards, including where
; the device was brought back, because that is the thing worth reading.  Only a
; device that did not come back replaces it, and then the tester is no longer
; armed and the next attempt to run says so.
; ---------------------------------------------------------------------------
run_finish:
        BSR     calc_mean
        BSR     draw_counts
        MOVEQ   #0,D0
        MOVE.B  PT_STAT,D0
        BSR     draw_status
        TST.B   PT_LOST
        BEQ.S   .rf_done
        BSR     recover
        TST.B   D0
        BEQ.S   .rf_done
        CLR.B   PT_ARMED
        MOVEQ   #STAT_NO_RECOVER,D0
        BSR     draw_status
.rf_done:
        BRA     menu

; ---------------------------------------------------------------------------
; recover — the device is not answering, so put it back together.
;
; RBCP_RESET flushes a partially received command of up to nine argument bytes
; and two framing bytes, which is what a frame that slipped by a byte leaves
; behind.  Command-response mode is entered again rather than the session
; opened from scratch: the rest of opening a session decides whether to talk to
; the device at all, and that was settled before anything called this.
;
; Output: D0.B = 0 back in command-response mode, 1 gave up
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
        MOVEQ   #1,D0
        BRA.S   .rc_out
.rc_back:
        CLR.B   PT_LOST
        MOVEQ   #0,D0
.rc_out:
        MOVEM.L (SP)+,D1
        RTS

; ===========================================================================
; Sending
; ===========================================================================

; ---------------------------------------------------------------------------
; send_line — the 64 bytes in PT_LINE, PT_CHUNK of them a command.
;
; PIPE_WRITE takes the whole chunk or none, so a failure of any kind sends the
; same bytes again.  A retry goes back to the gather rather than to the send,
; because asking the pipe how much room it has is itself a command and writes
; over the payload.
;
; 64 is sixteen whole PIPE_WRITE payloads and sixty-four single-byte ones, so
; neither path ever carries a partial line.
;
; Output: D0.B = 0 the line went, 1 the run is over with PT_STAT saying why
; Clobbers (saved/restored): D1-D4/A0-A1
; ---------------------------------------------------------------------------
send_line:
        MOVEM.L D1-D4/A0-A1,-(SP)
        CLR.B   PT_STALL                ; the stall bound is per line
        MOVEQ   #0,D4                   ; bytes of the line already gone
.sl_chunk:
        LEA     (PT_LINE).W,A0
        ADDA.W  D4,A0
        LEA     (RBCP_ARG0).W,A1
        MOVEQ   #0,D3
        MOVE.B  PT_CHUNK,D3
        MOVE.W  D3,D2
        SUBQ.W  #1,D2
.sl_gather:
        MOVE.B  (A0)+,(A1)+
        DBF     D2,.sl_gather

        MOVE.B  D3,D0                   ; count
        MOVE.B  PT_PIPE,D1
        BSR     rbcp_cmd_pipe_write
        TST.B   D0
        BEQ.S   .sl_taken
        CMPI.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        BNE.S   .sl_dead                ; it did not answer at all
        MOVE.B  D3,D0                   ; the bytes it was offered
        BSR     fault_refused
        TST.B   D0
        BEQ     .sl_chunk               ; the same bytes, gathered afresh
        MOVEQ   #1,D0
        BRA.S   .sl_out
.sl_dead:
        BSR     fault_stage
        MOVEQ   #1,D0
        BRA.S   .sl_out
.sl_taken:
        ADD.W   D3,D4
        CMPI.W  #LINE_LEN,D4
        BCS     .sl_chunk
        MOVEQ   #0,D0
.sl_out:
        MOVEM.L (SP)+,D1-D4/A0-A1
        RTS

; ---------------------------------------------------------------------------
; PAYLOAD_ADDRS — the four payload bytes at A0 as addresses on the command
; page, ready for a frame to read.
;
; Three fit in the address registers the tuned frame no longer needs for the
; group, the command and the count.  There is no fourth left, so payload 3
; stays an offset and its read carries an index.
;
; A macro rather than a subroutine because the place that matters is inside
; send_tuned_line's loop, where a BSR and an RTS are a tenth of a frame.
;
; Input : A0 the four bytes, A5 the command page
; Output: A1, A2, A6 payloads 0 to 2, D7.W payload 3's offset, A0 past the four
; Clobbers: D0
; ---------------------------------------------------------------------------
PAYLOAD_ADDRS MACRO
        MOVEQ   #0,D0
        MOVE.B  (A0)+,D0
        ADD.W   D0,D0
        LEA     (A5,D0.W),A1
        MOVEQ   #0,D0
        MOVE.B  (A0)+,D0
        ADD.W   D0,D0
        LEA     (A5,D0.W),A2
        MOVEQ   #0,D0
        MOVE.B  (A0)+,D0
        ADD.W   D0,D0
        LEA     (A5,D0.W),A6
        MOVEQ   #0,D0
        MOVE.B  (A0)+,D0
        ADD.W   D0,D0
        MOVE.W  D0,D7
        ENDM

; ---------------------------------------------------------------------------
; send_tuned_line — the 64 bytes in PT_LINE, four to a command, without the
; library.
;
; A PIPE_WRITE frame is eight command bytes and eight reads of the command
; page.  Three of those bytes never change at all — the group, the command and
; the count — and each is a displacement off the address register holding the
; command page.  The pipe number is fixed within a line and has an address
; register of its own.  Only the four payload bytes have an address that
; changes from one block to the next.
;
; rbcp_send_cmd reaches the same eight reads through a MOVEM pair of four long
; registers and a byte-to-offset conversion it repeats every time.  That
; difference is what LIB4 against TUNED4 measures.
;
; On real hardware most of a command is the host sitting in the poll waiting
; for the device, so the work that would otherwise follow the poll is done
; between the last command byte and the first read of the back channel instead:
; the next block's four payload addresses, and on a line's last block the
; stripe and sequence for the line after it.  A command then costs the longer
; of the device's turnaround and that work rather than the two added together.
; The poll itself is untouched — nothing sits between its reads, and a turn is
; the same 22 and 26 cycles it was.
;
; A DBcc carries the poll's timeout, so a turn costs what an untimed loop
; would.  It leaves the condition codes alone, so the branch after the loop
; tells an answer apart from a counter that ran out.
;
; PIPE_WRITE is all or nothing, so a refusal sends the same four bytes again.
; fault_refused asks the device how much room the pipe has, which is a command
; in its own right and leaves none of these registers standing, so a retry
; builds them again.  Every block but the last builds them from the buffer.
; The last block's four bytes are not in the buffer any more, because the next
; line has been written over them, so its four addresses are carried across the
; call and used as they stand.
;
; Output: D0.B = 0 the line went, 1 the run is over with PT_STAT saying why
; Clobbers (saved/restored): D1-D7/A0-A6
; ---------------------------------------------------------------------------
send_tuned_line:
        MOVEM.L D1-D7/A0-A6,-(SP)
        CLR.B   PT_STALL                ; the stall bound is per line
        CLR.B   PT_ADVANCED             ; and so is the line's own advance
        MOVEQ   #0,D6                   ; bytes of the line already gone

.stl_setup:
        MOVEA.L #CONFIG_RBCP_CMD_PAGE_ABS,A5
        LEA     (PT_LINE).W,A0
        ADDA.W  D6,A0
        PAYLOAD_ADDRS                   ; the first block has no wait to sit in
        BRA.S   .stl_regs

; A retry of the last block of a line, whose four bytes are in A1, A2, A6 and
; D7 and no longer in the buffer.  A0 is not set because the last block has no
; block after it to work an address out for.
.stl_retry:
        MOVEA.L #CONFIG_RBCP_CMD_PAGE_ABS,A5

.stl_regs:
        MOVEQ   #0,D0
        MOVE.B  PT_PIPE,D0
        ADD.W   D0,D0
        LEA     (A5,D0.W),A3            ; the pipe number's own address
        MOVEA.L #RBCP_TOKEN_LSB_ADDR,A4
        MOVE.B  #RBCP_COMPLETE,D3       ; $BB > 127, so not a MOVEQ
        MOVE.B  #RBCP_STATUS_OK,D4
        MOVE.W  #LINE_LEN,D5
        SUB.W   D6,D5
        LSR.W   #2,D5
        SUBQ.W  #1,D5                   ; blocks left, as DBF counts them

.stl_block:
        MOVE.B  (A4),D2                 ; the token as it stands before the frame
        TST.W   TUNED_GROUP_OFF(A5)     ; group
        TST.W   TUNED_CMD_OFF(A5)       ; command
        TST.W   (A1)                    ; payload 0
        TST.W   (A2)                    ; payload 1
        TST.W   (A6)                    ; payload 2
        TST.W   (A5,D7.W)               ; payload 3
        TST.W   (A3)                    ; pipe
        TST.W   TUNED_COUNT_OFF(A5)     ; count

        ; The device has the frame and is working on it.  So is the host.
        TST.W   D5
        BEQ.S   .stl_last               ; the line's own work, below the poll
        PAYLOAD_ADDRS                   ; the block after this one
.stl_poll:
        MOVE.W  #TUNED_POLL,D1
.stl_token:
        MOVE.B  (A4),D0
        CMP.B   D2,D0
        DBNE    D1,.stl_token
        BEQ.S   .stl_no_answer          ; the token never moved

        MOVE.W  #TUNED_POLL,D1
.stl_prog:
        MOVE.B  TUNED_PROG_OFF(A4),D0
        CMP.B   D3,D0
        DBEQ    D1,.stl_prog
        BNE.S   .stl_no_complete

        MOVE.B  TUNED_RESP_OFF(A4),D0
        CMP.B   D4,D0
        BNE.S   .stl_refused
        ADDQ.W  #4,D6
        DBF     D5,.stl_block
        MOVEQ   #0,D0
        BRA.S   .stl_out

; The last block of the line has nothing after it to work an address out for,
; so its wait builds the next line instead.  The four bytes are delivered — the
; device takes a command byte from the address of a read — so the buffer is the
; host's again.  A refusal comes back through here, and must not advance it a
; second time.
.stl_last:
        TST.B   PT_ADVANCED
        BNE.S   .stl_poll
        MOVE.B  #1,PT_ADVANCED
        BSR     line_next
        BRA.S   .stl_poll

.stl_no_answer:
        MOVEQ   #STAT_NO_ANSWER,D0
        BRA.S   .stl_dead
.stl_no_complete:
        MOVEQ   #STAT_NO_COMPLETE,D0
.stl_dead:
        BSR     fault_note
        MOVEQ   #1,D0
        BRA.S   .stl_out

.stl_refused:
        MOVEM.L D6-D7/A1-A2/A6,-(SP)    ; how far into the line the retry
        MOVEQ   #RBCP_PIPE_WRITE_MAX,D0 ; resumes, and the four bytes it
        BSR     fault_refused           ; resumes with
        MOVEM.L (SP)+,D6-D7/A1-A2/A6
        TST.B   D0
        BNE.S   .stl_over
        CMPI.W  #LINE_LEN-4,D6
        BEQ     .stl_retry              ; the last block: the buffer has moved
        BRA     .stl_setup              ; any other: its bytes are still there
.stl_over:
        MOVEQ   #1,D0
.stl_out:
        MOVEM.L (SP)+,D1-D7/A0-A6
        RTS

; ---------------------------------------------------------------------------
; fault_refused — the device answered a PIPE_WRITE with failure.
;
; Input : D0.B = the bytes it was offered
;
; A burst of immediate retries comes first, because a pipe that is momentarily
; full is the case the retry exists for and it costs one branch.  When the
; burst runs out GET_PIPE_INFO says how much room the pipe has now.  Room for
; the bytes that were just refused is not fullness — it is a device answering
; about something else — so the run ends and says so.
;
; Where the pipe really is full the wait goes on, but the stop key is read on
; every round and the whole stall is bounded at STALL_SECS.
;
; Output: D0.B = 0 send the same bytes again, 1 end the run
; Clobbers (saved/restored): D1-D2
; ---------------------------------------------------------------------------
fault_refused:
        MOVEM.L D1-D2,-(SP)
        MOVEQ   #0,D2
        MOVE.B  D0,D2                   ; bytes offered
        ADDQ.L  #1,PT_REFUSALS

        TST.B   PT_STALL
        BNE.S   .fr_burst
        MOVE.B  #1,PT_STALL             ; a stall has begun
        BSR     tod_now
        MOVE.L  D0,PT_STALL_AT
        CLR.B   PT_SAW_ROOM
        MOVE.B  #FAULT_BURST,PT_BURST
.fr_burst:
        SUBQ.B  #1,PT_BURST
        BNE     .fr_again               ; the same bytes, at once

        MOVE.B  #FAULT_BURST,PT_BURST
        MOVE.B  PT_PIPE,D0
        BSR     rbcp_cmd_get_pipe_info
        TST.B   D0
        BNE.S   .fr_no_info
        MOVEQ   #3,D0                   ; type, flags and room
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVEQ   #0,D0
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_INFO_FREE).W,D0
        CMP.W   D2,D0
        BCS.S   .fr_full                ; less room than was offered

        ; Room for them.  A far end that drained between the refusal and this
        ; question would look the same, so the answer has to come twice.
        TST.B   PT_SAW_ROOM
        BNE.S   .fr_not_full
        MOVE.B  #1,PT_SAW_ROOM
        MOVE.B  #1,PT_BURST             ; ask again at the very next refusal
        BRA.S   .fr_again

.fr_no_info:
        CMPI.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        BEQ.S   .fr_not_full            ; it refused a question that answers
        BSR     fault_stage             ; it did not answer at all
        MOVEQ   #1,D0
        BRA.S   .fr_out

; A refusal that fullness does not explain: either the pipe had room for the
; bytes, or the device would not say how much room it has.  Both are a device
; answering about a command this program did not send.
.fr_not_full:
        MOVEQ   #STAT_BAD_REFUSAL,D0
        BSR     fault_note
        MOVEQ   #1,D0
        BRA.S   .fr_out

.fr_full:
        CLR.B   PT_SAW_ROOM
        BSR     amiga_getkey
        CMPI.B  #KEY_RETURN,D0
        BEQ.S   .fr_stopped
        BSR     tod_now
        SUB.L   PT_STALL_AT,D0
        ANDI.L  #TOD_MASK,D0
        CMP.L   PT_STALL_TICKS,D0
        BCS.S   .fr_again
        MOVE.B  #STAT_PIPE_STUCK,PT_STAT
        ADDQ.L  #1,PT_ERRORS            ; it is answering, so nothing to fix
        MOVEQ   #1,D0
        BRA.S   .fr_out
.fr_stopped:
        MOVE.B  #STAT_STOPPED,PT_STAT
        MOVEQ   #1,D0
        BRA.S   .fr_out
.fr_again:
        MOVEQ   #0,D0
.fr_out:
        MOVEM.L (SP)+,D1-D2
        RTS

; ---------------------------------------------------------------------------
; fault_stage — the device did not answer.  RBCP_ERROR_CODE says which of the
; two ways, and the run ends naming it.
; Clobbers: D0
; ---------------------------------------------------------------------------
fault_stage:
        CMPI.B  #RBCP_ERR_TOKEN,RBCP_ERROR_CODE
        BNE.S   .fs_unfinished
        MOVEQ   #STAT_NO_ANSWER,D0
        BRA.S   fault_note
.fs_unfinished:
        MOVEQ   #STAT_NO_COMPLETE,D0
        ; fall through

; ---------------------------------------------------------------------------
; fault_note — D0.B = the status that ends the run.  The device is marked as
; needing putting back together and the error count moves.
; Clobbers: D0
; ---------------------------------------------------------------------------
fault_note:
        MOVE.B  D0,PT_STAT
        MOVE.B  #1,PT_LOST
        ADDQ.L  #1,PT_ERRORS
        RTS

; ===========================================================================
; The one-second window, and the counters it closes over
; ===========================================================================

; ---------------------------------------------------------------------------
; clock_pick — how many time of day ticks make a second on this machine.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
clock_pick:
        MOVEM.L D0,-(SP)
        MOVE.L  #TOD_HZ_NTSC,D0
        TST.B   VAR_IS_PAL
        BEQ.S   .cp_set
        MOVE.L  #TOD_HZ_PAL,D0
.cp_set:
        MOVE.L  D0,PT_TICKS
        MULU    #STALL_SECS,D0
        MOVE.L  D0,PT_STALL_TICKS
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; win_open — now is the start of a window.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
win_open:
        MOVEM.L D0,-(SP)
        BSR     tod_now
        MOVE.L  D0,PT_WIN_AT
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; win_step — close the window if a second has gone by, and open the next.
;
; The byte count in a closed window is the rate, because the window is a
; second.  The next window starts where this one ended rather than at the
; moment the check noticed, so the boundaries do not walk forward by however
; late each check was.
;
; Output: D0.B = 0 the window is still open, 1 one closed
; Clobbers (saved/restored): D1
; ---------------------------------------------------------------------------
win_step:
        MOVEM.L D1,-(SP)
        BSR     tod_now
        SUB.L   PT_WIN_AT,D0
        ANDI.L  #TOD_MASK,D0            ; the counter is 24 bits and wraps
        CMP.L   PT_TICKS,D0
        BCS.S   .ws_open

        MOVE.L  PT_BYTES_WIN,D1
        MOVE.L  D1,PT_RATE_NOW
        CMP.L   PT_RATE_BEST,D1
        BLS.S   .ws_not_best
        MOVE.L  D1,PT_RATE_BEST
.ws_not_best:
        CLR.L   PT_BYTES_WIN
        ADDQ.L  #1,PT_SECS
        MOVE.L  PT_WIN_AT,D1
        ADD.L   PT_TICKS,D1
        ANDI.L  #TOD_MASK,D1
        MOVE.L  D1,PT_WIN_AT
        BSR     calc_mean               ; the window that just closed counts
        MOVEQ   #1,D0
        BRA.S   .ws_out
.ws_open:
        MOVEQ   #0,D0
.ws_out:
        MOVEM.L (SP)+,D1
        RTS

; ---------------------------------------------------------------------------
; count_line — one 64-byte line has gone out.
; Clobbers: nothing
; ---------------------------------------------------------------------------
count_line:
        ADDI.L  #LINE_LEN,PT_BYTES_WIN
        ADDI.L  #LINE_LEN,PT_BYTES_TOTAL
        ADDQ.L  #1,PT_LINES_TOTAL
        RTS

; ---------------------------------------------------------------------------
; calc_mean — total bytes over windows closed.  The only division the tester
; does, once a second and once when a run stops.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
calc_mean:
        MOVEM.L D0,-(SP)
        MOVE.L  PT_SECS,D0
        BNE.S   .cm_divide
        CLR.L   PT_RATE_MEAN            ; a run shorter than a window has none
        BRA.S   .cm_out
.cm_divide:
        MOVE.L  D0,PT_NUM_DEN
        MOVE.L  PT_BYTES_TOTAL,PT_NUM_VAL
        BSR     num_div
        MOVE.L  PT_NUM_VAL,PT_RATE_MEAN
.cm_out:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; zero_all — every variable the tester owns, before anything uses one.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
zero_all:
        MOVEM.L D0/A0,-(SP)
        LEA     (PT_VARS).W,A0
        MOVE.W  #(PT_END+3-PT_VARS)/4-1,D0
.za_loop:
        CLR.L   (A0)+
        DBF     D0,.za_loop
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; zero_run — the counters a run owns, which sit in one block.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
zero_run:
        MOVEM.L D0/A0,-(SP)
        LEA     (PT_COUNTS).W,A0
        MOVE.W  #(PT_COUNTS_END-PT_COUNTS)/4-1,D0
.zr_loop:
        CLR.L   (A0)+
        DBF     D0,.zr_loop
        MOVEM.L (SP)+,D0/A0
        RTS

; ===========================================================================
; The line
;
; Only three things change from line to line — the stripe leaves one cell and
; enters the next, and the sequence increments.  Everything else is written
; once at the start of a run.
; ===========================================================================

; ---------------------------------------------------------------------------
; line_reset — the whole line, with the sequence at 0000 and the stripe in the
; first body column.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
line_reset:
        MOVEM.L D0-D2/A0,-(SP)
        LEA     (PT_LINE).W,A0
        MOVEQ   #4-1,D2
.lr_seq:
        MOVE.B  #'0',(A0)+
        DBF     D2,.lr_seq
        MOVE.B  #' ',(A0)+

        MOVEQ   #0,D1                   ; the ruler digit
        MOVEQ   #BODY_LEN-1,D2
.lr_body:
        MOVE.B  D1,D0
        ADDI.B  #'0',D0
        MOVE.B  D0,(A0)+
        ADDQ.B  #1,D1
        CMPI.B  #10,D1
        BCS.S   .lr_wrapped
        MOVEQ   #0,D1
.lr_wrapped:
        DBF     D2,.lr_body

        MOVE.B  #13,(A0)+
        MOVE.B  #10,(A0)+

        CLR.W   PT_SEQ
        CLR.B   PT_STRIPE_COL
        CLR.B   PT_STRIPE_DIG
        MOVE.B  #'#',(PT_LINE+BODY_START).W
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; line_next — the stripe leaves its cell for the next one and the sequence
; increments.  Called once a line's bytes have gone out.  On TUNED4 that is
; while the line's last command is still in flight, which is safe: the device
; takes a command byte from the address of a read, so a byte that has been read
; has been delivered and the buffer is the host's again.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
line_next:
        MOVEM.L D0-D2/A0,-(SP)
        LEA     (PT_LINE+BODY_START).W,A0
        MOVEQ   #0,D1
        MOVE.B  PT_STRIPE_COL,D1
        MOVE.B  PT_STRIPE_DIG,D0        ; put the ruler back where it was
        ADDI.B  #'0',D0
        MOVE.B  D0,(A0,D1.W)

        ADDQ.B  #1,PT_STRIPE_DIG
        CMPI.B  #10,PT_STRIPE_DIG
        BCS.S   .ln_digit
        CLR.B   PT_STRIPE_DIG
.ln_digit:
        ADDQ.B  #1,PT_STRIPE_COL
        CMPI.B  #BODY_LEN,PT_STRIPE_COL
        BCS.S   .ln_column
        CLR.B   PT_STRIPE_COL           ; column 0's ruler digit is 0
        CLR.B   PT_STRIPE_DIG
.ln_column:
        MOVEQ   #0,D1
        MOVE.B  PT_STRIPE_COL,D1
        MOVE.B  #'#',(A0,D1.W)

        ADDQ.W  #1,PT_SEQ
        MOVE.W  PT_SEQ,D1
        LEA     (PT_LINE+4).W,A0
        MOVEQ   #4-1,D2
.ln_hex:
        MOVE.W  D1,D0
        ANDI.W  #$000F,D0
        CMPI.B  #10,D0
        BCS.S   .ln_dec
        ADDI.B  #'A'-10,D0
        BRA.S   .ln_put
.ln_dec:
        ADDI.B  #'0',D0
.ln_put:
        MOVE.B  D0,-(A0)
        LSR.W   #4,D1
        DBF     D2,.ln_hex
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; build_banner — "#### RUN nnn PATH" padded to 62 characters, then CR and LF.
;
; Four hashes are how the checking tool knows one run from the next, and the
; sequence restarting at 0000 on the line after is not a gap.
; Clobbers (saved/restored): D0-D2/A0-A1
; ---------------------------------------------------------------------------
build_banner:
        MOVEM.L D0-D2/A0-A1,-(SP)
        LEA     (PT_LINE).W,A0
        MOVEQ   #62-1,D2
.bb_blank:
        MOVE.B  #' ',(A0)+
        DBF     D2,.bb_blank
        MOVE.B  #13,(A0)+
        MOVE.B  #10,(A0)+

        LEA     (PT_LINE).W,A0
        MOVEQ   #4-1,D2
.bb_hash:
        MOVE.B  #'#',(A0)+
        DBF     D2,.bb_hash

        LEA     (str_run_word).L,A1
        LEA     (PT_LINE+5).W,A0
.bb_word:
        MOVE.B  (A1)+,D0
        BEQ.S   .bb_number
        MOVE.B  D0,(A0)+
        BRA.S   .bb_word

        ; Three digits, because the run number is a byte and two digits stop
        ; at 99.
.bb_number:
        MOVEQ   #0,D0
        MOVE.B  PT_RUN_NO,D0
        DIVU    #100,D0
        MOVE.W  D0,D1                   ; hundreds
        ADDI.B  #'0',D1
        MOVE.B  D1,(PT_LINE+9).W
        CLR.W   D0
        SWAP    D0                      ; the remainder
        DIVU    #10,D0
        MOVE.W  D0,D1
        ADDI.B  #'0',D1
        MOVE.B  D1,(PT_LINE+10).W
        CLR.W   D0
        SWAP    D0
        ADDI.B  #'0',D0
        MOVE.B  D0,(PT_LINE+11).W

        MOVEQ   #0,D1
        MOVE.B  PT_PATH,D1
        LSL.W   #2,D1                   ; a long per name
        LEA     (path_names).L,A1
        MOVEA.L (A1,D1.W),A1
        LEA     (PT_LINE+13).W,A0
.bb_name:
        MOVE.B  (A1)+,D0
        BEQ.S   .bb_done
        MOVE.B  D0,(A0)+
        BRA.S   .bb_name
.bb_done:
        MOVEM.L (SP)+,D0-D2/A0-A1
        RTS

; ===========================================================================
; The session
; ===========================================================================

; ---------------------------------------------------------------------------
; sess_open — knock, command-response mode, the version check and the three
; strings the device calls itself.
;
; The tester owns the machine from reset and never gives it back, so there is
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
        LEA     (PT_DEV_TYPE).W,A1
        BSR     copy_name
.ri_ver:
        BSR     rbcp_cmd_get_device_version
        TST.B   D0
        BNE.S   .ri_proto
        LEA     (PT_DEV_VER).W,A1
        BSR     copy_name
.ri_proto:
        BSR     rbcp_cmd_get_proto_version
        TST.B   D0
        BNE.S   .ri_out
        MOVEQ   #4,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        LEA     (PT_PROTO).W,A1
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

; ---------------------------------------------------------------------------
; find_pipe — the pipe the stream goes down.
;
; The first pipe reporting OUT is the one.  A device offering more than one has
; no way to say which it would prefer.
;
; The two commands asked here run once each and are as likely to be mangled as
; any other, so a single bad one would otherwise cost the whole session.  Each
; gets OPEN_TRIES goes.  A mangled command usually comes back as a refusal,
; which is also how a device whose protocol version predates the group answers
; the first of them, so the refusal is not told apart from the rest — the count
; is what stops this.
;
; Where there is no pipe to send down, PT_STAT says which kind of nothing it
; is: a device with no pipes at all, or one whose pipes all run the other way.
; Clobbers (saved/restored): D0-D4
; ---------------------------------------------------------------------------
find_pipe:
        MOVEM.L D0-D4,-(SP)
        CLR.B   PT_HAVE_PIPE
        MOVEQ   #OPEN_TRIES,D3
.fp_cap:
        BSR     rbcp_cmd_get_pipe_cap
        TST.B   D0
        BEQ.S   .fp_count
        SUBQ.B  #1,D3
        BNE.S   .fp_cap
        BRA.S   .fp_none
.fp_count:
        MOVEQ   #1,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVEQ   #0,D2
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_CAP_COUNT).W,D2
        BEQ.S   .fp_none
        MOVEQ   #0,D4                   ; the pipe being asked about
.fp_try:
        MOVEQ   #OPEN_TRIES,D3
.fp_info:
        MOVE.B  D4,D0
        BSR     rbcp_cmd_get_pipe_info
        TST.B   D0
        BEQ.S   .fp_flags
        SUBQ.B  #1,D3
        BNE.S   .fp_info
        BRA.S   .fp_next
.fp_flags:
        MOVEQ   #2,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_INFO_FLAGS).W,D0
        ANDI.B  #RBCP_PIPE_FLAG_OUT,D0
        BEQ.S   .fp_next
        MOVE.B  D4,PT_PIPE
        MOVE.B  #1,PT_HAVE_PIPE
        BRA.S   .fp_out
.fp_next:
        ADDQ.B  #1,D4
        CMP.B   D2,D4
        BCS.S   .fp_try
        MOVE.B  #STAT_PIPE_DIR,PT_STAT  ; it has pipes and none takes bytes
        BRA.S   .fp_out
.fp_none:
        MOVE.B  #STAT_NO_PIPE,PT_STAT
.fp_out:
        MOVEM.L (SP)+,D0-D4
        RTS

; ===========================================================================
; The arithmetic behind the figures
;
; Every count is 32 bits, so the division is 32 by 32 and a rendered number
; takes the ten digits 4294967295 has.  All of it runs once a second and never
; once a line.
; ===========================================================================

; ---------------------------------------------------------------------------
; num_div — PT_NUM_VAL = PT_NUM_VAL / PT_NUM_DEN, shift and subtract.
;
; Doubling the partial remainder and taking in the next bit can need one bit
; more than the divisor's thirty-two.  That bit falls out of the shift into the
; carry, and a remainder that produced it is certainly at least the divisor,
; which is what keeps a divisor above $80000000 from giving a wrong answer.
;
; The caller must not ask for a division by zero.  calc_mean is the only
; caller and it says so rather than divide.
; Clobbers (saved/restored): D0-D4
; ---------------------------------------------------------------------------
num_div:
        MOVEM.L D0-D4,-(SP)
        MOVE.L  PT_NUM_VAL,D0           ; dividend, shifted out of the top
        MOVE.L  PT_NUM_DEN,D1
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
        MOVE.L  D3,PT_NUM_VAL
        MOVEM.L (SP)+,D0-D4
        RTS

; ---------------------------------------------------------------------------
; num_dec — PT_NUM_VAL to ten ASCII digits in PT_NUM_TXT, right aligned with
; the leading zeros blanked, and PT_NUM_FIRST pointing at the first of them.
; The last digit is a digit even where the whole number is zero.
;
; Repeated subtraction of a power of ten, at most nine goes a digit.
; Clobbers (saved/restored): D0-D4/A0-A1
; ---------------------------------------------------------------------------
num_dec:
        MOVEM.L D0-D4/A0-A1,-(SP)
        MOVE.L  PT_NUM_VAL,D0
        LEA     (pow10).L,A0
        LEA     (PT_NUM_TXT).W,A1
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

        LEA     (PT_NUM_TXT).W,A1
        MOVEQ   #0,D3
        MOVEQ   #NUM_DIGITS-2,D4        ; the last digit always stands
.ndc_blank:
        CMPI.B  #'0',(A1)
        BNE.S   .ndc_first
        MOVE.B  #' ',(A1)+
        ADDQ.B  #1,D3
        DBF     D4,.ndc_blank
.ndc_first:
        MOVE.B  D3,PT_NUM_FIRST
        MOVEM.L (SP)+,D0-D4/A0-A1
        RTS

; ===========================================================================
; The screen
;
; The words are drawn once by draw_frame and the numbers over them by
; draw_counts as they change.  A loop that redrew the whole thing every window
; would spend more of the second on the screen than on the pipe.
; ===========================================================================

; ---------------------------------------------------------------------------
; draw_title — the heading band, before anything has been asked of the device.
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
; Clobbers (saved/restored): D0-D3/A0-A1
; ---------------------------------------------------------------------------
draw_frame:
        MOVEM.L D0-D3/A0-A1,-(SP)

        MOVE.B  #PEN_TEXT,VAR_PEN
        LEA     (PT_DEV_TYPE).W,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_DEV,D2
        BSR     screen_print
        LEA     (PT_DEV_VER).W,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_VER,D2
        BSR     screen_print
        LEA     (PT_PROTO).W,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_PROTO,D2
        BSR     screen_print

        ; Which pipe the stream goes down, or that there is nothing to send to.
        MOVE.B  #ROW_PIPE,D2
        MOVE.B  #COL_TEXT,D1
        TST.B   PT_HAVE_PIPE
        BEQ.S   .df_no_pipe
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_pipe).L,A0
        BSR     screen_print
        ADDI.B  #str_pipe_len,D1
        MOVE.B  PT_PIPE,D0
        BSR     print_hex_byte
        BRA.S   .df_band
.df_no_pipe:
        MOVE.B  #PEN_WARN,VAR_PEN
        LEA     (str_no_send).L,A0
        BSR     screen_print

        ; The headline gets a band of its own, so the figure somebody is meant
        ; to read off the screen cannot be missed.
.df_band:
        MOVE.B  #PEN_GOLD,VAR_PEN
        MOVEQ   #ROW_BPS,D0
        BSR     screen_fill_row
        MOVE.B  #PEN_BG,VAR_PEN
        MOVE.B  #PEN_GOLD,VAR_PEN_BG
        LEA     (str_bps).L,A0
        MOVE.B  #COL_LABEL,D1
        MOVE.B  #ROW_BPS,D2
        BSR     screen_print
        MOVE.B  #PEN_BG,VAR_PEN_BG

        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVEQ   #0,D3
.df_label:
        MOVE.W  D3,D0
        LSL.W   #2,D0                   ; a long per name
        LEA     (label_names).L,A0
        MOVEA.L (A0,D0.W),A0
        LEA     (label_rows).L,A1
        MOVE.B  #COL_LABEL,D1
        MOVE.B  (A1,D3.W),D2
        BSR     screen_print
        ADDQ.W  #1,D3
        CMPI.W  #LABEL_COUNT,D3
        BCS.S   .df_label

        LEA     (str_path_lbl).L,A0
        MOVE.B  #COL_PATH_LBL,D1
        MOVE.B  #ROW_PATHS,D2
        BSR     screen_print

        LEA     (str_keys_1).L,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_KEYS,D2
        BSR     screen_print
        LEA     (str_keys_2).L,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_KEYS+1,D2
        BSR     screen_print

        MOVE.B  #PEN_TEXT,VAR_PEN
        BSR     draw_paths
        MOVEM.L (SP)+,D0-D3/A0-A1
        RTS

; ---------------------------------------------------------------------------
; draw_paths — the send paths, the one in hand in its own pen.
; Clobbers (saved/restored): D0-D3/A0-A1
; ---------------------------------------------------------------------------
draw_paths:
        MOVEM.L D0-D3/A0-A1,-(SP)
        MOVEQ   #0,D3
.dp_one:
        MOVE.W  D3,D0
        LSL.W   #2,D0
        LEA     (path_screen).L,A0
        MOVEA.L (A0,D0.W),A0
        LEA     (path_cols).L,A1
        MOVE.B  (A1,D3.W),D1
        MOVE.B  #ROW_PATHS,D2
        MOVE.B  #PEN_LABEL,VAR_PEN
        CMP.B   PT_PATH,D3
        BNE.S   .dp_pen
        MOVE.B  #PEN_MARK,VAR_PEN
.dp_pen:
        BSR     screen_print
        ADDQ.W  #1,D3
        CMPI.W  #PATH_COUNT,D3
        BCS.S   .dp_one
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D3/A0-A1
        RTS

; ---------------------------------------------------------------------------
; draw_status — D0.B = a status code.  The row is blanked first, so a short
; message never leaves the tail of a longer one behind it.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
draw_status:
        MOVEM.L D0-D3/A0,-(SP)
        MOVEQ   #0,D3
        MOVE.B  D0,D3
        CMPI.W  #STAT_COUNT,D3
        BCS.S   .ds_known
        MOVEQ   #STAT_BLANK,D3
.ds_known:
        MOVEQ   #ROW_STATUS,D0
        BSR     clear_row
        LSL.W   #2,D3
        LEA     (stat_names).L,A0
        MOVEA.L (A0,D3.W),A0
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_STATUS,D2
        BSR     screen_print
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; draw_counts — every number on the screen.
;
; Each is worked out into its slot first and the slots go on the screen
; afterwards, in one run.  A photograph of the screen has to have the totals
; agreeing with the rates above them, and drawing each field as soon as it is
; worked out leaves the top carrying this second's figures and the bottom the
; last second's for as long as the arithmetic takes.
;
; The three rates are counted in bytes and shown in bits, because bits a
; second is what the far end quotes and the two figures have to be comparable.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
draw_counts:
        MOVEM.L D0,-(SP)

        MOVE.L  PT_RATE_NOW,D0
        LSL.L   #3,D0
        MOVE.L  D0,PT_NUM_VAL
        MOVEQ   #FLD_BPS,D0
        BSR     stage_num
        MOVE.L  PT_RATE_BEST,D0
        LSL.L   #3,D0
        MOVE.L  D0,PT_NUM_VAL
        MOVEQ   #FLD_BEST,D0
        BSR     stage_num
        MOVE.L  PT_RATE_MEAN,D0
        LSL.L   #3,D0
        MOVE.L  D0,PT_NUM_VAL
        MOVEQ   #FLD_MEAN,D0
        BSR     stage_num

        MOVE.L  PT_BYTES_TOTAL,PT_NUM_VAL
        MOVEQ   #FLD_TOTAL,D0
        BSR     stage_num
        MOVE.L  PT_LINES_TOTAL,PT_NUM_VAL
        MOVEQ   #FLD_LINES,D0
        BSR     stage_num
        MOVE.L  PT_SECS,PT_NUM_VAL
        MOVEQ   #FLD_SECS,D0
        BSR     stage_num
        MOVE.L  PT_REFUSALS,PT_NUM_VAL
        MOVEQ   #FLD_REFUSALS,D0
        BSR     stage_num
        MOVE.L  PT_ERRORS,PT_NUM_VAL
        MOVEQ   #FLD_ERRORS,D0
        BSR     stage_num

        BSR     draw_paint
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; stage_num — D0.W = a field, PT_NUM_VAL = the value.  Its ten digits, right
; aligned, into the field's slot.
; Clobbers (saved/restored): D0-D1/A0-A1
; ---------------------------------------------------------------------------
stage_num:
        MOVEM.L D0-D1/A0-A1,-(SP)
        BSR     num_dec
        MULU    #FLD_WIDTH,D0
        LEA     (PT_NOW).W,A1
        ADDA.W  D0,A1
        LEA     (PT_NUM_TXT).W,A0
        MOVEQ   #FLD_WIDTH-1,D1
.sn_copy:
        MOVE.B  (A0)+,(A1)+
        DBF     D1,.sn_copy
        MOVEM.L (SP)+,D0-D1/A0-A1
        RTS

; ---------------------------------------------------------------------------
; draw_paint — the characters in each slot the screen does not already have.
;
; A count that has gone up by a few hundred moves its last two or three digits
; and no more, so most of a refresh writes nothing.
; Clobbers (saved/restored): D0-D7/A0-A2
; ---------------------------------------------------------------------------
draw_paint:
        MOVEM.L D0-D7/A0-A2,-(SP)
        MOVEQ   #0,D7
.dp_field:
        MOVE.W  D7,D6
        LEA     (fld_row).L,A0
        MOVE.B  (A0,D6.W),D5
        LEA     (fld_pen).L,A0
        MOVE.B  (A0,D6.W),VAR_PEN
        LEA     (fld_bg).L,A0
        MOVE.B  (A0,D6.W),VAR_PEN_BG
        MOVE.B  #COL_NUM,D4
        MULU    #FLD_WIDTH,D6
        LEA     (PT_NOW).W,A1
        ADDA.W  D6,A1
        LEA     (PT_SHOWN).W,A2
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
        ADDQ.W  #1,D7
        CMPI.W  #FLD_COUNT,D7
        BCS.S   .dp_field
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVEM.L (SP)+,D0-D7/A0-A2
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
        DC.B    "RBCP PIPE TESTER "
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
str_pipe:
        DC.B    "WRITING TO PIPE ",0
str_pipe_len            EQU 16
        EVEN
str_no_send:
        DC.B    "NOTHING HERE TAKES HOST BYTES",0
        EVEN
str_bps:
        DC.B    "BITS PER SECOND",0
        EVEN
str_path_lbl:
        DC.B    "PATH",0
        EVEN
str_keys_1:
        DC.B    "RETURN STARTS AND STOPS A RUN",0
        EVEN
str_keys_2:
        DC.B    "T RUNS FOR TEN SECONDS",0

        EVEN
label_names:
        DC.L    str_best,str_mean,str_total,str_lines
        DC.L    str_secs,str_refusals,str_errors
        EVEN
label_rows:
        DC.B    ROW_BEST,ROW_MEAN,ROW_TOTAL,ROW_LINES
        DC.B    ROW_SECS,ROW_REFUSALS,ROW_ERRORS
        EVEN
str_best:
        DC.B    "BEST SECOND",0
        EVEN
str_mean:
        DC.B    "MEAN THIS RUN",0
        EVEN
str_total:
        DC.B    "TOTAL BYTES",0
        EVEN
str_lines:
        DC.B    "LINES",0
        EVEN
str_secs:
        DC.B    "SECONDS",0
        EVEN
str_refusals:
        DC.B    "REFUSALS",0
        EVEN
str_errors:
        DC.B    "ERRORS",0

; The send paths, as the paths row names them and as the banner names them.
; The banner's go down the wire, so they are the shorter of the two.
        EVEN
path_screen:
        DC.L    str_p_lib4,str_p_lib1,str_p_tuned4
        EVEN
path_cols:
        DC.B    COL_PATH_0,COL_PATH_1,COL_PATH_2
        EVEN
str_p_lib4:
        DC.B    "1 LIB4",0
        EVEN
str_p_lib1:
        DC.B    "2 LIB1",0
        EVEN
str_p_tuned4:
        DC.B    "3 TUNED4",0
        EVEN
path_names:
        DC.L    str_n_lib4,str_n_lib1,str_n_tuned4
        EVEN
str_n_lib4:
        DC.B    "LIB4",0
        EVEN
str_n_lib1:
        DC.B    "LIB1",0
        EVEN
str_n_tuned4:
        DC.B    "TUNED4",0
        EVEN
str_run_word:
        DC.B    "RUN",0

; What the status row says, in the order amiga_defs.s numbers them.
        EVEN
stat_names:
        DC.L    str_s_blank,str_s_armed,str_s_no_pipe,str_s_pipe_dir
        DC.L    str_s_running,str_s_stopped,str_s_not_armed,str_s_no_answer
        DC.L    str_s_no_complete,str_s_bad_refusal,str_s_pipe_stuck
        DC.L    str_s_no_recover
        EVEN
str_s_blank:
        DC.B    0
        EVEN
str_s_armed:
        DC.B    "READY",0
        EVEN
str_s_no_pipe:
        DC.B    "THE DEVICE HAS NO PIPE",0
        EVEN
str_s_pipe_dir:
        DC.B    "NO PIPE HERE WILL TAKE HOST BYTES",0
        EVEN
str_s_running:
        DC.B    "RUNNING",0
        EVEN
str_s_stopped:
        DC.B    "STOPPED",0
        EVEN
str_s_not_armed:
        DC.B    "NO PIPE - NOTHING TO RUN",0
        EVEN
str_s_no_answer:
        DC.B    "THE DEVICE DID NOT TAKE THE COMMAND",0
        EVEN
str_s_no_complete:
        DC.B    "THE DEVICE NEVER FINISHED THE COMMAND",0
        EVEN
str_s_bad_refusal:
        DC.B    "REFUSED WITH THE PIPE NOT FULL",0
        EVEN
str_s_pipe_stuck:
        DC.B    "THE PIPE STAYED FULL - RUN ENDED",0
        EVEN
str_s_no_recover:
        DC.B    "THE DEVICE DID NOT COME BACK",0

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
; Where each number field goes, in the order draw_counts fills the slots.
; Every field is ten digits ending in the same column, so only the row and the
; two pens differ.
; ---------------------------------------------------------------------------
        EVEN
fld_row:
        DC.B    ROW_BPS,ROW_BEST,ROW_MEAN,ROW_TOTAL
        DC.B    ROW_LINES,ROW_SECS,ROW_REFUSALS,ROW_ERRORS
        EVEN
fld_pen:
        DC.B    PEN_BG,PEN_TEXT,PEN_TEXT,PEN_TEXT
        DC.B    PEN_TEXT,PEN_TEXT,PEN_BAD,PEN_BAD
        EVEN
fld_bg:
        DC.B    PEN_GOLD,PEN_BG,PEN_BG,PEN_BG
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
