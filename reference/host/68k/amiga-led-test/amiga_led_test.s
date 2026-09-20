; amiga_led_test.s — Amiga RBCP LED tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Purpose
; -------
; The tester drives a device's LEDs and shows what each one should be doing, so
; that a person with the board in front of them can hold the screen against it.
; Every key that changes something sends one SET_LED, reads every LED back and
; compares.  That comparison is the only check available — nothing the host
; reads proves an LED lit, because GET_LED_INFO answers out of the same place
; SET_LED wrote to.  What is left is whether the device agrees with itself, and
; whether what is on the board matches what is on the screen.
;
; The lamps
; ---------
; A lamp is a round lens with a lit centre, a body, a darker edge and the light
; it throws on the board around it — four pens, and the copper writes all four
; at the top of that lamp's own band of scan lines.  Six lamps in six different
; colours therefore cost four pens between them, and a mode that goes dark and
; light again moves four words with nothing redrawn.
;
; The colour and the brightness are the ones the device reports, scaled
; straight into a twelve-bit pen.  Nothing is matched to
; a nearest colour and nothing is dithered, so what is on the screen is what
; the device said it was driving.
;
; An LED whose mode is Off keeps the shading and loses the colour, because that
; is what an unlit lens looks like sitting on a board.  An LED that is dark for
; an instant of a blink or a breathe is not that — it has gone out, and the way
; to draw gone out is for the lamp to be black.
;
; The three screens
; -----------------
; The table is a row per LED with everything GET_LED_INFO reported.  The lamps
; screen is every LED at once, drawn big enough to read from where the board
; is.  The colour page is the list C steps through, with the LED it is stepping
; beside it.  T, L and C reach them.
;
; The tester owns the Amiga
; -------------------------
; The tester is a Kickstart image.  It runs from reset and never hands the
; machine back, so there is nothing to exit to and nothing to repair on the way
; out.  The device reloads its RAM slot from flash at power-on, so switching
; off is the repair.  An LED's state outlives the session, so an LED left lit
; stays lit until a device reset.
;
; Top-aligned ROM image layout — 256 KB from $FC0000 or 512 KB from $F80000:
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

; The tester draws none of the bootloader's artwork, so the pens that carry it
; are free.  A pen already defined keeps its value, so these go in before the
; palette is included.  Pens 8 to 13 are written by the copper while the
; program runs, so what they hold here is only what the screen shows before the
; first LED is read.
PEN06_RGB                   EQU $0999       ; PEN_LABEL
PEN07_RGB                   EQU $0FA0       ; PEN_WARN
PEN08_RGB                   EQU $0000
PEN09_RGB                   EQU $0000
PEN10_RGB                   EQU $0000
PEN11_RGB                   EQU $0000
PEN12_RGB                   EQU $0000
PEN13_RGB                   EQU $0000
PEN14_RGB                   EQU $0F44       ; PEN_BAD
PEN15_RGB                   EQU $0222       ; PEN_LENS

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
; ROM-section hardware routines
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
; BSR/BRA within this section are PC-relative and span the same distance in
; ROM and in the copy.  References out of it use absolute long addressing.
; ============================================================
ram_section_rom_start:

; ---------------------------------------------------------------------------
; ram_entry — the tester proper, running from chip RAM.  The session, the
; device's LEDs, then the loop.  It does not return.
; ---------------------------------------------------------------------------
ram_entry:
        BSR     zero_vars               ; before anything below is written
        MOVE.L  #BITPLANE_BASE,VAR_DRAW_BASE
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        CLR.B   VAR_MENU_COL            ; a filled row is the whole row here
        ; The beam line the tick is taken from, which is the first line off the
        ; bottom of the display.
        MOVE.W  #FIELD_TICK_NTSC,VAR_TICK_LINE
        TST.B   VAR_IS_PAL
        BEQ.S   .ae_ntsc
        MOVE.W  #FIELD_TICK_PAL,VAR_TICK_LINE
.ae_ntsc:
        MOVE.W  #SCAN_FIELDS,LT_SCAN_LEFT

        BSR     screen_clear
        BSR     draw_title              ; before anything is asked of the device

        BSR     sess_open               ; err_halt on the way out where it fails
        BSR     report_open
        BSR     led_discover

        ; From here every screen is built in the bitmap the copper is not
        ; showing.  err_halt is reachable only out of sess_open, above, and it
        ; draws to BITPLANE_BASE — which is still what the copper is showing,
        ; because nothing has been exchanged yet.
        MOVE.L  #BITPLANE_BASE,LT_FRONT
        MOVE.L  #BITPLANE_BACK,VAR_DRAW_BASE

        ; The lamps screen is the one to open on: its lamps are read from
        ; where the board is and the table is a keypress away.  A device with
        ; no LEDs opens on the table instead, because that is the screen that
        ; says why there is nothing to look at.
        CMPI.B  #LEDS_PRESENT,LT_STATE
        BNE.S   .ae_table
        MOVE.W  #SCR_LAMPS,LT_SCREEN
.ae_table:
        BSR     draw_screen

; ---------------------------------------------------------------------------
; led_loop — the tester's resting state.  The keyboard as often as the machine
; can read it, and everything else once a field.
;
; The keyboard arrives a byte at a time over the CIA-A serial port and the
; register holds one, so a poll that only came round once a field would drop
; keys.  The field's work hangs off the beam instead.
; ---------------------------------------------------------------------------
led_loop:
        BSR     tick_due
        TST.B   D0
        BEQ.S   .ll_keys
        BSR     screen_swap             ; what was drawn last field, put up
        BSR     on_tick
.ll_keys:
        BSR     amiga_getkey
        TST.B   D0
        BEQ     led_loop
        BSR     take_key
        BRA     led_loop

; ---------------------------------------------------------------------------
; tick_due — D0.B = 1 on the first poll of each new field, else 0.
;
; The beam crossing the tick line is the edge.  LT_TICK_ARM is set while the
; beam is still above it, so one crossing gives one tick however many times
; this is called.
; Clobbers: D0
; ---------------------------------------------------------------------------
tick_due:
        BSR     beam_line
        CMP.W   VAR_TICK_LINE,D0
        BCC.S   .td_reached
        MOVE.B  #1,LT_TICK_ARM
        MOVEQ   #0,D0
        RTS
.td_reached:
        MOVEQ   #0,D0
        TST.B   LT_TICK_ARM
        BEQ.S   .td_out
        CLR.B   LT_TICK_ARM
        MOVEQ   #1,D0
.td_out:
        RTS

; ---------------------------------------------------------------------------
; on_tick — the animation, the parade and the refresh scan, once a field.
;
; The scan is the refresh — one GET_LED_INFO per LED, so the picture is as live
; as the device is fast.  An LED something else on the device changed shows up
; here without this program having asked.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
on_tick:
        MOVEM.L D0,-(SP)
        TST.B   LT_GONE
        BNE.S   .ot_out
        CMPI.B  #LEDS_PRESENT,LT_STATE
        BNE.S   .ot_out
        BSR     anim_tick
        TST.B   LT_PARADE
        BEQ.S   .ot_scan
        BSR     parade_tick
        BRA.S   .ot_out
.ot_scan:
        SUBQ.W  #1,LT_SCAN_LEFT
        BNE.S   .ot_out
        MOVE.W  #SCAN_FIELDS,LT_SCAN_LEFT
        BSR     led_scan
        BSR     draw_scanned
.ot_out:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; zero_vars — the state of a machine that has just come out of reset.
;
; Chip RAM holds whatever it held, so the variables the shared routines own,
; the library's un-swap buffer and this program's own block are all cleared
; here.  VAR_IS_PAL and VAR_KEY_RESEND are not among them: screen_init and
; kbd_init set those before this ran.  Nor is VAR_LOG_PIPE, which log_open
; sets along with VAR_PIPE_PRESENT, or VAR_ERR_SNAP, which err_halt fills when
; it needs it.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
zero_vars:
        MOVEM.L D0/A0,-(SP)
        LEA     (VAR_BASE).W,A0
        MOVEQ   #24-1,D0                ; up to but not including VAR_IS_PAL
.zv_var:
        CLR.B   (A0)+
        DBF     D0,.zv_var
        LEA     (APP_BASE+$158).W,A0
        MOVEQ   #12-1,D0
.zv_app:
        CLR.B   (A0)+
        DBF     D0,.zv_app
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        MOVEQ   #CONFIG_RBCP_DATA_BUF_SIZE-1,D0
.zv_buf:
        CLR.B   (A0)+
        DBF     D0,.zv_buf
        LEA     (LT_VARS).W,A0
        MOVE.W  #LT_END-LT_VARS-1,D0
.zv_own:
        CLR.B   (A0)+
        DBF     D0,.zv_own
        MOVEM.L (SP)+,D0/A0
        RTS

; ===========================================================================
; The session
; ===========================================================================

; ---------------------------------------------------------------------------
; sess_open — knock, command-response mode, the version check and the three
; strings the device calls itself.
;
; A session that will not open goes to err_halt and does not come back.
; Output: D0=0, or err_halt on the way out where it fails
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
        LEA     (LT_DEV_TYPE).W,A1
        BSR     copy_name
.ri_ver:
        BSR     rbcp_cmd_get_device_version
        TST.B   D0
        BNE.S   .ri_proto
        LEA     (LT_DEV_VER).W,A1
        BSR     copy_name
.ri_proto:
        BSR     rbcp_cmd_get_proto_version
        TST.B   D0
        BNE.S   .ri_out
        MOVEQ   #4,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        LEA     (LT_PROTO).W,A1
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
; Clobbers: A1, advanced past the string.  D0-D1/A0 saved and restored.
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
; recover — the device did not answer, so put it back together.
;
; RBCP_RESET flushes a partially received command of up to nine argument bytes
; and two framing bytes, which is exactly what a frame that slipped by a byte
; onto a command taking arguments leaves behind.  Command-response mode is
; entered again rather than the session opened from scratch: the rest of
; opening a session decides whether to talk to the device at all, and that was
; settled before anything called this.
;
; Output: D0=0 back in command-response mode, D0=1 gave up
; Clobbers: D0
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
        MOVEQ   #0,D0
.rc_out:
        MOVEM.L (SP)+,D1
        RTS

; ---------------------------------------------------------------------------
; take_failure — what to do about the command that just failed.
;
; A device that answered and said no leaves the session in step: it discards
; what is left of the frame before it reports completion.  A device that did
; not answer may be waiting for argument bytes that will never arrive, and
; only a reset clears that.
;
; Output: D0.B = FAIL_REFUSED, FAIL_BACK or FAIL_GONE
; Clobbers: D0
; ---------------------------------------------------------------------------
take_failure:
        CMPI.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        BNE.S   .tf_lost
        MOVEQ   #FAIL_REFUSED,D0
        RTS
.tf_lost:
        BSR     recover
        TST.B   D0
        BNE.S   .tf_gone
        MOVEQ   #NOTE_SLIPPED,D0
        BSR     draw_note
        BSR     log_slipped
        MOVEQ   #FAIL_BACK,D0
        RTS
.tf_gone:
        MOVE.B  #1,LT_GONE
        MOVEQ   #NOTE_GONE,D0
        BSR     draw_note
        MOVEQ   #FAIL_GONE,D0
        RTS

; ===========================================================================
; The device's LEDs
; ===========================================================================

; ---------------------------------------------------------------------------
; led_discover — the capability, then every LED the screen has room for.
;
; A device with no LEDs is legal and is not an error.  So is one whose protocol
; version predates the group, which fails the capability command without
; consuming anything.  Either way there is nothing to drive, and the screen
; says which of the two it was.
; Clobbers (saved/restored): D0-D1
; ---------------------------------------------------------------------------
led_discover:
        MOVEM.L D0-D1,-(SP)
        BSR     rbcp_cmd_get_led_cap
        TST.B   D0
        BEQ.S   .ld_got
        BSR     take_failure
        MOVE.B  #LEDS_NO_GROUP,LT_STATE
        BRA     .ld_out
.ld_got:
        MOVEQ   #3,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+LED_CAP_MAX_PERIOD).W,LT_MAX_PERIOD
        MOVE.B  (CONFIG_RBCP_DATA_BUF+LED_CAP_MAX_HOLD).W,LT_MAX_HOLD
        MOVEQ   #0,D0
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_LED_CAP_COUNT).W,D0
        MOVE.B  D0,LT_TOTAL
        BSR     log_caps
        TST.B   D0
        BNE.S   .ld_some
        MOVE.B  #LEDS_NONE,LT_STATE
        BRA.S   .ld_out
.ld_some:
        CMPI.B  #LED_MAX,D0
        BLS.S   .ld_fits
        MOVEQ   #LED_MAX,D0
.ld_fits:
        MOVE.B  D0,LT_COUNT
        BSR     led_scan
        BSR     init_wants
        BSR     mode_info_refresh
        BSR     log_leds
.ld_out:
        MOVEM.L (SP)+,D0-D1
        RTS

; ---------------------------------------------------------------------------
; led_scan — GET_LED_INFO for every LED on the screen.
; Clobbers (saved/restored): D0/D3
; ---------------------------------------------------------------------------
led_scan:
        MOVEM.L D0/D3,-(SP)
        MOVEQ   #0,D3
.ls_led:
        MOVE.W  D3,D0
        BSR     read_led
        TST.B   D0
        BNE.S   .ls_bad
        ADDQ.W  #1,D3
        CMP.B   LT_COUNT,D3
        BCS.S   .ls_led
        BRA.S   .ls_out
.ls_bad:
        BSR     take_failure
.ls_out:
        MOVEM.L (SP)+,D0/D3
        RTS

; ---------------------------------------------------------------------------
; read_led — one LED's record into the tables.
; Input : D0.W = LED
; Output: D0.B = 0 read, non-zero the command failed
; Clobbers: D0
; ---------------------------------------------------------------------------
read_led:
        MOVEM.L D1/D3/A0-A1,-(SP)
        MOVE.W  D0,D3
        BSR     rbcp_cmd_get_led_info
        TST.B   D0
        BNE.S   .rl_out
        MOVEQ   #16,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A1
        LEA     (LT_TYPE).W,A0
        MOVE.B  RBCP_LED_INFO_TYPE(A1),(A0,D3.W)
        LEA     (LT_MODE).W,A0
        MOVE.B  RBCP_LED_INFO_MODE(A1),(A0,D3.W)
        LEA     (LT_RED).W,A0
        MOVE.B  LED_INFO_RED(A1),(A0,D3.W)
        LEA     (LT_GREEN).W,A0
        MOVE.B  LED_INFO_GREEN(A1),(A0,D3.W)
        LEA     (LT_BLUE).W,A0
        MOVE.B  LED_INFO_BLUE(A1),(A0,D3.W)
        LEA     (LT_BRIGHT).W,A0
        MOVE.B  LED_INFO_BRIGHT(A1),(A0,D3.W)
        LEA     (LT_PERIOD).W,A0
        MOVE.B  LED_INFO_PERIOD(A1),(A0,D3.W)
        LEA     (LT_MODES).W,A0
        MOVE.B  LED_INFO_MODES(A1),(A0,D3.W)
        MOVEQ   #0,D0
.rl_out:
        MOVEM.L (SP)+,D1/D3/A0-A1
        RTS

; ---------------------------------------------------------------------------
; init_wants — starts every LED where the device already has it, so the first
; key changes one thing rather than everything.
;
; SET_LED carries every field at once, so there is no way to change a mode and
; leave a brightness alone.  It can only start from the mode the device
; reports.  Colour, brightness, period and hold start at the entry that leaves
; each of them to the device.
; Clobbers (saved/restored): D0/D3/A0-A1
; ---------------------------------------------------------------------------
init_wants:
        MOVEM.L D0/D3/A0-A1,-(SP)
        MOVEQ   #0,D3
.iw_led:
        LEA     (LT_MODE).W,A0
        LEA     (LT_W_MODE).W,A1
        MOVE.B  (A0,D3.W),(A1,D3.W)
        LEA     (LT_W_COL).W,A0
        CLR.B   (A0,D3.W)
        LEA     (LT_W_BRIGHT).W,A0
        CLR.B   (A0,D3.W)
        LEA     (LT_W_PERIOD).W,A0
        CLR.B   (A0,D3.W)
        LEA     (LT_W_HOLD).W,A0
        CLR.B   (A0,D3.W)
        ADDQ.W  #1,D3
        CMP.B   LT_COUNT,D3
        BCS.S   .iw_led
        MOVEM.L (SP)+,D0/D3/A0-A1
        RTS

; ---------------------------------------------------------------------------
; mode_info_refresh — what the mode the next command will carry needs from the
; host, for the LED the keys are on.
;
; A device that answers and says no is answering: the mode takes no period on
; that LED, or the LED does not have it.  Only a device that says nothing at
; all is a failure.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
mode_info_refresh:
        MOVEM.L D0-D1/A0,-(SP)
        CLR.B   LT_MODE_FLAGS
        CLR.B   LT_MODE_MIN
        CMPI.B  #LEDS_PRESENT,LT_STATE
        BNE.S   .mi_out
        TST.B   LT_GONE
        BNE.S   .mi_out
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        MOVEQ   #0,D1
        LEA     (LT_W_MODE).W,A0
        MOVE.B  (A0,D0.W),D1
        BSR     rbcp_cmd_get_led_mode_info
        TST.B   D0
        BNE.S   .mi_refused
        MOVEQ   #2,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_LED_MODE_FLAGS).W,LT_MODE_FLAGS
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_LED_MODE_MIN_PERIOD).W,LT_MODE_MIN
        BRA.S   .mi_out
.mi_refused:
        CMPI.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        BEQ.S   .mi_out
        BSR     take_failure
.mi_out:
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; led_supports — D0.W = LED, D1.W = mode.  Z clear where that LED reports the
; mode.
;
; The bitmap reports modes $00 to $07 and nothing else, so this answers no for
; anything above.  Nothing here offers one.
; Clobbers: nothing but the condition codes
; ---------------------------------------------------------------------------
led_supports:
        MOVEM.L D2/A0,-(SP)
        CMPI.W  #8,D1
        BCC.S   .lsu_no
        LEA     (LT_MODES).W,A0
        MOVE.B  (A0,D0.W),D2
        BTST    D1,D2
        BRA.S   .lsu_out
.lsu_no:
        MOVEQ   #0,D2
        BTST    #0,D2                   ; Z set, so: no
.lsu_out:
        MOVEM.L (SP)+,D2/A0
        RTS

; ===========================================================================
; The keys
; ===========================================================================

; ---------------------------------------------------------------------------
; take_key — D0.B = a key code.
;
; Any key stops the parade and does nothing else, because a parade is
; something to watch and stopping it is what somebody reaching for the
; keyboard means.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
take_key:
        MOVEM.L D0-D1/A0,-(SP)
        TST.B   LT_PARADE
        BEQ.S   .tk_live
        CLR.B   LT_PARADE
        MOVEQ   #NOTE_BLANK,D0
        BSR     draw_note
        BRA     .tk_out
.tk_live:
        CMPI.B  #LEDS_PRESENT,LT_STATE
        BNE     .tk_out
        TST.B   LT_GONE
        BNE     .tk_out

        CMPI.B  #KEY_UP,D0
        BNE.S   .tk_not_up
        BSR     key_prev
        BRA     .tk_out
.tk_not_up:
        CMPI.B  #KEY_DOWN,D0
        BNE.S   .tk_not_down
        BSR     key_next
        BRA     .tk_out
.tk_not_down:
        CMPI.B  #KEY_RETURN,D0
        BNE.S   .tk_letter
        BSR     send_current
        BRA     .tk_out

        ; A letter is the same key in either case, so the shift is folded out
        ; before any of these are tried.
.tk_letter:
        ORI.B   #KEY_LOWER,D0
        CMPI.B  #KEY_MODE,D0
        BEQ     .tk_do_mode
        CMPI.B  #KEY_COLOUR,D0
        BEQ     .tk_do_colour
        CMPI.B  #KEY_BRIGHT,D0
        BEQ     .tk_do_bright
        CMPI.B  #KEY_PERIOD,D0
        BEQ     .tk_do_period
        CMPI.B  #KEY_HOLD,D0
        BEQ     .tk_do_hold
        CMPI.B  #KEY_PARADE,D0
        BEQ     .tk_do_parade
        CMPI.B  #KEY_TABLE,D0
        BEQ     .tk_do_table
        CMPI.B  #KEY_LAMPS,D0
        BEQ     .tk_do_lamps
        BRA.S   .tk_out
.tk_do_mode:
        BSR     key_mode
        BRA.S   .tk_out
.tk_do_colour:
        BSR     key_colour
        BRA.S   .tk_out
.tk_do_bright:
        BSR     key_bright
        BRA.S   .tk_out
.tk_do_period:
        BSR     key_period
        BRA.S   .tk_out
.tk_do_hold:
        BSR     key_hold
        BRA.S   .tk_out
.tk_do_parade:
        BSR     key_parade
        BRA.S   .tk_out
.tk_do_table:
        MOVEQ   #SCR_TABLE,D0
        BSR     show_screen
        BRA.S   .tk_out
.tk_do_lamps:
        MOVEQ   #SCR_LAMPS,D0
        BSR     show_screen
.tk_out:
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; key_next, key_prev — the LED the keys land on.  A device with one LED has
; nowhere to move to.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
key_next:
        MOVEM.L D0,-(SP)
        MOVE.B  LT_CUR,D0
        ADDQ.B  #1,D0
        CMP.B   LT_COUNT,D0
        BCS.S   .kn_store
        MOVEQ   #0,D0
.kn_store:
        MOVE.B  D0,LT_CUR
        BSR     led_changed
        MOVEM.L (SP)+,D0
        RTS

key_prev:
        MOVEM.L D0,-(SP)
        MOVE.B  LT_CUR,D0
        BNE.S   .kp_down
        MOVE.B  LT_COUNT,D0
.kp_down:
        SUBQ.B  #1,D0
        MOVE.B  D0,LT_CUR
        BSR     led_changed
        MOVEM.L (SP)+,D0
        RTS

; led_changed — everything that follows the selection moving.
; Clobbers (saved/restored): D0
led_changed:
        MOVEM.L D0,-(SP)
        MOVE.B  #READ_NONE,LT_READ
        BSR     mode_info_refresh
        BSR     draw_body
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; key_mode — the next mode this LED reports, wrapping.
;
; A mode the LED does not report is never offered, because the device reported
; which ones it has and this is what that report is for.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
key_mode:
        MOVEM.L D0-D2/A0,-(SP)
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        MOVEQ   #0,D1
        LEA     (LT_W_MODE).W,A0
        MOVE.B  (A0,D0.W),D1
        MOVEQ   #LED_MODE_COUNT,D2      ; goes, so an LED reporting none of the
                                        ; named modes does not spin
.km_step:
        ADDQ.W  #1,D1
        CMPI.W  #LED_MODE_COUNT,D1
        BCS.S   .km_try
        MOVEQ   #0,D1
.km_try:
        BSR     led_supports
        BNE.S   .km_take
        SUBQ.W  #1,D2
        BNE.S   .km_step
        BRA.S   .km_out
.km_take:
        LEA     (LT_W_MODE).W,A0
        MOVE.B  D1,(A0,D0.W)
        BSR     mode_info_refresh
        BSR     send_current
.km_out:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; key_colour — the next colour in the list.  A monochrome LED shows one colour
; and it is not the host's to set.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
key_colour:
        MOVEM.L D0-D1/A0,-(SP)
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        LEA     (LT_TYPE).W,A0
        CMPI.B  #RBCP_LED_TYPE_RGB,(A0,D0.W)
        BEQ.S   .kc_ours
        MOVEQ   #NOTE_NO_COLOUR,D0
        BSR     draw_note
        BRA.S   .kc_out
.kc_ours:
        LEA     (LT_W_COL).W,A0
        MOVE.B  (A0,D0.W),D1
        ADDQ.B  #1,D1
        CMPI.B  #COLOUR_COUNT,D1
        BCS.S   .kc_store
        MOVEQ   #0,D1
.kc_store:
        MOVE.B  D1,(A0,D0.W)
        ; The colour page is where the list can be seen, so stepping the list
        ; goes there and steps it again from then on.
        MOVEQ   #SCR_COLOURS,D0
        BSR     show_screen
        BSR     send_current
.kc_out:
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; key_bright — the next brightness in the list.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
key_bright:
        MOVEM.L D0-D1/A0,-(SP)
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        LEA     (LT_W_BRIGHT).W,A0
        MOVE.B  (A0,D0.W),D1
        ADDQ.B  #1,D1
        CMPI.B  #BRIGHT_STEPS,D1
        BCS.S   .kb_store
        MOVEQ   #0,D1
.kb_store:
        MOVE.B  D1,(A0,D0.W)
        BSR     send_current
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; key_period — the next period the mode and the device both accept.
;
; The range depends on the mode as well as the device, so a value the mode
; would refuse is stepped over rather than sent.  Entry 0 names no period and
; is always allowed: it asks for the mode's own default.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
key_period:
        MOVEM.L D0-D3/A0,-(SP)
        BSR     mode_info_refresh
        MOVE.B  LT_MODE_FLAGS,D0
        ANDI.B  #RBCP_LED_MODE_TAKES_PERIOD,D0
        BNE.S   .kpe_have
        MOVEQ   #NOTE_NO_PERIOD,D0
        BSR     draw_note
        BRA     .kpe_out
.kpe_have:
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        LEA     (LT_W_PERIOD).W,A0
        MOVE.B  (A0,D0.W),D1
        MOVEQ   #PERIOD_STEPS,D3        ; goes, so a device accepting none of
                                        ; them does not spin
.kpe_step:
        ADDQ.B  #1,D1
        CMPI.B  #PERIOD_STEPS,D1
        BCS.S   .kpe_try
        MOVEQ   #0,D1
.kpe_try:
        MOVEQ   #0,D2
        MOVE.B  D1,D2
        LEA     (period_steps).L,A0
        MOVE.B  (A0,D2.W),D2
        BEQ.S   .kpe_take               ; the mode's own default, always allowed
        CMP.B   LT_MODE_MIN,D2
        BCS.S   .kpe_next               ; under the shortest this mode accepts
        CMP.B   LT_MAX_PERIOD,D2
        BLS.S   .kpe_take
.kpe_next:
        SUBQ.B  #1,D3
        BNE.S   .kpe_step
        BRA.S   .kpe_out
.kpe_take:
        LEA     (LT_W_PERIOD).W,A0
        MOVE.B  D1,(A0,D0.W)
        BSR     send_current
.kpe_out:
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; key_hold — the next hold the device will time.  Entry 0 names no hold and
; leaves the mode in force until something changes it.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
key_hold:
        MOVEM.L D0-D3/A0,-(SP)
        TST.B   LT_MAX_HOLD
        BNE.S   .kh_have
        MOVEQ   #NOTE_NO_HOLD,D0
        BSR     draw_note
        BRA.S   .kh_out
.kh_have:
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        LEA     (LT_W_HOLD).W,A0
        MOVE.B  (A0,D0.W),D1
        MOVEQ   #HOLD_STEPS,D3
.kh_step:
        ADDQ.B  #1,D1
        CMPI.B  #HOLD_STEPS,D1
        BCS.S   .kh_try
        MOVEQ   #0,D1
.kh_try:
        MOVEQ   #0,D2
        MOVE.B  D1,D2
        LEA     (hold_steps).L,A0
        MOVE.B  (A0,D2.W),D2
        BEQ.S   .kh_take                ; until something changes it
        CMP.B   LT_MAX_HOLD,D2
        BLS.S   .kh_take
        SUBQ.B  #1,D3
        BNE.S   .kh_step
        BRA.S   .kh_out
.kh_take:
        LEA     (LT_W_HOLD).W,A0
        MOVE.B  D1,(A0,D0.W)
        BSR     send_current
.kh_out:
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; key_parade — every LED through every mode it reports, one at a time.
;
; This is the whole of what the device claims it can do, driven without
; anybody having to press a key for each of them.  Any key stops it.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
key_parade:
        MOVEM.L D0,-(SP)
        MOVE.B  #1,LT_PARADE
        CLR.B   LT_P_LED
        MOVE.B  #$FF,LT_P_MODE          ; parade_step moves on before it sends
        MOVE.W  #1,LT_P_LEFT
        MOVEQ   #NOTE_PARADE,D0
        BSR     draw_note
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; parade_tick — one field of the parade.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
parade_tick:
        MOVEM.L D0,-(SP)
        SUBQ.W  #1,LT_P_LEFT
        BNE.S   .pt_out
        BSR     parade_step
.pt_out:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; parade_step — the next mode of the next LED, sent.
;
; It runs to the end and stops there, leaving every LED in the last mode it
; was given.  Putting them back would undo the thing somebody just watched.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
parade_step:
        MOVEM.L D0-D2/A0,-(SP)
        MOVEQ   #0,D0
        MOVE.B  LT_P_LED,D0
        MOVEQ   #0,D1
        MOVE.B  LT_P_MODE,D1
        EXT.W   D1                      ; the $FF before the first step is -1,
                                        ; so the step after it is mode 0 of
                                        ; LED 0 rather than a wrap onto LED 1
.ps_next:
        ADDQ.W  #1,D1
        CMPI.W  #LED_MODE_COUNT,D1
        BCS.S   .ps_try
        MOVEQ   #0,D1                   ; this LED is done, so the next one
        ADDQ.W  #1,D0
        CMP.B   LT_COUNT,D0
        BCC.S   .ps_end
.ps_try:
        BSR     led_supports
        BEQ.S   .ps_next
        MOVE.B  D0,LT_P_LED
        MOVE.B  D1,LT_P_MODE
        MOVE.W  #PARADE_FIELDS,LT_P_LEFT
        MOVE.B  D0,LT_CUR
        LEA     (LT_W_MODE).W,A0
        MOVE.B  D1,(A0,D0.W)
        BSR     send_current
        MOVEQ   #NOTE_PARADE,D0         ; send_current has its own to say and
        BSR     draw_note               ; the parade's stands over it
        BRA.S   .ps_out
.ps_end:
        CLR.B   LT_PARADE
        MOVEQ   #NOTE_BLANK,D0
        BSR     draw_note
.ps_out:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ===========================================================================
; Sending, and the read back
; ===========================================================================

; ---------------------------------------------------------------------------
; send_current — one SET_LED for the selected LED, then a read back of every
; LED and a comparison against what was asked for.
; Clobbers (saved/restored): D0-D1
; ---------------------------------------------------------------------------
send_current:
        MOVEM.L D0-D1,-(SP)
        MOVEQ   #NOTE_BLANK,D0
        BSR     draw_note
        BSR     stage_args
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        BSR     rbcp_cmd_set_led
        TST.B   D0
        BEQ.S   .sc_sent

        BSR     take_failure
        CMPI.B  #FAIL_REFUSED,D0
        BNE.S   .sc_out                 ; the note says what became of it
        MOVE.B  #READ_REFUSED,LT_READ
        MOVEQ   #NOTE_REFUSED,D0
        BSR     draw_note
        BSR     log_refused
        BSR     led_scan
        BRA.S   .sc_show
.sc_sent:
        BSR     log_set
        BSR     led_scan
        TST.B   LT_GONE
        BNE.S   .sc_out
        BSR     check_read
        BSR     log_got
.sc_show:
        BSR     draw_body
.sc_out:
        MOVEM.L (SP)+,D0-D1
        RTS

; ---------------------------------------------------------------------------
; stage_args — the seven SET_LED bytes the stepping lists name.
; Clobbers (saved/restored): D0-D1/A0-A1
; ---------------------------------------------------------------------------
stage_args:
        MOVEM.L D0-D1/A0-A1,-(SP)
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        LEA     (LT_SENT).W,A1

        LEA     (LT_W_MODE).W,A0
        MOVE.B  (A0,D0.W),SENT_MODE(A1)

        ; The colour.  Entry 0 is three zeroes, which asks the device to choose
        ; one.  A monochrome LED shows its own colour whatever goes out here.
        LEA     (LT_W_COL).W,A0
        MOVEQ   #0,D1
        MOVE.B  (A0,D0.W),D1
        MULU    #3,D1
        LEA     (colour_rgb).L,A0
        ADDA.W  D1,A0
        MOVE.B  (A0)+,SENT_RED(A1)
        MOVE.B  (A0)+,SENT_GREEN(A1)
        MOVE.B  (A0)+,SENT_BLUE(A1)

        LEA     (LT_W_BRIGHT).W,A0
        MOVEQ   #0,D1
        MOVE.B  (A0,D0.W),D1
        LEA     (bright_steps).L,A0
        MOVE.B  (A0,D1.W),SENT_BRIGHT(A1)

        LEA     (LT_W_PERIOD).W,A0
        MOVEQ   #0,D1
        MOVE.B  (A0,D0.W),D1
        LEA     (period_steps).L,A0
        MOVE.B  (A0,D1.W),SENT_PERIOD(A1)

        LEA     (LT_W_HOLD).W,A0
        MOVEQ   #0,D1
        MOVE.B  (A0,D0.W),D1
        LEA     (hold_steps).L,A0
        MOVE.B  (A0,D1.W),SENT_HOLD(A1)

        MOVE.B  SENT_MODE(A1),RBCP_ARG0
        MOVE.B  SENT_RED(A1),RBCP_ARG1
        MOVE.B  SENT_GREEN(A1),RBCP_ARG2
        MOVE.B  SENT_BLUE(A1),RBCP_ARG3
        MOVE.B  SENT_BRIGHT(A1),RBCP_ARG4
        MOVE.B  SENT_PERIOD(A1),RBCP_ARG5
        MOVE.B  SENT_HOLD(A1),RBCP_ARG6
        MOVEM.L (SP)+,D0-D1/A0-A1
        RTS

; ---------------------------------------------------------------------------
; check_read — what the device now reports for the selected LED against what it
; was given, field by field and only for the fields the host named.
;
; A brightness of zero, a period of zero and a colour of three zeroes all mean
; the device chooses, so there is nothing to compare on those.  A monochrome
; LED's colour is never the host's, so there is nothing to compare there
; either.  What is left is what the device promised to do.
;
; The first field that differs stops the comparison, and LT_READ_FIELD and
; LT_READ_GOT keep which one it was and what the device gave, so the screen
; can name it.
; Clobbers (saved/restored): D0-D3/A0-A1
; ---------------------------------------------------------------------------
check_read:
        MOVEM.L D0-D3/A0-A1,-(SP)
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        LEA     (LT_SENT).W,A1

        MOVEQ   #RDF_MODE,D3
        MOVE.B  SENT_MODE(A1),D1
        LEA     (LT_MODE).W,A0
        CMP.B   (A0,D0.W),D1
        BNE     .cr_differs

        MOVEQ   #RDF_BRIGHT,D3
        MOVE.B  SENT_BRIGHT(A1),D1
        BEQ.S   .cr_bright_ok
        LEA     (LT_BRIGHT).W,A0
        CMP.B   (A0,D0.W),D1
        BNE     .cr_differs
.cr_bright_ok:
        MOVEQ   #RDF_PERIOD,D3
        MOVE.B  SENT_PERIOD(A1),D1
        BEQ.S   .cr_period_ok
        LEA     (LT_PERIOD).W,A0
        CMP.B   (A0,D0.W),D1
        BNE     .cr_differs
.cr_period_ok:
        LEA     (LT_TYPE).W,A0
        CMPI.B  #RBCP_LED_TYPE_RGB,(A0,D0.W)
        BNE     .cr_match
        MOVE.B  SENT_RED(A1),D1
        MOVE.B  SENT_GREEN(A1),D2
        OR.B    D2,D1
        MOVE.B  SENT_BLUE(A1),D2
        OR.B    D2,D1
        BEQ.S   .cr_match               ; the device chose it, so it is its own
        MOVEQ   #RDF_RED,D3
        MOVE.B  SENT_RED(A1),D1
        LEA     (LT_RED).W,A0
        CMP.B   (A0,D0.W),D1
        BNE.S   .cr_differs
        MOVEQ   #RDF_GREEN,D3
        MOVE.B  SENT_GREEN(A1),D1
        LEA     (LT_GREEN).W,A0
        CMP.B   (A0,D0.W),D1
        BNE.S   .cr_differs
        MOVEQ   #RDF_BLUE,D3
        MOVE.B  SENT_BLUE(A1),D1
        LEA     (LT_BLUE).W,A0
        CMP.B   (A0,D0.W),D1
        BNE.S   .cr_differs
.cr_match:
        MOVE.B  #READ_MATCH,LT_READ
        BRA.S   .cr_out
.cr_differs:
        ; A0 is the table the field came out of and D0 the LED, so what the
        ; device gave is there to be kept alongside which field it was.
        MOVE.B  D3,LT_READ_FIELD
        MOVE.B  (A0,D0.W),LT_READ_GOT
        MOVE.B  #READ_DIFFERS,LT_READ
.cr_out:
        MOVEM.L (SP)+,D0-D3/A0-A1
        RTS

; ===========================================================================
; The lamps
;
; A lamp is four pens, written into the copper list.  So an LED's state this
; instant costs four words rather than a redraw, and the animation is free.
; ===========================================================================

; ---------------------------------------------------------------------------
; anim_tick — one field on for every LED that is moving.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
anim_tick:
        MOVEM.L D0-D3/A0,-(SP)
        MOVEQ   #0,D3
.at_led:
        MOVE.W  D3,D0
        BSR     anim_steps_of
        CMPI.W  #2,D1
        BCS.S   .at_next                ; one step, so nothing moves
        MOVE.W  D3,D2
        ADD.W   D2,D2                   ; a word each
        LEA     (LT_A_LEFT).W,A0
        SUBQ.W  #1,(A0,D2.W)
        BNE.S   .at_next
        MOVE.W  D3,D0
        BSR     anim_advance
.at_next:
        ADDQ.W  #1,D3
        CMP.B   LT_COUNT,D3
        BCS.S   .at_led
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; anim_advance — D0.W = LED.  One step on, and the lamp with it.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
anim_advance:
        MOVEM.L D0-D2/A0,-(SP)
        BSR     anim_steps_of           ; D1.W = steps
        LEA     (LT_A_STEP).W,A0
        MOVEQ   #0,D2
        MOVE.B  (A0,D0.W),D2
        ADDQ.W  #1,D2
        CMP.W   D1,D2
        BCS.S   .aa_store
        MOVEQ   #0,D2
.aa_store:
        MOVE.B  D2,(A0,D0.W)
        BSR     anim_reload
        BSR     lamp_write
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; anim_reload — D0.W = LED.  The fields the next step lasts, from the period
; the device reports.
;
; A device reporting no period is animated at ANIM_DEFAULT_PERIOD, because a
; mode with no period still has to be drawn doing something.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
anim_reload:
        MOVEM.L D0-D2/A0,-(SP)
        BSR     anim_steps_of           ; D1.W = steps
        LEA     (LT_PERIOD).W,A0
        MOVEQ   #0,D2
        MOVE.B  (A0,D0.W),D2
        BNE.S   .ar_have
        MOVEQ   #ANIM_DEFAULT_PERIOD,D2
.ar_have:
        MULU    #ANIM_FIELDS_UNIT,D2
        DIVU    D1,D2
        ANDI.L  #$FFFF,D2
        BNE.S   .ar_store
        MOVEQ   #1,D2                   ; never nought fields, which would
.ar_store:                              ; leave the step never taken
        MOVE.W  D0,D1
        ADD.W   D1,D1
        LEA     (LT_A_LEFT).W,A0
        MOVE.W  D2,(A0,D1.W)
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; anim_steps_of — D0.W = LED.  D1.W = steps in one repetition of its mode.
; A mode this program does not animate has one, which is steady.
; Clobbers: D1
; ---------------------------------------------------------------------------
anim_steps_of:
        MOVEM.L A0,-(SP)
        LEA     (LT_MODE).W,A0
        MOVEQ   #0,D1
        MOVE.B  (A0,D0.W),D1
        CMPI.W  #LED_MODE_COUNT,D1
        BCC.S   .as_one
        LEA     (anim_steps).L,A0
        MOVE.B  (A0,D1.W),D1
        BRA.S   .as_out
.as_one:
        MOVEQ   #1,D1
.as_out:
        MOVEM.L (SP)+,A0
        RTS

; ---------------------------------------------------------------------------
; anim_check — D0.W = LED.  Restarts the animation where the mode or the
; period the device reports is not the one the state was built for, so a stale
; step is never carried across.
; Clobbers (saved/restored): D0-D2/A0-A1
; ---------------------------------------------------------------------------
anim_check:
        MOVEM.L D0-D2/A0-A1,-(SP)
        LEA     (LT_MODE).W,A0
        LEA     (LT_A_MODE).W,A1
        MOVE.B  (A0,D0.W),D1
        CMP.B   (A1,D0.W),D1
        BNE.S   .ac_restart
        LEA     (LT_PERIOD).W,A0
        LEA     (LT_A_PERIOD).W,A1
        MOVE.B  (A0,D0.W),D1
        CMP.B   (A1,D0.W),D1
        BEQ.S   .ac_out
.ac_restart:
        LEA     (LT_MODE).W,A0
        LEA     (LT_A_MODE).W,A1
        MOVE.B  (A0,D0.W),(A1,D0.W)
        LEA     (LT_PERIOD).W,A0
        LEA     (LT_A_PERIOD).W,A1
        MOVE.B  (A0,D0.W),(A1,D0.W)
        LEA     (LT_A_STEP).W,A0
        CLR.B   (A0,D0.W)
        BSR     anim_reload
.ac_out:
        MOVEM.L (SP)+,D0-D2/A0-A1
        RTS

; ---------------------------------------------------------------------------
; lamp_write — D0.W = LED.  Its four pens, as the copper will next read them.
;
; A screen that draws no lamp for this LED left its copper pointer clear, and
; then there is nothing to write.
; Clobbers (saved/restored): D0-D7/A0-A1
; ---------------------------------------------------------------------------
lamp_write:
        MOVEM.L D0-D7/A0-A1,-(SP)
        MOVE.W  D0,D6
        LSL.W   #2,D6                   ; a long per LED
        LEA     (LT_LAMP_COP).W,A1
        MOVEA.L (A1,D6.W),A0
        MOVE.L  A0,D6
        BEQ.S   .lw_out

        LEA     (LT_MODE).W,A1
        TST.B   (A1,D0.W)
        BNE.S   .lw_lit
        MOVE.W  #LENS_CORE_RGB,(A0)     ; a lens with nothing behind it
        MOVE.W  #LENS_BODY_RGB,4(A0)
        MOVE.W  #LENS_EDGE_RGB,8(A0)
        MOVE.W  #LENS_GLOW_RGB,12(A0)
        BRA.S   .lw_out
.lw_lit:
        BSR     lamp_source             ; D1-D3 = red, green and blue
        MOVE.W  D4,D7                   ; and how lit the lamp is
        LEA     (shade_tab).L,A1
        MOVEQ   #4-1,D6
.lw_shade:
        MOVEQ   #0,D4
        MOVE.B  (A1)+,D4                ; what this shade keeps
        MOVEQ   #0,D5
        MOVE.B  (A1)+,D5                ; and how far towards white it goes
        MULU    D7,D5                   ; which follows how lit the lamp is, so
        LSR.L   #8,D5                   ; one that has gone out is black and not
        BSR     shade_pack              ; a white centre on nothing
        MOVE.W  D0,(A0)
        ADDQ.L  #4,A0
        DBF     D6,.lw_shade
.lw_out:
        MOVEM.L (SP)+,D0-D7/A0-A1
        RTS

; ---------------------------------------------------------------------------
; lamp_source — D0.W = LED.  D1, D2 and D3 = the red, green and blue its lamp
; is showing this instant, 0 to 255, and D4.W = how lit it is over the same
; range.
;
; The colour is the one the device reports, scaled by the brightness it reports
; and by where the animation has got to.  A cycling LED has no colour to
; report, so the hue comes from where the cycle is instead.  A colour of three
; zeroes is a device stating none, and the lamp is drawn neutral rather than in
; a colour nobody asked for.
; Clobbers: D1-D4
; ---------------------------------------------------------------------------
lamp_source:
        MOVEM.L D0/D5-D6/A0,-(SP)
        LEA     (LT_MODE).W,A0
        MOVEQ   #0,D4
        MOVE.B  (A0,D0.W),D4            ; the mode
        LEA     (LT_A_STEP).W,A0
        MOVEQ   #0,D5
        MOVE.B  (A0,D0.W),D5            ; and where it has got to

        CMPI.B  #RBCP_LED_CYCLE,D4
        BEQ.S   .lso_cycle

        LEA     (LT_RED).W,A0
        MOVEQ   #0,D1
        MOVE.B  (A0,D0.W),D1
        LEA     (LT_GREEN).W,A0
        MOVEQ   #0,D2
        MOVE.B  (A0,D0.W),D2
        LEA     (LT_BLUE).W,A0
        MOVEQ   #0,D3
        MOVE.B  (A0,D0.W),D3
        MOVE.W  D1,D6
        OR.W    D2,D6
        OR.W    D3,D6
        BNE.S   .lso_level
        MOVE.W  #$00C0,D1               ; lit, in a colour the device does not
        MOVE.W  #$00C0,D2               ; state
        MOVE.W  #$00C0,D3
        BRA.S   .lso_level
.lso_cycle:
        MULU    #3,D5
        LEA     (cycle_hues).L,A0
        ADDA.W  D5,A0
        MOVEQ   #0,D1
        MOVE.B  (A0)+,D1
        MOVEQ   #0,D2
        MOVE.B  (A0)+,D2
        MOVEQ   #0,D3
        MOVE.B  (A0)+,D3
.lso_level:
        BSR     lamp_level              ; D4.W = 0 to 255
        MULU    D4,D1
        LSR.L   #8,D1
        MULU    D4,D2
        LSR.L   #8,D2
        MULU    D4,D3
        LSR.L   #8,D3
        MOVEM.L (SP)+,D0/D5-D6/A0
        RTS

; ---------------------------------------------------------------------------
; shade_pack — D1, D2 and D3 = red, green and blue 0 to 255, D4.W = what this
; shade keeps and D5.W = how far towards white it goes, both out of 256.
; D0.W = the twelve-bit pen.
; Clobbers: D0
; ---------------------------------------------------------------------------
shade_pack:
        MOVEM.L D1-D3/D6-D7,-(SP)
        MOVE.W  D1,D6
        BSR     shade_one
        MOVE.W  D6,D7
        LSL.W   #8,D7
        MOVE.W  D2,D6
        BSR     shade_one
        LSL.W   #4,D6
        OR.W    D6,D7
        MOVE.W  D3,D6
        BSR     shade_one
        OR.W    D6,D7
        MOVE.W  D7,D0
        ANDI.W  #$0FFF,D0
        MOVEM.L (SP)+,D1-D3/D6-D7
        RTS

; ---------------------------------------------------------------------------
; shade_one — D6.W = one channel 0 to 255, D4.W = what to keep, D5.W = how far
; towards white.  D6.W = the four bits the pen carries.
; Clobbers: D6
; ---------------------------------------------------------------------------
shade_one:
        MOVEM.L D0-D1,-(SP)
        ANDI.L  #$00FF,D6
        MULU    D4,D6
        LSR.L   #8,D6
        TST.W   D5
        BEQ.S   .s1_out
        MOVE.W  #255,D1
        SUB.W   D6,D1
        ANDI.L  #$FFFF,D1
        MULU    D5,D1
        LSR.L   #8,D1
        ADD.W   D1,D6
        CMPI.W  #255,D6
        BLS.S   .s1_out
        MOVE.W  #255,D6
.s1_out:
        LSR.W   #4,D6
        MOVEM.L (SP)+,D0-D1
        RTS

; ---------------------------------------------------------------------------
; lamp_level — D0.W = LED, D4.B = its mode, D5.B = its animation step.
; D4.W = how lit the lamp is, 0 to 255: where the mode has it this instant,
; scaled by the brightness the device reports.
;
; An LED reporting no brightness has none to report, and is drawn lit.
; Clobbers: D4
; ---------------------------------------------------------------------------
lamp_level:
        MOVEM.L D0/D5/A0,-(SP)
        CMPI.B  #RBCP_LED_BLINK,D4
        BEQ.S   .ll_blink
        CMPI.B  #RBCP_LED_BREATHE,D4
        BEQ.S   .ll_breathe
        CMPI.B  #RBCP_LED_BEACON,D4
        BEQ.S   .ll_beacon
        MOVE.W  #ANIM_FULL,D4
        BRA.S   .ll_bright
.ll_blink:
        LEA     (blink_level).L,A0
        BRA.S   .ll_table
.ll_breathe:
        LEA     (breathe_level).L,A0
        BRA.S   .ll_table
.ll_beacon:
        LEA     (beacon_level).L,A0
.ll_table:
        ANDI.W  #$00FF,D5
        MOVEQ   #0,D4
        MOVE.B  (A0,D5.W),D4
.ll_bright:
        LEA     (LT_BRIGHT).W,A0
        MOVEQ   #0,D5
        MOVE.B  (A0,D0.W),D5
        BNE.S   .ll_scale
        MOVEQ   #100,D5                 ; no brightness on this LED, so lit
.ll_scale:
        MULU    D5,D4
        DIVU    #100,D4
        ANDI.L  #$FFFF,D4
        MOVEM.L (SP)+,D0/D5/A0
        RTS

; ===========================================================================
; The copper list
;
; screen_init leaves a list that sets the sixteen pens once at the top of the
; field.  Everything below is appended over its END, a band of scan lines at a
; time, so a lamp's pens hold what that lamp needs while the beam is crossing
; it.
;
; A band is one WAIT and the MOVEs after it, and the bands go down the screen
; in order because that is the only order a copper can be given.
; ===========================================================================

; ---------------------------------------------------------------------------
; cop_reset — start again at the template's END, with no lamp registered.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
cop_reset:
        MOVEM.L D0/A0,-(SP)
        MOVE.L  #COPPER_BASE+COP_LIST_LEN-4,LT_COP_PTR
        LEA     (LT_LAMP_COP).W,A0
        MOVEQ   #LED_MAX-1,D0
.crs_clear:
        CLR.L   (A0)+
        DBF     D0,.crs_clear
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; cop_wait — D0.W = the first pixel row of the band.
;
; The wait is for the far end of the line above, so the MOVEs after it have
; landed before the band's own first line is drawn.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
cop_wait:
        MOVEM.L D0-D1/A0,-(SP)
        MOVEA.L LT_COP_PTR,A0
        MOVE.W  D0,D1
        ADDI.W  #COP_LINE0-1,D1
        LSL.W   #8,D1
        ORI.W   #COP_WAIT_HP,D1
        MOVE.W  D1,(A0)+
        MOVE.W  #$FFFE,(A0)+            ; every mask bit, and not the blitter
        MOVE.L  A0,LT_COP_PTR
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; cop_move — D0.W = pen, D1.W = the colour it takes from this band down.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
cop_move:
        MOVEM.L D0-D2/A0,-(SP)
        MOVEA.L LT_COP_PTR,A0
        MOVE.W  D0,D2
        ADD.W   D2,D2                   ; a register per pen
        ADDI.W  #COP_COLOR00,D2
        MOVE.W  D2,(A0)+
        MOVE.W  D1,(A0)+
        MOVE.L  A0,LT_COP_PTR
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; cop_end — the instruction that stops the copper for this field.
; Clobbers (saved/restored): A0
; ---------------------------------------------------------------------------
cop_end:
        MOVEM.L A0,-(SP)
        MOVEA.L LT_COP_PTR,A0
        MOVE.W  #$FFFF,(A0)+
        MOVE.W  #$FFFE,(A0)+
        MOVEM.L (SP)+,A0
        RTS

; ---------------------------------------------------------------------------
; cop_lamp_pens — four MOVEs for one lamp, and a note of where they landed so
; the animation can write through them.
; Input : D1.W = the LED they belong to, D2.W = the first of the four pens
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
cop_lamp_pens:
        MOVEM.L D0-D3/A0,-(SP)
        MOVE.W  D1,D3
        LSL.W   #2,D3                   ; a long per LED
        LEA     (LT_LAMP_COP).W,A0
        MOVE.L  LT_COP_PTR,D0
        ADDQ.L  #2,D0                   ; past the register, onto the colour
        MOVE.L  D0,(A0,D3.W)
        MOVEQ   #4-1,D3
.clp_one:
        MOVE.W  D2,D0
        MOVEQ   #0,D1
        BSR     cop_move
        ADDQ.W  #1,D2
        DBF     D3,.clp_one
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; cop_band_row — D1.W = an entry.  D0.W = the first pixel row of its band.
;
; Every screen lays its entries out the same way, so this reads the pitch and
; the first row layout_entries worked out rather than knowing which screen is
; up.
; Clobbers: D0
; ---------------------------------------------------------------------------
cop_band_row:
        MOVEM.L D2,-(SP)
        MOVEQ   #0,D0
        MOVE.B  LT_PITCH,D0
        MULU    D1,D0
        MOVEQ   #0,D2
        MOVE.B  LT_FIRST,D2
        ADD.W   D2,D0
        LSL.W   #3,D0                   ; eight pixel rows to a character row
        MOVEM.L (SP)+,D2
        RTS

; ---------------------------------------------------------------------------
; band_middle — D1.W = an entry.  D0.W = the pixel row its lamp is centred on,
; which is halfway down its band.
; Clobbers: D0
; ---------------------------------------------------------------------------
band_middle:
        MOVEM.L D2,-(SP)
        BSR     cop_band_row
        MOVEQ   #0,D2
        MOVE.B  LT_PITCH,D2
        LSL.W   #2,D2                   ; half the band, in pixel rows
        ADD.W   D2,D0
        MOVEM.L (SP)+,D2
        RTS

; ---------------------------------------------------------------------------
; cop_strip — D1.W = a band's number, D2.W = the one that is picked.  The
; background across the band, which is the strip behind whatever is selected.
; Clobbers (saved/restored): D0-D1
; ---------------------------------------------------------------------------
cop_strip:
        MOVEM.L D0-D1,-(SP)
        MOVE.W  #PEN00_RGB,D0
        CMP.W   D1,D2
        BNE.S   .cst_put
        MOVE.W  #HILITE_RGB,D0
.cst_put:
        MOVE.W  D0,D1
        MOVEQ   #PEN_BG,D0
        BSR     cop_move
        MOVEM.L (SP)+,D0-D1
        RTS

; ---------------------------------------------------------------------------
; cop_build — the bands this screen needs, and then every lamp's colour.
;
; screen_swap is the only caller and it runs with the beam off the bottom of
; the display, so the copper is stopped at the list's END and never part way
; down a list that is changing under it.
; Clobbers (saved/restored): D0-D2
; ---------------------------------------------------------------------------
cop_build:
        MOVEM.L D0-D2,-(SP)
        BSR     cop_reset
        CMPI.B  #LEDS_PRESENT,LT_STATE
        BNE     .cb_close
        CMPI.W  #SCR_COLOURS,LT_SCREEN
        BEQ.S   .cb_colours

        MOVEQ   #0,D1                   ; a band per LED
.cb_band:
        BSR     cop_band_row
        BSR     cop_wait
        MOVEQ   #PEN_LAMP,D2
        BSR     cop_lamp_pens
        MOVEQ   #0,D2
        MOVE.B  LT_CUR,D2
        BSR     cop_strip
        ADDQ.W  #1,D1
        CMP.B   LT_COUNT,D1
        BCS.S   .cb_band

        BSR     cop_band_row            ; the row under the last of them
        BSR     cop_wait
        MOVEQ   #PEN_BG,D0
        MOVE.W  #PEN00_RGB,D1
        BSR     cop_move
        BRA.S   .cb_close

.cb_colours:
        ; A band per colour in the list, each holding that colour's swatch.
        ; The first carries the selected LED's own four pens as well, because
        ; its lamp stands beside the list and no band below changes them.
        MOVEQ   #0,D1
.cb_pick:
        BSR     cop_band_row
        BSR     cop_wait
        TST.W   D1
        BNE.S   .cb_swatch
        MOVEQ   #0,D1
        MOVE.B  LT_CUR,D1
        MOVEQ   #PEN_LAMP,D2
        BSR     cop_lamp_pens
        MOVEQ   #0,D1
.cb_swatch:
        BSR     cop_swatch
        BSR     cur_colour              ; D2.W = the entry the next send carries
        BSR     cop_strip
        ADDQ.W  #1,D1
        CMPI.W  #COLOUR_COUNT,D1
        BCS.S   .cb_pick

        BSR     cop_band_row            ; the row under the last of them
        BSR     cop_wait
        MOVEQ   #PEN_BG,D0
        MOVE.W  #PEN00_RGB,D1
        BSR     cop_move
.cb_close:
        BSR     cop_end
        BSR     lamps_write_all
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; cur_colour — D2.W = the colour list entry the selected LED's next command
; will carry.
; Clobbers: D2
; ---------------------------------------------------------------------------
cur_colour:
        MOVEM.L D0/A0,-(SP)
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        LEA     (LT_W_COL).W,A0
        MOVEQ   #0,D2
        MOVE.B  (A0,D0.W),D2
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; cop_swatch — D1.W = an entry in the colour list.  Its two pens.
;
; The swatch is the colour that goes on the wire rather than a name for it.
; Entry zero asks the device to choose and has no colour of its own, so it is
; drawn as an unlit lens.
; Clobbers (saved/restored): D0-D5/A0
; ---------------------------------------------------------------------------
cop_swatch:
        MOVEM.L D0-D5/A0,-(SP)
        MOVE.W  #LENS_CORE_RGB,D2
        MOVE.W  #LENS_EDGE_RGB,D3
        TST.W   D1
        BEQ.S   .csw_put
        MOVE.W  D1,D0
        MULU    #3,D0
        LEA     (colour_rgb).L,A0
        ADDA.W  D0,A0
        MOVEQ   #0,D1
        MOVE.B  (A0)+,D1
        MOVEQ   #0,D2
        MOVE.B  (A0)+,D2
        MOVEQ   #0,D3
        MOVE.B  (A0)+,D3
        MOVEQ   #0,D5
        MOVE.W  #255,D4
        BSR     shade_pack
        MOVE.W  D0,-(SP)
        MOVE.W  #115,D4
        BSR     shade_pack
        MOVE.W  D0,D3                   ; the darker edge
        MOVE.W  (SP)+,D2                ; and the swatch itself
.csw_put:
        MOVE.W  D2,D1
        MOVEQ   #PEN_SWATCH,D0
        BSR     cop_move
        MOVE.W  D3,D1
        MOVEQ   #PEN_SWATCH+1,D0
        BSR     cop_move
        MOVEM.L (SP)+,D0-D5/A0
        RTS

; ---------------------------------------------------------------------------
; lamps_write_all — every LED's lamp colour into the list just built.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
lamps_write_all:
        MOVEM.L D0,-(SP)
        CMPI.B  #LEDS_PRESENT,LT_STATE
        BNE.S   .lwa_out
        MOVEQ   #0,D0
.lwa_led:
        BSR     lamp_write
        ADDQ.W  #1,D0
        CMP.B   LT_COUNT,D0
        BCS.S   .lwa_led
.lwa_out:
        MOVEM.L (SP)+,D0
        RTS

; ===========================================================================
; Painting a lamp
;
; The lens is an ellipse and the shades inside it are smaller ellipses of the
; same shape, so a point belongs to whichever one it first falls inside.  The
; half-width comes from the Agnus fitted, so a round LED comes out round on
; either.
;
; A lamp is painted when a screen is built and not again.  What it is doing
; from one field to the next is carried by its pens.
; ===========================================================================

; ---------------------------------------------------------------------------
; lamp_axis — D0.W = the half-height.  D1.W = the half-width that draws a
; circle with the Agnus fitted.
; Clobbers: D1
; ---------------------------------------------------------------------------
lamp_axis:
        MOVEM.L D0/D2,-(SP)
        MOVE.W  D0,D2
        ANDI.L  #$FFFF,D2
        MOVE.L  D2,D0
        MULU    #12,D0                  ; six across to five down
        DIVU    #10,D0
        TST.B   VAR_IS_PAL
        BEQ.S   .lax_out
        MOVE.L  D2,D0
        MULU    #15,D0                  ; and fifteen to sixteen on a PAL one
        DIVU    #16,D0
.lax_out:
        MOVE.W  D0,D1
        ANDI.L  #$FFFF,D1
        MOVEM.L (SP)+,D0/D2
        RTS

; ---------------------------------------------------------------------------
; lamp_set — the lamp about to be painted.
; Input : D0.W = centre column, D1.W = centre pixel row, D2.W = half-height,
;         D3.W = the first of its four pens
; Clobbers (saved/restored): D0-D3
; ---------------------------------------------------------------------------
lamp_set:
        MOVEM.L D0-D3,-(SP)
        MOVE.W  D0,LT_LAMP_CX
        MOVE.W  D1,LT_LAMP_CY
        MOVE.W  D2,LT_LAMP_B
        MOVE.W  D2,D0
        BSR     lamp_axis
        MOVE.W  D1,LT_LAMP_A
        MOVE.B  D3,(LT_LAMP_PENS).W
        ADDQ.B  #1,D3
        MOVE.B  D3,(LT_LAMP_PENS+1).W
        ADDQ.B  #1,D3
        MOVE.B  D3,(LT_LAMP_PENS+2).W
        ADDQ.B  #1,D3
        MOVE.B  D3,(LT_LAMP_PENS+3).W
        MOVEM.L (SP)+,D0-D3
        RTS

; ---------------------------------------------------------------------------
; lamp_paint — the lamp LT_LAMP_CX, LT_LAMP_CY, LT_LAMP_B and LT_LAMP_PENS
; describe, into the bitmap.
;
; The whole footprint is painted, the background around the glow included, so
; nothing of what was there before is left showing.  A lamp is placed so that
; its footprint is on the screen — nothing here clips.
; Clobbers (saved/restored): D0-D7/A0-A3
; ---------------------------------------------------------------------------
lamp_paint:
        MOVEM.L D0-D7/A0-A3,-(SP)

        ; The half-axes squared, and the five ellipses scaled off them.
        MOVEQ   #0,D0
        MOVE.W  LT_LAMP_A,D0
        MOVE.W  D0,D1
        MULU    D1,D0
        MOVE.W  D0,LT_A2
        MOVEQ   #0,D2
        MOVE.W  LT_LAMP_B,D2
        MOVE.W  D2,D3
        MULU    D3,D2
        MOVE.W  D2,LT_B2
        MULU    D2,D0                   ; both together
        LEA     (shade_ratio).L,A0
        LEA     (LT_THRESH).W,A1
        MOVEQ   #5-1,D3
.lpa_thresh:
        MOVE.L  D0,D4
        MOVEQ   #0,D5
        MOVE.W  (A0)+,D5
        MULU    D5,D4
        LSR.L   #8,D4
        MOVE.L  D4,(A1)+
        DBF     D3,.lpa_thresh

        ; How far the glow reaches, and how far up and left the lit centre is.
        MOVEQ   #0,D0
        MOVE.W  LT_LAMP_A,D0
        MULU    #GLOW_NUM,D0
        DIVU    #GLOW_DEN,D0
        ANDI.L  #$FFFF,D0
        ADDQ.W  #1,D0
        MOVE.W  D0,LT_LAMP_XREACH
        MOVEQ   #0,D1
        MOVE.W  LT_LAMP_B,D1
        MULU    #GLOW_NUM,D1
        DIVU    #GLOW_DEN,D1
        ANDI.L  #$FFFF,D1
        ADDQ.W  #1,D1
        MOVE.W  D1,LT_LAMP_YREACH
        MOVE.W  LT_LAMP_B,D2
        LSR.W   #2,D2                   ; a quarter of the way up and left
        MOVE.W  D2,LT_LAMP_OFF

        MOVE.W  LT_LAMP_CX,D3
        SUB.W   D0,D3
        MOVE.W  D3,LT_LAMP_X0
        MOVE.W  LT_LAMP_CX,D3
        ADD.W   D0,D3
        MOVE.W  D3,LT_LAMP_X1

        ; One term of the ellipse per column, from the leftmost the glow
        ; reaches to the rightmost the lit centre asks about.
        MOVE.W  D0,D3
        ADD.W   D2,D3                   ; the last index wanted
        MOVE.W  D0,D4
        NEG.W   D4                      ; and the first
        LEA     (LT_DX_MID).W,A0
        MOVE.W  D4,D5
        ADD.W   D5,D5
        ADDA.W  D5,A0
.lpa_dx:
        MOVE.W  D4,D5
        MULS    D5,D5
        MULU    LT_B2,D5
        MOVE.W  D5,(A0)+
        ADDQ.W  #1,D4
        CMP.W   D3,D4
        BLE.S   .lpa_dx

        MOVE.W  LT_LAMP_YREACH,D7
        NEG.W   D7                      ; the first row, as a distance out
.lpa_row:
        ; This row's two terms: the lens's, and the lit centre's.
        MOVE.W  D7,D0
        MULS    D0,D0
        MULU    LT_A2,D0
        MOVE.W  D0,LT_LAMP_DYT
        MOVE.W  D7,D0
        ADD.W   LT_LAMP_OFF,D0
        MULS    D0,D0
        MULU    LT_A2,D0
        MOVE.W  D0,LT_LAMP_DYTC

        ; Where the row starts in the bitmap, and in the column terms.
        MOVEQ   #0,D0
        MOVE.W  LT_LAMP_CY,D0
        ADD.W   D7,D0
        MULU    #SCREEN_ROW_BYTES,D0
        MOVEA.L VAR_DRAW_BASE,A3
        ADDA.L  D0,A3
        MOVE.W  LT_LAMP_X0,D6
        MOVE.W  LT_LAMP_XREACH,D0
        NEG.W   D0
        ADD.W   D0,D0
        LEA     (LT_DX_MID).W,A0
        ADDA.W  D0,A0
        MOVEA.L A0,A1
        MOVE.W  LT_LAMP_OFF,D0
        ADD.W   D0,D0
        ADDA.W  D0,A1                   ; the lit centre's, offset by that much

.lpa_col:
        MOVEQ   #0,D0
        MOVE.W  (A0)+,D0
        MOVEQ   #0,D1
        MOVE.W  LT_LAMP_DYT,D1
        ADD.L   D1,D0                   ; how far out of the lens this point is
        MOVEQ   #0,D1
        MOVE.W  (A1)+,D1
        MOVEQ   #0,D2
        MOVE.W  LT_LAMP_DYTC,D2
        ADD.L   D2,D1                   ; and how far out of the lit centre

        LEA     (LT_THRESH).W,A2
        MOVEQ   #PEN_BG,D5
        CMP.L   16(A2),D0
        BHI.S   .lpa_put                ; past the glow, so the background
        MOVEQ   #0,D5
        MOVE.B  (LT_LAMP_PENS+3).W,D5
        CMP.L   12(A2),D0
        BHI.S   .lpa_put                ; the light thrown around the lamp
        MOVEQ   #PEN_LENS,D5
        CMP.L   8(A2),D0
        BHI.S   .lpa_put                ; the package the lens sits in
        MOVEQ   #0,D5
        MOVE.B  (LT_LAMP_PENS).W,D5
        CMP.L   (A2),D1
        BLS.S   .lpa_put                ; the lit centre
        MOVEQ   #0,D5
        MOVE.B  (LT_LAMP_PENS+1).W,D5
        CMP.L   4(A2),D0
        BLS.S   .lpa_put                ; the body of the lens
        MOVEQ   #0,D5
        MOVE.B  (LT_LAMP_PENS+2).W,D5   ; and its darker edge

.lpa_put:
        MOVE.W  D6,D3
        LSR.W   #3,D3
        MOVEA.L A3,A2
        ADDA.W  D3,A2
        MOVE.W  D6,D4
        NOT.W   D4
        ANDI.W  #7,D4                   ; the bit, counting from the left
        MOVEQ   #0,D2
.lpa_plane:
        BTST    D2,D5
        BEQ.S   .lpa_clear
        BSET    D4,(A2)
        BRA.S   .lpa_step
.lpa_clear:
        BCLR    D4,(A2)
.lpa_step:
        ADDA.W  #SCREEN_BPL_W,A2
        ADDQ.W  #1,D2
        CMPI.W  #SCREEN_PLANES,D2
        BCS.S   .lpa_plane

        ADDQ.W  #1,D6
        CMP.W   LT_LAMP_X1,D6
        BLE     .lpa_col

        ADDQ.W  #1,D7
        MOVE.W  LT_LAMP_YREACH,D0
        CMP.W   D0,D7
        BLE     .lpa_row

        MOVEM.L (SP)+,D0-D7/A0-A3
        RTS


; ===========================================================================
; The two bitmaps
;
; The CPU draws a character cell at a time, so a screen built where it can be
; seen is seen being built.  Every screen is built in the bitmap the copper is
; not showing, and the two are exchanged between fields: four pointers in the
; copper list, and the screen appears whole.
;
; After an exchange the bitmap now behind holds the screen from before the one
; just put up, and a redraw that touches only the rows the device changed would
; build on that.  So the blitter copies the shown bitmap over it, and the two
; hold the same picture again before anything is drawn.
; ===========================================================================

; ---------------------------------------------------------------------------
; screen_swap — the copper list the drawing asked for, then the bitmap it was
; drawn into, then the copy that brings the other bitmap up to it.
;
; The two go up together.  A copper list rewritten while the bitmap it belongs
; to is still behind puts one screen's bands of colour across the other
; screen's text.  That lasts as long as the drawing does.
;
; Called with the beam off the bottom of the display.  The copper reads the
; bitplane pointers at the top of its list, which is the top of the next field,
; so what is written here is what that field is drawn from.
;
; The copy is left running.  Everything that draws waits for the blitter first.
; Clobbers (saved/restored): D0-D4/A0-A1
; ---------------------------------------------------------------------------
screen_swap:
        MOVEM.L D0-D4/A0-A1,-(SP)
        TST.B   LT_COP_DUE
        BEQ.S   .ssw_bitmap
        CLR.B   LT_COP_DUE
        BSR     cop_build
.ssw_bitmap:
        TST.B   LT_DIRTY
        BEQ     .ssw_out
        CLR.B   LT_DIRTY

        ; Each plane starts at its own 40 bytes within the bitmap's first pixel
        ; row, as screen_init set them up.
        LEA     (COPPER_BASE+COP_OFF_BPL1PTH).L,A1
        MOVE.L  VAR_DRAW_BASE,D1
        MOVEQ   #SCREEN_PLANES-1,D0
.ssw_ptr:
        MOVE.L  D1,D2
        SWAP    D2
        MOVE.W  D2,(A1)                 ; BPLnPTH data word
        MOVE.W  D1,4(A1)                ; BPLnPTL data word
        ADDA.W  #8,A1
        ADD.L   #SCREEN_BPL_W,D1
        DBF     D0,.ssw_ptr

        MOVE.L  LT_FRONT,D0
        MOVE.L  VAR_DRAW_BASE,LT_FRONT
        MOVE.L  D0,VAR_DRAW_BASE

        MOVEA.L LT_FRONT,A0
        MOVEA.L VAR_DRAW_BASE,A1
        MOVE.W  #SWAP_WORDS,D0
        MOVE.W  #SWAP_ROWS,D1
        MOVEQ   #0,D2                   ; both are the whole bitmap, so neither
        MOVEQ   #0,D3                   ; steps over anything and neither shifts
        MOVEQ   #0,D4
        BSR     blit_copy
.ssw_out:
        MOVEM.L (SP)+,D0-D4/A0-A1
        RTS

; ---------------------------------------------------------------------------
; draw_clear — the bitmap being drawn to, back to the background.
;
; The blitter clears the whole 40960 bytes in under 6ms.  screen_clear's CPU
; loop takes about 43ms over the same bytes, which is more than two whole
; fields on either machine.
; Clobbers (saved/restored): D0-D2/A1
; ---------------------------------------------------------------------------
draw_clear:
        MOVEM.L D0-D2/A1,-(SP)
        MOVEA.L VAR_DRAW_BASE,A1
        MOVE.W  #SWAP_WORDS,D0
        MOVE.W  #SWAP_ROWS,D1
        MOVEQ   #0,D2
        BSR     blit_clear
        BSR     blit_wait
        MOVEM.L (SP)+,D0-D2/A1
        RTS

; ===========================================================================
; The screen
; ===========================================================================

; ---------------------------------------------------------------------------
; layout_entries — the pitch, the first row and the text offset this screen's
; entries take, and the colour page's caption row.
;
; How many LEDs there are is the device's to say, so an entry takes as many
; rows as the space will give it up to the most the screen can use, and what
; is left over is split above and below.  A screen of two LEDs puts them in
; the middle of the space with a lamp half as big again as a screen of six
; can give them.
;
; The text inside a band sits level with the lamp beside it rather than at the
; top of the band, which is what LT_TEXT_OFF carries.
; Clobbers (saved/restored): D0-D7/A0
; ---------------------------------------------------------------------------
layout_entries:
        MOVEM.L D0-D7/A0,-(SP)
        MOVEQ   #0,D0
        MOVE.B  LT_COUNT,D0
        MOVEQ   #TABLE_TOP,D1
        MOVEQ   #TABLE_ROWS,D2
        MOVEQ   #TABLE_PITCH_MIN,D3
        MOVEQ   #TABLE_PITCH_MAX,D4
        MOVEQ   #TABLE_TEXT_ROWS,D5
        MOVEQ   #TABLE_SPACE,D7
        CMPI.W  #SCR_TABLE,LT_SCREEN
        BEQ.S   .lay_pitch
        CMPI.W  #SCR_COLOURS,LT_SCREEN
        BEQ.S   .lay_colours
        MOVEQ   #LAMPS_TOP,D1
        MOVEQ   #LAMPS_ROWS,D2
        MOVEQ   #LAMPS_PITCH_MIN,D3
        MOVEQ   #LAMPS_PITCH_MAX,D4
        MOVEQ   #LAMPS_TEXT_ROWS,D5
        MOVEQ   #LAMPS_SPACE,D7
        BRA.S   .lay_pitch
.lay_colours:
        MOVEQ   #COLOUR_COUNT,D0
        MOVEQ   #PICK_TOP,D1
        MOVEQ   #PICK_ROWS,D2
        MOVEQ   #PICK_PITCH_MIN,D3
        MOVEQ   #PICK_PITCH_MAX,D4
        MOVEQ   #PICK_TEXT_ROWS,D5
        MOVEQ   #PICK_SPACE,D7

        ; The most rows an entry can have and still leave every entry on the
        ; screen.  A device with more LEDs than the space holds is not one of
        ; these — led_discover cut the count to what fits.
.lay_pitch:
        MOVE.W  D4,D6
.lay_try:
        CMP.W   D3,D6
        BLS.S   .lay_got
        MOVE.W  D0,D4
        MULU    D6,D4
        CMP.W   D2,D4
        BLS.S   .lay_got
        SUBQ.W  #1,D6
        BRA.S   .lay_try
.lay_got:
        MOVE.B  D6,LT_PITCH

        MOVE.W  D0,D4                   ; how deep the entries come to
        MULU    D6,D4
        MOVE.W  D7,D0
        SUB.W   D4,D0
        BCC.S   .lay_slack
        MOVEQ   #0,D0
.lay_slack:
        LSR.W   #1,D0                   ; the slack, split above and below
        ADD.W   D1,D0
        MOVE.B  D0,LT_FIRST

        ; The colour page's caption and the lamp under it are one block, and
        ; it is centred on the list beside it.
        CMPI.W  #SCR_COLOURS,LT_SCREEN
        BNE.S   .lay_text
        SUBI.W  #PICK_LED_ROWS,D4
        BCC.S   .lay_cap
        MOVEQ   #0,D4
.lay_cap:
        LSR.W   #1,D4
        ADD.W   D0,D4
        MOVE.B  D4,LT_PICK_CAP

.lay_text:
        MOVE.W  D6,D1                   ; the text, level with the lamp
        SUB.W   D5,D1
        BCC.S   .lay_half
        MOVEQ   #0,D1
.lay_half:
        LSR.W   #1,D1
        MOVE.B  D1,LT_TEXT_OFF

        MOVEQ   #0,D1                   ; the lamp the band has room for
        MOVE.W  D6,D1
        LEA     (lamp_half).L,A0
        MOVE.B  (A0,D1.W),LT_LAMP_HALF
        MOVEM.L (SP)+,D0-D7/A0
        RTS

; ---------------------------------------------------------------------------
; entry_row — D3.W = an entry.  D2.B = the row its text starts on.
; Clobbers: D2
; ---------------------------------------------------------------------------
entry_row:
        MOVEM.L D0,-(SP)
        MOVEQ   #0,D2
        MOVE.B  LT_PITCH,D2
        MULU    D3,D2
        MOVEQ   #0,D0
        MOVE.B  LT_FIRST,D0
        ADD.W   D0,D2
        MOVE.B  LT_TEXT_OFF,D0
        ADD.W   D0,D2
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; draw_screen — the screen LT_SCREEN names, from a blank bitmap.
;
; The lamps go down once here and are not painted again.  What they are doing
; from one field to the next is carried by their pens, and every row of text
; beside one is cleared a span at a time so that a redraw never crosses it.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_screen:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #1,LT_REDRAW            ; nothing on the bitmap survives this
        MOVE.B  #1,LT_DIRTY
        BSR     layout_entries          ; before anything asks where a row is
        BSR     draw_clear
        BSR     draw_title
        CMPI.W  #SCR_LAMPS,LT_SCREEN
        BEQ.S   .dsc_lamps
        CMPI.W  #SCR_COLOURS,LT_SCREEN
        BEQ.S   .dsc_colours
        BSR     frame_table
        BRA.S   .dsc_body
.dsc_lamps:
        BSR     frame_lamps
        BRA.S   .dsc_body
.dsc_colours:
        BSR     frame_colours
.dsc_body:
        BSR     paint_lamps
        BSR     draw_body
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_body — everything on this screen that changes, and the copper list the
; lamps take their colours from.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
draw_body:
        MOVEM.L D0,-(SP)
        MOVE.B  #1,LT_DIRTY
        MOVE.B  #1,LT_COP_DUE
        BSR     blit_wait               ; the bitmap behind is up to date now
        CMPI.W  #SCR_LAMPS,LT_SCREEN
        BEQ.S   .dbo_lamps
        CMPI.W  #SCR_COLOURS,LT_SCREEN
        BEQ.S   .dbo_colours
        BSR     draw_table
        CMPI.B  #LEDS_PRESENT,LT_STATE
        BNE.S   .dbo_out
        BSR     draw_modes
        BSR     draw_sends
        BSR     draw_mode_info
        BSR     draw_read
        BRA.S   .dbo_out
.dbo_lamps:
        BSR     draw_lamps
        BSR     draw_read
        BRA.S   .dbo_out
.dbo_colours:
        BSR     draw_picks
        BSR     draw_read
.dbo_out:
        CLR.B   LT_REDRAW
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; draw_scanned — the lamps and the rows a refresh scan can have changed, and
; nothing else.
;
; A scan reads every LED once a field.  The lamps follow it through their
; pens, the rows follow it where the device reports something new, and the
; rest of the screen only changes when a key is pressed.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
draw_scanned:
        MOVEM.L D0,-(SP)
        MOVE.B  #1,LT_COP_DUE           ; the lamps take their colours from it
        BSR     blit_wait               ; the bitmap behind is up to date now
        CMPI.W  #SCR_LAMPS,LT_SCREEN
        BEQ.S   .dsn_lamps
        CMPI.W  #SCR_COLOURS,LT_SCREEN
        BEQ.S   .dsn_out
        BSR     draw_table
        BSR     draw_modes
        BRA.S   .dsn_out
.dsn_lamps:
        BSR     draw_lamps
.dsn_out:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; row_changed — D3.W = LED.  Z clear where what the device now reports differs
; from what is drawn for it, and the note of what is drawn is brought up to
; date either way.
; Clobbers: nothing but the condition codes
; ---------------------------------------------------------------------------
row_changed:
        MOVEM.L D0-D2/A0-A2,-(SP)
        MOVE.W  D3,D0
        MULU    #ROW_SHOWN_SZ,D0
        LEA     (LT_SHOWN).W,A2
        ADDA.W  D0,A2
        LEA     (row_fields).L,A1
        MOVEQ   #0,D2                   ; anything that differs sets this
        MOVEQ   #ROW_FIELDS-1,D1
.rch_field:
        MOVEA.L (A1)+,A0
        MOVE.B  (A0,D3.W),D0
        CMP.B   (A2),D0
        BEQ.S   .rch_same
        MOVEQ   #1,D2
.rch_same:
        MOVE.B  D0,(A2)+
        DBF     D1,.rch_field

        MOVEQ   #0,D0                   ; and whether the keys land on it
        CMP.B   LT_CUR,D3
        BNE.S   .rch_mark
        MOVEQ   #1,D0
.rch_mark:
        CMP.B   (A2),D0
        BEQ.S   .rch_marked
        MOVEQ   #1,D2
.rch_marked:
        MOVE.B  D0,(A2)
        TST.B   LT_REDRAW
        BEQ.S   .rch_out
        MOVEQ   #1,D2
.rch_out:
        TST.B   D2
        MOVEM.L (SP)+,D0-D2/A0-A2
        RTS

; ---------------------------------------------------------------------------
; modes_changed — Z clear where the modes row is out of date, and the note of
; what is drawn is brought up to date either way.
; Clobbers: nothing but the condition codes
; ---------------------------------------------------------------------------
modes_changed:
        MOVEM.L D0-D2/A0-A1,-(SP)
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        LEA     (LT_SHOWN_MODES).W,A1
        MOVEQ   #0,D2
        MOVE.B  D0,D1
        CMP.B   (A1),D1
        BEQ.S   .mch_led
        MOVEQ   #1,D2
.mch_led:
        MOVE.B  D1,(A1)+
        LEA     (LT_MODE).W,A0
        MOVE.B  (A0,D0.W),D1
        CMP.B   (A1),D1
        BEQ.S   .mch_mode
        MOVEQ   #1,D2
.mch_mode:
        MOVE.B  D1,(A1)+
        LEA     (LT_MODES).W,A0
        MOVE.B  (A0,D0.W),D1
        CMP.B   (A1),D1
        BEQ.S   .mch_bits
        MOVEQ   #1,D2
.mch_bits:
        MOVE.B  D1,(A1)
        TST.B   LT_REDRAW
        BEQ.S   .mch_out
        MOVEQ   #1,D2
.mch_out:
        TST.B   D2
        MOVEM.L (SP)+,D0-D2/A0-A1
        RTS

; ---------------------------------------------------------------------------
; show_screen — D0.W = the screen to move to.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
show_screen:
        MOVEM.L D0,-(SP)
        CMP.W   LT_SCREEN,D0
        BEQ.S   .ssc_out
        MOVE.W  D0,LT_SCREEN
        BSR     draw_screen
.ssc_out:
        MOVEM.L (SP)+,D0
        RTS

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
; frame_table — the table screen's fixed text.
;
; A device with no LEDs to drive gets the identity and nothing else, because
; none of the keys would do anything.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
frame_table:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #PEN_TEXT,VAR_PEN

        BSR     draw_device_row

        MOVE.B  #ROW_PIPE,D2
        BSR     put_pipe

        CMPI.B  #LEDS_PRESENT,LT_STATE
        BNE     .ft_out

        MOVE.B  #ROW_COUNTS,D2
        BSR     put_counts

        ; The two limits every LED on the device shares, filling the right of
        ; the two rows above the table.
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #ROW_COUNTS,D2
        MOVE.B  #COL_MAX_HOLD,D1
        LEA     (str_max_hold).L,A0
        BSR     screen_print
        ADDI.B  #str_max_hold_len,D1
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  LT_MAX_HOLD,D0
        BSR     put_secs

        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #ROW_PIPE,D2
        MOVE.B  #COL_MAX_PERIOD,D1
        LEA     (str_max_period).L,A0
        BSR     screen_print
        ADDI.B  #str_max_period_len,D1
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  LT_MAX_PERIOD,D0
        BSR     put_secs

        ; The heading over the table, in the columns the rows use.
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #ROW_HEAD,D2
        LEA     (str_h_num).L,A0
        MOVE.B  #COL_NUM,D1
        BSR     screen_print
        LEA     (str_h_type).L,A0
        MOVE.B  #COL_TYPE,D1
        BSR     screen_print
        LEA     (str_h_mode).L,A0
        MOVE.B  #COL_MODE,D1
        BSR     screen_print
        LEA     (str_h_colour).L,A0
        MOVE.B  #COL_RGB,D1
        BSR     screen_print
        LEA     (str_h_bri).L,A0
        MOVE.B  #COL_BRI,D1
        BSR     screen_print
        LEA     (str_h_per).L,A0
        MOVE.B  #COL_PER,D1
        BSR     screen_print

        ; And the heading over what the next command will carry.
        MOVE.B  #ROW_SEND_HEAD,D2
        LEA     (str_sends).L,A0
        MOVEQ   #0,D1
        BSR     screen_print
        LEA     (str_h_colour).L,A0
        MOVE.B  #COL_SEND_COL,D1
        BSR     screen_print
        LEA     (str_h_bright).L,A0
        MOVE.B  #COL_SEND_BRI,D1
        BSR     screen_print
        LEA     (str_h_per).L,A0
        MOVE.B  #COL_SEND_PER,D1
        BSR     screen_print
        LEA     (str_h_hold).L,A0
        MOVE.B  #COL_SEND_HOLD,D1
        BSR     screen_print

        BSR     draw_keys
.ft_out:
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; frame_lamps — the lamps screen's fixed text.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
frame_lamps:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #PEN_TEXT,VAR_PEN
        BSR     draw_device_row
        MOVE.B  #ROW_COUNTS,D2
        BSR     put_counts
        BSR     draw_keys
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; frame_colours — the colour page's fixed text.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
frame_colours:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #PEN_TEXT,VAR_PEN
        BSR     draw_device_row
        BSR     draw_keys
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_device_row — the device's name, its own version and the protocol
; version, on ROW_DEV.  Every screen draws this and nothing else on that row,
; so changing screen does not move it or re-wrap it.
;
; The version follows the name with a space between, and both stop where the
; protocol version begins.  Drawn from the buffers read while the session was
; opening, so a device that has since stopped answering still has a name here.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_device_row:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #COL_PROTO-1,VAR_COL_MAX
        LEA     (LT_DEV_TYPE).W,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_DEV,D2
        BSR     screen_print
        MOVEQ   #COL_TEXT+1,D0          ; the column after the name, and a space
.ddr_len:
        TST.B   (A0)+
        BEQ.S   .ddr_ver
        ADDQ.B  #1,D0
        BRA.S   .ddr_len
.ddr_ver:
        MOVE.B  D0,D1
        LEA     (LT_DEV_VER).W,A0
        BSR     screen_print
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        LEA     (LT_PROTO).W,A0
        MOVE.B  #COL_PROTO,D1
        BSR     screen_print
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; put_pipe — D2.B = row.  Which pipe the report goes down, or that there is
; none and the only record of this run is the screen.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
put_pipe:
        MOVEM.L D0-D1/A0,-(SP)
        MOVE.B  #COL_TEXT,D1
        TST.B   VAR_PIPE_PRESENT
        BEQ.S   .pp_none
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_pipe).L,A0
        BSR     screen_print
        ADDI.B  #str_pipe_len,D1
        MOVE.B  VAR_LOG_PIPE,D0
        BSR     print_hex_byte
        BRA.S   .pp_out
.pp_none:
        MOVE.B  #PEN_WARN,VAR_PEN
        LEA     (str_no_pipe).L,A0
        BSR     screen_print
.pp_out:
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; put_counts — D2.B = row.  How many LEDs the device has and how many of them
; the screen holds.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
put_counts:
        MOVEM.L D0-D1/A0,-(SP)
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #COL_TEXT,D1
        MOVE.B  LT_TOTAL,D0
        BSR     put_dec
        LEA     (str_leds).L,A0
        BSR     screen_print
        ADDI.B  #str_leds_len,D1
        MOVE.B  LT_COUNT,D0
        CMP.B   LT_TOTAL,D0
        BEQ.S   .pc_out
        BSR     put_dec
        LEA     (str_shown).L,A0
        BSR     screen_print
.pc_out:
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; draw_keys — the legend.
;
; The first two rows are every key that sends a command and the third is the
; ones that do not.  The screen key names the screens this is not, because a
; user standing on the lamps screen does not need telling how to reach it.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_keys:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #KEYS_COL1,D1
        LEA     (str_keys1).L,A0
        MOVE.B  #ROW_KEYS1,D2
        BSR     screen_print
        LEA     (str_keys2).L,A0
        MOVE.B  #ROW_KEYS2,D2
        BSR     screen_print
        LEA     (str_keys3).L,A0
        MOVE.B  #ROW_KEYS3,D2
        BSR     screen_print

        MOVE.B  #KEYS_COL2,D1
        CMPI.W  #SCR_TABLE,LT_SCREEN
        BEQ.S   .dk_lamps
        LEA     (str_k_table).L,A0
        BSR     screen_print
        CMPI.W  #SCR_LAMPS,LT_SCREEN
        BEQ.S   .dk_out
        MOVE.B  #KEYS_COL3,D1           ; the colour page is neither of them
.dk_lamps:
        LEA     (str_k_lamps).L,A0
        BSR     screen_print
.dk_out:
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; paint_lamps — every lamp this screen shows, once.
; Clobbers (saved/restored): D0-D4
; ---------------------------------------------------------------------------
paint_lamps:
        MOVEM.L D0-D4,-(SP)
        CMPI.B  #LEDS_PRESENT,LT_STATE
        BNE     .pl_out
        CMPI.W  #SCR_COLOURS,LT_SCREEN
        BEQ.S   .pl_picks

        MOVEQ   #0,D4
.pl_led:
        MOVE.W  D4,D1
        BSR     band_middle             ; D0.W = the band's middle pixel row
        MOVE.W  D0,D1
        MOVE.W  #LAMP_CX,D0
        MOVEQ   #0,D2
        MOVE.B  LT_LAMP_HALF,D2
        MOVEQ   #PEN_LAMP,D3
        BSR     lamp_set
        BSR     lamp_paint
        ADDQ.W  #1,D4
        CMP.B   LT_COUNT,D4
        BCS.S   .pl_led
        BRA.S   .pl_out

.pl_picks:
        ; A swatch beside every colour, in the colour itself, and the LED the
        ; page is picking for as a lamp of its own.
        MOVEQ   #0,D4
.pl_pick:
        MOVE.W  D4,D1
        BSR     band_middle
        MOVE.W  D0,D1
        MOVE.W  #PICK_CX,D0
        MOVEQ   #PICK_B,D2
        MOVEQ   #PEN_SWATCH,D3
        BSR     lamp_set
        MOVE.B  #PEN_SWATCH+1,(LT_LAMP_PENS+2).W    ; two shades and no glow
        MOVE.B  #PEN_BG,(LT_LAMP_PENS+3).W
        BSR     lamp_paint
        ADDQ.W  #1,D4
        CMPI.W  #COLOUR_COUNT,D4
        BCS.S   .pl_pick

        MOVEQ   #0,D1
        MOVE.B  LT_PICK_CAP,D1
        LSL.W   #3,D1
        ADDI.W  #PICK_LED_GAP+PICK_LED_REACH,D1
        MOVE.W  #PICK_LED_CX,D0
        MOVEQ   #PICK_LED_B,D2
        MOVEQ   #PEN_LAMP,D3
        BSR     lamp_set
        BSR     lamp_paint
.pl_out:
        MOVEM.L (SP)+,D0-D4
        RTS

; ---------------------------------------------------------------------------
; draw_table — a row for every LED, or the reason there are none.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
draw_table:
        MOVEM.L D0-D3/A0,-(SP)
        CMPI.B  #LEDS_PRESENT,LT_STATE
        BEQ.S   .dt_rows
        MOVEQ   #0,D0
        MOVE.B  LT_FIRST,D0
        BSR     clear_row
        MOVE.B  #PEN_TEXT,VAR_PEN
        LEA     (str_no_leds).L,A0
        CMPI.B  #LEDS_NONE,LT_STATE
        BEQ.S   .dt_say
        LEA     (str_no_led_group).L,A0
.dt_say:
        MOVE.B  #COL_TEXT,D1
        MOVE.B  LT_FIRST,D2
        BSR     screen_print
        BRA.S   .dt_out
.dt_rows:
        MOVEQ   #0,D3
.dt_row:
        BSR     draw_row
        ADDQ.W  #1,D3
        CMP.B   LT_COUNT,D3
        BCS.S   .dt_row
.dt_out:
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; draw_row — D3.W = LED.  Everything GET_LED_INFO reported about it, beside
; the lamp the copper is driving.
;
; A brightness of zero and a period of zero are left blank.  Zero is not a
; brightness and not a period, and printing one would say it was.
; Clobbers (saved/restored): D0-D2/D6/A0
; ---------------------------------------------------------------------------
draw_row:
        MOVEM.L D0-D2/D6/A0,-(SP)
        MOVE.W  D3,D0
        BSR     anim_check
        BSR     row_changed
        BEQ     .dr_out
        MOVE.B  #1,LT_DIRTY

        BSR     entry_row
        MOVE.B  D2,D0
        MOVE.B  #COL_MARK,D1
        MOVE.B  #SCREEN_COLS-COL_MARK,D6
        BSR     clear_span
        ADDQ.B  #1,D0
        MOVE.B  #COL_MARK,D1
        BSR     clear_span

        MOVE.B  #PEN_LABEL,D6           ; the pen this row's text takes
        CMP.B   LT_CUR,D3
        BNE.S   .dr_plain
        MOVE.B  #PEN_TEXT,D6
        MOVE.B  #PEN_GOLD,VAR_PEN
        MOVEQ   #'>',D0
        MOVE.B  #COL_MARK,D1
        BSR     screen_putchar
.dr_plain:
        MOVE.B  D6,VAR_PEN
        MOVE.B  #COL_NUM,D1
        MOVE.W  D3,D0
        BSR     put_dec

        MOVE.B  #COL_TYPE,D1
        LEA     (LT_TYPE).W,A0
        MOVE.B  (A0,D3.W),D0
        BSR     put_type

        MOVE.B  #COL_MODE,D1
        LEA     (LT_MODE).W,A0
        MOVE.B  (A0,D3.W),D0
        BSR     put_mode

        MOVE.B  #COL_RGB,D1
        BSR     put_rgb

        MOVE.B  #COL_BRI,D1
        BSR     put_report_bright
        MOVE.B  #COL_PER,D1
        BSR     put_report_period
.dr_out:
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D2/D6/A0
        RTS

; ---------------------------------------------------------------------------
; put_rgb — D3.W = LED, D1.B = column, D2.B = row.  The three colour bytes the
; device reports, as they came.
; Clobbers: D1
; ---------------------------------------------------------------------------
put_rgb:
        MOVEM.L D0/A0,-(SP)
        LEA     (LT_RED).W,A0
        MOVE.B  (A0,D3.W),D0
        BSR     print_hex_byte
        LEA     (LT_GREEN).W,A0
        MOVE.B  (A0,D3.W),D0
        BSR     print_hex_byte
        LEA     (LT_BLUE).W,A0
        MOVE.B  (A0,D3.W),D0
        BSR     print_hex_byte
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; put_report_bright — D3.W = LED, D1.B = column, D2.B = row.  The brightness
; the device reports, where it reports one and the LED is lit at all.
; Clobbers: D1
; ---------------------------------------------------------------------------
put_report_bright:
        MOVEM.L D0/A0,-(SP)
        LEA     (LT_MODE).W,A0
        TST.B   (A0,D3.W)
        BEQ.S   .prb_out                ; an unlit LED is not lit at a
        LEA     (LT_BRIGHT).W,A0        ; brightness
        MOVE.B  (A0,D3.W),D0
        BEQ.S   .prb_out
        BSR     put_dec
        MOVEQ   #'%',D0
        BSR     screen_putchar
.prb_out:
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; put_report_period — D3.W = LED, D1.B = column, D2.B = row.
; Clobbers: D1
; ---------------------------------------------------------------------------
put_report_period:
        MOVEM.L D0/A0,-(SP)
        LEA     (LT_PERIOD).W,A0
        MOVE.B  (A0,D3.W),D0
        BEQ.S   .prp_out
        BSR     put_secs
.prp_out:
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; draw_lamps — every LED on the lamps screen, three rows each.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
draw_lamps:
        MOVEM.L D0-D3/A0,-(SP)
        MOVEQ   #0,D3
.dl_led:
        BSR     draw_lamp_entry
        ADDQ.W  #1,D3
        CMP.B   LT_COUNT,D3
        BCS.S   .dl_led
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; draw_lamp_entry — D3.W = LED.  What the device says about it, beside a lamp
; big enough to read from where the board is.
; Clobbers (saved/restored): D0-D2/D6/A0
; ---------------------------------------------------------------------------
draw_lamp_entry:
        MOVEM.L D0-D2/D6/A0,-(SP)
        MOVE.W  D3,D0
        BSR     anim_check
        BSR     row_changed
        BEQ     .dle_out
        MOVE.B  #1,LT_DIRTY

        BSR     entry_row
        MOVE.B  #SCREEN_COLS-LAMPS_COL+1,D6
        MOVE.B  D2,D0
        MOVE.B  #LAMPS_COL-1,D1
        BSR     clear_span
        ADDQ.B  #1,D0
        MOVE.B  #LAMPS_COL-1,D1
        BSR     clear_span
        ADDQ.B  #1,D0
        MOVE.B  #LAMPS_COL-1,D1
        BSR     clear_span

        MOVE.B  #PEN_LABEL,D6
        CMP.B   LT_CUR,D3
        BNE.S   .dle_plain
        MOVE.B  #PEN_TEXT,D6
.dle_plain:
        MOVE.B  D6,VAR_PEN

        ; Which LED, what it is and what it is doing.
        LEA     (str_led).L,A0
        MOVE.B  #LAMPS_COL,D1
        BSR     screen_print
        ADDI.B  #str_led_len,D1
        MOVE.W  D3,D0
        BSR     put_dec
        MOVE.B  #LAMPS_COL_TYPE,D1
        LEA     (LT_TYPE).W,A0
        MOVE.B  (A0,D3.W),D0
        BSR     put_type
        MOVE.B  #LAMPS_COL_MODE,D1
        LEA     (LT_MODE).W,A0
        MOVE.B  (A0,D3.W),D0
        BSR     put_mode

        ; The colour it reports, the brightness and the period.
        ADDQ.B  #1,D2
        MOVE.B  #LAMPS_COL,D1
        BSR     put_rgb
        MOVE.B  #LAMPS_COL_BRI,D1
        BSR     put_report_bright
        MOVE.B  #LAMPS_COL_PER,D1
        BSR     put_report_period

        ; And the modes it has, which is the whole of what it can be asked to
        ; do.
        ADDQ.B  #1,D2
        MOVE.W  D3,D0
        BSR     put_modes
.dle_out:
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D2/D6/A0
        RTS

; ---------------------------------------------------------------------------
; draw_picks — the colour list, the LED it is picking for and the colour the
; next command will carry.
; Clobbers (saved/restored): D0-D3/D6-D7/A0
; ---------------------------------------------------------------------------
draw_picks:
        MOVEM.L D0-D3/D6-D7/A0,-(SP)

        MOVEQ   #PICK_ROW_HEAD,D0
        BSR     clear_row
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_colour_for).L,A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #PICK_ROW_HEAD,D2
        BSR     screen_print
        ADDI.B  #str_colour_for_len,D1
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        BSR     put_dec

        ; The caption over the LED's own lamp, which stands beside the list.
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #PICK_COL_LED,D1
        MOVE.B  LT_PICK_CAP,D2
        LEA     (str_led).L,A0
        BSR     screen_print
        ADDI.B  #str_led_len,D1
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        BSR     put_dec

        MOVEQ   #0,D3                   ; the entry being listed
.dp_entry:
        BSR     entry_row
        MOVE.W  D2,D7                   ; the row this entry's name goes on
        MOVE.B  #PICK_COL_RGB-PICK_COL_NAME+8,D6
        MOVE.B  D7,D0
        MOVE.B  #PICK_COL_NAME-1,D1
        BSR     clear_span
        MOVE.B  D7,D0
        ADDQ.B  #1,D0
        MOVE.B  #PICK_COL_NAME-1,D1
        BSR     clear_span

        BSR     cur_colour              ; D2.W = the entry the next send carries
        MOVE.B  #PEN_LABEL,VAR_PEN
        CMP.W   D3,D2
        BNE.S   .dp_plain
        MOVE.B  #PEN_GOLD,VAR_PEN
.dp_plain:
        MOVE.W  D3,D1
        LSL.W   #2,D1                   ; a long per name
        LEA     (colour_names).L,A0
        MOVEA.L (A0,D1.W),A0
        MOVE.B  D7,D2
        MOVE.B  #PICK_COL_NAME,D1
        BSR     screen_print

        ; The three bytes picking it puts on the wire, which is the whole of
        ; what picking it does.
        MOVE.B  #PICK_COL_RGB,D1
        MOVE.W  D3,D0
        MULU    #3,D0
        LEA     (colour_rgb).L,A0
        ADDA.W  D0,A0
        MOVE.B  (A0)+,D0
        BSR     print_hex_byte
        MOVE.B  (A0)+,D0
        BSR     print_hex_byte
        MOVE.B  (A0)+,D0
        BSR     print_hex_byte

        ADDQ.W  #1,D3
        CMPI.W  #COLOUR_COUNT,D3
        BCS     .dp_entry

        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D3/D6-D7/A0
        RTS

; ---------------------------------------------------------------------------
; draw_modes — which modes the selected LED has, on the table screen.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_modes:
        MOVEM.L D0-D2/A0,-(SP)
        BSR     modes_changed
        BEQ.S   .dmo_out
        MOVE.B  #1,LT_DIRTY
        MOVEQ   #ROW_MODES,D0
        BSR     clear_row
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_modes).L,A0
        MOVEQ   #0,D1
        MOVE.B  #ROW_MODES,D2
        BSR     screen_print
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0
        MOVE.B  #ROW_MODES,D2
        BSR     put_modes
        MOVE.B  #PEN_TEXT,VAR_PEN
.dmo_out:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; put_modes — D0.W = LED, D2.B = row.  Each mode the protocol names, where it
; sits on the row.
;
; A mode the LED does not have is grey, and the one in force is gold.  The
; order is the protocol's order.
; Clobbers (saved/restored): D0-D3/A0-A1
; ---------------------------------------------------------------------------
put_modes:
        MOVEM.L D0-D3/A0-A1,-(SP)
        MOVEQ   #0,D3                   ; the mode being listed
.pmd_mode:
        MOVE.W  D3,D1
        BSR     led_supports
        BNE.S   .pmd_has
        MOVE.B  #PEN_LABEL,VAR_PEN
        BRA.S   .pmd_pen
.pmd_has:
        MOVE.B  #PEN_TEXT,VAR_PEN
        LEA     (LT_MODE).W,A0
        MOVE.B  (A0,D0.W),D1
        CMP.B   D3,D1
        BNE.S   .pmd_pen
        MOVE.B  #PEN_GOLD,VAR_PEN       ; the one in force
.pmd_pen:
        MOVE.W  D3,D1
        LSL.W   #2,D1                   ; a long per name
        LEA     (mode_names).L,A0
        MOVEA.L (A0,D1.W),A0
        LEA     (mode_cols).L,A1
        MOVE.B  (A1,D3.W),D1
        BSR     screen_print
        ADDQ.W  #1,D3
        CMPI.W  #LED_MODE_COUNT,D3
        BCS.S   .pmd_mode
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D3/A0-A1
        RTS

; ---------------------------------------------------------------------------
; draw_sends — what the next command will carry for the selected LED.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_sends:
        MOVEM.L D0-D2/A0,-(SP)
        MOVEQ   #ROW_SENDS,D0
        BSR     clear_row
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #ROW_SENDS,D2
        MOVEQ   #0,D0
        MOVE.B  LT_CUR,D0

        LEA     (LT_W_COL).W,A0
        MOVEQ   #0,D1
        MOVE.B  (A0,D0.W),D1
        LSL.W   #2,D1                   ; a long per name
        LEA     (colour_names).L,A0
        MOVEA.L (A0,D1.W),A0
        MOVE.B  #COL_SEND_COL,D1
        BSR     screen_print

        MOVE.B  #COL_SEND_BRI,D1
        BSR     put_bright
        MOVE.B  #COL_SEND_PER,D1
        BSR     put_send_period
        MOVE.B  #COL_SEND_HOLD,D1
        BSR     put_send_hold
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; put_bright — D0.W = LED, D1.B = column, D2.B = row.  The brightness the next
; command will carry, or that the device is to choose one.
put_bright:
        MOVEM.L D0/D3/A0,-(SP)
        LEA     (LT_W_BRIGHT).W,A0
        MOVEQ   #0,D3
        MOVE.B  (A0,D0.W),D3
        LEA     (bright_steps).L,A0
        MOVE.B  (A0,D3.W),D3
        BNE.S   .pb_value
        LEA     (str_device).L,A0
        BSR     screen_print
        BRA.S   .pb_out
.pb_value:
        MOVE.B  D3,D0
        BSR     put_dec
        MOVEQ   #'%',D0
        BSR     screen_putchar
.pb_out:
        MOVEM.L (SP)+,D0/D3/A0
        RTS

; put_send_period — D0.W = LED, D1.B = column, D2.B = row.
put_send_period:
        MOVEM.L D0/D3/A0,-(SP)
        LEA     (LT_W_PERIOD).W,A0
        MOVEQ   #0,D3
        MOVE.B  (A0,D0.W),D3
        LEA     (period_steps).L,A0
        MOVE.B  (A0,D3.W),D3
        BNE.S   .psp_value
        LEA     (str_default).L,A0
        BSR     screen_print
        BRA.S   .psp_out
.psp_value:
        MOVE.B  D3,D0
        BSR     put_secs
.psp_out:
        MOVEM.L (SP)+,D0/D3/A0
        RTS

; put_send_hold — D0.W = LED, D1.B = column, D2.B = row.
put_send_hold:
        MOVEM.L D0/D3/A0,-(SP)
        LEA     (LT_W_HOLD).W,A0
        MOVEQ   #0,D3
        MOVE.B  (A0,D0.W),D3
        LEA     (hold_steps).L,A0
        MOVE.B  (A0,D3.W),D3
        BNE.S   .psh_value
        LEA     (str_none).L,A0
        BSR     screen_print
        BRA.S   .psh_out
.psh_value:
        MOVE.B  D3,D0
        BSR     put_secs
.psh_out:
        MOVEM.L (SP)+,D0/D3/A0
        RTS

; ---------------------------------------------------------------------------
; draw_mode_info — the period GET_LED_MODE_INFO says the next command's mode
; needs from the host.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_mode_info:
        MOVEM.L D0-D2/A0,-(SP)
        MOVEQ   #ROW_MODE_INFO,D0
        BSR     clear_row
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #ROW_MODE_INFO,D2
        MOVE.B  #COL_TEXT,D1

        MOVE.B  LT_MODE_FLAGS,D0
        ANDI.B  #RBCP_LED_MODE_TAKES_PERIOD,D0
        BNE.S   .dmi_takes
        LEA     (str_no_period).L,A0
        BSR     screen_print
        BRA.S   .dmi_out
.dmi_takes:
        TST.B   LT_MODE_MIN
        BNE.S   .dmi_range
        LEA     (str_period_upto).L,A0
        BSR     screen_print
        ADDI.B  #str_period_upto_len,D1
        BRA.S   .dmi_max
.dmi_range:
        LEA     (str_period_from).L,A0
        BSR     screen_print
        ADDI.B  #str_period_from_len,D1
        MOVE.B  LT_MODE_MIN,D0
        BSR     put_secs
        LEA     (str_period_to).L,A0
        BSR     screen_print
        ADDI.B  #str_period_to_len,D1
.dmi_max:
        MOVE.B  LT_MAX_PERIOD,D0
        BSR     put_secs
        LEA     (str_period_tail).L,A0
        BSR     screen_print
.dmi_out:
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_note — D0.B = a NOTE_ code, on the status row.
;
; The note and the read back share the row.  A key that could not send draws
; its note after everything else and a key that sent draws the read back last,
; so whichever of the two has something to say is the one left standing.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_note:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #1,LT_DIRTY
        BSR     blit_wait               ; the bitmap behind is up to date now
        MOVE.B  D0,D2
        MOVEQ   #ROW_STATUS,D0
        BSR     clear_row
        MOVEQ   #0,D1
        MOVE.B  D2,D1
        LEA     (note_pens).L,A0
        MOVE.B  (A0,D1.W),VAR_PEN
        LSL.W   #2,D1                   ; a long per message
        LEA     (note_msgs).L,A0
        MOVEA.L (A0,D1.W),A0
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_STATUS,D2
        BSR     screen_print
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_read — the field the last SET_LED read back differently on, and nothing
; where every field agreed.
;
; This is the only check the program can make on its own.  The field the
; device disagreed on is what says so.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
draw_read:
        MOVEM.L D0-D3/A0,-(SP)
        MOVEQ   #ROW_STATUS,D0
        BSR     clear_row
        MOVE.B  #PEN_BAD,VAR_PEN
        MOVE.B  #COL_TEXT,D1
        MOVE.B  #ROW_STATUS,D2
        CMPI.B  #READ_REFUSED,LT_READ
        BNE.S   .drd_differs
        LEA     (str_r_refused).L,A0
        BSR     screen_print
        BRA.S   .drd_out
.drd_differs:
        CMPI.B  #READ_DIFFERS,LT_READ
        BNE.S   .drd_out
        MOVEQ   #0,D3
        MOVE.B  LT_READ_FIELD,D3
        MOVE.W  D3,D0
        LSL.W   #2,D0                   ; a long per name
        LEA     (read_fields).L,A0
        MOVEA.L (A0,D0.W),A0
        BSR     screen_print
        LEA     (read_field_len).L,A0
        ADD.B   (A0,D3.W),D1
        LEA     (str_r_back).L,A0
        BSR     screen_print
        ADDI.B  #str_r_back_len,D1
        MOVE.B  LT_READ_GOT,D0
        BSR     put_read_got
.drd_out:
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; put_read_got — D3.B = the field, D0.B = what the device gave for it, at
; D1.B = column, D2.B = row.  A mode is a name, a brightness a percentage, a
; period seconds and a colour byte the two hex digits that came off the wire.
; Clobbers: D0-D1
; ---------------------------------------------------------------------------
put_read_got:
        CMPI.B  #RDF_MODE,D3
        BEQ     put_mode
        CMPI.B  #RDF_PERIOD,D3
        BEQ     put_secs
        CMPI.B  #RDF_BRIGHT,D3
        BEQ.S   .prg_bright
        BRA     print_hex_byte
.prg_bright:
        BSR     put_dec
        MOVEQ   #'%',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
        RTS

; ---------------------------------------------------------------------------
; clear_span — D0.B = row, D1.B = first column, D6.B = how many cells, back to
; background.
;
; A whole row cannot be cleared where a lamp is standing in it, so the text
; beside a lamp is cleared by the span it occupies.
; Clobbers (saved/restored): D0-D3
; ---------------------------------------------------------------------------
clear_span:
        MOVEM.L D0-D3,-(SP)
        MOVEQ   #0,D3
        MOVE.B  D6,D3
        SUBQ.W  #1,D3
        BMI.S   .csp_out
        MOVE.B  D0,D2                   ; the row, where screen_putchar wants it
        MOVE.B  #PEN_BG,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVEQ   #' ',D0
.csp_cell:
        BSR     screen_putchar
        ADDQ.B  #1,D1
        DBF     D3,.csp_cell
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
.csp_out:
        MOVEM.L (SP)+,D0-D3
        RTS

; ---------------------------------------------------------------------------
; clear_row — D0.B = row, back to background.  For a row no lamp reaches.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
clear_row:
        MOVEM.L D0,-(SP)
        MOVE.B  #PEN_BG,VAR_PEN
        BSR     screen_fill_row
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; put_type — D0.B = an LED type, at D1.B = column, D2.B = row.  A type the
; protocol does not name is shown as its number, because a device is allowed
; one.
; Clobbers: D1
; ---------------------------------------------------------------------------
put_type:
        MOVEM.L D0/A0,-(SP)
        CMPI.B  #RBCP_LED_TYPE_MONO,D0
        BNE.S   .pty_rgb
        LEA     (str_mono).L,A0
        BRA.S   .pty_str
.pty_rgb:
        CMPI.B  #RBCP_LED_TYPE_RGB,D0
        BNE.S   .pty_num
        LEA     (str_rgb).L,A0
.pty_str:
        BSR     screen_print
        BRA.S   .pty_out
.pty_num:
        MOVEM.L D0,-(SP)
        MOVEQ   #'T',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
        MOVEM.L (SP)+,D0
        BSR     put_dec
.pty_out:
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; put_mode — D0.B = a mode, at D1.B = column, D2.B = row.  A mode the protocol
; does not name is shown as its number, for the reason put_type gives.
; Clobbers: D1
; ---------------------------------------------------------------------------
put_mode:
        MOVEM.L D0/D3/A0,-(SP)
        CMPI.B  #LED_MODE_FLAME,D0
        BNE.S   .pmo_named
        LEA     (str_flame).L,A0
        BRA.S   .pmo_str
.pmo_named:
        CMPI.B  #LED_MODE_COUNT,D0
        BCC.S   .pmo_num
        MOVEQ   #0,D3
        MOVE.B  D0,D3
        LSL.W   #2,D3
        LEA     (mode_names).L,A0
        MOVEA.L (A0,D3.W),A0
.pmo_str:
        BSR     screen_print
        BRA.S   .pmo_out
.pmo_num:
        MOVE.B  D0,D3
        LEA     (str_mode).L,A0
        BSR     screen_print
        ADDI.B  #str_mode_len,D1
        MOVE.B  D3,D0
        BSR     put_dec
.pmo_out:
        MOVEM.L (SP)+,D0/D3/A0
        RTS

; ---------------------------------------------------------------------------
; put_dec — D0.B = 0 to 255 in decimal at D1.B = column, D2.B = row, with no
; leading zero.  D1 ends past the last digit, so the next field chains on.
; Clobbers: D1
; ---------------------------------------------------------------------------
put_dec:
        MOVEM.L D0/D3-D6,-(SP)
        MOVEQ   #0,D3
        MOVE.B  D0,D3                   ; what is left to print
        MOVEQ   #0,D4                   ; a digit has gone out
        MOVE.W  #100,D5
.pd_round:
        MOVE.L  D3,D6
        DIVU    D5,D6
        MOVE.W  D6,D0
        ANDI.W  #$00FF,D0               ; this column's digit
        SWAP    D6
        MOVEQ   #0,D3
        MOVE.W  D6,D3                   ; and the rest of the number
        TST.B   D0
        BNE.S   .pd_put
        TST.B   D4
        BNE.S   .pd_put
        CMPI.W  #1,D5
        BNE.S   .pd_step                ; a leading zero, and not the last
.pd_put:
        MOVEQ   #1,D4
        ADDI.B  #'0',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
.pd_step:
        CMPI.W  #1,D5
        BEQ.S   .pd_out
        MOVEQ   #0,D6
        MOVE.W  D5,D6
        DIVU    #10,D6
        MOVE.W  D6,D5
        BRA.S   .pd_round
.pd_out:
        MOVEM.L (SP)+,D0/D3-D6
        RTS

; ---------------------------------------------------------------------------
; put_secs — D0.B = a time in 100ms units, at D1.B = column, D2.B = row, as
; seconds and tenths.  D1 ends past it.
; Clobbers: D1
; ---------------------------------------------------------------------------
put_secs:
        MOVEM.L D0/D3-D4,-(SP)
        MOVEQ   #0,D3
        MOVE.B  D0,D3
        MOVE.L  D3,D4
        DIVU    #10,D4
        MOVE.W  D4,D0
        ANDI.W  #$00FF,D0
        BSR     put_dec
        MOVEQ   #'.',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
        SWAP    D4
        MOVE.W  D4,D0
        ANDI.W  #$000F,D0
        ADDI.B  #'0',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
        MOVEQ   #'S',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
        MOVEM.L (SP)+,D0/D3-D4
        RTS

; ===========================================================================
; The report
;
; The screen is what somebody watching the board reads.  The pipe is what a
; machine reads.
;
; A pipe write is itself an RBCP command, so none of it happens while the
; session is broken.
; ===========================================================================

; ---------------------------------------------------------------------------
; report_open — find a pipe that carries host to device, and say so.
;
; The first pipe reporting OUT is the one.  A device offering more than one has
; no way to say which it would prefer.  A device with no pipes, or one whose
; protocol version predates the group, leaves reporting off and the run is read
; off the screen.
;
; Each of the two commands gets OPEN_TRIES goes, because this runs once and a
; single mangled command would otherwise cost the whole run its log.
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
        LEA     (str_log_start).L,A0
        BSR     log_line
        BRA.S   .ro_out
.ro_next:
        ADDQ.B  #1,D4
        CMP.B   D2,D4
        BCS.S   .ro_try
.ro_out:
        MOVEM.L (SP)+,D0-D4/A0
        RTS

; ---------------------------------------------------------------------------
; log_caps — the LED capability, as one line.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
log_caps:
        TST.B   VAR_PIPE_PRESENT
        BNE.S   .lc_go
        RTS
.lc_go:
        MOVEM.L D0/A0,-(SP)
        LEA     (str_log_leds).L,A0
        BSR     pipe_puts
        MOVE.B  LT_TOTAL,D0
        BSR     log_num
        LEA     (str_log_max_per).L,A0
        BSR     pipe_puts
        MOVE.B  LT_MAX_PERIOD,D0
        BSR     log_num
        LEA     (str_log_max_hold).L,A0
        BSR     pipe_puts
        MOVE.B  LT_MAX_HOLD,D0
        BSR     log_num
        BSR     log_crlf
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; log_leds — a line per LED, saying what it is and which modes it has.
; Clobbers (saved/restored): D0/D3/A0
; ---------------------------------------------------------------------------
log_leds:
        TST.B   VAR_PIPE_PRESENT
        BNE.S   .ll_go
        RTS
.ll_go:
        MOVEM.L D0/D3/A0,-(SP)
        MOVEQ   #0,D3
.ll_led:
        LEA     (str_log_led).L,A0
        BSR     pipe_puts
        MOVE.B  D3,D0
        BSR     log_num
        LEA     (str_log_type).L,A0
        BSR     pipe_puts
        LEA     (LT_TYPE).W,A0
        MOVE.B  (A0,D3.W),D0
        BSR     log_num
        LEA     (str_log_modes).L,A0
        BSR     pipe_puts
        LEA     (LT_MODES).W,A0
        MOVE.B  (A0,D3.W),D0
        BSR     log_hex_byte
        BSR     log_crlf
        ADDQ.W  #1,D3
        CMP.B   LT_COUNT,D3
        BCS.S   .ll_led
        MOVEM.L (SP)+,D0/D3/A0
        RTS

; ---------------------------------------------------------------------------
; log_set — the SET_LED that just went out, whole.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
log_set:
        TST.B   VAR_PIPE_PRESENT
        BNE.S   .ls_go
        RTS
.ls_go:
        MOVEM.L D0/A0,-(SP)
        LEA     (str_log_set).L,A0
        BSR     pipe_puts
        MOVE.B  LT_CUR,D0
        BSR     log_num
        LEA     (str_log_mode).L,A0
        BSR     pipe_puts
        MOVE.B  (LT_SENT+SENT_MODE).W,D0
        BSR     log_hex_byte
        LEA     (str_log_col).L,A0
        BSR     pipe_puts
        MOVE.B  (LT_SENT+SENT_RED).W,D0
        BSR     log_hex_byte
        MOVE.B  (LT_SENT+SENT_GREEN).W,D0
        BSR     log_hex_byte
        MOVE.B  (LT_SENT+SENT_BLUE).W,D0
        BSR     log_hex_byte
        LEA     (str_log_bri).L,A0
        BSR     pipe_puts
        MOVE.B  (LT_SENT+SENT_BRIGHT).W,D0
        BSR     log_num
        LEA     (str_log_per).L,A0
        BSR     pipe_puts
        MOVE.B  (LT_SENT+SENT_PERIOD).W,D0
        BSR     log_num
        LEA     (str_log_hold).L,A0
        BSR     pipe_puts
        MOVE.B  (LT_SENT+SENT_HOLD).W,D0
        BSR     log_num
        BSR     log_crlf
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; log_got — what the device reports for that LED now, and whether the two
; agree.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
log_got:
        TST.B   VAR_PIPE_PRESENT
        BNE.S   .lg_go
        RTS
.lg_go:
        MOVEM.L D0-D1/A0,-(SP)
        MOVEQ   #0,D1
        MOVE.B  LT_CUR,D1
        LEA     (str_log_got).L,A0
        BSR     pipe_puts
        MOVE.B  D1,D0
        BSR     log_num
        LEA     (str_log_mode).L,A0
        BSR     pipe_puts
        LEA     (LT_MODE).W,A0
        MOVE.B  (A0,D1.W),D0
        BSR     log_hex_byte
        LEA     (str_log_col).L,A0
        BSR     pipe_puts
        LEA     (LT_RED).W,A0
        MOVE.B  (A0,D1.W),D0
        BSR     log_hex_byte
        LEA     (LT_GREEN).W,A0
        MOVE.B  (A0,D1.W),D0
        BSR     log_hex_byte
        LEA     (LT_BLUE).W,A0
        MOVE.B  (A0,D1.W),D0
        BSR     log_hex_byte
        LEA     (str_log_bri).L,A0
        BSR     pipe_puts
        LEA     (LT_BRIGHT).W,A0
        MOVE.B  (A0,D1.W),D0
        BSR     log_num
        LEA     (str_log_per).L,A0
        BSR     pipe_puts
        LEA     (LT_PERIOD).W,A0
        MOVE.B  (A0,D1.W),D0
        BSR     log_num
        MOVEQ   #0,D1
        MOVE.B  LT_READ,D1
        LSL.W   #2,D1
        LEA     (log_read_msgs).L,A0
        MOVEA.L (A0,D1.W),A0
        BSR     pipe_puts
        BSR     log_crlf
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; log_refused — the device answered this one and said no.
log_refused:
        MOVEM.L A0,-(SP)
        LEA     (str_log_refused).L,A0
        BSR     log_line
        MOVEM.L (SP)+,A0
        RTS

; log_slipped — a command the device never answered, and the reset that
; brought it back.
log_slipped:
        MOVEM.L A0,-(SP)
        LEA     (str_log_slipped).L,A0
        BSR     log_line
        MOVEM.L (SP)+,A0
        RTS

; ---------------------------------------------------------------------------
; log_num — D0.B = 0 to 255, sent as one to three decimal digits with no
; leading zero.  log_dec in the shared code stops at two.
; Clobbers (saved/restored): D0-D4/A0
; ---------------------------------------------------------------------------
log_num:
        MOVEM.L D0-D4/A0,-(SP)
        MOVEQ   #0,D1
        MOVE.B  D0,D1                   ; what is left
        MOVEQ   #0,D2                   ; digits placed
        MOVE.W  #100,D3
        LEA     (RBCP_ARG0).W,A0
.ln_round:
        MOVE.L  D1,D4
        DIVU    D3,D4
        MOVE.W  D4,D0
        ANDI.W  #$00FF,D0
        SWAP    D4
        MOVEQ   #0,D1
        MOVE.W  D4,D1
        TST.B   D0
        BNE.S   .ln_put
        TST.B   D2
        BNE.S   .ln_put
        CMPI.W  #1,D3
        BNE.S   .ln_step
.ln_put:
        ADDI.B  #'0',D0
        MOVE.B  D0,(A0)+
        ADDQ.B  #1,D2
.ln_step:
        CMPI.W  #1,D3
        BEQ.S   .ln_send
        MOVEQ   #0,D4
        MOVE.W  D3,D4
        DIVU    #10,D4
        MOVE.W  D4,D3
        BRA.S   .ln_round
.ln_send:
        MOVE.B  D2,D0
        BSR     log_write
        MOVEM.L (SP)+,D0-D4/A0
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
; Copper template, font, strings and tables.  Reached from RAM code by
; absolute long address, so correct from any PC.
; ============================================================

        INCLUDE "../amiga-common/amiga_screen_data.s"

; How long the list screen_init installed is.  What this program appends goes
; over its END.
COP_LIST_LEN        EQU copper_template_end-copper_template

        EVEN
str_title:
        DC.B    "RBCP LED TESTER "
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
        DC.B    "REPORTING ON PIPE ",0
str_pipe_len        EQU 18
        EVEN
str_no_pipe:
        DC.B    "NO OUT PIPE AVAILABLE",0
        EVEN
str_max_period:
        DC.B    "MAX PERIOD ",0
str_max_period_len  EQU 11
        EVEN
str_max_hold:
        DC.B    "MAX HOLD ",0
str_max_hold_len    EQU 9
        EVEN
str_leds:
        DC.B    " LEDS  ",0
str_leds_len        EQU 7
        EVEN
str_shown:
        DC.B    " SHOWN",0

        EVEN
str_h_num:
        DC.B    "N",0
        EVEN
str_h_type:
        DC.B    "TYPE",0
        EVEN
str_h_mode:
        DC.B    "MODE",0
        EVEN
str_h_colour:
        DC.B    "COLOUR",0
        EVEN
str_h_bri:
        DC.B    "BRI",0
        EVEN
str_h_per:
        DC.B    "PERIOD",0
        EVEN
str_h_bright:
        DC.B    "BRIGHT",0
        EVEN
str_h_hold:
        DC.B    "HOLD",0
        EVEN
str_sends:
        DC.B    "SENDS",0

        EVEN
str_mono:
        DC.B    "MONO",0
        EVEN
str_rgb:
        DC.B    "RGB",0
        EVEN
str_modes:
        DC.B    "MODES",0
        EVEN
str_mode:
        DC.B    "MODE ",0
str_mode_len        EQU 5
        EVEN
str_flame:
        DC.B    "FLAME",0
        EVEN
str_device:
        DC.B    "DEVICE",0
        EVEN
str_default:
        DC.B    "DEFAULT",0
        EVEN
str_none:
        DC.B    "NONE",0

        EVEN
str_no_leds:
        DC.B    "THIS DEVICE HAS NO LEDS",0
        EVEN
str_no_led_group:
        DC.B    "THIS DEVICE ANSWERS NO LED COMMANDS",0

        EVEN
str_no_period:
        DC.B    "THIS MODE TAKES NO PERIOD ON THIS LED",0
        EVEN
str_period_from:
        DC.B    "PERIOD ",0
str_period_from_len EQU 7
        EVEN
str_period_to:
        DC.B    " TO ",0
str_period_to_len   EQU 4
        EVEN
str_period_upto:
        DC.B    "PERIOD UP TO ",0
str_period_upto_len EQU 13
        EVEN
str_period_tail:
        DC.B    " ON THIS MODE",0

; The legend.
        EVEN
str_keys1:
        DC.B    "M MODE    C COLOUR  B BRIGHT  P PERIOD",0
        EVEN
str_keys2:
        DC.B    "H HOLD    A PARADE  RETURN SENDS AGAIN",0
        EVEN
str_keys3:
        DC.B    "CRSR LED",0
        EVEN
str_k_table:
        DC.B    "T TABLE",0
        EVEN
str_k_lamps:
        DC.B    "L LAMPS",0

        EVEN
str_led:
        DC.B    "LED ",0
str_led_len         EQU 4
        EVEN
str_colour_for:
        DC.B    "COLOUR FOR LED ",0
str_colour_for_len  EQU 15

; ---------------------------------------------------------------------------
; The modes the protocol names, in its order, and where each one sits on the
; modes row.
; ---------------------------------------------------------------------------
        EVEN
mode_names:
        DC.L    str_m_off, str_m_on, str_m_blink
        DC.L    str_m_breathe, str_m_cycle, str_m_beacon
        EVEN
str_m_off:
        DC.B    "OFF",0
        EVEN
str_m_on:
        DC.B    "ON",0
        EVEN
str_m_blink:
        DC.B    "BLINK",0
        EVEN
str_m_breathe:
        DC.B    "BREATHE",0
        EVEN
str_m_cycle:
        DC.B    "CYCLE",0
        EVEN
str_m_beacon:
        DC.B    "BEACON",0
        EVEN
mode_cols:
        DC.B    6,10,13,19,27,33

; ---------------------------------------------------------------------------
; The colours this program will send.  Entry 0 is three zeroes, which asks the
; device to choose one.  The rest are a channel at full strength, because an
; LED asked for a dim red lights a washed out white instead.  Black is not
; offered — whether an LED is lit is carried by its mode, so a colour being set
; is always one meant to be seen.
; ---------------------------------------------------------------------------
        EVEN
colour_rgb:
        DC.B    $00,$00,$00             ; the device's own choice
        DC.B    $FF,$FF,$FF             ; white
        DC.B    $FF,$00,$00             ; red
        DC.B    $00,$FF,$FF             ; cyan
        DC.B    $FF,$00,$FF             ; purple
        DC.B    $00,$FF,$00             ; green
        DC.B    $00,$00,$FF             ; blue
        DC.B    $FF,$FF,$00             ; yellow
        EVEN
colour_names:
        DC.L    str_device, str_c_white, str_c_red, str_c_cyan
        DC.L    str_c_purple, str_c_green, str_c_blue, str_c_yellow
        EVEN
str_c_white:
        DC.B    "WHITE",0
        EVEN
str_c_red:
        DC.B    "RED",0
        EVEN
str_c_cyan:
        DC.B    "CYAN",0
        EVEN
str_c_purple:
        DC.B    "PURPLE",0
        EVEN
str_c_green:
        DC.B    "GREEN",0
        EVEN
str_c_blue:
        DC.B    "BLUE",0
        EVEN
str_c_yellow:
        DC.B    "YELLOW",0

; ---------------------------------------------------------------------------
; The values the stepping keys walk.  Entry 0 of each leaves the choice to the
; device.
; ---------------------------------------------------------------------------
        EVEN
bright_steps:
        DC.B    0,25,50,75,100
        EVEN
period_steps:
        DC.B    0,5,10,20,50
        EVEN
hold_steps:
        DC.B    0,5,10,20,50

; ---------------------------------------------------------------------------
; The animation.  Steps in one repetition of each mode, and how lit the lamp is
; at each step of the ones that move.
;
; Off and On do not move.  Cycle takes its colour from cycle_hues instead of a
; level, so it has no table here.
; ---------------------------------------------------------------------------
        EVEN
anim_steps:
        DC.B    1,1,2,8,6,8
        EVEN
blink_level:
        DC.B    255,0
        EVEN
breathe_level:
        DC.B    0,64,128,192,255,192,128,64
        EVEN
beacon_level:
        DC.B    255,0,255,0,0,0,0,0
; ---------------------------------------------------------------------------
; The fields a row is drawn from.  A row is redrawn where one of them moves.
; ---------------------------------------------------------------------------
        EVEN
row_fields:
        DC.L    LT_TYPE, LT_MODE, LT_RED, LT_GREEN, LT_BLUE
        DC.L    LT_BRIGHT, LT_PERIOD

; ---------------------------------------------------------------------------
; The four shades a lamp is drawn in.  Each keeps that much of the colour the
; device reports, out of 256, and the lit centre takes that much of the way
; towards white after it.
;
; White goes into the centre alone.  A lamp's middle reads hotter than its
; edge and that is what a lit LED looks like, but whitening every shade would
; take the colour out of the whole lens.
; ---------------------------------------------------------------------------
        EVEN
shade_tab:
        DC.B    255,80                  ; the lit centre
        DC.B    205,0                   ; the body of the lens
        DC.B    115,0                   ; its darker edge
        DC.B    48,0                    ; the light it throws around itself

; The five ellipses a point is tested against, as the square of how far out
; each one is, out of 256.  The fourth is the package the lens sits in and
; takes PEN_LENS.  The other four are the shades, in order.
        EVEN
shade_ratio:
        DC.W    37                      ; the lit centre, 0.38 of the way out
        DC.W    118                     ; the body of the lens, 0.68
        DC.W    172                     ; its darker edge, 0.82
        DC.W    256                     ; the package the lens sits in
        DC.W    310                     ; and how far the glow reaches, 1.1

; ---------------------------------------------------------------------------
; The largest half-height a lamp can take in a band of that many character
; rows, indexed by the pitch layout_entries settled on.
;
; A lamp's glow reaches B*GLOW_NUM/GLOW_DEN+1 rows either side of its centre
; and the band below is where the next lamp's pens are written, so the reach
; has to stay inside half the band.  LAMP_B_MAX is where the six columns
; beside the text run out, which is what caps the widest band.
; ---------------------------------------------------------------------------
        EVEN
lamp_half:
        DC.B    0, 1, 6, 9, 13, LAMP_B_MAX

        EVEN
cycle_hues:
        DC.B    $FF,$00,$00
        DC.B    $FF,$FF,$00
        DC.B    $00,$FF,$00
        DC.B    $00,$FF,$FF
        DC.B    $00,$00,$FF
        DC.B    $FF,$00,$FF

; ---------------------------------------------------------------------------
; The note row, and the pen each message takes.
; ---------------------------------------------------------------------------
        EVEN
note_msgs:
        DC.L    str_n_blank, str_n_refused, str_n_nocolour, str_n_noperiod
        DC.L    str_n_nohold, str_n_parade, str_n_slipped, str_n_gone
        EVEN
note_pens:
        DC.B    PEN_TEXT, PEN_BAD, PEN_TEXT, PEN_TEXT
        DC.B    PEN_TEXT, PEN_TEXT, PEN_WARN, PEN_BAD
        EVEN
str_n_blank:
        DC.B    0
        EVEN
str_n_refused:
        DC.B    "THE DEVICE REFUSED THAT",0
        EVEN
str_n_nocolour:
        DC.B    "THIS LED'S COLOUR IS NOT OURS TO SET",0
        EVEN
str_n_noperiod:
        DC.B    "THIS MODE TAKES NO PERIOD ON THIS LED",0
        EVEN
str_n_nohold:
        DC.B    "THIS DEVICE TIMES NO HOLDS",0
        EVEN
str_n_parade:
        DC.B    "WATCH THE DEVICE   ANY KEY STOPS",0
        EVEN
str_n_slipped:
        DC.B    "A COMMAND WAS LOST  THE DEVICE IS BACK",0
        EVEN
str_n_gone:
        DC.B    "THE SESSION IS OVER",0

; ---------------------------------------------------------------------------
; The field a read back differed on, and how long each name is so the rest of
; the line chains on after it.
; ---------------------------------------------------------------------------
        EVEN
read_fields:
        DC.L    str_f_mode, str_f_bright, str_f_period
        DC.L    str_f_red, str_f_green, str_f_blue
        EVEN
read_field_len:
        DC.B    4, 6, 6, 3, 5, 4
        EVEN
str_f_mode:
        DC.B    "MODE",0
        EVEN
str_f_bright:
        DC.B    "BRIGHT",0
        EVEN
str_f_period:
        DC.B    "PERIOD",0
        EVEN
str_f_red:
        DC.B    "RED",0
        EVEN
str_f_green:
        DC.B    "GREEN",0
        EVEN
str_f_blue:
        DC.B    "BLUE",0
        EVEN
str_r_back:
        DC.B    " READ BACK AS ",0
str_r_back_len      EQU 14
        EVEN
str_r_refused:
        DC.B    "DEVICE REFUSED THE SET",0

; ---------------------------------------------------------------------------
; The error screen.  Only a session that never opened ends this way.
; ---------------------------------------------------------------------------
        EVEN
err_msgs:
        DC.L    msg_err_0, msg_err_1, msg_err_2
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
; Words down the pipe
; ---------------------------------------------------------------------------
        EVEN
str_log_start:
        DC.B    "RBCP LED TESTER START "
        APP_VERSION
        DC.B    0
        EVEN
str_log_leds:
        DC.B    "LEDS ",0
        EVEN
str_log_max_per:
        DC.B    " MAX PERIOD ",0
        EVEN
str_log_max_hold:
        DC.B    " MAX HOLD ",0
        EVEN
str_log_led:
        DC.B    "LED ",0
        EVEN
str_log_type:
        DC.B    " TYPE ",0
        EVEN
str_log_modes:
        DC.B    " MODES ",0
        EVEN
str_log_set:
        DC.B    "SET ",0
        EVEN
str_log_got:
        DC.B    "GOT ",0
        EVEN
str_log_mode:
        DC.B    " MODE ",0
        EVEN
str_log_col:
        DC.B    " COL ",0
        EVEN
str_log_bri:
        DC.B    " BRI ",0
        EVEN
str_log_per:
        DC.B    " PER ",0
        EVEN
str_log_hold:
        DC.B    " HOLD ",0
        EVEN
str_log_refused:
        DC.B    "REFUSED",0
        EVEN
str_log_slipped:
        DC.B    "LOST, THE DEVICE IS BACK",0
        EVEN
log_read_msgs:
        DC.L    str_lr_none, str_lr_match, str_lr_differs, str_lr_refused
        EVEN
str_lr_none:
        DC.B    0
        EVEN
str_lr_match:
        DC.B    " AGREES",0
        EVEN
str_lr_differs:
        DC.B    " DIFFERS",0
        EVEN
str_lr_refused:
        DC.B    " REFUSED",0

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
