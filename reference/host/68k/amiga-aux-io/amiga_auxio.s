; amiga_auxio.s — Amiga RBCP auxiliary I/O tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Purpose
; -------
; The tester asks a device what auxiliary pins it has, draws them, and drives
; the one under the cursor.  A pin is a pad.  The ring is in the pen of whoever
; owns it and the centre is lit where the level is high.  The protocol says
; nothing about what is wired to a pin, so neither does this program.
;
; The tester owns the machine
; ---------------------------
; It is a Kickstart image.  It runs from reset, it never hands the machine
; back, and the way out is the power switch or the reset the `R` screen
; offers.  A pin's state outlives the session, so switching off is what puts a
; driven pin back.
;
; ROM image layout, top-aligned — 256 KB from $FC0000 or 512 KB from $F80000:
;
;   ROM SECTION  — executed directly from ROM
;     ROM header, rom_cold_start, JMP rom_entry
;     amiga_hw.s: a500_hw_init, exc_halt, kbd_init, screen_init
;     rom_entry: HW init, screen up, copy RAM section, JMP $28000
;
;   RAM SECTION  — stored in ROM, copied to RAM_CODE_BASE ($28000) at boot
;     ram_entry: the session, the discovery, then the loop
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

; The tester draws none of the bootloader's artwork.  Every pen that carries it
; is free, so the tester has all sixteen to itself.  A pen already defined
; keeps its value, so these go in before the palette is included.
;
; Three saturated colours for the three things that can own a pin, and a
; muted one of each for the centre of a pad whose level is low.  Each pair is
; the same colour at two brightnesses, so a pad says who owns it at either
; level.
PEN00_RGB                   EQU $0001       ; the background, all but black
PEN01_RGB                   EQU $0141       ; the board the pads sit on
PEN04_RGB                   EQU $0383       ; the light line along its edges
PEN06_RGB                   EQU $0F44       ; the Amiga is driving this pin
PEN07_RGB                   EQU $0FFF       ; nobody is driving it
PEN08_RGB                   EQU $066F       ; the device ROM has it reserved
PEN09_RGB                   EQU $0AAA       ; labels, dimmer than the figures
PEN10_RGB                   EQU $0FA0       ; the line of plain English
PEN11_RGB                   EQU $0611       ; the same three, held low
PEN12_RGB                   EQU $0777
PEN13_RGB                   EQU $0237
PEN14_RGB                   EQU $0FFE       ; spare
PEN15_RGB                   EQU $0444       ; spare

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
; ram_entry — the tester proper, running from chip RAM.  The session, what the
; device has, then the loop.  It does not return.
; ---------------------------------------------------------------------------
ram_entry:
        BSR     zero_vars
        MOVE.L  #BITPLANE_BASE,VAR_DRAW_BASE
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        CLR.B   VAR_MENU_COL            ; a filled row is the whole row here
        CLR.B   VAR_LINE_CUT
        CLR.B   VAR_TOTAL_RAM
        CLR.B   VAR_TOTAL_FLASH
        ; The beam line wait_field works from.  It is the first line off the
        ; bottom of the display.
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
        BSR     draw_title              ; before anything is asked of the device

        BSR     sess_open               ; err_halt on the way out where it fails
        BSR     report_open
        BSR     pins_discover           ; and again where there are no pins

        ; The device line and the keys read the same on every page, so they go
        ; down once and a page change leaves them alone.
        BSR     draw_device_row
        BSR     draw_keys
        BSR     paint_page

        ; The second the rate is counted over runs from now, so the first one
        ; covers a second of the loop and not the session that opened it.
        BSR     tod_now
        MOVE.L  D0,AUX_RATE_TOD

; ---------------------------------------------------------------------------
; main_loop — the resting state.  One field: the pins read again, the pads
; that moved drawn again, and whatever was pressed acted on.
;
; The Amiga talks to the device with the display up, so there is nothing to
; wait for between reads and no reason to read the pins any less often than
; the screen can change.  A field is that rate.
;
; A key is acted on at the top of the next field.  The field it was read in is
; most of the way through by then, and a key that rebuilds the page would
; start that rebuild under the beam.
; ---------------------------------------------------------------------------
main_loop:
        BSR     live_tick
        TST.B   D0
        BEQ.S   main_loop
        MOVE.W  D0,-(SP)
        BSR     wait_field
        MOVE.W  (SP)+,D0
        BSR     take_key
        BRA.S   main_loop

; ---------------------------------------------------------------------------
; take_key — D0.B = a key.  All four cursor keys walk the drivable pins and
; everything else is a character, which amiga_getkey returns in the case it
; was typed in.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
take_key:
        MOVEM.L D0,-(SP)
        CMPI.B  #KEY_UP,D0
        BEQ     .tk_prev
        CMPI.B  #KEY_LEFT,D0
        BEQ     .tk_prev
        CMPI.B  #KEY_DOWN,D0
        BEQ     .tk_next
        CMPI.B  #KEY_RIGHT,D0
        BEQ     .tk_next
        CMPI.B  #KEY_PAGE_NEXT,D0
        BEQ     .tk_pagen
        CMPI.B  #KEY_PAGE_PREV,D0
        BEQ     .tk_pagep
        ORI.B   #$20,D0                 ; a letter, whichever case it came in
        CMPI.B  #KEY_LOW,D0
        BEQ     .tk_low
        CMPI.B  #KEY_HIGH,D0
        BEQ     .tk_high
        CMPI.B  #KEY_RELEASE,D0
        BEQ     .tk_rel
        CMPI.B  #KEY_BLINK,D0
        BEQ     .tk_blink
        CMPI.B  #KEY_RESET,D0
        BEQ     .tk_reset
        CMPI.B  #KEY_TIME,D0
        BEQ     .tk_time
        BRA     .tk_out
.tk_prev:
        BSR     pin_prev
        BRA     .tk_out
.tk_next:
        BSR     pin_next
        BRA     .tk_out
.tk_pagen:
        BSR     page_next
        BRA     .tk_out
.tk_pagep:
        BSR     page_prev
        BRA     .tk_out
.tk_low:
        MOVEQ   #RBCP_AUX_LOW,D0
        BSR     drive
        BRA     .tk_out
.tk_high:
        MOVEQ   #RBCP_AUX_HIGH,D0
        BSR     drive
        BRA     .tk_out
.tk_rel:
        MOVEQ   #RBCP_AUX_RELEASE,D0
        BSR     drive
        BRA     .tk_out
.tk_blink:
        BSR     blink
        BRA     .tk_out
.tk_reset:
        BSR     show_reset
        BRA     .tk_out
.tk_time:
        BSR     time_screen
.tk_out:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; zero_vars — the tester's own variables and the library's un-swap buffer.
; Nothing in either may start as whatever chip RAM held at reset.  The
; variables the shared routines own are set by hand in ram_entry, because
; screen_init has already put the Agnus it found in one of them.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
zero_vars:
        MOVEM.L D0/A0,-(SP)
        LEA     (AUX_VARS).W,A0
        MOVE.W  #(AUX_END-AUX_VARS)/2-1,D0
.zv_vars:
        CLR.W   (A0)+
        DBF     D0,.zv_vars
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        MOVE.W  #CONFIG_RBCP_DATA_BUF_SIZE/2-1,D0
.zv_buf:
        CLR.W   (A0)+
        DBF     D0,.zv_buf
        MOVE.B  #RBCP_AUX_RELEASE,AUX_AFTER
        MOVE.B  #PEN_BOARD,AUX_CELL_BG
        BSR     tod_start               ; the clock the sweep is measured by
        MOVEM.L (SP)+,D0/A0
        RTS

; ===========================================================================
; The session
;
; The tester is a ROM and the image it runs out of is its own, so there is no
; exit to repair.  Opening a session is the knock, command-response mode, the
; version check, the three strings the device calls itself, and what the reset
; screen needs to bring the machine back.
; ===========================================================================

; ---------------------------------------------------------------------------
; sess_open — a session, or the error screen.  Does not return where it fails.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
sess_open:
        MOVEM.L D0,-(SP)
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
        BSR     read_identity
        BSR     find_spare
        BSR     read_flash_count
        ; A switch needs both a spare RAM slot to load into and an image to
        ; load.  Without either the reset still works and the machine comes
        ; back as this program.
        TST.B   AUX_FLASH_COUNT
        BNE.S   .so_out
        CLR.B   AUX_CAN_SWITCH
.so_out:
        MOVEM.L (SP)+,D0
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
        LEA     (AUX_DEV_TYPE).W,A1
        BSR     copy_name
.ri_ver:
        BSR     rbcp_cmd_get_device_version
        TST.B   D0
        BNE.S   .ri_proto
        LEA     (AUX_DEV_VER).W,A1
        BSR     copy_name
.ri_proto:
        BSR     rbcp_cmd_get_proto_version
        TST.B   D0
        BNE.S   .ri_out
        MOVEQ   #4,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        LEA     (AUX_PROTO).W,A1
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
; find_spare — the first RAM slot that is not the active one, which is where
; the reset screen stages the image it brings the machine back as.  A device
; with one slot has no spare and AUX_CAN_SWITCH stays clear.
; Clobbers (saved/restored): D0-D1
; ---------------------------------------------------------------------------
find_spare:
        MOVEM.L D0-D1,-(SP)
        BSR     rbcp_cmd_get_ram_info_all
        TST.B   D0
        BNE.S   .fs_out
        MOVEQ   #3,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_RAM_TOTAL).W,D0
        MOVE.B  D0,VAR_TOTAL_RAM
        CMPI.B  #2,D0
        BCS.S   .fs_out
        CLR.B   AUX_SPARE_SLOT
        TST.B   (CONFIG_RBCP_DATA_BUF+RBCP_RAM_ACTIVE).W
        BNE.S   .fs_have                ; slot 0, since another one is active
        MOVE.B  #1,AUX_SPARE_SLOT
.fs_have:
        MOVE.B  #1,AUX_CAN_SWITCH
.fs_out:
        MOVEM.L (SP)+,D0-D1
        RTS

; ---------------------------------------------------------------------------
; read_flash_count — how many flash slots the reset screen can offer.  Only
; the whole records count: a record the reply had no room for has no name to
; show, and the device says how many came back.
; Clobbers (saved/restored): D0-D1
; ---------------------------------------------------------------------------
read_flash_count:
        MOVEM.L D0-D1,-(SP)
        BSR     rbcp_cmd_get_flash_info_all
        TST.B   D0
        BNE.S   .rfc_out
        MOVEQ   #3,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_FLASH_ALL_WHOLE).W,AUX_FLASH_COUNT
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_FLASH_ALL_TOTAL).W,VAR_TOTAL_FLASH
.rfc_out:
        MOVEM.L (SP)+,D0-D1
        RTS

; ---------------------------------------------------------------------------
; read_flash_name — D0.B = flash slot.  Its name into AUX_FLASH_NAME, from a
; fresh GET_FLASH_SLOT_INFO_ALL.
;
; The reply runs to a 32 byte record a slot and the un-swap buffer holds one
; of them, so this reads the window the wanted record sits in rather than the
; whole reply.  A device that refuses empties the name rather than leaving the
; last one standing.
; Clobbers (saved/restored): D0-D2/A0-A1
; ---------------------------------------------------------------------------
read_flash_name:
        MOVEM.L D0-D2/A0-A1,-(SP)
        MOVE.B  D0,D2                   ; the slot
        LEA     (AUX_FLASH_NAME).W,A1
        CLR.B   (A1)
        BSR     rbcp_cmd_get_flash_info_all
        TST.B   D0
        BNE.S   .rfn_out
        MOVEQ   #0,D1
        MOVE.B  D2,D1
        MULU    #RBCP_FLASH_RECORD_SIZE,D1
        ADDI.W  #RBCP_FLASH_ALL_RECORDS,D1
        MOVEQ   #RBCP_FLASH_RECORD_SIZE,D0
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF+RBCP_FLASH_NAME).W,A0
        MOVEQ   #RBCP_FLASH_RECORD_SIZE-2,D1
.rfn_ch:
        MOVE.B  (A0)+,(A1)+
        BEQ.S   .rfn_out
        DBF     D1,.rfn_ch
        CLR.B   (A1)
.rfn_out:
        MOVEM.L (SP)+,D0-D2/A0-A1
        RTS

; ---------------------------------------------------------------------------
; load_spare — D0.B = flash slot.  Loads it into the spare RAM slot, so that
; the reset has something to come back as.
; Output: D0=0 loaded, D0=1 refused
; Clobbers: D0
; ---------------------------------------------------------------------------
load_spare:
        MOVEM.L D1,-(SP)
        MOVE.B  D0,D1                   ; flash slot
        MOVE.B  AUX_SPARE_SLOT,D0       ; RAM slot
        BSR     rbcp_cmd_load_slot
        TST.B   D0
        BEQ.S   .ls_out
        MOVEQ   #1,D0
.ls_out:
        MOVEM.L (SP)+,D1
        RTS

; ===========================================================================
; The report
;
; Every line goes down the device's own pipe.  A machine drawing to a bitmap
; leaves nothing to read as text, and the log is the only record that a run
; happened and what the device was asked for.
; ===========================================================================

; ---------------------------------------------------------------------------
; report_open — find a pipe that carries host to device, and say so.
;
; The first pipe reporting OUT is the one.  A device offering more than one
; has no way to say which it would prefer.  A device with no pipes leaves
; reporting off and the run is read off the screen.
; Clobbers (saved/restored): D0-D3/A0
; ---------------------------------------------------------------------------
report_open:
        MOVEM.L D0-D3/A0,-(SP)
        CLR.B   VAR_PIPE_PRESENT
        BSR     rbcp_cmd_get_pipe_cap
        TST.B   D0
        BNE     .ro_out
        MOVEQ   #1,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVEQ   #0,D2
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_CAP_COUNT).W,D2
        BEQ     .ro_out                 ; no pipes at all
        MOVEQ   #0,D3                   ; the pipe being asked about
.ro_try:
        MOVE.B  D3,D0
        BSR     rbcp_cmd_get_pipe_info
        TST.B   D0
        BNE.S   .ro_next
        MOVEQ   #2,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_INFO_FLAGS).W,D0
        ANDI.B  #RBCP_PIPE_FLAG_OUT,D0
        BEQ.S   .ro_next
        MOVE.B  D3,D0
        BSR     log_open
        LEA     (str_log_start).L,A0
        BSR     log_line
        BSR     log_device
        BRA.S   .ro_out
.ro_next:
        ADDQ.B  #1,D3
        CMP.B   D2,D3
        BCS.S   .ro_try
.ro_out:
        MOVEM.L (SP)+,D0-D3/A0
        RTS

; ---------------------------------------------------------------------------
; report_groups — what the device said it has, one line a group.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
report_groups:
        MOVEM.L D0-D2/A0,-(SP)
        TST.B   VAR_PIPE_PRESENT
        BEQ     .rgp_out
        MOVEQ   #0,D2
.rgp_line:
        LEA     (str_log_group).L,A0
        BSR     pipe_puts
        MOVE.B  D2,D0
        BSR     log_dec
        LEA     (str_log_type).L,A0
        BSR     pipe_puts
        MOVEQ   #0,D1
        MOVE.B  D2,D1
        LEA     (AUX_GROUP_TYPE).W,A0
        MOVE.B  (A0,D1.W),D0
        BSR     log_hex_byte
        LEA     (str_log_pins).L,A0
        BSR     pipe_puts
        LEA     (AUX_GROUP_PINS).W,A0
        MOVE.B  (A0,D1.W),D0
        BSR     log_dec
        LEA     (str_log_drv).L,A0
        BSR     pipe_puts
        LEA     (AUX_GROUP_DRV).W,A0
        MOVE.B  (A0,D1.W),D0
        BSR     log_dec
        BSR     log_crlf
        ADDQ.B  #1,D2
        CMP.B   AUX_GROUP_COUNT,D2
        BCS.S   .rgp_line
.rgp_out:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; report_set — D0.B = state, D1.B = pin, D2.B = group, D3.B = 0 where the
; device took it.  One line saying what was asked of which pin, and what came
; back.
; Clobbers (saved/restored): D0-D4/A0
; ---------------------------------------------------------------------------
report_set:
        MOVEM.L D0-D4/A0,-(SP)
        TST.B   VAR_PIPE_PRESENT
        BEQ     .rst_out
        MOVE.B  D0,D4                   ; the state, across the numbers
        LEA     (str_log_set).L,A0
        BSR     pipe_puts
        MOVE.B  D2,D0
        BSR     log_dec
        LEA     (str_log_slash).L,A0
        BSR     pipe_puts
        MOVE.B  D1,D0
        BSR     log_dec
        ANDI.W  #$00FF,D4
        CMPI.W  #3,D4
        BCC.S   .rst_end
        LSL.W   #2,D4
        LEA     (state_names).L,A0
        MOVEA.L (A0,D4.W),A0
        BSR     pipe_puts
.rst_end:
        LEA     (str_log_taken).L,A0
        TST.B   D3
        BEQ.S   .rst_say
        LEA     (str_log_refused).L,A0
.rst_say:
        BSR     log_line
.rst_out:
        MOVEM.L (SP)+,D0-D4/A0
        RTS

; ---------------------------------------------------------------------------
; report_reset — the last line the log carries.  It goes out before the
; terminal command, because after that there is no session to send down.
; D1.B = pin, D2.B = group.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
report_reset:
        MOVEM.L D0-D2/A0,-(SP)
        TST.B   VAR_PIPE_PRESENT
        BEQ.S   .rr_out
        LEA     (str_log_reset).L,A0
        BSR     pipe_puts
        MOVE.B  D2,D0
        BSR     log_dec
        LEA     (str_log_slash).L,A0
        BSR     pipe_puts
        MOVE.B  D1,D0
        BSR     log_dec
        TST.B   AUX_CAN_SWITCH
        BEQ.S   .rr_stay
        LEA     (str_log_slot).L,A0
        BSR     pipe_puts
        MOVE.B  AUX_SPARE_SLOT,D0
        BSR     log_dec
        BSR     log_crlf
        BRA.S   .rr_out
.rr_stay:
        LEA     (str_log_stay).L,A0
        BSR     log_line
.rr_out:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ===========================================================================
; The pins
;
; Group indices are not stable across boards, so the tester reads the count
; from GET_AUX_CAPABILITY and takes every group as the device describes it.  A
; pin is addressed by group*MAX_PINS+pin, in one word.
; ===========================================================================

; ---------------------------------------------------------------------------
; pins_discover — everything about the pins that does not change while the
; session is open.  A device with none goes to err_halt and does not come
; back.
; Clobbers (saved/restored): D0-D1
; ---------------------------------------------------------------------------
pins_discover:
        MOVEM.L D0-D1,-(SP)
        ; GET_AUX_CAPABILITY takes no argument bytes, so a device whose
        ; protocol version predates the auxiliary group fails it and stays in
        ; step.  Failure means no auxiliary pins here either way.
        BSR     rbcp_cmd_get_aux_cap
        TST.B   D0
        BNE.S   .pd_none
        MOVEQ   #2,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_AUX_CAP_MAX_HOLD).W,AUX_MAX_HOLD
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_AUX_CAP_GROUPS).W,D0
        BEQ.S   .pd_none
        CMPI.B  #MAX_GROUPS,D0
        BLS.S   .pd_fit
        MOVE.B  #1,AUX_TRUNCATED
        MOVEQ   #MAX_GROUPS,D0
.pd_fit:
        MOVE.B  D0,AUX_GROUP_COUNT
        BSR     read_groups
        TST.B   D0
        BNE.S   .pd_none
        BSR     pins_scan_all
        TST.B   D0
        BNE.S   .pd_lost
        BSR     report_groups
        MOVEM.L (SP)+,D0-D1
        RTS
.pd_none:
        MOVEQ   #ERR_NO_AUX,D0
        BRA     err_halt
.pd_lost:
        MOVEQ   #ERR_LOST,D0
        BRA     err_halt

; ---------------------------------------------------------------------------
; read_groups — the type and pin count of every group the tester will show.
;
; A pin count of zero means 256, which is more than this program draws, so it
; clamps and says so rather than wrapping to nothing.
; Output: D0=0 read, D0=1 the device refused a group it had just claimed
; Clobbers: D0
; ---------------------------------------------------------------------------
read_groups:
        MOVEM.L D1-D3/A0,-(SP)
        MOVEQ   #0,D2                   ; the group being asked about
.rg_loop:
        MOVE.B  D2,D0
        BSR     rbcp_cmd_get_aux_group_info
        TST.B   D0
        BNE.S   .rg_fail
        MOVEQ   #2,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVEQ   #0,D3
        MOVE.B  D2,D3
        LEA     (AUX_GROUP_TYPE).W,A0
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_AUX_GROUP_TYPE).W,(A0,D3.W)
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_AUX_GROUP_PINS).W,D0
        BEQ.S   .rg_clamp               ; zero means 256, past our limit
        CMPI.B  #MAX_PINS,D0
        BLS.S   .rg_store
.rg_clamp:
        MOVE.B  #1,AUX_TRUNCATED
        MOVE.B  #MAX_PINS,D0            ; MOVEQ would sign-extend this one
.rg_store:
        LEA     (AUX_GROUP_PINS).W,A0
        MOVE.B  D0,(A0,D3.W)
        ADDQ.B  #1,D2
        CMP.B   AUX_GROUP_COUNT,D2
        BCS.S   .rg_loop
        MOVEQ   #0,D0
        BRA.S   .rg_out
.rg_fail:
        MOVEQ   #1,D0
.rg_out:
        MOVEM.L (SP)+,D1-D3/A0
        RTS

; ---------------------------------------------------------------------------
; pins_index — D0.B = pin, D1.B = group.  Returns the table index in D0.W.
; Clobbers: D0
; ---------------------------------------------------------------------------
pins_index:
        MOVEM.L D1,-(SP)
        ANDI.W  #$00FF,D0
        ANDI.W  #$00FF,D1
        LSL.W   #MAX_PINS_SHIFT,D1
        ADD.W   D1,D0
        MOVEM.L (SP)+,D1
        RTS

; ---------------------------------------------------------------------------
; pins_scan — D0.B = group.  One GET_AUX_PIN_INFO per pin, into AUX_PIN_FLAGS
; and AUX_PIN_STATE, then that group's drivable list again.
;
; A group at this program's limit of 128 pins is 128 commands and about 42ms,
; two fields.  The keyboard is polled between pins so a press struck across
; one of those is still there afterwards.
; Output: D0=0 read, D0=1 the device stopped answering
; Clobbers: D0
; ---------------------------------------------------------------------------
pins_scan:
        MOVEM.L D1-D4/A0-A1,-(SP)
        MOVE.B  D0,D4                   ; group
        MOVEQ   #0,D3                   ; pin
        BSR     group_pins
        MOVE.B  D0,D2                   ; pins to walk
        MOVE.B  D4,D0
        TST.B   D2
        BEQ.S   .ps_done
.ps_loop:
        MOVE.B  D3,D0
        MOVE.B  D4,D1
        BSR     pins_read_one
        TST.B   D0
        BNE.S   .ps_fail
        BSR     key_poll
        ADDQ.B  #1,D3
        CMP.B   D2,D3
        BCS.S   .ps_loop
.ps_done:
        MOVE.B  D4,D0
        BSR     pins_rebuild_drv
        MOVEQ   #0,D0
        BRA.S   .ps_out
.ps_fail:
        MOVEQ   #1,D0
.ps_out:
        MOVEM.L (SP)+,D1-D4/A0-A1
        RTS

; ---------------------------------------------------------------------------
; pins_scan_all — every group, the same failure.
; Output: D0=0 read, D0=1 the device stopped answering
; Clobbers: D0
; ---------------------------------------------------------------------------
pins_scan_all:
        MOVEM.L D1,-(SP)
        MOVEQ   #0,D1
.psa_loop:
        MOVE.B  D1,D0
        BSR     pins_scan
        TST.B   D0
        BNE.S   .psa_out
        ADDQ.B  #1,D1
        CMP.B   AUX_GROUP_COUNT,D1
        BCS.S   .psa_loop
        MOVEQ   #0,D0
.psa_out:
        MOVEM.L (SP)+,D1
        RTS

; ---------------------------------------------------------------------------
; pins_rebuild_drv — D0.B = group.  Writes the numbers of that group's
; drivable pins into its slice of AUX_DRV_LIST and sets its drivable count.
;
; An image select group is a number, and a number reads with its lowest digit
; on the right, so its pins are listed highest first and the pads come out in
; that order.  Every other group counts up from the left.
; Clobbers (saved/restored): D0-D4/A0-A1
; ---------------------------------------------------------------------------
pins_rebuild_drv:
        MOVEM.L D0-D4/A0-A1,-(SP)
        MOVEQ   #0,D4
        MOVE.B  D0,D4                   ; group
        BSR     group_pins
        MOVEQ   #0,D2
        MOVE.B  D0,D2                   ; pins to walk
        MOVE.W  D4,D0
        LSL.W   #MAX_PINS_SHIFT,D0      ; the slice base
        LEA     (AUX_PIN_FLAGS).W,A0
        ADDA.W  D0,A0
        LEA     (AUX_DRV_LIST).W,A1
        ADDA.W  D0,A1
        MOVEQ   #0,D1                   ; drivable found so far

        MOVE.B  D4,D0
        BSR     group_type
        BSR     pins_reversed
        TST.B   D0
        BNE.S   .prd_back

        MOVEQ   #0,D3                   ; pin number, counting up
        TST.W   D2
        BEQ.S   .prd_done
.prd_up:
        MOVE.B  (A0,D3.W),D0
        ANDI.B  #RBCP_AUX_FLAG_DRIVABLE,D0
        BEQ.S   .prd_up_next
        MOVE.B  D3,(A1,D1.W)
        ADDQ.W  #1,D1
.prd_up_next:
        ADDQ.W  #1,D3
        CMP.W   D2,D3
        BCS.S   .prd_up
        BRA.S   .prd_done

.prd_back:
        MOVE.W  D2,D3                   ; one past the last pin
        BEQ.S   .prd_done
.prd_down:
        SUBQ.W  #1,D3
        MOVE.B  (A0,D3.W),D0
        ANDI.B  #RBCP_AUX_FLAG_DRIVABLE,D0
        BEQ.S   .prd_down_next
        MOVE.B  D3,(A1,D1.W)
        ADDQ.W  #1,D1
.prd_down_next:
        TST.W   D3
        BNE.S   .prd_down

.prd_done:
        LEA     (AUX_GROUP_DRV).W,A0
        MOVE.B  D1,(A0,D4.W)
        MOVEM.L (SP)+,D0-D4/A0-A1
        RTS

; ---------------------------------------------------------------------------
; group_type, group_pins, group_drv — D0.B = group.  Its type byte, the pins
; the device reports in it, and how many of those can be driven.
; Clobbers: D0
; ---------------------------------------------------------------------------
group_type:
        MOVEM.L D1/A0,-(SP)
        LEA     (AUX_GROUP_TYPE).W,A0
        BRA.S   group_fetch

group_pins:
        MOVEM.L D1/A0,-(SP)
        LEA     (AUX_GROUP_PINS).W,A0
        BRA.S   group_fetch

group_drv:
        MOVEM.L D1/A0,-(SP)
        LEA     (AUX_GROUP_DRV).W,A0
        ; fall through

group_fetch:
        MOVEQ   #0,D1
        MOVE.B  D0,D1
        MOVE.B  (A0,D1.W),D0
        MOVEM.L (SP)+,D1/A0
        TST.B   D0
        RTS

; ---------------------------------------------------------------------------
; pins_reversed — D0.B = group type.  Returns 1 where that group's pins are
; drawn right to left, which is every type whose pins read as a number with
; its low end on the right.
; Clobbers: D0
; ---------------------------------------------------------------------------
pins_reversed:
        CMPI.B  #RBCP_AUX_TYPE_IMGSEL,D0
        BEQ.S   .pr_yes
        CMPI.B  #RBCP_AUX_TYPE_XPADS,D0
        BEQ.S   .pr_yes
        MOVEQ   #0,D0
        RTS
.pr_yes:
        MOVEQ   #1,D0
        RTS

; ---------------------------------------------------------------------------
; pins_drv_at — D0.B = index into the group's drivable list, D1.B = group.
; Returns the pin number in D0.B.
; Clobbers: D0
; ---------------------------------------------------------------------------
pins_drv_at:
        MOVEM.L D1/A0,-(SP)
        ANDI.W  #$00FF,D0
        ANDI.W  #$00FF,D1
        LSL.W   #MAX_PINS_SHIFT,D1
        ADD.W   D1,D0
        LEA     (AUX_DRV_LIST).W,A0
        MOVE.B  (A0,D0.W),D0
        MOVEM.L (SP)+,D1/A0
        RTS

; ---------------------------------------------------------------------------
; pins_tier — D0.B = drivable pin count.  Returns the tier in D0.B: the
; largest pad that holds them all on the board.  A count past the last tier's
; capacity gets that tier anyway, and whoever filled the tables has already
; set AUX_TRUNCATED.
; Clobbers: D0
; ---------------------------------------------------------------------------
pins_tier:
        MOVEM.L D1-D2/A0,-(SP)
        LEA     (tier_cap).L,A0
        MOVEQ   #0,D1
.pt_try:
        MOVE.B  (A0,D1.W),D2
        CMP.B   D2,D0
        BLS.S   .pt_found
        ADDQ.W  #1,D1
        CMPI.W  #TIER_LAST,D1
        BCS.S   .pt_try
.pt_found:
        MOVE.B  D1,D0
        MOVEM.L (SP)+,D1-D2/A0
        RTS

; ---------------------------------------------------------------------------
; pins_set — D0.B = state, D1.B = pin, D2.B = group, with AUX_HOLD and
; AUX_AFTER.
; Output: D0=0 the device took it, D0=1 refused
; Clobbers: D0
; ---------------------------------------------------------------------------
pins_set:
        BSR     set_args
        BSR     rbcp_cmd_set_aux
        TST.B   D0
        RTS

; ---------------------------------------------------------------------------
; pins_set_exit — as pins_set, and terminal: the device writes no response
; header and nothing may be sent afterwards.
;
; This is the one to use where the pin stops the host, because a machine held
; in reset cannot poll for an answer.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
pins_set_exit:
        MOVEM.L D0,-(SP)
        BSR     set_args
        BSR     rbcp_cmd_set_aux_and_exit
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; pins_switch_exit — as pins_set_exit, and activates the spare RAM slot as
; well.
;
; Pin first, because the pin this is for is one that stops the host: the
; machine is held while the image underneath it changes.  Under that ordering
; the device does not apply after until the switch is done, so the hold lasts
; at least as long as the switch takes.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
pins_switch_exit:
        MOVEM.L D0,-(SP)
        BSR     set_args
        MOVE.B  RBCP_ARG4,RBCP_ARG5     ; group, one slot further along
        MOVE.B  RBCP_ARG3,RBCP_ARG4     ; pin
        MOVE.B  #RBCP_AUX_PIN_FIRST,RBCP_ARG3
        MOVE.B  AUX_SPARE_SLOT,RBCP_ARG6
        BSR     rbcp_cmd_set_aux_switch_exit
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; set_args — D0.B = state, D1.B = pin, D2.B = group into the SET_AUX argument
; layout, with the hold and the after state the tester is carrying.
; Clobbers: nothing
; ---------------------------------------------------------------------------
set_args:
        MOVE.B  D0,RBCP_ARG0            ; state
        MOVE.B  AUX_AFTER,RBCP_ARG1
        MOVE.B  AUX_HOLD,RBCP_ARG2
        MOVE.B  D1,RBCP_ARG3            ; pin
        MOVE.B  D2,RBCP_ARG4            ; group
        RTS

; ===========================================================================
; The keys
; ===========================================================================

; ---------------------------------------------------------------------------
; pin_next, pin_prev — one step along the drivable list, wrapping.  The cursor
; lives on that list, so a group with nothing drivable has nowhere for it to
; be and both keys do nothing.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
pin_next:
        MOVEM.L D0,-(SP)
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_drv
        BEQ.S   .pn_out
        ADDQ.B  #1,AUX_CUR_SLOT
        CMP.B   AUX_CUR_SLOT,D0
        BHI.S   .pn_out
        CLR.B   AUX_CUR_SLOT
.pn_out:
        MOVE.B  #1,AUX_FORCE            ; the bracket has moved, the pads have not
        BSR     draw_rings
        BSR     note_pin
        MOVEM.L (SP)+,D0
        RTS

pin_prev:
        MOVEM.L D0,-(SP)
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_drv
        BEQ.S   .pp_out
        TST.B   AUX_CUR_SLOT
        BNE.S   .pp_down
        MOVE.B  D0,AUX_CUR_SLOT
.pp_down:
        SUBQ.B  #1,AUX_CUR_SLOT
.pp_out:
        MOVE.B  #1,AUX_FORCE            ; as pin_next
        BSR     draw_rings
        BSR     note_pin
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; page_next, page_prev — one page per group of pins, and one more after them
; holding every pin at once.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
page_next:
        MOVEM.L D0,-(SP)
        ADDQ.B  #1,AUX_CUR_PAGE
        MOVE.B  AUX_GROUP_COUNT,D0
        CMP.B   AUX_CUR_PAGE,D0
        BCC.S   .pgn_changed            ; the all-pins page sits after the last
        CLR.B   AUX_CUR_PAGE
.pgn_changed:
        BSR     page_changed
        MOVEM.L (SP)+,D0
        RTS

page_prev:
        MOVEM.L D0,-(SP)
        TST.B   AUX_CUR_PAGE
        BNE.S   .pgp_down
        MOVE.B  AUX_GROUP_COUNT,D0
        ADDQ.B  #1,D0
        MOVE.B  D0,AUX_CUR_PAGE
.pgp_down:
        SUBQ.B  #1,AUX_CUR_PAGE
        BSR     page_changed
        MOVEM.L (SP)+,D0
        RTS

page_changed:
        CLR.B   AUX_CUR_SLOT
        BRA     paint_page

; ---------------------------------------------------------------------------
; drive — D0.B = the state to put the cursor's pin in.
; Clobbers (saved/restored): D0-D3
; ---------------------------------------------------------------------------
drive:
        MOVEM.L D0-D3,-(SP)
        MOVE.B  D0,D3                   ; the state, across the check
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_drv
        BNE.S   .dr_have
        MOVEQ   #NOTE_NOT_DRIVABLE,D0
        BSR     draw_note
        BRA.S   .dr_out
.dr_have:
        MOVE.B  AUX_CUR_SLOT,D0
        MOVE.B  AUX_CUR_GROUP,D1
        BSR     pins_drv_at
        MOVE.B  D0,D1                   ; pin
        MOVE.B  AUX_CUR_GROUP,D2        ; group
        MOVE.B  D3,D0                   ; state
        BSR     pins_set
        MOVE.B  D0,D3                   ; what came back
        MOVE.B  RBCP_ARG0,D0
        MOVE.B  RBCP_ARG3,D1
        MOVE.B  RBCP_ARG4,D2
        BSR     report_set
        TST.B   D3
        BEQ.S   .dr_ok
        MOVEQ   #NOTE_REFUSED,D0
        BSR     draw_note
        BRA.S   .dr_out
.dr_ok:
        ; The pin's new state is on screen at the next field, because
        ; scan_slice reads the cursor's pin before any other.
.dr_out:
        MOVEM.L (SP)+,D0-D3
        RTS

; ---------------------------------------------------------------------------
; blink — drives the cursor's pin high and low until a key is pressed.
;
; Two commands a cycle with no hold, and the wait between them is the
; tester's.  A hold would have the device time the high half and answer only
; once it was over, which is exactly the half of it nobody could then see.
; Clobbers (saved/restored): D0-D3
; ---------------------------------------------------------------------------
blink:
        MOVEM.L D0-D3,-(SP)
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_drv
        BNE.S   .bl_have
        MOVEQ   #NOTE_NOT_DRIVABLE,D0
        BSR     draw_note
        BRA.S   .bl_out
.bl_have:
        MOVEQ   #NOTE_BLINKING,D0
        BSR     draw_note
.bl_cycle:
        MOVE.B  AUX_BLINK_PHASE,D0
        EORI.B  #1,D0
        MOVE.B  D0,AUX_BLINK_PHASE
        BNE.S   .bl_high
        MOVEQ   #RBCP_AUX_LOW,D3
        BRA.S   .bl_send
.bl_high:
        MOVEQ   #RBCP_AUX_HIGH,D3
.bl_send:
        MOVE.B  AUX_CUR_SLOT,D0
        MOVE.B  AUX_CUR_GROUP,D1
        BSR     pins_drv_at
        MOVE.B  D0,D1
        MOVE.B  AUX_CUR_GROUP,D2
        MOVE.B  D3,D0
        BSR     pins_set
        TST.B   D0
        BNE.S   .bl_stop                ; it will not take the next one either
        BSR     blink_wait              ; the fields it waits draw the pin
        TST.B   D0
        BEQ.S   .bl_cycle
.bl_stop:
        BSR     note_pin
.bl_out:
        MOVEM.L (SP)+,D0-D3
        RTS

; ---------------------------------------------------------------------------
; blink_wait — half a second, or until something is pressed.  Twenty five
; fields is half a second on PAL and a little over four tenths on NTSC.
;
; The wait is spent in the ordinary field loop, so the pins carry on being
; read and drawn while the pin under the cursor blinks.  A pin wired to the
; blinking one is therefore seen following it.  That loop polls the keyboard
; every field, which it has to, because a press left unread for the length of
; the wait does not appear until the wait ends.
; Output: D0.B = the key that cut the wait short, 0 where it ran out
; Clobbers: D0
; ---------------------------------------------------------------------------
blink_wait:
        MOVEM.L D1,-(SP)
        MOVEQ   #25-1,D1
.bw_field:
        BSR     live_tick
        TST.B   D0
        BNE.S   .bw_out
        DBF     D1,.bw_field
        MOVEQ   #0,D0
.bw_out:
        MOVEM.L (SP)+,D1
        RTS

; ===========================================================================
; The reset screen
;
; The one terminal thing this program can do, behind a screen that says so.
; RETURN goes, Z backs out.
;
; The pin is driven low and released afterwards, never driven high.  The line
; this is for is one the host pulls up itself, and a 3V3 pin driving into it
; would be wrong on every board that has one.
;
; A machine held in reset cannot poll for an answer, so the pin goes out on a
; terminal command.  Where the device has a spare RAM slot and an image to put
; in it, the same command activates that image and the machine comes back as
; something else.  Where it has not, the machine comes back as this program.
; ===========================================================================

show_reset:
        MOVEM.L D0-D2,-(SP)
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_drv
        BNE.S   .sr_have
        MOVEQ   #NOTE_NOT_DRIVABLE,D0
        BSR     draw_note
        BRA     .sr_out
.sr_have:
        ; A pulse the device will not time is a pin driven low and left there,
        ; and a machine that never comes out of reset.
        BSR     reset_hold
        BNE.S   .sr_pulse
        MOVEQ   #NOTE_NO_PULSE,D0
        BSR     draw_note
        BRA     .sr_out
.sr_pulse:
        MOVE.B  AUX_CUR_SLOT,D0
        MOVE.B  AUX_CUR_GROUP,D1
        BSR     pins_drv_at
        MOVE.B  D0,AUX_RESET_PIN
        CLR.B   AUX_RESET_FLASH
        BSR     reset_screen
.sr_wait:
        BSR     amiga_getkey
        TST.B   D0
        BEQ.S   .sr_wait
        CMPI.B  #KEY_RETURN,D0
        BEQ.S   .sr_go
        CMPI.B  #KEY_DOWN,D0
        BEQ.S   .sr_pick
        ORI.B   #$20,D0
        CMPI.B  #KEY_RELEASE,D0
        BNE.S   .sr_wait                ; a key with no meaning here does nothing
        BSR     paint_page
        BRA.S   .sr_out
.sr_pick:
        TST.B   AUX_CAN_SWITCH
        BEQ.S   .sr_wait                ; there is no choice to make
        BSR     next_image
        BSR     reset_screen
        BRA.S   .sr_wait
.sr_go:
        BSR     do_reset
.sr_out:
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; reset_hold — how long the reset pulse asks the device to hold the pin, in
; the 10ms units the protocol counts holds in.  RESET_HOLD, or the most the
; device says it will take where that is less.
; Output: D0.B = the hold, zero where the device times none at all
; Clobbers: D0
; ---------------------------------------------------------------------------
reset_hold:
        MOVE.B  AUX_MAX_HOLD,D0
        BEQ.S   .rh_out
        CMPI.B  #RESET_HOLD,D0
        BCS.S   .rh_out
        MOVEQ   #RESET_HOLD,D0
.rh_out:
        TST.B   D0
        RTS

; ---------------------------------------------------------------------------
; next_image — the flash slot after the one showing, wrapping.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
next_image:
        MOVEM.L D0,-(SP)
        MOVE.B  AUX_RESET_FLASH,D0
        ADDQ.B  #1,D0
        CMP.B   AUX_FLASH_COUNT,D0
        BCS.S   .ni_take
        MOVEQ   #0,D0
.ni_take:
        MOVE.B  D0,AUX_RESET_FLASH
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; do_reset — the pin, and the image to come back as, in one command.
;
; Anything that has to follow a slot switch belongs in the same command as the
; switch: afterwards the served image is another one, with a back channel of
; its own wherever it chose to put it.
;
; Returns only where the load was refused, in which case nothing was sent.
; ---------------------------------------------------------------------------
do_reset:
        TST.B   AUX_CAN_SWITCH
        BEQ.S   .dr_armed
        MOVE.B  AUX_RESET_FLASH,D0
        BSR     load_spare
        TST.B   D0
        BEQ.S   .dr_armed
        MOVEQ   #NOTE_REFUSED,D0
        BSR     draw_note
        RTS
.dr_armed:
        BSR     reset_hold
        MOVE.B  D0,AUX_HOLD
        MOVE.B  #RBCP_AUX_RELEASE,AUX_AFTER
        MOVE.B  AUX_RESET_PIN,D1
        MOVE.B  AUX_CUR_GROUP,D2
        BSR     report_reset
        MOVEQ   #RBCP_AUX_LOW,D0
        TST.B   AUX_CAN_SWITCH
        BEQ.S   .dr_stay
        BSR     pins_switch_exit
        BRA.S   .dr_sent
.dr_stay:
        BSR     pins_set_exit
.dr_sent:
        MOVEQ   #NOTE_GONE,D0
        BSR     draw_note
.dr_halt:
        BRA.S   .dr_halt

; ===========================================================================
; The screen
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
        BSR     plain_pens
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_title_at — D2.B = row.  The heading, which err_halt draws on the error
; screen.
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
; plain_pens — back to text on background, after a band or a pad.
; Clobbers: nothing
; ---------------------------------------------------------------------------
plain_pens:
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        RTS

; ---------------------------------------------------------------------------
; draw_device_row — what the device calls itself, each part cut to the space
; it has.  Drawn from the buffers read while the session was opening.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_device_row:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #COL_DEV_VER-1,VAR_COL_MAX
        LEA     (AUX_DEV_TYPE).W,A0
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_DEVICE,D2
        BSR     screen_print
        MOVE.B  #COL_DEV_PROTO-1,VAR_COL_MAX
        LEA     (AUX_DEV_VER).W,A0
        MOVE.B  #COL_DEV_VER,D1
        BSR     screen_print
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        LEA     (AUX_PROTO).W,A0
        MOVE.B  #COL_DEV_PROTO,D1
        BSR     screen_print
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_keys — the two rows of key names along the bottom.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_keys:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_keys1).L,A0
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_KEYS1,D2
        BSR     screen_print
        LEA     (str_keys2).L,A0
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_KEYS2,D2
        BSR     screen_print
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEM.L (SP)+,D0-D2/A0
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

; ---------------------------------------------------------------------------
; band_row — D2.B = row.  Turns the heading band over, from the group name to
; the end of the page count, so the heading reads as one thing rather than two
; facts at opposite ends of a line.  The width is fixed, so the reset screen
; gets the same band as every other page although it has no page count.  The
; pens are left on the band for the text that goes over it.
; Clobbers (saved/restored): D0-D1/D3
; ---------------------------------------------------------------------------
band_row:
        MOVEM.L D0/D1/D3,-(SP)
        MOVE.B  #PEN_BG,VAR_PEN
        MOVE.B  #PEN_GOLD,VAR_PEN_BG
        MOVE.B  #COL_GROUP,D1
        MOVEQ   #BAND_WIDTH-1,D3
.br_cell:
        MOVEQ   #' ',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
        DBF     D3,.br_cell
        MOVEM.L (SP)+,D0/D1/D3
        RTS

; ---------------------------------------------------------------------------
; clear_page — the rows a page owns, back to background: the heading band down
; to the note.  The title, the device line and the two key rows stand outside
; that span and read the same on every page.
;
; The blitter does it, so the gap between a page going and the next one
; arriving is the drawing alone.
; Clobbers (saved/restored): D0-D2
; ---------------------------------------------------------------------------
clear_page:
        MOVEM.L D0-D2,-(SP)
        MOVE.B  #PEN_BG,D0
        MOVE.W  #ROW_GROUP*8,D1
        MOVE.W  #(ROW_NOTE+1-ROW_GROUP)*8,D2
        BSR     pix_band
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; paint_page — the whole of the page AUX_CUR_PAGE names.
;
; The pins are read before anything on screen changes, so what the reader sees
; is one page and then the next, and not a blank screen for as long as it
; takes to ask the device.  A page is cleared before it is drawn, because one
; that painted only its own parts would leave whatever the last page put in
; the rows it does not use.
;
; The pieces go down in the order the beam reaches them, so the rebuild is
; running ahead of the display rather than across it.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
paint_page:
        MOVEM.L D0,-(SP)
        MOVE.B  AUX_CUR_PAGE,D0
        CMP.B   AUX_GROUP_COUNT,D0
        BCC.S   .pp_all
        MOVE.B  D0,AUX_CUR_GROUP
        BSR     pins_scan
        TST.B   D0
        BNE.S   .pp_lost
        BSR     clear_page
        BSR     pins_repaint
        BSR     draw_group_head
        BSR     draw_rate
        BSR     draw_legend
        BSR     draw_rings
        BSR     note_pin
        BRA.S   .pp_out
.pp_all:
        BSR     pins_scan_all
        TST.B   D0
        BNE.S   .pp_lost
        BSR     clear_page
        BSR     pins_repaint
        BSR     draw_all_head
        BSR     draw_rate
        BSR     draw_legend
        BSR     draw_all
        MOVEQ   #NOTE_BLANK,D0
        TST.B   AUX_TRUNCATED
        BEQ.S   .pp_note
        MOVEQ   #NOTE_TRUNCATED,D0
.pp_note:
        BSR     draw_note
.pp_out:
        MOVEM.L (SP)+,D0
        RTS
.pp_lost:
        MOVEQ   #ERR_LOST,D0
        BRA     err_halt

; ---------------------------------------------------------------------------
; draw_group_head — the group's name, which page of how many, and how many of
; its pins can be driven.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_group_head:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #ROW_GROUP,D2
        BSR     band_row
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_type
        BSR     type_name
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_GROUP,D2
        BSR     screen_print
        BSR     draw_page_of
        BSR     plain_pens

        ; "n OF m PINS CAN BE DRIVEN"
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_COUNT,D2
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_drv
        BSR     print_dec
        ADDQ.B  #1,D1
        LEA     (str_of).L,A0
        BSR     screen_print
        ADDQ.B  #3,D1
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_pins
        BSR     print_dec
        ADDQ.B  #1,D1
        LEA     (str_drivable).L,A0
        BSR     screen_print
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_all_head — the same band over the page holding every pin at once.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_all_head:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #ROW_GROUP,D2
        BSR     band_row
        LEA     (str_all_title).L,A0
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_GROUP,D2
        BSR     screen_print
        BSR     draw_page_of
        BSR     plain_pens
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_page_of — "n OF m" at the right of the heading band.  There is one page
; per group of pins and one more after them holding every pin at once, and
; this is what says which of them is on screen.  The pens are the band's, set
; by the caller.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_page_of:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #COL_OF,D1
        MOVE.B  #ROW_GROUP,D2
        MOVE.B  AUX_CUR_PAGE,D0
        ADDQ.B  #1,D0
        BSR     print_dec
        ADDQ.B  #1,D1
        LEA     (str_of).L,A0
        BSR     screen_print
        ADDQ.B  #3,D1
        MOVE.B  AUX_GROUP_COUNT,D0
        ADDQ.B  #1,D0                   ; the all-pins page is one past the last
        BSR     print_dec
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; type_name — D0.B = group type.  Returns what to call it in A0.  A type
; outside the tables is shown as "OTHER PINS" rather than guessed at, which is
; what a host is supposed to do with a value it has never seen.
; Clobbers: A0
; ---------------------------------------------------------------------------
type_name:
        CMPI.B  #RBCP_AUX_TYPE_GPIO,D0
        BNE.S   .tn_imgsel
        LEA     (str_gpio).L,A0
        RTS
.tn_imgsel:
        CMPI.B  #RBCP_AUX_TYPE_IMGSEL,D0
        BNE.S   .tn_xpads
        LEA     (str_imgsel).L,A0
        RTS
.tn_xpads:
        CMPI.B  #RBCP_AUX_TYPE_XPADS,D0
        BNE.S   .tn_none
        LEA     (str_xpads).L,A0
        RTS
.tn_none:
        CMPI.B  #RBCP_AUX_TYPE_NONE,D0
        BNE.S   .tn_other
        LEA     (str_none).L,A0
        RTS
.tn_other:
        LEA     (str_other).L,A0
        RTS

; ---------------------------------------------------------------------------
; note_pin — the line under the pads.  A group with nothing drivable says so,
; a device reporting more than this screen shows says that, and otherwise
; nothing is said at all.  The pads are the answer and a sentence repeating
; them is noise.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
note_pin:
        MOVEM.L D0,-(SP)
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_drv
        BNE.S   .np_drv
        MOVEQ   #NOTE_NO_DRIVE,D0
        BRA.S   .np_say
.np_drv:
        MOVEQ   #NOTE_BLANK,D0
        TST.B   AUX_TRUNCATED
        BEQ.S   .np_say
        MOVEQ   #NOTE_TRUNCATED,D0
.np_say:
        BSR     draw_note
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; draw_note — D0.B = a NOTE_ code.  The one line of plain English on the
; screen.  It is the only place the program explains itself.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
draw_note:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  D0,D2
        MOVEQ   #ROW_NOTE,D0
        BSR     clear_row
        ANDI.W  #$00FF,D2
        BEQ.S   .dn_out
        CMPI.W  #NOTE_COUNT,D2
        BCC.S   .dn_out
        LSL.W   #2,D2
        LEA     (note_msgs).L,A0
        MOVEA.L (A0,D2.W),A0
        MOVE.B  #PEN_NOTE,VAR_PEN
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_NOTE,D2
        BSR     screen_print
        MOVE.B  #PEN_TEXT,VAR_PEN
.dn_out:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; put_pin_label — D0.B = pin number, D1.B = column, D2.B = row, the group in
; AUX_CUR_GROUP.
;
; An image select pin is named by letter, because that is what a One ROM calls
; its pads and what the board is silkscreened with.  An X pad is called X1
; upwards rather than X0.  Everything else is numbered as the device numbers
; it.  D1 comes back past the label either way.
; Clobbers: D1
; ---------------------------------------------------------------------------
put_pin_label:
        MOVEM.L D0/D3,-(SP)
        MOVE.B  D0,D3
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_type
        CMPI.B  #RBCP_AUX_TYPE_IMGSEL,D0
        BEQ.S   .ppl_letter
        CMPI.B  #RBCP_AUX_TYPE_XPADS,D0
        BNE.S   .ppl_plain
        ADDQ.B  #1,D3
.ppl_plain:
        MOVE.B  D3,D0
        BSR     print_dec
        BRA.S   .ppl_out
.ppl_letter:
        MOVE.B  D3,D0
        ADDI.B  #'A',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
.ppl_out:
        MOVEM.L (SP)+,D0/D3
        RTS

; ---------------------------------------------------------------------------
; print_dec — D0.B = value, D1.B = column, D2.B = row.  One to three digits
; with no leading zero, and D1 comes back past them.
; Clobbers: D1
; ---------------------------------------------------------------------------
print_dec:
        MOVEM.L D0/D3-D5,-(SP)
        MOVEQ   #0,D3                   ; hundreds
        MOVEQ   #0,D4                   ; tens
        MOVE.B  D0,D5                   ; and what is left is the units
.pdc_h:
        CMPI.B  #100,D5
        BCS.S   .pdc_t
        SUBI.B  #100,D5
        ADDQ.B  #1,D3
        BRA.S   .pdc_h
.pdc_t:
        CMPI.B  #10,D5
        BCS.S   .pdc_write
        SUBI.B  #10,D5
        ADDQ.B  #1,D4
        BRA.S   .pdc_t
.pdc_write:
        TST.B   D3
        BEQ.S   .pdc_tens_q
        MOVE.B  D3,D0
        ADDI.B  #'0',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
        BRA.S   .pdc_tens
.pdc_tens_q:
        TST.B   D4
        BEQ.S   .pdc_units
.pdc_tens:
        MOVE.B  D4,D0
        ADDI.B  #'0',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
.pdc_units:
        MOVE.B  D5,D0
        ADDI.B  #'0',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
        MOVEM.L (SP)+,D0/D3-D5
        RTS

; ---------------------------------------------------------------------------
; print_dec_w — D0.W = value, D1.B = column, D2.B = row.  One to five digits
; with no leading zero, and D1 comes back past them.
;
; print_dec reads a byte and the timer's figures run past one.
; Clobbers: D1
; ---------------------------------------------------------------------------
print_dec_w:
        MOVEM.L D0/D3-D4/A0,-(SP)
        LEA     (AUX_DEC_BUF).W,A0
        ANDI.L  #$0000FFFF,D0
        MOVEQ   #0,D3                   ; digits, lowest first
.pdw_digit:
        DIVU    #10,D0                  ; quotient low, remainder high
        MOVE.L  D0,D4
        SWAP    D4
        ADDI.B  #'0',D4
        MOVE.B  D4,(A0,D3.W)
        ADDQ.W  #1,D3
        ANDI.L  #$0000FFFF,D0
        BNE.S   .pdw_digit
.pdw_put:
        SUBQ.W  #1,D3
        MOVE.B  (A0,D3.W),D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
        TST.W   D3
        BNE.S   .pdw_put
        MOVEM.L (SP)+,D0/D3-D4/A0
        RTS

; ---------------------------------------------------------------------------
; reset_screen — the exit and reset page, drawn over the pads.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
reset_screen:
        MOVEM.L D0-D2/A0,-(SP)
        TST.B   AUX_CAN_SWITCH
        BEQ.S   .rsc_draw
        MOVE.B  AUX_RESET_FLASH,D0
        BSR     read_flash_name
.rsc_draw:
        BSR     clear_rings
        MOVEQ   #ROW_COUNT,D0
        BSR     clear_row
        MOVE.B  #ROW_GROUP,D2
        BSR     band_row
        LEA     (str_r_title).L,A0
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_GROUP,D2
        BSR     screen_print
        BSR     plain_pens

        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_r_pin).L,A0
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_R_PIN,D2
        BSR     screen_print
        LEA     (str_r_hold).L,A0
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_R_HOLD,D2
        BSR     screen_print
        LEA     (str_r_image).L,A0
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_R_IMAGE,D2
        BSR     screen_print
        MOVE.B  #PEN_TEXT,VAR_PEN

        MOVE.B  #COL_R_VAL,D1
        MOVE.B  #ROW_R_PIN,D2
        MOVE.B  AUX_RESET_PIN,D0
        BSR     put_pin_label

        MOVE.B  #COL_R_VAL,D1
        MOVE.B  #ROW_R_HOLD,D2
        BSR     reset_hold
        MULU    #10,D0                  ; the hold, in milliseconds
        BSR     print_dec
        ADDQ.B  #1,D1
        LEA     (str_r_ms).L,A0
        BSR     screen_print

        MOVE.B  #COL_R_VAL,D1
        MOVE.B  #ROW_R_IMAGE,D2
        TST.B   AUX_CAN_SWITCH
        BEQ.S   .rsc_stay
        LEA     (AUX_FLASH_NAME).W,A0
        BSR     screen_print
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_r_pick).L,A0
        MOVE.B  #COL_R_VAL,D1
        MOVE.B  #ROW_R_IMAGE+1,D2
        BSR     screen_print
        BRA.S   .rsc_ends
.rsc_stay:
        LEA     (str_r_stay).L,A0
        BSR     screen_print
.rsc_ends:
        MOVE.B  #PEN_NOTE,VAR_PEN
        LEA     (str_r_ends).L,A0
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_R_ENDS,D2
        BSR     screen_print
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_r_keys).L,A0
        MOVE.B  #COL_GROUP,D1
        MOVE.B  #ROW_R_ENDS+2,D2
        BSR     screen_print
        MOVE.B  #PEN_TEXT,VAR_PEN

        MOVEQ   #NOTE_BLANK,D0
        BSR     draw_note
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ============================================================
; The pins on the screen (run from RAM)
; ============================================================
        INCLUDE "../amiga-common/amiga_blit.s"
        INCLUDE "amiga_auxio_pix.s"
        INCLUDE "amiga_auxio_pins.s"

; ============================================================
; The command timer (runs from RAM)
; ============================================================
        INCLUDE "amiga_auxio_time.s"

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
        DC.B    "RBCP AUX I/O "
        APP_VERSION
        DC.B    0
        EVEN
str_brand:
        DC.B    "PIERS.ROCKS",0

        INCLUDE "../amiga-common/amiga_error_data.s"
        INCLUDE "../amiga-common/amiga_log_data.s"
        INCLUDE "../amiga-common/amiga_diag_data.s"
        INCLUDE "../amiga-common/amiga_input_data.s"
        INCLUDE "amiga_auxio_art.s"

; ---------------------------------------------------------------------------
; Words on the screen
; ---------------------------------------------------------------------------
        EVEN
str_of:
        DC.B    "OF",0
        EVEN
str_pins:
        DC.B    "PINS",0
        EVEN
str_drivable:
        DC.B    "PINS CAN BE DRIVEN",0
        EVEN
str_all_title:
        DC.B    "ALL PINS",0
        EVEN
str_keys1:
        DC.B    "CRSR MOVES  [ ] PAGE  R RESET  T TIME",0
        EVEN
str_keys2:
        DC.B    "L LOW  H HIGH  Z REL  B BLINK",0

; The group types, as the screen names them.
        EVEN
str_gpio:
        DC.B    "GPIO",0
        EVEN
str_imgsel:
        DC.B    "IMAGE SELECT",0
        EVEN
str_xpads:
        DC.B    "X PINS",0
        EVEN
str_none:
        DC.B    "UNSORTED PINS",0
        EVEN
str_other:
        DC.B    "OTHER PINS",0

; The reset screen.
        EVEN
str_r_title:
        DC.B    "EXIT AND RESET",0
        EVEN
str_r_pin:
        DC.B    "SELECTED PIN",0
        EVEN
str_r_hold:
        DC.B    "HELD LOW FOR",0
        EVEN
str_r_ms:
        DC.B    "MS, THEN RELEASED",0
        EVEN
str_r_image:
        DC.B    "COMES BACK AS",0
        EVEN
str_r_stay:
        DC.B    "THIS PROGRAM AGAIN",0
        EVEN
str_r_pick:
        DC.B    "CRSR DOWN PICKS ANOTHER",0
        EVEN
str_r_ends:
        DC.B    "THIS ENDS THE PROGRAM",0
        EVEN
str_r_keys:
        DC.B    "RETURN RESETS, Z BACKS OUT",0

; The note row, in the order amiga_defs.s numbers the codes.  Entry 0 is the
; blank one and never reaches the screen.
        EVEN
note_msgs:
        DC.L    0
        DC.L    msg_no_drive,msg_blinking,msg_refused
        DC.L    msg_not_drivable,msg_truncated,msg_gone
        DC.L    msg_no_pulse
        EVEN
msg_no_drive:
        DC.B    "EVERY PIN HERE IS IN USE BY THE ROM",0
        EVEN
msg_blinking:
        DC.B    "BLINKING - ANY KEY STOPS",0
        EVEN
msg_refused:
        DC.B    "THE DEVICE REFUSED THAT",0
        EVEN
msg_not_drivable:
        DC.B    "THAT PIN IS NOT THE AMIGA'S TO DRIVE",0
        EVEN
msg_truncated:
        DC.B    "MORE PINS THAN THIS SCREEN SHOWS",0
        EVEN
msg_gone:
        DC.B    "SENT - THE SESSION IS OVER",0
        EVEN
msg_no_pulse:
        DC.B    "THIS DEVICE CANNOT TIME A PULSE",0

; The reasons a session ends where it started, in the order amiga_defs.s
; numbers them.
        EVEN
err_msgs:
        DC.L    msg_err_0,msg_err_1,msg_err_2,msg_err_3,msg_err_4
        EVEN
msg_err_0:
        DC.B    "NO DEVICE ANSWERED THE KNOCK",0
        EVEN
msg_err_1:
        DC.B    "THE DEVICE REFUSED THE SESSION",0
        EVEN
msg_err_2:
        DC.B    "THE DEVICE'S VERSION IS INCOMPATIBLE",0
        EVEN
msg_err_3:
        DC.B    "THIS DEVICE HAS NO PINS TO DRIVE",0
        EVEN
msg_err_4:
        DC.B    "THE DEVICE STOPPED ANSWERING",0

; ---------------------------------------------------------------------------
; Words on the wire.  These go down the pipe and never reach a screen.
; ---------------------------------------------------------------------------
        EVEN
str_log_start:
        DC.B    "RBCP AUX I/O START "
        APP_VERSION
        DC.B    0
        EVEN
str_log_group:
        DC.B    "GROUP ",0
        EVEN
str_log_type:
        DC.B    " TYPE ",0
        EVEN
str_log_pins:
        DC.B    " PINS ",0
        EVEN
str_log_drv:
        DC.B    " DRIVABLE ",0
        EVEN
str_log_set:
        DC.B    "SET ",0
        EVEN
str_log_slash:
        DC.B    "/",0
        EVEN
str_log_taken:
        DC.B    " TAKEN",0
        EVEN
str_log_refused:
        DC.B    " REFUSED",0
        EVEN
str_log_reset:
        DC.B    "RESET ",0
        EVEN
str_log_slot:
        DC.B    " RAM SLOT ",0
        EVEN
str_log_stay:
        DC.B    " NO SWITCH",0

; The three states a pin can be put in, in the order the protocol numbers
; them.
        EVEN
state_names:
        DC.L    str_st_low,str_st_high,str_st_rel
        EVEN
str_st_low:
        DC.B    " LOW",0
        EVEN
str_st_high:
        DC.B    " HIGH",0
        EVEN
str_st_rel:
        DC.B    " RELEASED",0

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
