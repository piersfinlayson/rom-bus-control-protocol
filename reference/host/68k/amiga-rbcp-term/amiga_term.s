; amiga_term.s — Amiga RBCP terminal
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Purpose
; -------
; Typed characters go down an RBCP pipe to whatever is listening on the machine
; the device's USB is plugged into, and what that far end says comes back on a
; second pipe and lands on the screen.
;
; A line reaches the text area only once the device has taken all of it, so a
; line still on the input row is a line that has not gone.
;
; The terminal owns the machine
; -----------------------------
; It is a Kickstart image.  It runs from reset, it never hands the machine
; back, and you switch off when you have finished typing.  The device reloads
; its RAM slot from flash at power-on, so switching off is the repair and there
; is no exit to build.
;
; The keyboard
; ------------
; amiga_getkey gives every printable character the keyboard has, and a line is
; made of those.  BACKSPACE rubs out the last one.  README.md lists what a
; line can hold.
;
; A press nobody reads waits at the keyboard until somebody does, so a program
; that stops polling stops showing what is typed at it.  Every wait and every
; long copy in this program therefore polls the keyboard as it goes and puts
; what it finds in a ring, and the loop empties the ring once a field.
; RETURN waits on the device.  No other keystroke does.
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
;   screen routines read the font from ROM and are called throughout, but never
;   between the knock and the response to ENTER_CMD_RESP.
;
; Addressing note:
;   RAM-section code reaches ROM data through explicit absolute long
;   addressing — LEA (label).L,A0 — never PC-relative, because the code is
;   assembled at its ROM address but executes from $28000.

; The terminal draws no artwork, so pens 6 and 7 are free.  A pen already defined keeps its value, so these go in before
; the palette is included.
PEN06_RGB                   EQU $0999       ; labels, dimmer than the text
PEN07_RGB                   EQU $0FA0       ; a direction with no pipe for it

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
        MOVEA.L #STACK_TOP,SP       ; the stack is chip RAM, which OVL was covering
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
; BSR/BRA within this section are PC-relative and span the same distance in
; ROM and in the copy.
; ============================================================
ram_section_rom_start:

; ---------------------------------------------------------------------------
; ram_entry — the terminal proper, running from chip RAM.  The session with
; the device, then the loop.  It does not return.
; ---------------------------------------------------------------------------
ram_entry:
        MOVE.L  #BITPLANE_BASE,VAR_DRAW_BASE
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        CLR.B   VAR_MENU_COL            ; a filled row is the whole row here
        ; The beam line field_wait works from, which is the first line off the
        ; bottom of the display.
        MOVE.W  #FIELD_TICK_NTSC,VAR_TICK_LINE
        TST.B   VAR_IS_PAL
        BEQ.S   .ae_ntsc
        MOVE.W  #FIELD_TICK_PAL,VAR_TICK_LINE
.ae_ntsc:
        ; The typing goes down the pipe, so nothing else does.  err_halt reads
        ; this and stays quiet.
        CLR.B   VAR_PIPE_PRESENT

        BSR     zero_vars
        BSR     screen_clear
        BSR     draw_title
        MOVEQ   #STAT_OPENING,D0
        BSR     draw_status
        BSR     draw_input

        BSR     sess_open               ; err_halt on the way out where it fails
        BSR     read_identity
        BSR     scan_pipes
        BSR     draw_frame

        ; Without a pipe taking bytes from the host there is nothing to type
        ; at.  The screen stands, so what the device calls itself and which
        ; way its pipes run can be read off it.
        CMPI.B  #PIPE_NONE,TRM_PIPE_OUT
        BNE.S   .ae_armed
        MOVEQ   #STAT_NO_PIPE,D0
        TST.B   TRM_PIPE_COUNT
        BEQ.S   .ae_say
        MOVEQ   #STAT_PIPE_DIR,D0
.ae_say:
        BSR     draw_status
        BRA.S   term_loop

        ; A device with no inbound pipe is one this terminal can only talk at.
        ; It runs send-only on one rather than refusing to open.
.ae_armed:
        MOVE.B  #1,TRM_ARMED
        CMPI.B  #PIPE_NONE,TRM_PIPE_IN
        BEQ.S   .ae_send_only
        MOVE.B  #1,TRM_RX_ARMED
.ae_send_only:
        BSR     show_ready

; ---------------------------------------------------------------------------
; term_loop — one field: the keys pressed in the last one, then a read of the
; receive pipe.
;
; The keys go first, so a character appears at the top of a field rather than
; half way down one, and so a keystroke is never behind a read of the device.
; ---------------------------------------------------------------------------
term_loop:
        BSR     field_wait
        BSR     take_keys
        BSR     read_pipe
        BRA.S   term_loop

; ---------------------------------------------------------------------------
; field_wait — hold until the beam next leaves the display, polling the
; keyboard throughout.
;
; A whole field spent not polling is a whole field in which a press and its
; release both arrive in the one serial register, leaving only the release.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
field_wait:
        MOVEM.L D0,-(SP)
.fw_below:
        BSR     key_poll
        BSR     beam_line
        CMP.W   VAR_TICK_LINE,D0
        BCC.S   .fw_below               ; still past it from last time
.fw_reach:
        BSR     key_poll
        BSR     beam_line
        CMP.W   VAR_TICK_LINE,D0
        BCS.S   .fw_reach
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; key_poll — one poll of the keyboard, into the ring.  A full ring loses the
; key that has just arrived rather than the ones waiting, so what does come
; out is in the order it was typed.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
key_poll:
        MOVEM.L D0-D2/A0,-(SP)
        BSR     amiga_getkey
        TST.B   D0
        BEQ.S   .kp_out
        MOVEQ   #0,D1
        MOVE.B  TRM_KEY_HEAD,D1
        MOVE.B  D1,D2
        ADDQ.B  #1,D2
        ANDI.B  #KEY_RING_MASK,D2
        CMP.B   TRM_KEY_TAIL,D2
        BEQ.S   .kp_out                 ; the ring is full
        LEA     (TRM_KEY_RING).W,A0
        MOVE.B  D0,(A0,D1.W)
        MOVE.B  D2,TRM_KEY_HEAD
.kp_out:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; take_keys — the ring, emptied.  What a key does can take longer than a field
; and polls the keyboard while it does, so the keys that arrive during one are
; taken in this pass rather than the next.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
take_keys:
        MOVEM.L D0-D1/A0,-(SP)
.tks_next:
        MOVEQ   #0,D1
        MOVE.B  TRM_KEY_TAIL,D1
        CMP.B   TRM_KEY_HEAD,D1
        BEQ.S   .tks_out
        LEA     (TRM_KEY_RING).W,A0
        MOVE.B  (A0,D1.W),D0
        ADDQ.B  #1,D1
        ANDI.B  #KEY_RING_MASK,D1
        MOVE.B  D1,TRM_KEY_TAIL
        BSR     take_key
        BRA.S   .tks_next
.tks_out:
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; take_key — D0.B = what amiga_getkey returned.
;
; Anything from $20 up is a character and goes in the line.  Everything below
; it is a token, and the terminal uses two of them.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
take_key:
        MOVEM.L D0-D1/A0,-(SP)
        CMPI.B  #KEY_RETURN,D0
        BEQ.S   .tk_send
        CMPI.B  #KEY_RUBOUT,D0
        BEQ.S   .tk_rubout
        CMPI.B  #CHAR_FIRST,D0
        BCS.S   .tk_out
        MOVEQ   #0,D1
        MOVE.B  TRM_LINE_LEN,D1
        CMPI.B  #LINE_MAX,D1
        BCC.S   .tk_out                 ; the line is full, so the key does nothing
        LEA     (TRM_LINE).W,A0
        MOVE.B  D0,(A0,D1.W)
        ADDQ.B  #1,TRM_LINE_LEN
        BSR     draw_typed
        BRA.S   .tk_out
.tk_rubout:
        TST.B   TRM_LINE_LEN
        BEQ.S   .tk_out
        SUBQ.B  #1,TRM_LINE_LEN
        BSR     draw_deleted
        BRA.S   .tk_out
.tk_send:
        BSR     send_line
.tk_out:
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; send_line — RETURN.  The line goes out with a carriage return and a line
; feed behind it, and reaches the text area only once all of it has gone.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
send_line:
        MOVEM.L D0/A0,-(SP)
        TST.B   TRM_ARMED
        BNE.S   .sl_armed
        MOVEQ   #STAT_NOT_ARMED,D0
        BSR     draw_status
        BRA.S   .sl_out
.sl_armed:
        MOVEQ   #0,D0
        MOVE.B  TRM_LINE_LEN,D0
        LEA     (TRM_LINE).W,A0
        MOVE.B  #13,(A0,D0.W)
        ADDQ.W  #1,D0
        MOVE.B  #10,(A0,D0.W)
        ADDQ.W  #1,D0
        MOVE.B  D0,TRM_SEND_LEN
        BSR     write_line
        TST.B   D0
        BNE.S   .sl_failed
        BSR     draw_sent
        CLR.B   TRM_LINE_LEN
        BSR     draw_input
        BSR     show_ready
        BRA.S   .sl_out

        ; A line that did not go stays on the input row, so RETURN sends it
        ; again.  A device that stopped answering is put back together first,
        ; and one that does not come back leaves nothing to send down.
.sl_failed:
        MOVE.B  TRM_FAULT,D0
        BSR     draw_status
        CMPI.B  #STAT_PIPE_FULL,TRM_FAULT
        BEQ.S   .sl_out
        BSR     recover
.sl_out:
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; write_line — the whole of TRM_SEND_LEN, four bytes at a time.
;
; PIPE_WRITE takes all the bytes it is offered or none, so a refusal sends the
; same ones again.  A refusal is the pipe being full, which is the far end not
; reading, and it is given FULL_TRIES goes before the line is given up on.
;
; Output: D0.B = 0 the line went, 1 it did not, with the reason in TRM_FAULT
; Clobbers (saved/restored): D1-D4/A0-A1
; ---------------------------------------------------------------------------
write_line:
        MOVEM.L D1-D4/A0-A1,-(SP)
        CLR.B   TRM_SEND_POS
.wl_chunk:
        MOVEQ   #0,D2
        MOVE.B  TRM_SEND_LEN,D2
        MOVEQ   #0,D3
        MOVE.B  TRM_SEND_POS,D3
        SUB.W   D3,D2                   ; what is left to send
        BEQ     .wl_done
        CMPI.W  #RBCP_PIPE_WRITE_MAX,D2
        BCS.S   .wl_have
        MOVEQ   #RBCP_PIPE_WRITE_MAX,D2
.wl_have:
        MOVE.B  D2,TRM_CHUNK
        MOVE.W  #FULL_TRIES,D4

        ; The gather runs again on every go, because it costs nothing and puts
        ; the question of what the library leaves in the arguments out of
        ; reach.  A full pipe is sat through FULL_TRIES times, so the poll
        ; here is what keeps the keyboard alive through a far end that has
        ; stopped reading.
.wl_gather:
        BSR     key_poll
        LEA     (TRM_LINE).W,A0
        ADDA.W  D3,A0
        LEA     (RBCP_ARG0).W,A1
        MOVE.W  D2,D1
        SUBQ.W  #1,D1
.wl_byte:
        MOVE.B  (A0)+,(A1)+
        DBF     D1,.wl_byte

        MOVE.B  TRM_CHUNK,D0
        MOVE.B  TRM_PIPE_OUT,D1
        BSR     rbcp_cmd_pipe_write
        TST.B   D0
        BEQ.S   .wl_taken

        CMPI.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        BNE.S   .wl_stage
        SUBQ.W  #1,D4
        BNE.S   .wl_gather
        MOVE.B  #STAT_PIPE_FULL,TRM_FAULT
        BRA.S   .wl_failed
.wl_stage:
        MOVE.B  #STAT_NO_ANSWER,TRM_FAULT
        CMPI.B  #RBCP_ERR_TOKEN,RBCP_ERROR_CODE
        BEQ.S   .wl_failed
        MOVE.B  #STAT_NO_COMPLETE,TRM_FAULT
.wl_failed:
        MOVEQ   #1,D0
        BRA.S   .wl_out

.wl_taken:
        MOVE.B  TRM_CHUNK,D0
        ADD.B   D0,TRM_SEND_POS
        BRA     .wl_chunk
.wl_done:
        MOVEQ   #0,D0
.wl_out:
        MOVEM.L (SP)+,D1-D4/A0-A1
        RTS

; ---------------------------------------------------------------------------
; show_ready — the bar, saying whether this device talks back.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
show_ready:
        MOVEM.L D0,-(SP)
        MOVEQ   #STAT_READY,D0
        TST.B   TRM_RX_ARMED
        BNE.S   .sr_show
        MOVEQ   #STAT_SEND_ONLY,D0
.sr_show:
        BSR     draw_status
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; recover — the device stopped answering, so put it back together.
;
; RBCP_RESET flushes a partially received command of up to nine argument bytes
; and two framing bytes, which is what a frame that slipped by a byte onto a
; command taking arguments leaves behind.  Command-response mode is entered
; again rather than the session opened from scratch: the rest of opening a
; session decides whether to talk to the device at all, and that was settled
; before anything called this.
;
; A device that comes back leaves the status the caller put up standing, that
; being the reason the caller had to come here.
; Clobbers (saved/restored): D0-D1
; ---------------------------------------------------------------------------
recover:
        MOVEM.L D0-D1,-(SP)
        MOVEQ   #RECOVER_TRIES,D1
.rc_try:
        BSR     key_poll
        BSR     rbcp_reset
        BSR     rbcp_cmd_enter_cmd_resp
        TST.B   D0
        BEQ.S   .rc_out
        SUBQ.B  #1,D1
        BNE.S   .rc_try
        CLR.B   TRM_ARMED
        CLR.B   TRM_RX_ARMED
        MOVEQ   #STAT_NO_RECOVER,D0
        BSR     draw_status
.rc_out:
        MOVEM.L (SP)+,D0-D1
        RTS

; ===========================================================================
; Receiving
;
; The receive pipe is read once a field.  A command costs about 188us against
; the 20ms a PAL field lasts, and the Amiga talks to the device with the
; display up, so there is nothing to save by reading any less often.
; ===========================================================================

; ---------------------------------------------------------------------------
; read_pipe — what the far end has sent, on the screen.
;
; Reads run back to back while the device says more is waiting, up to
; RX_BURST_MAX, so a burst arrives at the speed the back channel allows rather
; than RX_MAX bytes a field.  The keyboard is polled before each one.
;
; A read that did not happen leaves any row it was filling closed, so what
; arrives next starts a fresh one rather than running on from a gap.
;
; A device that did not answer is put back together, as a line that would not
; go is.  One that answered and said no is refusing the pipe number or the
; room for the answer, which will be just as wrong at the next poll, so
; reading stops and the bar says so.
; Clobbers (saved/restored): D0-D1
; ---------------------------------------------------------------------------
read_pipe:
        MOVEM.L D0-D1,-(SP)
        TST.B   TRM_ARMED
        BEQ.S   .rp_out
        TST.B   TRM_RX_ARMED
        BEQ.S   .rp_out
        MOVE.B  #RX_BURST_MAX,TRM_BURST
.rp_read:
        BSR     key_poll
        BSR     read_once
        TST.B   D0
        BNE.S   .rp_failed
        TST.B   D1
        BEQ.S   .rp_out                 ; nothing waiting, so back to the keys
        SUBQ.B  #1,TRM_BURST
        BNE.S   .rp_read
.rp_out:
        MOVEM.L (SP)+,D0-D1
        RTS
.rp_failed:
        CLR.B   TRM_RX_COL
        CMPI.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        BEQ.S   .rp_refused
        BSR     recover
        BRA.S   .rp_out
.rp_refused:
        CLR.B   TRM_RX_ARMED
        MOVEQ   #STAT_RX_FAIL,D0
        BSR     draw_status
        BRA.S   .rp_out

; ---------------------------------------------------------------------------
; read_once — one read, and what it returned on the screen.
;
; The reading and the drawing are one piece of work because the bytes go
; through the library's buffer, which the next command overwrites.
;
; How many came back is in two places in the reply.  With FULL set the count
; asked for is the count that came, and with it clear PIPE_READ_COUNT says how
; many.
;
; Output: D0.B = 0 read, 1 failed with the stage in RBCP_ERROR_CODE
;         D1.B = what the device says is still waiting
; Clobbers (saved/restored): D2/A0
; ---------------------------------------------------------------------------
read_once:
        MOVEM.L D2/A0,-(SP)
        MOVE.B  #RX_MAX,D0
        MOVE.B  TRM_PIPE_IN,D1
        BSR     rbcp_cmd_pipe_read
        TST.B   D0
        BNE.S   .ro_failed

        MOVE.W  #RX_MAX+8,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        MOVEQ   #0,D2
        MOVE.B  RBCP_PIPE_READ_FLAGS(A0),D2
        ANDI.B  #RBCP_PIPE_READ_FLAG_FULL,D2
        BEQ.S   .ro_counted
        MOVE.B  #RX_MAX,D2
        BRA.S   .ro_have
.ro_counted:
        MOVE.B  RBCP_PIPE_READ_COUNT(A0),D2
.ro_have:
        MOVE.B  D2,TRM_RX_LEN
        BEQ.S   .ro_shown               ; an empty pipe, which is not a failure
        ADDA.W  #RBCP_PIPE_READ_DATA,A0
.ro_byte:
        BSR     key_poll                ; a cell costs about half a millisecond
        MOVE.B  (A0)+,D0
        BSR     rx_byte
        SUBQ.B  #1,D2
        BNE.S   .ro_byte
.ro_shown:
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        MOVE.B  RBCP_PIPE_READ_WAITING(A0),D1
        MOVEQ   #0,D0
        MOVEM.L (SP)+,D2/A0
        RTS
.ro_failed:
        MOVEQ   #1,D0
        MOVEM.L (SP)+,D2/A0
        RTS

; ===========================================================================
; The session
; ===========================================================================

; ---------------------------------------------------------------------------
; sess_open — the knock, command-response mode and the version check.
;
; A session that will not open goes to err_halt and does not come back.  There
; is nothing to type at and nothing to read, so the error screen and its raw
; device state are the whole of what the machine has to say.
; Clobbers: D0
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
        BEQ.S   .so_ok
        MOVEQ   #ERR_VERSION,D0
        BRA     err_halt
.so_ok:
        RTS

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
        LEA     (TRM_DEV_TYPE).W,A1
        BSR     copy_name
.ri_ver:
        BSR     rbcp_cmd_get_device_version
        TST.B   D0
        BNE.S   .ri_proto
        LEA     (TRM_DEV_VER).W,A1
        BSR     copy_name
.ri_proto:
        BSR     rbcp_cmd_get_proto_version
        TST.B   D0
        BNE.S   .ri_out
        MOVEQ   #4,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        LEA     (TRM_PROTO).W,A1
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
; Clobbers (saved/restored): D0-D1/A0.  A1 is left inside the buffer.
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
; scan_pipes — the pipe a line goes out of and the pipe bytes come back on,
; each the lowest numbered pipe carrying that direction, or PIPE_NONE where no
; pipe does.
;
; One ROM puts the outbound pipe at 0 and the inbound one at 1, but nothing
; requires that, so neither number is assumed.  A pipe that will not describe
; itself is passed over rather than ending the scan.
;
; GET_PIPE_CAPABILITY takes no argument bytes, so a device whose protocol
; version predates the Pipes group fails it and stays in step.
; Clobbers (saved/restored): D0-D3
; ---------------------------------------------------------------------------
scan_pipes:
        MOVEM.L D0-D3,-(SP)
        MOVE.B  #PIPE_NONE,TRM_PIPE_OUT
        MOVE.B  #PIPE_NONE,TRM_PIPE_IN
        CLR.B   TRM_PIPE_COUNT

        BSR     rbcp_cmd_get_pipe_cap
        TST.B   D0
        BNE.S   .sp_out
        MOVEQ   #1,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_CAP_COUNT).W,D2
        MOVE.B  D2,TRM_PIPE_COUNT
        BEQ.S   .sp_out
        MOVEQ   #0,D3
.sp_pipe:
        MOVE.B  D3,D0
        BSR     rbcp_cmd_get_pipe_info
        TST.B   D0
        BNE.S   .sp_next
        MOVEQ   #2,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_INFO_FLAGS).W,D1
        MOVE.B  D1,D0
        ANDI.B  #RBCP_PIPE_FLAG_OUT,D0
        BEQ.S   .sp_in
        CMPI.B  #PIPE_NONE,TRM_PIPE_OUT
        BNE.S   .sp_in
        MOVE.B  D3,TRM_PIPE_OUT
.sp_in:
        MOVE.B  D1,D0
        ANDI.B  #RBCP_PIPE_FLAG_IN,D0
        BEQ.S   .sp_next
        CMPI.B  #PIPE_NONE,TRM_PIPE_IN
        BNE.S   .sp_next
        MOVE.B  D3,TRM_PIPE_IN
.sp_next:
        ADDQ.B  #1,D3
        CMP.B   D2,D3
        BCS.S   .sp_pipe
.sp_out:
        MOVEM.L (SP)+,D0-D3
        RTS

; ---------------------------------------------------------------------------
; zero_vars — the terminal's variables clear, and the library's buffer clear
; to its last whole long.
; Nothing clears chip RAM at boot.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
zero_vars:
        MOVEM.L D0/A0,-(SP)
        LEA     (TRM_VARS).W,A0
        MOVE.W  #((TRM_END-TRM_VARS)/4)-1,D0
.zv_vars:
        CLR.L   (A0)+
        DBF     D0,.zv_vars
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        MOVE.W  #(CONFIG_RBCP_DATA_BUF_SIZE/4)-1,D0
.zv_buf:
        CLR.L   (A0)+
        DBF     D0,.zv_buf
        MOVEM.L (SP)+,D0/A0
        RTS

; ===========================================================================
; The screen
;
; A title bar, the device, the pipes, a text area holding what has gone and
; what has arrived, the line being typed and a status bar.  Both bars are gold
; with black on them, so the text area is the only part that looks like text.
;
; Every row in the text area opens with a mark saying which way it went: > for
; a line that has gone and < for bytes that arrived.  The mark sits in column
; 0, under the prompt on the input row, so a line keeps the mark it was typed
; at as it scrolls up.  Arriving text is reversed, mark and all, as far along
; the row as the text goes.
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
; draw_title_at — D2.B = row.  The heading, which err_halt draws on the error
; screen.  Clobbers (saved/restored): D0-D2/A0
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
; draw_frame — what the device calls itself and which of its pipes carries
; what.  Drawn once and never touched again, so it does not scroll away with
; the text.
;
; The name and its version go hard left and the protocol version hard right,
; which is where the title bar above puts its two.  The name is cut at the
; protocol version's column so a long one cannot run into it.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_frame:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #COL_PROTO-1,VAR_COL_MAX
        LEA     (TRM_DEV_TYPE).W,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_DEV,D2
        BSR     screen_print
        BSR     str_len
        ADD.B   D0,D1
        ADDQ.B  #1,D1
        LEA     (TRM_DEV_VER).W,A0
        BSR     screen_print
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        LEA     (TRM_PROTO).W,A0
        MOVE.B  #COL_PROTO,D1
        BSR     screen_print

        MOVE.B  #ROW_PIPE,D2
        MOVE.B  #COL_TEXT,D1
        CMPI.B  #PIPE_NONE,TRM_PIPE_OUT
        BNE.S   .df_sending
        MOVE.B  #PEN_WARN,VAR_PEN
        LEA     (str_no_pipe).L,A0
        TST.B   TRM_PIPE_COUNT
        BEQ.S   .df_say
        LEA     (str_pipe_dir).L,A0
.df_say:
        BSR     screen_print
        BRA.S   .df_done
.df_sending:
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_send_pipe).L,A0
        BSR     screen_print
        ADDI.B  #str_send_pipe_len,D1
        MOVE.B  TRM_PIPE_OUT,D0
        BSR     print_hex_byte
        MOVE.B  #COL_RX_PIPE,D1
        CMPI.B  #PIPE_NONE,TRM_PIPE_IN
        BEQ.S   .df_no_rx
        LEA     (str_read_pipe).L,A0
        BSR     screen_print
        ADDI.B  #str_read_pipe_len,D1
        MOVE.B  TRM_PIPE_IN,D0
        BSR     print_hex_byte
        BRA.S   .df_done
.df_no_rx:
        MOVE.B  #PEN_WARN,VAR_PEN
        LEA     (str_no_rx).L,A0
        BSR     screen_print
.df_done:
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_status — D0.B = the status code.  The bar carries it and the count of
; characters the line has left, and is drawn whole each time the code changes.
; A message wider than the space left of the count is cut.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_status:
        MOVEM.L D0-D2/A0,-(SP)
        CMPI.B  #STAT_COUNT,D0
        BCS.S   .ds_known
        MOVEQ   #STAT_BLANK,D0
.ds_known:
        MOVE.B  D0,TRM_STAT
        MOVE.B  #PEN_GOLD,VAR_PEN
        MOVEQ   #ROW_STATUS,D0
        BSR     key_poll
        BSR     screen_fill_row
        MOVE.B  #PEN_BG,VAR_PEN
        MOVE.B  #PEN_GOLD,VAR_PEN_BG

        MOVEQ   #0,D0
        MOVE.B  TRM_STAT,D0
        LSL.W   #2,D0                   ; a long per table entry
        LEA     (str_status_tab).L,A0
        MOVEA.L (A0,D0.W),A0
        MOVE.B  #COL_LEFT-1,VAR_COL_MAX
        MOVE.B  #COL_TITLE,D1
        MOVE.B  #ROW_STATUS,D2
        ; screen_print draws the whole message before it comes back.
        BSR     key_poll
        BSR     screen_print
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX

        LEA     (str_left).L,A0
        MOVE.B  #COL_LEFT_LBL,D1
        BSR     key_poll
        BSR     screen_print
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        BSR     draw_count
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_count — how many characters the line has left, and nothing else on the
; bar.  A keystroke changes this and no other part of it.
; Clobbers (saved/restored): D0-D3
; ---------------------------------------------------------------------------
draw_count:
        MOVEM.L D0-D3,-(SP)
        MOVE.B  #PEN_BG,VAR_PEN
        MOVE.B  #PEN_GOLD,VAR_PEN_BG
        MOVEQ   #LINE_MAX,D3
        SUB.B   TRM_LINE_LEN,D3
        MOVE.B  #COL_LEFT,D1
        MOVE.B  #ROW_STATUS,D2
        MOVEQ   #0,D0
.dct_tens:
        CMPI.B  #10,D3
        BCS.S   .dct_units
        SUBI.B  #10,D3
        ADDQ.B  #1,D0
        BRA.S   .dct_tens
.dct_units:
        ADDI.B  #'0',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
        MOVE.B  D3,D0
        ADDI.B  #'0',D0
        BSR     screen_putchar
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVEM.L (SP)+,D0-D3
        RTS

; ---------------------------------------------------------------------------
; draw_input — the whole input row: the prompt, the line as it stands and the
; cursor after it.  Drawn at startup and once a line has gone.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
draw_input:
        MOVEM.L D0-D3/A0,-(SP)
        MOVEQ   #ROW_INPUT,D0
        BSR     clear_row
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVE.B  #'>',D0
        MOVEQ   #0,D1
        MOVE.B  #ROW_INPUT,D2
        BSR     screen_putchar
        LEA     (TRM_LINE).W,A0
        MOVEQ   #0,D3
.di_ch:
        CMP.B   TRM_LINE_LEN,D3
        BCC.S   .di_done
        BSR     key_poll
        MOVE.B  (A0)+,D0
        MOVE.B  D3,D1
        ADDQ.B  #1,D1
        BSR     screen_putchar
        ADDQ.B  #1,D3
        BRA.S   .di_ch
.di_done:
        BSR     draw_cursor
        BSR     draw_count
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; draw_typed — the character just added to the line, and the cursor moved
; along.  Two cells, because redrawing the whole row on every key makes it
; flicker.
;
; Called with TRM_LINE_LEN already counting the new character, so it goes in
; the column that number names and the cursor one to the right of it.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_typed:
        MOVEM.L D0-D2/A0,-(SP)
        LEA     (TRM_LINE).W,A0
        MOVEQ   #0,D1
        MOVE.B  TRM_LINE_LEN,D1
        MOVE.B  -1(A0,D1.W),D0
        MOVE.B  TRM_LINE_LEN,D1
        MOVE.B  #ROW_INPUT,D2
        BSR     screen_putchar
        BSR     draw_cursor
        BSR     draw_count
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_deleted — the cursor back one, and the cell it came out of blanked.
;
; Called with TRM_LINE_LEN already counting the character gone, so the cursor
; was two columns past where it now stands.
; Clobbers (saved/restored): D0-D2
; ---------------------------------------------------------------------------
draw_deleted:
        MOVEM.L D0-D2,-(SP)
        MOVE.B  #' ',D0
        MOVE.B  TRM_LINE_LEN,D1
        ADDQ.B  #2,D1
        MOVE.B  #ROW_INPUT,D2
        BSR     screen_putchar
        BSR     draw_cursor
        BSR     draw_count
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; draw_cursor — a reversed space one column past the line.
; Clobbers (saved/restored): D0-D2
; ---------------------------------------------------------------------------
draw_cursor:
        MOVEM.L D0-D2,-(SP)
        MOVE.B  #PEN_BG,VAR_PEN
        MOVE.B  #PEN_TEXT,VAR_PEN_BG
        MOVE.B  #' ',D0
        MOVE.B  TRM_LINE_LEN,D1
        ADDQ.B  #1,D1
        MOVE.B  #ROW_INPUT,D2
        BSR     screen_putchar
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; draw_sent — the line that has just gone, on a row of the text area.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
draw_sent:
        MOVEM.L D0-D3/A0,-(SP)
        ; An open received row is finished with.  The line goes below it.
        CLR.B   TRM_RX_COL
        BSR     text_new_row
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVE.B  #'>',D0
        MOVEQ   #0,D1
        MOVE.B  #ROW_TEXT_BOT,D2
        BSR     screen_putchar
        LEA     (TRM_LINE).W,A0
        MOVEQ   #0,D3
.dsn_ch:
        CMP.B   TRM_LINE_LEN,D3
        BCC.S   .dsn_done
        BSR     key_poll
        MOVE.B  (A0)+,D0
        MOVE.B  D3,D1
        ADDQ.B  #1,D1
        BSR     screen_putchar
        ADDQ.B  #1,D3
        BRA.S   .dsn_ch
.dsn_done:
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; rx_byte — D0.B = a byte off the pipe, on the screen in reverse.
;
; A carriage return or a line feed ends the row rather than drawing anything,
; so a far end sending both ends one row and not two.  A row that fills up runs
; on to the next and carries its own mark, so a line over two rows is marked on
; both.  Anything the screen cannot draw becomes a full stop, so a byte that
; arrived is always a mark and never a gap.
;
; The cell is turned over one at a time rather than the row at the end, because
; the row has no end until the far end sends one.
; Clobbers (saved/restored): D0-D2
; ---------------------------------------------------------------------------
rx_byte:
        MOVEM.L D0-D2,-(SP)
        ANDI.B  #$7F,D0                 ; a far end that sets bit 7 still lands on its character
        CMPI.B  #13,D0
        BEQ.S   .rb_close
        CMPI.B  #10,D0
        BEQ.S   .rb_close
        CMPI.B  #CHAR_FIRST,D0
        BCS.S   .rb_dot
        CMPI.B  #CHAR_LAST+1,D0
        BCS.S   .rb_have
.rb_dot:
        MOVE.B  #'.',D0
.rb_have:
        MOVE.B  D0,D2
        TST.B   TRM_RX_COL
        BEQ.S   .rb_open
        CMPI.B  #SCREEN_COLS,TRM_RX_COL
        BCS.S   .rb_cell
.rb_open:
        BSR     rx_open_row
.rb_cell:
        MOVE.B  #PEN_BG,VAR_PEN
        MOVE.B  #PEN_TEXT,VAR_PEN_BG
        MOVE.B  D2,D0
        MOVE.B  TRM_RX_COL,D1
        MOVE.B  #ROW_TEXT_BOT,D2
        BSR     screen_putchar
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        ADDQ.B  #1,TRM_RX_COL
        MOVEM.L (SP)+,D0-D2
        RTS
.rb_close:
        CLR.B   TRM_RX_COL
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; rx_open_row — the text area up one, and the row that frees at the bottom
; marked as received and ready for the bytes.
; Clobbers (saved/restored): D0-D2
; ---------------------------------------------------------------------------
rx_open_row:
        MOVEM.L D0-D2,-(SP)
        BSR     text_new_row
        MOVE.B  #PEN_BG,VAR_PEN
        MOVE.B  #PEN_TEXT,VAR_PEN_BG
        MOVE.B  #'<',D0
        MOVEQ   #0,D1
        MOVE.B  #ROW_TEXT_BOT,D2
        BSR     screen_putchar
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVE.B  #1,TRM_RX_COL
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; text_new_row — the text area up one row, and the row that leaves free at the
; bottom blanked.
;
; It scrolls whether or not the area is full, so what has just happened always
; sits directly above the line being typed.  Bitmap to bitmap, so no ROM is
; read and the copy is safe wherever the session has got to.
;
; 23040 bytes go up one row.  The blitter takes them in a single BLTSIZE,
; because the text area is contiguous and the destination is above the source,
; and the CPU reads the keyboard while it works.  The wait at the end is what
; makes the bitmap the caller's again: the line it prints next goes into the
; rows this just moved.
; Clobbers (saved/restored): D0-D4/A0-A1
; ---------------------------------------------------------------------------
text_new_row:
        MOVEM.L D0-D4/A0-A1,-(SP)
        LEA     (BITPLANE_BASE+((ROW_TEXT_TOP+1)*ROW_STRIDE)).L,A0
        LEA     (BITPLANE_BASE+(ROW_TEXT_TOP*ROW_STRIDE)).L,A1
        MOVE.W  #SCREEN_BPL_W/2,D0      ; one plane row, in words
        MOVE.W  #SCROLL_ROWS,D1
        MOVEQ   #0,D2                   ; destination modulo, contiguous
        MOVEQ   #0,D3                   ; a whole row, so no shift
        MOVEQ   #0,D4                   ; source modulo, contiguous
        BSR     blit_copy
.tnr_wait:
        BSR     key_poll
        BTST    #6,(DMACONR).L          ; BBUSY
        BNE.S   .tnr_wait
        MOVEQ   #ROW_TEXT_BOT,D0
        BSR     clear_row
        MOVEM.L (SP)+,D0-D4/A0-A1
        RTS

; ---------------------------------------------------------------------------
; clear_row — D0.B = row, back to background.  Filling a row writes 1280 bytes
; and takes about four milliseconds, so the keyboard is read first.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
clear_row:
        MOVEM.L D0,-(SP)
        BSR     key_poll
        MOVE.B  #PEN_BG,VAR_PEN
        BSR     screen_fill_row
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; str_len — A0 = a null-terminated string.  Output: D0.W = its length.
; Clobbers (saved/restored): A0
; ---------------------------------------------------------------------------
str_len:
        MOVEM.L A0,-(SP)
        MOVEQ   #0,D0
.stl_ch:
        TST.B   (A0)+
        BEQ.S   .stl_done
        ADDQ.W  #1,D0
        BRA.S   .stl_ch
.stl_done:
        MOVEM.L (SP)+,A0
        RTS

; ============================================================
; Shared Amiga routines (run from RAM)
; ============================================================
        INCLUDE "../amiga-common/amiga_input.s"
        INCLUDE "../amiga-common/amiga_log.s"
        INCLUDE "../amiga-common/amiga_error.s"
        INCLUDE "../amiga-common/amiga_time.s"
        INCLUDE "../amiga-common/amiga_blit.s"

; ============================================================
; RBCP library (runs from RAM)
; ============================================================
        INCLUDE "../rbcp/rbcp.s"

        INCLUDE "../amiga-common/amiga_screen.s"

        EVEN
ram_section_rom_end:

; ============================================================
; ROM DATA SECTION
; Copper template, font, strings and tables.
; ============================================================

        INCLUDE "../amiga-common/amiga_screen_data.s"

        EVEN
str_title:
        DC.B    "RBCP TERMINAL "
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
; The device and pipe rows
; ---------------------------------------------------------------------------
        EVEN
str_send_pipe:
        DC.B    "SENDING ON PIPE ",0
str_send_pipe_len       EQU 16
        EVEN
str_read_pipe:
        DC.B    "READING ON PIPE ",0
str_read_pipe_len       EQU 16
        EVEN
str_no_rx:
        DC.B    "NOTHING COMES BACK",0
        EVEN
str_no_pipe:
        DC.B    "THE DEVICE HAS NO PIPES",0
        EVEN
str_pipe_dir:
        DC.B    "NO PIPE TAKES BYTES FROM HERE",0

; ---------------------------------------------------------------------------
; The status bar.  Every word this program puts on it is here, in the order
; amiga_defs.s numbers the codes.
; ---------------------------------------------------------------------------
        EVEN
str_status_tab:
        DC.L    str_blank,str_opening,str_ready,str_send_only
        DC.L    str_no_pipe,str_pipe_dir,str_no_answer,str_no_complete
        DC.L    str_pipe_full,str_not_armed,str_no_recover,str_rx_fail
        EVEN
str_left:
        DC.B    "LEFT",0
        EVEN
str_blank:
        DC.B    0
        EVEN
str_opening:
        DC.B    "OPENING RBCP SESSION",0
        EVEN
str_ready:
        DC.B    "READY",0
        EVEN
str_send_only:
        DC.B    "READY - NOTHING COMES BACK",0
        EVEN
str_no_answer:
        DC.B    "DEVICE DID NOT TAKE THE LINE",0
        EVEN
str_no_complete:
        DC.B    "DEVICE NEVER FINISHED WRITE",0
        EVEN
str_pipe_full:
        DC.B    "PIPE FULL - RETURN SENDS AGAIN",0
        EVEN
str_not_armed:
        DC.B    "NO SESSION - NOTHING TO SEND",0
        EVEN
str_no_recover:
        DC.B    "DEVICE DID NOT COME BACK",0
        EVEN
str_rx_fail:
        DC.B    "DEVICE REFUSED A READ",0

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
