; amiga_boot.s — Amiga RBCP Kickstart bootloader
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Lets an Amiga pick which Kickstart image it boots from those held on the
; RBCP device serving its ROM socket.  It enters command-response mode, reads
; what the device holds, and boots the remembered or default image at once.
; Holding both mouse buttons at boot brings up a menu instead.  See README.md
; for the controls, the display and what has been tested on hardware.
;
; Build:
;   make            (see Makefile)
;
; ROM image layout (top-aligned; 256 KB from $FC0000 or 512 KB from $F80000):
;
;   ROM SECTION  — executed directly from ROM
;     ROM header, boot_cold_start, JMP boot_rom_entry
;     amiga_hw.s: a500_hw_init, exc_halt, screen_init
;     boot_rom_entry: HW init, screen up, copy RAM section, JMP $8000
;
;   RAM SECTION  — stored in ROM, copied to RAM_CODE_BASE ($8000) at boot
;     boot_ram_entry: the RBCP session
;     rbcp.s: RBCP protocol library
;     Screen rendering and hex output
;
;   ROM DATA SECTION — referenced via absolute long addresses from RAM code
;     copper_template, font_data, strings
;
;   $FFFC00  back-channel region (512 bytes, zeroed)
;   $FFFE00  command page        (512 bytes, zeroed)
;
; Why the split?
;   The knock and command sequences work by triggering specific ROM address
;   reads.  If the code performing them is itself fetched from that ROM, the
;   instruction-fetch addresses land on the bus and corrupt the sequence the
;   device sees.  Running from chip RAM removes all ROM instruction fetches
;   during the critical windows.
;
;   Once command-response mode is established the device filters on the
;   command page, so ROM reads elsewhere become harmless — which is why the
;   screen routines (which read the font from ROM) may be called after entry,
;   but never between the knock and the response to ENTER_CMD_RESP.
;
;   The initial hardware setup runs from ROM because it must execute before
;   the RAM section is copied.  It performs no RBCP address sequences.
;
; Addressing note:
;   RAM-section code reaches ROM data through explicit absolute long
;   addressing — LEA (label).L,A0 — never PC-relative.  The code is
;   assembled at its ROM address but executes from $8000, so a PC-relative
;   displacement computed at assembly time resolves to the wrong place at
;   run time.  The .L suffix also stops the assembler shortening high
;   addresses to sign-extended absolute short, which works on a 68000's
;   24-bit bus but not on a 32-bit one.

; Definitions first — the ORG below depends on CONFIG_ROM_BASE.  None of
; these emit any code or data.
        INCLUDE "rbcp_config.s"
        INCLUDE "../rbcp/rbcp_defs.s"
        INCLUDE "amiga_defs.s"

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
        DC.L    boot_cold_start         ; initial PC

        DCB.B   $D0-(*-ROMStart),$00    ; pad to offset $D0

        RESET                           ; +$D0: soft-reset entry
boot_cold_start:                        ; +$D2: CPU jumps here on power-on
        JMP     boot_rom_entry

; ---------------------------------------------------------------------------
; ROM-section hardware routines: a500_hw_init, exc_halt, screen_init
; screen_init contains a forward BSR to screen_clear in the RAM section; both
; are in ROM at assembly time so the PC-relative branch is correct there.
; ---------------------------------------------------------------------------
        INCLUDE "amiga_hw.s"

; ---------------------------------------------------------------------------
; boot_rom_entry — runs from ROM
;
; 1. Clear OVL so chip RAM appears at $0, then set the stack
; 2. Hardware init (chipset silent, exception vectors)
; 3. Bring up the display
; 4. Copy the RAM section from ROM to chip RAM at RAM_CODE_BASE
; 5. JMP to RAM_CODE_BASE = boot_ram_entry
; ---------------------------------------------------------------------------
boot_rom_entry:
        MOVE.W  #COL_RED,COLOR00
        MOVE.B  #$03,CIAA_DDRA      ; clear OVL — chip RAM now at $0
        MOVE.B  #$02,CIAA_PRA
        MOVEA.L #STACK_TOP,SP       ; SP set AFTER OVL cleared
        BSR     a500_hw_init
        MOVE.W  #COL_YELLOW,COLOR00

        BSR     screen_init
        BSR     kbd_init            ; CIA-A serial port to keyboard input

        ; Copy the RAM section (stored in the ROM image) to chip RAM
        LEA     (ram_section_rom_start).L,A0
        MOVEA.L #RAM_CODE_BASE,A1
        MOVE.W  #(ram_section_rom_end-ram_section_rom_start)/2-1,D0
.broe_copy:
        MOVE.W  (A0)+,(A1)+
        DBF     D0,.broe_copy

        ; boot_ram_entry is at offset 0 from ram_section_rom_start, so
        ; RAM_CODE_BASE is its exact address in chip RAM.
        JMP     RAM_CODE_BASE

; ============================================================
; RAM SECTION
; Stored in the ROM image between ram_section_rom_start and
; ram_section_rom_end, copied word-by-word to RAM_CODE_BASE ($8000).
;
; boot_ram_entry is at offset 0 so JMP RAM_CODE_BASE enters it directly.
;
; All BSR/BRA within this section are PC-relative and the distances between
; instructions are identical in ROM and in the RAM copy, so they resolve
; correctly from $8000.  References OUT of this section — to ROM data — use
; absolute long addressing.
; ============================================================
ram_section_rom_start:

; ---------------------------------------------------------------------------
; boot_ram_entry — the bootloader proper, running from chip RAM
;
; Enter command-response mode, learn what the device holds, and boot the
; remembered or default image at once.  Holding both mouse buttons at boot
; brings up a numbered menu instead, where a left click or the arrows change
; the choice and a right click or RETURN boots it.  Logging, the RGB LED and
; the remembered choice each follow the device's capabilities.
;
; A device with a single RAM slot (a 27C400, or a 27C200 on some boards)
; cannot stage a load in a spare slot, so it boots with LOAD_AND_EXIT into the
; active slot instead, and cannot remember a choice.
; ---------------------------------------------------------------------------
boot_ram_entry:
        MOVE.W  #COL_GREEN,COLOR00
        BSR     screen_clear

        BSR     rbcp_reset
        BSR     rbcp_cmd_enter_cmd_resp
        TST.B   D0
        BEQ.S   .ok_enter
        MOVEQ   #ERR_NO_CMD_RESP,D0
        BRA     err_halt
.ok_enter:
        BSR     rbcp_check_protocol_version
        TST.B   D0
        BEQ.S   .ok_ver
        MOVEQ   #ERR_VERSION,D0
        BRA     err_halt
.ok_ver:
        ; --- RAM slots: they decide how the boot switch works ---
        BSR     rbcp_cmd_get_ram_info_all
        TST.B   D0
        BEQ.S   .ok_ram
        MOVEQ   #ERR_RAM_INFO,D0
        BRA     err_halt
.ok_ram:
        MOVEQ   #4,D0
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_RAM_TOTAL).W,VAR_TOTAL_RAM
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_RAM_ACTIVE).W,VAR_ACTIVE_RAM
        MOVE.B  VAR_TOTAL_RAM,D0
        CMPI.B  #2,D0
        BCS.S   .one_slot
        MOVE.B  VAR_ACTIVE_RAM,D0
        EORI.B  #1,D0                   ; the other of two slots
        MOVE.B  D0,VAR_TARGET_RAM
        CLR.B   VAR_SINGLE_SLOT
        BRA.S   .ram_done
.one_slot:
        MOVE.B  VAR_ACTIVE_RAM,VAR_TARGET_RAM
        MOVE.B  #1,VAR_SINGLE_SLOT
.ram_done:

        ; --- is there a pipe to log through? ---
        CLR.B   VAR_PIPE_PRESENT
        BSR     rbcp_cmd_get_pipe_cap
        TST.B   D0
        BNE.S   .pipe_done
        MOVEQ   #1,D0
        BSR     rbcp_read_data
        TST.B   (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_CAP_COUNT).W
        BEQ.S   .pipe_done
        MOVE.B  #1,VAR_PIPE_PRESENT
        LEA     (msg_rule).L,A0
        BSR     log_line
        LEA     (str_log_title).L,A0
        BSR     log_line
.pipe_done:

        ; --- which LED can show a colour? ---
        MOVE.B  #$FF,VAR_LED
        BSR     rbcp_cmd_get_led_cap
        TST.B   D0
        BNE.S   .led_done
        MOVEQ   #1,D0
        BSR     rbcp_read_data
        MOVEQ   #0,D3
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_LED_CAP_COUNT).W,D3
        BEQ.S   .led_done
        MOVEQ   #0,D4                   ; LED index
.led_scan:
        MOVE.B  D4,D0
        BSR     rbcp_cmd_get_led_info
        TST.B   D0
        BNE.S   .led_next
        MOVEQ   #1,D0
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_LED_INFO_TYPE).W,D0
        CMPI.B  #RBCP_LED_TYPE_RGB,D0
        BNE.S   .led_next
        MOVE.B  D4,VAR_LED
        BRA.S   .led_done
.led_next:
        ADDQ.B  #1,D4
        CMP.B   D3,D4
        BCS.S   .led_scan
.led_done:

        ; --- how many images are there? ---
        BSR     rbcp_cmd_get_flash_count
        TST.B   D0
        BEQ.S   .ok_flash
        MOVEQ   #ERR_FLASH_INFO,D0
        BRA     err_halt
.ok_flash:
        MOVEQ   #1,D0
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF).W,VAR_TOTAL_FLASH
        CMPI.B  #2,VAR_TOTAL_FLASH      ; slot 0 is this bootloader
        BCC.S   .ok_flashcount
        MOVEQ   #ERR_NO_IMAGES,D0
        BRA     err_halt
.ok_flashcount:
        MOVE.B  VAR_TOTAL_FLASH,D0
        SUBQ.B  #1,D0                   ; drop slot 0 from the count
        CMPI.B  #MAX_DISPLAY+1,D0
        BCS.S   .disp_ok
        MOVEQ   #MAX_DISPLAY,D0
.disp_ok:
        MOVE.B  D0,VAR_NUM_DISPLAY

        BSR     log_device

        ; --- the remembered choice, where the device can hold one ---
        CLR.B   VAR_NV_PRESENT
        CLR.B   VAR_NV_STORED
        MOVE.B  #1,VAR_BOOT_FLASH
        TST.B   VAR_SINGLE_SLOT
        BNE.S   .nv_done                ; no spare slot to stage a write in
        BSR     rbcp_cmd_get_nv_cap
        TST.B   D0
        BNE.S   .nv_done
        MOVEQ   #4,D0
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_NV_CAP_SIZE_LO).W,D0
        OR.B    (CONFIG_RBCP_DATA_BUF+RBCP_NV_CAP_SIZE_HI).W,D0
        BEQ.S   .nv_done                ; no storage
        TST.B   (CONFIG_RBCP_DATA_BUF+RBCP_NV_CAP_WRITABLE).W
        BEQ.S   .nv_done                ; read only
        MOVE.B  #1,VAR_NV_PRESENT
        MOVE.B  #1,RBCP_ARG0            ; count = 1
        CLR.B   RBCP_ARG1               ; location LSB
        CLR.B   RBCP_ARG2               ; location MSB
        BSR     rbcp_cmd_nv_peek
        TST.B   D0
        BNE.S   .nv_done
        MOVEQ   #1,D0
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF).W,D0
        MOVE.B  D0,VAR_NV_STORED
        BEQ.S   .nv_done                ; 0 = never stored
        CMP.B   VAR_TOTAL_FLASH,D0
        BCC.S   .nv_done                ; out of range
        MOVE.B  D0,VAR_BOOT_FLASH
.nv_done:
        BSR     log_stored

        ; selection follows the stored slot, clamped to what is shown
        MOVE.B  VAR_BOOT_FLASH,D0
        SUBQ.B  #1,D0
        CMP.B   VAR_NUM_DISPLAY,D0
        BCS.S   .sel_ok
        MOVEQ   #0,D0
.sel_ok:
        MOVE.B  D0,VAR_SELECTION

        ; --- the menu on demand, otherwise straight to the choice ---
        ; Holding both mouse buttons at boot asks for the menu, the gesture the
        ; Amiga's own early-startup screen uses.  With nothing held, boot the
        ; remembered or default image at once.
        BSR     both_buttons_held
        TST.B   D0
        BNE.S   .want_menu
        LEA     (msg_autoboot).L,A0
        BSR     log_line
        MOVE.B  VAR_BOOT_FLASH,D0
        BRA     boot_slot
.want_menu:
        LEA     (msg_menu).L,A0
        BSR     log_line
        BSR     led_cycle
        ; Draw the menu at once, so it is on screen while the buttons are still
        ; held, then wait for them to come up before a click is read — so the
        ; gesture that opened the menu is not taken as a selection in it.
        BSR     draw_title
        BSR     draw_device
        BSR     draw_list
        BSR     highlight_selection
        BSR     draw_footer
        BSR     wait_buttons_release
        CLR.B   VAR_LMB_HELD
        CLR.B   VAR_RMB_HELD
        BRA     key_loop

; ---------------------------------------------------------------------------
; Menu — a left click or the arrows change the choice, a right click or RETURN
; boots it, and a digit picks one of the first nine.  It only appears when
; asked for, so there is no countdown.
; ---------------------------------------------------------------------------
key_loop:
        BSR     amiga_getkey
key_act:
        TST.B   D0
        BEQ.S   key_loop
        CMPI.B  #KEY_RETURN,D0
        BEQ     do_boot
        CMPI.B  #KEY_RMB,D0
        BEQ     do_boot                 ; a right click boots the highlight
        CMPI.B  #KEY_UP,D0
        BEQ.S   do_up
        CMPI.B  #KEY_LMB,D0
        BEQ.S   do_click
        CMPI.B  #KEY_DOWN,D0
        BEQ.S   do_down
        CMPI.B  #'1',D0
        BCS.S   key_loop
        CMPI.B  #'9'+1,D0
        BCC.S   key_loop
        SUBI.B  #'1',D0                 ; the digit is the entry
        CMP.B   VAR_NUM_DISPLAY,D0
        BCC.S   key_loop
        MOVE.B  D0,VAR_SAVED_KEY
        BSR     unhighlight_selection
        MOVE.B  VAR_SAVED_KEY,VAR_SELECTION
        BSR     highlight_selection
        BRA.S   key_loop

do_up:
        TST.B   VAR_SELECTION
        BEQ.S   key_loop
        BSR     unhighlight_selection
        SUBQ.B  #1,VAR_SELECTION
        BSR     highlight_selection
        BRA.S   key_loop

do_down:
        MOVEQ   #0,D0
        MOVE.B  VAR_SELECTION,D0
        ADDQ.B  #1,D0
        CMP.B   VAR_NUM_DISPLAY,D0
        BCC.S   key_loop
        BSR     unhighlight_selection
        ADDQ.B  #1,VAR_SELECTION
        BSR     highlight_selection
        BRA     key_loop

do_click:
        BSR     sel_cycle_down
        BRA     key_loop

; sel_cycle_down — move the highlight down one, wrapping to the top.  Used by
; a click both during the countdown and in the menu, so mouse-only operation
; can reach every entry.
sel_cycle_down:
        MOVEM.L D0,-(SP)
        BSR     unhighlight_selection
        MOVEQ   #0,D0
        MOVE.B  VAR_SELECTION,D0
        ADDQ.B  #1,D0
        CMP.B   VAR_NUM_DISPLAY,D0
        BCS.S   .scd_ok
        MOVEQ   #0,D0                   ; past the end, wrap to the top
.scd_ok:
        MOVE.B  D0,VAR_SELECTION
        BSR     highlight_selection
        MOVEM.L (SP)+,D0
        RTS

do_boot:
        MOVEQ   #0,D0
        MOVE.B  VAR_SELECTION,D0
        ADDQ.B  #1,D0                   ; 1-based flash slot
        MOVE.B  D0,VAR_BOOT_FLASH

        ; Remember the choice, where the device can hold one and it changed.
        TST.B   VAR_NV_PRESENT
        BEQ.S   boot_slot_entry
        MOVE.B  VAR_BOOT_FLASH,D0
        CMP.B   VAR_NV_STORED,D0
        BEQ.S   boot_slot_entry
        MOVE.B  D0,RBCP_ARG0            ; byte to store
        CLR.B   RBCP_ARG1               ; location LSB
        CLR.B   RBCP_ARG2               ; location MSB
        MOVE.B  VAR_TARGET_RAM,RBCP_ARG3 ; staging slot
        BSR     rbcp_cmd_nv_poke_commit_byte
        BSR     log_stored_upd          ; says nothing on a write that failed
boot_slot_entry:
        MOVE.B  VAR_BOOT_FLASH,D0
        ; fall through

; ---------------------------------------------------------------------------
; boot_slot — D0 = flash slot.  Loads it and hands the machine to it.
; ---------------------------------------------------------------------------
boot_slot:
        MOVE.B  D0,VAR_BOOT_FLASH
        MOVE.B  D0,D3                   ; flash slot, kept across the calls
        MOVE.B  D3,D0
        BSR     led_set_colour          ; the image's own colour, which outlives us
        MOVE.B  D3,D0
        BSR     log_switch
        LEA     (msg_resetting).L,A0
        BSR     log_line                ; the last line before the switch ends the session

        TST.B   VAR_SINGLE_SLOT
        BNE.S   .single
        ; Two or more slots: load into the spare, then switch to it.  LOAD_SLOT
        ; polls to completion, so the switch that follows cannot race the load.
        MOVE.B  VAR_TARGET_RAM,D0
        MOVE.B  D3,D1
        BSR     rbcp_cmd_load_slot
        TST.B   D0
        BEQ.S   .loaded
        MOVEQ   #ERR_LOAD,D0
        BRA     err_halt
.loaded:
        MOVE.B  VAR_TARGET_RAM,D0
        BSR     rbcp_cmd_switch_and_exit
        BRA.S   boot_into_rom
.single:
        ; One slot: load the chosen image into the active slot and exit.  No
        ; completion is reported, so wait for the in-device copy before the
        ; machine reads the new ROM.
        MOVE.B  VAR_ACTIVE_RAM,D0
        MOVE.B  D3,D1
        BSR     rbcp_cmd_load_and_exit
        BSR     boot_settle
        ; fall through

; ---------------------------------------------------------------------------
; boot_into_rom — the device now serves the chosen image.  Hand the machine
; to it by cold-starting through its own reset vector, chipset quiet.
;
; OVL is left as it is: setting it would map ROM over this very code in chip
; RAM.  Kickstart configures the memory map itself, so a clean jump to its
; entry is enough.
; ---------------------------------------------------------------------------
boot_into_rom:
        ORI.W   #$0700,SR               ; interrupts off
        MOVE.W  #$7FFF,INTENA
        MOVE.W  #$7FFF,INTREQ
        MOVE.W  #$03FF,DMACON           ; all DMA off, display included
        MOVEA.L (CONFIG_ROM_BASE).L,SP        ; SSP from the new ROM
        MOVEA.L (CONFIG_ROM_BASE+4).L,A0      ; initial PC from the new ROM
        JMP     (A0)

; boot_settle — a delay long enough for the device to finish a LOAD_AND_EXIT
; copy before the machine reads the new ROM.  Roughly 170ms at 7MHz.
boot_settle:
        MOVEM.L D0-D1,-(SP)
        MOVEQ   #6,D0
.bs_o:  MOVE.W  #$FFFF,D1
.bs_i:  DBF     D1,.bs_i
        DBF     D0,.bs_o
        MOVEM.L (SP)+,D0-D1
        RTS

; ===========================================================================
; Menu drawing
; ===========================================================================

draw_title:
        LEA     (str_title).L,A0
        MOVE.B  #TITLE_COL,D1
        MOVE.B  #TITLE_ROW,D2
        BSR     screen_print
        MOVEQ   #TITLE_ROW,D0
        BRA     invert_row

; ---------------------------------------------------------------------------
; draw_device — the device's own name and version along the bottom, with the
; author beside them.  Both come from the device, so the line says what is
; actually serving the ROM.  A device that will not name itself gets the
; author line alone.
; ---------------------------------------------------------------------------
draw_device:
        BSR     rbcp_cmd_get_device_type
        TST.B   D0
        BNE.S   .rocks
        MOVEQ   #24,D0
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        MOVE.B  #DEVICE_COL,D1
        MOVE.B  #DEVICE_ROW,D2
        BSR     screen_print
        ; measure the type to place the version after it
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        MOVEQ   #DEVICE_COL,D3
.dd_len:
        TST.B   (A0)+
        BEQ.S   .dd_gotlen
        ADDQ.B  #1,D3
        BRA.S   .dd_len
.dd_gotlen:
        ADDQ.B  #1,D3                   ; a space between
        MOVE.B  D3,VAR_SAVED_KEY        ; the column, which the query clobbers
        BSR     rbcp_cmd_get_device_version
        TST.B   D0
        BNE.S   .rocks
        MOVEQ   #24,D0
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        MOVE.B  VAR_SAVED_KEY,D1
        MOVE.B  #DEVICE_ROW,D2
        BSR     screen_print
.rocks:
        LEA     (str_rocks).L,A0
        MOVE.B  #ROCKS_COL,D1
        MOVE.B  #DEVICE_ROW,D2
        BSR     screen_print
        MOVEQ   #DEVICE_ROW,D0
        BRA     invert_row

; ---------------------------------------------------------------------------
; draw_list — one line per image, each asked for as it is drawn.  The
; back-channel holds one slot record at a time, so the names arrive one
; command at a time and go straight to the screen and the log.  D7 holds the
; 0-based display index across the loop; the command helpers preserve it.
; ---------------------------------------------------------------------------
draw_list:
        MOVEM.L D5-D7,-(SP)
        MOVEQ   #0,D7
.dl_loop:
        MOVE.B  VAR_NUM_DISPLAY,D0
        CMP.B   D7,D0
        BLS     .dl_done                ; D7 >= num_display
        MOVE.B  D7,D0
        ADDQ.B  #1,D0                   ; flash slot
        BSR     rbcp_cmd_get_flash_info
        TST.B   D0
        BNE     .dl_next                ; a slot that will not describe: skip
        MOVEQ   #32,D0
        BSR     rbcp_read_data

        ; Centre the entry: an "N) " prefix of three columns and the name.
        LEA     (CONFIG_RBCP_DATA_BUF+RBCP_FLASH_NAME).W,A0
        MOVEQ   #0,D5
.dl_len:
        TST.B   (A0)+
        BEQ.S   .dl_gotlen
        ADDQ.W  #1,D5
        BRA.S   .dl_len
.dl_gotlen:
        MOVEQ   #SCREEN_COLS-3,D6
        SUB.W   D5,D6
        LSR.W   #1,D6                   ; D6 = start column

        ; The number shown is the flash slot, one more than the list place
        ; because slot 0 is the bootloader.  Only the first nine have a digit
        ; that picks them; the rest are reached with the cursor.
        MOVE.B  D7,D0
        CMPI.B  #9,D0
        BCC.S   .dl_blank
        ADDQ.B  #1,D0
        ADDI.B  #'0',D0                 ; '1'..'9'
        MOVEQ   #')',D3
        BRA.S   .dl_putnum
.dl_blank:
        MOVEQ   #' ',D0
        MOVEQ   #' ',D3
.dl_putnum:
        MOVE.B  D7,D2
        ADDI.B  #MENU_ROW0,D2
        MOVE.B  D6,D1                   ; start column
        BSR     screen_putchar          ; the digit or a space
        MOVE.B  D3,D0
        MOVE.B  D7,D2
        ADDI.B  #MENU_ROW0,D2
        MOVE.B  D6,D1
        ADDQ.B  #1,D1
        BSR     screen_putchar          ; the bracket or a space

        LEA     (CONFIG_RBCP_DATA_BUF+RBCP_FLASH_NAME).W,A0
        MOVE.B  D7,D2
        ADDI.B  #MENU_ROW0,D2
        MOVE.B  D6,D1
        ADDQ.B  #3,D1                   ; after the "N) " prefix
        BSR     screen_print

        BSR     log_entry               ; name is still in the buffer
.dl_next:
        ADDQ.B  #1,D7
        BRA     .dl_loop
.dl_done:
        MOVEM.L (SP)+,D5-D7
        RTS

highlight_selection:
        MOVEQ   #0,D0
        MOVE.B  VAR_SELECTION,D0
        ADDI.B  #MENU_ROW0,D0
        BRA     invert_row

unhighlight_selection:
        MOVEQ   #0,D0
        MOVE.B  VAR_SELECTION,D0
        ADDI.B  #MENU_ROW0,D0
        BRA     invert_row              ; NOT toggles, so this clears it again

; invert_row — D0.B = text row.  Inverts all eight scan lines of that row
; across the full width, so a highlighted line reads as black on white.
invert_row:
        MOVEM.L D0-D2/A0,-(SP)
        ANDI.L  #$FF,D0
        MOVE.W  D0,D1
        LSL.W   #8,D1                   ; row * 256
        ADD.W   D1,D1                   ; row * 512
        MOVE.W  D0,D2
        LSL.W   #7,D2                   ; row * 128
        ADD.W   D2,D1                   ; row * 640 = the row's first byte
        LEA     (BITPLANE_BASE).L,A0
        ADDA.W  D1,A0
        MOVE.W  #(SCREEN_BPL_W*8)/4-1,D1
.ir_loop:
        NOT.L   (A0)+
        DBF     D1,.ir_loop
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; draw_footer — the controls line.
draw_footer:
        LEA     (str_footer).L,A0
        MOVE.B  #FOOTER_COL,D1
        MOVE.B  #FOOTER_ROW,D2
        BRA     screen_print

; ---------------------------------------------------------------------------
; amiga_getkey — one poll of the keyboard and the mouse buttons.
; Returns D0.B: 0 none, KEY_UP/DOWN/RETURN, KEY_LMB, or '1'..'9' for a digit.
;
; The keyboard arrives over the CIA-A serial port.  A received byte is the
; keycode rotated and inverted; bit 7 after decoding is the key-up flag.  The
; host must acknowledge each byte by driving the serial line as an output for
; a short pulse, or the keyboard stops sending.
; ---------------------------------------------------------------------------
amiga_getkey:
        MOVEM.L D1-D2/A0,-(SP)
        MOVE.B  (CIAA_ICR).L,D1         ; read and clear the CIA-A status
        BTST    #CIAA_ICR_SP,D1
        BEQ.S   .gk_lmb
        MOVE.B  (CIAA_SDR).L,D0         ; raw keycode
        BSET    #CIAA_CRA_SPMODE,(CIAA_CRA).L   ; drive the handshake
        MOVE.W  #250,D2
.gk_hs:
        DBF     D2,.gk_hs               ; ~85us and more
        BCLR    #CIAA_CRA_SPMODE,(CIAA_CRA).L   ; back to input
        NOT.B   D0
        ROR.B   #1,D0                   ; keycode = ror(~raw)
        BTST    #7,D0
        BNE.S   .gk_none                ; a key release, ignore
        ANDI.B  #$7F,D0
        CMPI.B  #KBD_UP,D0
        BEQ.S   .gk_up
        CMPI.B  #KBD_DOWN,D0
        BEQ.S   .gk_down
        CMPI.B  #KBD_RETURN,D0
        BEQ.S   .gk_ret
        TST.B   D0                      ; digit scancodes are $01..$09
        BEQ.S   .gk_none
        CMPI.B  #$0A,D0
        BCC.S   .gk_none
        ADDI.B  #'0',D0                 ; scancode n -> '1'..'9'
        BRA.S   .gk_out
.gk_up:
        MOVEQ   #KEY_UP,D0
        BRA.S   .gk_out
.gk_down:
        MOVEQ   #KEY_DOWN,D0
        BRA.S   .gk_out
.gk_ret:
        MOVEQ   #KEY_RETURN,D0
.gk_out:
        MOVEM.L (SP)+,D1-D2/A0
        RTS
.gk_lmb:
        BTST    #CIAA_PRA_LMB,(CIAA_PRA).L
        BNE.S   .gk_lmbup               ; bit set = not pressed
        TST.B   VAR_LMB_HELD
        BNE.S   .gk_rmb                 ; already reported this press
        MOVE.B  #1,VAR_LMB_HELD
        MOVEQ   #KEY_LMB,D0
        BRA.S   .gk_out
.gk_lmbup:
        CLR.B   VAR_LMB_HELD
.gk_rmb:
        MOVE.W  (POTGOR).L,D1
        BTST    #POTGOR_RMB,D1
        BNE.S   .gk_rmbup               ; bit set = not pressed
        TST.B   VAR_RMB_HELD
        BNE.S   .gk_none
        MOVE.B  #1,VAR_RMB_HELD
        MOVEQ   #KEY_RMB,D0
        BRA.S   .gk_out
.gk_rmbup:
        CLR.B   VAR_RMB_HELD
.gk_none:
        MOVEQ   #0,D0
        MOVEM.L (SP)+,D1-D2/A0
        RTS

; ---------------------------------------------------------------------------
; both_buttons_held — D0.B = 1 where the left and right mouse buttons are both
; down, else 0.  For the boot-time request for the menu.
; ---------------------------------------------------------------------------
both_buttons_held:
        MOVEM.L D1,-(SP)
        MOVEQ   #0,D0
        BTST    #CIAA_PRA_LMB,(CIAA_PRA).L
        BNE.S   .bbh_done               ; left not pressed
        MOVE.W  (POTGOR).L,D1
        BTST    #POTGOR_RMB,D1
        BNE.S   .bbh_done               ; right not pressed
        MOVEQ   #1,D0
.bbh_done:
        MOVEM.L (SP)+,D1
        RTS

; wait_buttons_release — block until both mouse buttons are up, so the gesture
; that opened the menu is not read as a click within it.  Debounced so a
; button that bounces on release does not slip a fresh press through.
wait_buttons_release:
        MOVEM.L D0-D2,-(SP)
        MOVE.L  #$00200000,D2           ; give up after a while, never hang
.wbr_loop:
        BTST    #CIAA_PRA_LMB,(CIAA_PRA).L
        BNE.S   .wbr_up                 ; left is up
        BRA.S   .wbr_next
.wbr_up:
        MOVE.W  (POTGOR).L,D1
        BTST    #POTGOR_RMB,D1
        BNE.S   .wbr_settle             ; both up
.wbr_next:
        SUBQ.L  #1,D2
        BNE.S   .wbr_loop
.wbr_settle:
        MOVE.W  #$2000,D0               ; short settle
.wbr_s:
        SUBQ.W  #1,D0
        BNE.S   .wbr_s
        MOVEM.L (SP)+,D0-D2
        RTS

; ===========================================================================
; RGB LED
; ===========================================================================

; led_cycle — cycle the hues while the menu is up.  Booting an image replaces
; this with that image's own colour, so a device still cycling never got there.
led_cycle:
        MOVEQ   #0,D0
        MOVE.B  VAR_LED,D0
        BMI.S   .lc_none
        MOVE.B  #RBCP_LED_CYCLE,RBCP_ARG0
        CLR.B   RBCP_ARG1
        CLR.B   RBCP_ARG2
        CLR.B   RBCP_ARG3               ; colour, which cycle does not take
        CLR.B   RBCP_ARG4               ; brightness, the device's to choose
        CLR.B   RBCP_ARG5               ; period, so it runs at its own rate
        CLR.B   RBCP_ARG6               ; hold, so it cycles until something stops it
        MOVE.B  VAR_LED,D0
        BRA     rbcp_cmd_set_led
.lc_none:
        RTS

; led_set_colour — D0 = flash slot.  Breathe the LED a colour of its own per
; image, so the machine says which one it runs after the bootloader has gone.
led_set_colour:
        MOVEQ   #0,D1
        MOVE.B  VAR_LED,D1
        BMI.S   .lsc_done
        ANDI.W  #$07,D0                 ; slot modulo eight
        MOVE.W  D0,D2
        ADD.W   D0,D0
        ADD.W   D2,D0                   ; slot * 3
        LEA     (led_colours).L,A0
        ADDA.W  D0,A0
        MOVE.B  (A0)+,RBCP_ARG1         ; red
        MOVE.B  (A0)+,RBCP_ARG2         ; green
        MOVE.B  (A0)+,RBCP_ARG3         ; blue
        MOVE.B  #RBCP_LED_BREATHE,RBCP_ARG0
        CLR.B   RBCP_ARG4               ; brightness
        CLR.B   RBCP_ARG5               ; period
        CLR.B   RBCP_ARG6               ; hold, so the colour stays
        MOVE.B  VAR_LED,D0
        BRA     rbcp_cmd_set_led
.lsc_done:
        RTS

; ===========================================================================
; Logging, through pipe 0 where the device has one
; ===========================================================================

; pipe_puts — A0 = null-terminated string, sent to pipe 0 in four-byte chunks.
; A chunk the device will not take ends the whole thing: waiting for room
; would hang the machine on a far end that is not reading.
pipe_puts:
        MOVEM.L D0-D2/A0-A1,-(SP)
.pp_chunk:
        MOVEQ   #0,D2                   ; bytes gathered
        LEA     (RBCP_ARG0).W,A1
.pp_gather:
        MOVE.B  (A0),D0
        BEQ.S   .pp_flush
        MOVE.B  D0,(A1)+
        ADDQ.L  #1,A0
        ADDQ.B  #1,D2
        CMPI.B  #RBCP_PIPE_WRITE_MAX,D2
        BNE.S   .pp_gather
.pp_flush:
        TST.B   D2
        BEQ.S   .pp_done
        MOVE.B  D2,D0                   ; count
        MOVEQ   #0,D1                   ; pipe 0
        BSR     rbcp_cmd_pipe_write
        TST.B   D0
        BNE.S   .pp_done                ; refused, or the far end is gone
        CMPI.B  #RBCP_PIPE_WRITE_MAX,D2
        BEQ.S   .pp_chunk               ; a full chunk, so there may be more
.pp_done:
        MOVEM.L (SP)+,D0-D2/A0-A1
        RTS

; log_line — A0 = string, sent with a trailing CRLF where a pipe is present.
log_line:
        TST.B   VAR_PIPE_PRESENT
        BEQ.S   .ll_done
        BSR     pipe_puts
        BRA.S   log_crlf
.ll_done:
        RTS

log_crlf:
        MOVE.B  #13,RBCP_ARG0
        MOVE.B  #10,RBCP_ARG1
        MOVEQ   #2,D0
        MOVEQ   #0,D1                   ; pipe 0
        BRA     rbcp_cmd_pipe_write

; log_dec — D0.B = value, sent as one or two decimal digits with no leading
; zero.  Slot and RAM counts are all that go this way and none reaches a hundred.
log_dec:
        MOVEM.L D2-D3,-(SP)
        MOVEQ   #0,D3                   ; tens
.ld_tens:
        CMPI.B  #10,D0
        BCS.S   .ld_units
        SUBI.B  #10,D0
        ADDQ.B  #1,D3
        BRA.S   .ld_tens
.ld_units:
        ADDI.B  #'0',D0
        TST.B   D3
        BEQ.S   .ld_one
        MOVE.B  D0,RBCP_ARG1            ; units
        ADDI.B  #'0',D3
        MOVE.B  D3,RBCP_ARG0            ; tens
        MOVEQ   #2,D0
        BRA.S   .ld_send
.ld_one:
        MOVE.B  D0,RBCP_ARG0
        MOVEQ   #1,D0
.ld_send:
        MOVEQ   #0,D1                   ; pipe 0
        BSR     rbcp_cmd_pipe_write
        MOVEM.L (SP)+,D2-D3
        RTS

; log_name_end — A0 = name, sent with a closing quote and a CRLF.  The opening
; quote belongs to whatever prefix the caller sent.
log_name_end:
        BSR     pipe_puts
        MOVE.B  #'"',RBCP_ARG0
        MOVE.B  #13,RBCP_ARG1
        MOVE.B  #10,RBCP_ARG2
        MOVEQ   #3,D0
        MOVEQ   #0,D1
        BRA     rbcp_cmd_pipe_write

; log_device — one line naming the device and what it holds.
log_device:
        TST.B   VAR_PIPE_PRESENT
        BEQ     .lgd_done
        BSR     rbcp_cmd_get_device_type
        TST.B   D0
        BNE.S   .lgd_counts
        MOVEQ   #24,D0
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        BSR     pipe_puts
        BSR     rbcp_cmd_get_device_version
        TST.B   D0
        BNE.S   .lgd_sep
        MOVEQ   #24,D0
        BSR     rbcp_read_data
        LEA     (msg_sp).L,A0
        BSR     pipe_puts
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        BSR     pipe_puts
.lgd_sep:
        LEA     (msg_comma).L,A0
        BSR     pipe_puts
.lgd_counts:
        MOVEQ   #0,D0
        MOVE.B  VAR_TOTAL_FLASH,D0
        BSR     log_dec
        LEA     (msg_flash_slots).L,A0
        BSR     pipe_puts
        MOVEQ   #0,D0
        MOVE.B  VAR_TOTAL_RAM,D0
        BSR     log_dec
        LEA     (msg_ram_slots).L,A0
        BRA     log_line
.lgd_done:
        RTS

; log_stored — what the device had remembered, before the menu is drawn.
log_stored:
        TST.B   VAR_PIPE_PRESENT
        BEQ.S   .ls_done
        TST.B   VAR_NV_PRESENT
        BEQ.S   .ls_cannot
        MOVEQ   #0,D0
        MOVE.B  VAR_NV_STORED,D0
        BEQ.S   .ls_unset
        CMP.B   VAR_TOTAL_FLASH,D0
        BCC.S   .ls_unset
        LEA     (msg_stored).L,A0
        BSR     pipe_puts
        MOVEQ   #0,D0
        MOVE.B  VAR_NV_STORED,D0
        BSR     log_dec
        BRA     log_crlf
.ls_cannot:
        LEA     (msg_nv_none).L,A0
        BRA     log_line
.ls_unset:
        LEA     (msg_nv_unset).L,A0
        BRA     log_line
.ls_done:
        RTS

; log_stored_upd — D0 = the write result.  Says the choice was written, and
; nothing on a write that failed, since nothing happened.
log_stored_upd:
        TST.B   D0
        BNE.S   .lsu_done
        TST.B   VAR_PIPE_PRESENT
        BEQ.S   .lsu_done
        LEA     (msg_stored_upd).L,A0
        BSR     pipe_puts
        MOVEQ   #0,D0
        MOVE.B  VAR_BOOT_FLASH,D0
        BSR     log_dec
        BRA     log_crlf
.lsu_done:
        RTS

; log_switch — D0 = slot, "Switching to slot N" and the name on the next line.
; The name is asked for again: the back-channel holds whichever slot the menu
; drew last, not the one the user went on to pick.
log_switch:
        TST.B   VAR_PIPE_PRESENT
        BEQ.S   .lsw_done
        MOVE.B  D0,VAR_LOG_SLOT
        LEA     (msg_switching).L,A0
        BSR     pipe_puts
        MOVEQ   #0,D0
        MOVE.B  VAR_LOG_SLOT,D0
        BSR     log_dec
        BSR     log_crlf
        MOVE.B  VAR_LOG_SLOT,D0
        BSR     rbcp_cmd_get_flash_info
        TST.B   D0
        BNE.S   .lsw_done
        MOVEQ   #32,D0
        BSR     rbcp_read_data
        LEA     (msg_name_open).L,A0
        BSR     pipe_puts
        LEA     (CONFIG_RBCP_DATA_BUF+RBCP_FLASH_NAME).W,A0
        BRA     log_name_end
.lsw_done:
        RTS

; log_entry — one line per menu entry, D7 holding its place.  The name is
; still in the buffer from the query that drew it.
log_entry:
        TST.B   VAR_PIPE_PRESENT
        BEQ.S   .le_done
        LEA     (msg_indent).L,A0
        BSR     pipe_puts
        MOVEQ   #0,D0
        MOVE.B  D7,D0
        ADDQ.B  #1,D0                   ; the flash slot the screen shows
        BSR     log_dec
        LEA     (msg_sp_quote).L,A0
        BSR     pipe_puts
        LEA     (CONFIG_RBCP_DATA_BUF+RBCP_FLASH_NAME).W,A0
        BRA     log_name_end
.le_done:
        RTS

; ===========================================================================
; Error handler — D0 = error number.  Says what went wrong and stops.  There
; is no way back: the session is in an unknown state and no image has loaded.
; ===========================================================================
err_halt:
        MOVE.B  D0,VAR_ERR_NUM
        BSR     log_error               ; to the pipe, where there is one
        BSR     screen_clear
        BSR     draw_title
        LEA     (str_err).L,A0
        MOVE.B  #ERROR_COL,D1
        MOVE.B  #ERROR_ROW,D2
        BSR     screen_print
        MOVEQ   #0,D1
        MOVE.B  VAR_ERR_NUM,D1
        LSL.W   #2,D1                   ; a long per table entry
        LEA     (err_msgs).L,A0
        MOVEA.L (A0,D1.W),A0
        MOVE.B  #ERROR_COL,D1
        MOVE.B  #ERROR_ROW+2,D2
        BSR     screen_print
        BSR     draw_err_diag
        MOVE.W  #COL_RED,COLOR00
.eh_halt:
        BRA.S   .eh_halt

; ---------------------------------------------------------------------------
; draw_err_diag — the raw state when the library gave up, for reporting.
;
; STAGE is how far the command got: 1 the device never acknowledged it, 2 it
; did but never completed, 3 it completed and reported failure.  SGRP/SCMD are
; what the bootloader was sending.  DGRP/DCMD are the last command the device
; says it processed, so a shifted frame shows as the device answering
; something other than what was asked.  TOK/PRG/RSP are the response header.
; ---------------------------------------------------------------------------
draw_err_diag:
        MOVEM.L D0-D2/A0,-(SP)

        MOVE.B  #ERROR_ROW+4,D2
        MOVE.B  #ERROR_COL,D1
        LEA     (str_d_stage).L,A0
        MOVE.B  RBCP_ERROR_CODE,D0
        BSR     diag_field
        ADDQ.B  #2,D1
        LEA     (str_d_sgrp).L,A0
        MOVE.B  RBCP_GROUP,D0
        BSR     diag_field
        ADDQ.B  #1,D1
        LEA     (str_d_cmd).L,A0
        MOVE.B  RBCP_CMD,D0
        BSR     diag_field

        MOVE.B  #ERROR_ROW+5,D2
        MOVE.B  #ERROR_COL,D1
        LEA     (str_d_dgrp).L,A0
        MOVE.B  (RBCP_LASTCMD_GRP_ADDR).L,D0
        BSR     diag_field
        ADDQ.B  #1,D1
        LEA     (str_d_cmd).L,A0
        MOVE.B  (RBCP_LASTCMD_CMD_ADDR).L,D0
        BSR     diag_field
        ADDQ.B  #1,D1
        LEA     (str_d_tok).L,A0
        MOVE.B  (RBCP_TOKEN_LSB_ADDR).L,D0
        BSR     diag_field
        ADDQ.B  #1,D1
        LEA     (str_d_prg).L,A0
        MOVE.B  (RBCP_PROGRESS_ADDR).L,D0
        BSR     diag_field
        ADDQ.B  #1,D1
        LEA     (str_d_rsp).L,A0
        MOVE.B  (RBCP_RESPONSE_ADDR).L,D0
        BSR     diag_field

        MOVEM.L (SP)+,D0-D2/A0
        RTS

; diag_field — A0 = label, D0.B = value, D1.B = column, D2.B = row.  Prints
; the label then the value as two hex digits, and leaves D1 past both so the
; next field chains on.  Clobbers D1 (deliberately); saves the rest.
diag_field:
        MOVEM.L D0/D3-D4/A0,-(SP)
        MOVE.B  D0,D4                   ; value
        BSR     screen_print            ; prints at D1, does not move it
.dgf_len:
        TST.B   (A0)+
        BEQ.S   .dgf_gotlen
        ADDQ.B  #1,D1
        BRA.S   .dgf_len
.dgf_gotlen:
        MOVE.B  D4,D0
        BSR     print_hex_byte          ; advances D1 by two
        MOVEM.L (SP)+,D0/D3-D4/A0
        RTS

; print_hex_byte — D0.B as two hex digits at (D1=col, D2=row), D1 advanced by
; two.  Saves everything but D1.
print_hex_byte:
        MOVEM.L D0/D3,-(SP)
        MOVE.B  D0,D3
        LSR.B   #4,D0
        BSR.S   .phb_conv
        BSR     screen_putchar
        ADDQ.B  #1,D1
        MOVE.B  D3,D0
        ANDI.B  #$0F,D0
        BSR.S   .phb_conv
        BSR     screen_putchar
        ADDQ.B  #1,D1
        MOVEM.L (SP)+,D0/D3
        RTS
.phb_conv:
        CMPI.B  #10,D0
        BCS.S   .phb_dig
        ADDI.B  #'A'-10,D0
        RTS
.phb_dig:
        ADDI.B  #'0',D0
        RTS

; ---------------------------------------------------------------------------
; log_error — the same diagnostics down the pipe, where there is one.  Nothing
; is sent where command-response mode was never entered, since there is no
; pipe then and the header would be meaningless.
; ---------------------------------------------------------------------------
log_error:
        TST.B   VAR_PIPE_PRESENT
        BEQ     .lge_done
        LEA     (msg_rule).L,A0
        BSR     log_line
        LEA     (msg_err_pre).L,A0
        BSR     pipe_puts
        MOVEQ   #0,D1
        MOVE.B  VAR_ERR_NUM,D1
        LSL.W   #2,D1
        LEA     (err_msgs).L,A0
        MOVEA.L (A0,D1.W),A0
        BSR     pipe_puts
        BSR     log_crlf
        LEA     (msg_err_st).L,A0       ; "  stage "
        BSR     pipe_puts
        MOVE.B  RBCP_ERROR_CODE,D0
        BSR     log_hex_byte
        LEA     (msg_err_sent).L,A0     ; " sent "
        BSR     pipe_puts
        MOVE.B  RBCP_GROUP,D0
        BSR     log_hex_byte
        LEA     (msg_err_slash).L,A0
        BSR     pipe_puts
        MOVE.B  RBCP_CMD,D0
        BSR     log_hex_byte
        LEA     (msg_err_dev).L,A0      ; " dev "
        BSR     pipe_puts
        MOVE.B  (RBCP_LASTCMD_GRP_ADDR).L,D0
        BSR     log_hex_byte
        LEA     (msg_err_slash).L,A0
        BSR     pipe_puts
        MOVE.B  (RBCP_LASTCMD_CMD_ADDR).L,D0
        BSR     log_hex_byte
        LEA     (msg_err_tok).L,A0      ; " tok "
        BSR     pipe_puts
        MOVE.B  (RBCP_TOKEN_LSB_ADDR).L,D0
        BSR     log_hex_byte
        LEA     (msg_err_prg).L,A0      ; " prg "
        BSR     pipe_puts
        MOVE.B  (RBCP_PROGRESS_ADDR).L,D0
        BSR     log_hex_byte
        LEA     (msg_err_rsp).L,A0      ; " rsp "
        BSR     pipe_puts
        MOVE.B  (RBCP_RESPONSE_ADDR).L,D0
        BSR     log_hex_byte
        BSR     log_crlf
.lge_done:
        RTS

; log_hex_byte — D0.B as two hex digits down pipe 0.
log_hex_byte:
        MOVEM.L D0/D2-D3,-(SP)
        MOVE.B  D0,D3
        LSR.B   #4,D0
        BSR.S   .lhb_conv
        MOVE.B  D0,RBCP_ARG0
        MOVE.B  D3,D0
        ANDI.B  #$0F,D0
        BSR.S   .lhb_conv
        MOVE.B  D0,RBCP_ARG1
        MOVEQ   #2,D0
        MOVEQ   #0,D1
        BSR     rbcp_cmd_pipe_write
        MOVEM.L (SP)+,D0/D2-D3
        RTS
.lhb_conv:
        CMPI.B  #10,D0
        BCS.S   .lhb_dig
        ADDI.B  #'A'-10,D0
        RTS
.lhb_dig:
        ADDI.B  #'0',D0
        RTS


; ============================================================
; RBCP library (runs from RAM)
; ============================================================
        INCLUDE "../rbcp/rbcp.s"

; ============================================================
; Screen rendering and hex output (RAM section)
; font_data lives in the ROM data section and is reached by absolute long
; address, correct from any execution address.
; ============================================================

; ---------------------------------------------------------------------------
; screen_clear — zero the entire bitplane
; Also called from screen_init in the ROM section, via the ROM copy here.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
screen_clear:
        MOVEM.L D0/A0,-(SP)
        LEA     (BITPLANE_BASE).L,A0
        MOVE.W  #SCREEN_BPL_SZ/4-1,D0
.sc_loop:
        CLR.L   (A0)+
        DBF     D0,.sc_loop
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; screen_putchar — render one ASCII character into the bitplane
; Input : D0.B = character code, D1.B = column (0-79), D2.B = row (0-27)
; Clobbers (saved/restored): D0-D4/A0-A1
; ---------------------------------------------------------------------------
screen_putchar:
        MOVEM.L D0-D4/A0-A1,-(SP)

        ; Bitplane byte address = BITPLANE_BASE + row*640 + col
        ; row*640 = row*512 + row*128
        MOVEQ   #0,D3
        MOVE.B  D2,D3
        MOVE.W  D3,D4
        LSL.W   #8,D3               ; row * 256
        ADD.W   D3,D3               ; row * 512 (68000 max immediate shift 8)
        LSL.W   #7,D4               ; row * 128
        ADD.W   D4,D3               ; row * 640
        MOVEQ   #0,D4
        MOVE.B  D1,D4
        ADD.W   D4,D3               ; row*640 + col
        LEA     (BITPLANE_BASE).L,A1
        ADDA.W  D3,A1

        ; Glyph address = font_data + char_code * 8
        MOVEQ   #0,D3
        MOVE.B  D0,D3
        ASL.W   #3,D3
        LEA     (font_data).L,A0
        ADDA.W  D3,A0

        MOVE.B  (A0)+,(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*1(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*2(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*3(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*4(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*5(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*6(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*7(A1)

        MOVEM.L (SP)+,D0-D4/A0-A1
        RTS

; ---------------------------------------------------------------------------
; screen_print — print a null-terminated ASCII string
; Input : A0 = string pointer, D1.B = column, D2.B = row
; Characters beyond the last column are dropped.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
screen_print:
        MOVEM.L D0-D2/A0,-(SP)
.sp_loop:
        MOVE.B  (A0)+,D0
        BEQ.S   .sp_done
        CMPI.B  #SCREEN_COLS,D1
        BCC.S   .sp_done
        BSR     screen_putchar
        ADDQ.B  #1,D1
        BRA.S   .sp_loop
.sp_done:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

        EVEN
ram_section_rom_end:

; ============================================================
; ROM DATA SECTION
; Copper template, font and strings.  Reached from RAM code by absolute long
; address, so correct from any PC.
; ============================================================

        EVEN
copper_template:
        DC.W    COP_BPL1PTH,$0000       ; patched by screen_init
        DC.W    COP_BPL1PTL,$0000       ; patched by screen_init
        DC.W    COP_BPLCON0,$9200       ; 1 plane, HIRES, colour enable
        DC.W    COP_BPLCON1,$0000
        DC.W    COP_BPLCON2,$0024
        DC.W    COP_BPL1MOD,$0000
        DC.W    COP_DDFSTRT,$003C
        DC.W    COP_DDFSTOP,$00D4
        DC.W    COP_DIWSTRT,$2C81       ; NTSC display window start
        DC.W    COP_DIWSTOP,$F4C1       ; NTSC, 224 lines
        DC.W    COP_COLOR00,$0000       ; border: black
        DC.W    COP_COLOR01,$0FFF       ; text: white
        DC.W    $2C01,$FFFE             ; WAIT for start of display
        DC.W    COP_COLOR00,$0000       ; background: black
        DC.W    $FFFF,$FFFE             ; END
copper_template_end:

; font_8x8.bin: 256 glyphs * 8 bytes = 2048 bytes, no header.
; One byte per scan line, MSB = leftmost pixel.
        EVEN
font_data:
        INCBIN  "font_8x8.bin"
font_data_end:

        EVEN
str_title:
        DC.B    "AMIGA RBCP BOOTLOADER 0.1.0",0
        EVEN
str_log_title:
        DC.B    "Amiga RBCP Bootloader 0.1.0",0
        EVEN
str_rocks:
        DC.B    "piers.rocks",0
        EVEN
; The placeholder digit at COUNT_COL is overprinted each tick.  40 characters,
str_footer:
        DC.B    "LEFT CLICK OR ARROWS CHOOSE   RIGHT CLICK OR RETURN BOOTS",0
        EVEN
str_err:
        DC.B    "RBCP ERROR",0
        EVEN
msg_rule:
        DC.B    "-----",0
        EVEN
msg_resetting:
        DC.B    "Bootloader finished - resetting system",0
        EVEN
msg_autoboot:
        DC.B    "Booting the stored choice",0
        EVEN
msg_menu:
        DC.B    "Both buttons held - showing the menu",0
        EVEN
msg_name_open:
        DC.B    "  ",$22,0
        EVEN
msg_indent:
        DC.B    "  ",0
        EVEN
msg_sp_quote:
        DC.B    " ",$22,0
        EVEN
msg_sp:
        DC.B    " ",0
        EVEN
msg_comma:
        DC.B    ", ",0
        EVEN
msg_flash_slots:
        DC.B    " flash ROM slots, ",0
        EVEN
msg_ram_slots:
        DC.B    " RAM slots",0
        EVEN
msg_switching:
        DC.B    "Switching to slot ",0
        EVEN
msg_stored:
        DC.B    "Stored choice: slot ",0
        EVEN
msg_stored_upd:
        DC.B    "Stored choice updated: slot ",0
        EVEN
msg_nv_none:
        DC.B    "Stored choice: not supported",0
        EVEN
msg_nv_unset:
        DC.B    "Stored choice: none",0
        EVEN
msg_err_0:
        DC.B    "NO REPLY",0
        EVEN
msg_err_1:
        DC.B    "PROTOCOL VERSION",0
        EVEN
msg_err_2:
        DC.B    "NO RAM INFO",0
        EVEN
msg_err_3:
        DC.B    "NO SLOT COUNT",0
        EVEN
msg_err_4:
        DC.B    "NO IMAGES",0
        EVEN
msg_err_5:
        DC.B    "LOAD FAILED",0
        EVEN
err_msgs:
        DC.L    msg_err_0, msg_err_1, msg_err_2
        DC.L    msg_err_3, msg_err_4, msg_err_5

; Diagnostic field labels, on screen.
        EVEN
str_d_stage:
        DC.B    "STAGE:",0
        EVEN
str_d_sgrp:
        DC.B    "SGRP:",0
        EVEN
str_d_cmd:
        DC.B    "CMD:",0
        EVEN
str_d_dgrp:
        DC.B    "DGRP:",0
        EVEN
str_d_tok:
        DC.B    "TOK:",0
        EVEN
str_d_prg:
        DC.B    "PRG:",0
        EVEN
str_d_rsp:
        DC.B    "RSP:",0
        EVEN

; Diagnostic labels, down the pipe.
msg_err_pre:
        DC.B    "RBCP ERROR: ",0
        EVEN
msg_err_st:
        DC.B    "  stage ",0
        EVEN
msg_err_sent:
        DC.B    " sent ",0
        EVEN
msg_err_slash:
        DC.B    "/",0
        EVEN
msg_err_dev:
        DC.B    " dev ",0
        EVEN
msg_err_tok:
        DC.B    " tok ",0
        EVEN
msg_err_prg:
        DC.B    " prg ",0
        EVEN
msg_err_rsp:
        DC.B    " rsp ",0
        EVEN

; A colour per flash slot, three bytes each, the slot taken modulo eight.
; Slot 0 is the bootloader and never boots, so its white entry is what a slot
; past the end of the table lands on.
        EVEN
led_colours:
        DC.B    $40,$40,$40             ; 0 white
        DC.B    $00,$FF,$00             ; 1 green
        DC.B    $00,$40,$FF             ; 2 blue
        DC.B    $FF,$00,$00             ; 3 red
        DC.B    $FF,$80,$00             ; 4 orange
        DC.B    $FF,$00,$FF             ; 5 magenta
        DC.B    $00,$FF,$FF             ; 6 cyan
        DC.B    $FF,$FF,$00             ; 7 yellow


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
