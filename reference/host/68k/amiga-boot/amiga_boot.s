; amiga_boot.s — Amiga RBCP Kickstart bootloader
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Lets an Amiga pick which Kickstart image it boots from those held on the
; RBCP device serving its ROM socket.  It enters command-response mode, reads
; what the device holds, and boots the remembered or default image at once.
; Holding both mouse buttons at boot brings up a menu instead.  See README.md
; for the controls, the display and what has been tested on hardware.
;
; ROM image layout, top-aligned — 256 KB from $FC0000 or 512 KB from $F80000:
;
;   ROM SECTION  — executed directly from ROM
;     ROM header, boot_cold_start, JMP boot_rom_entry
;     amiga_hw.s: a500_hw_init, exc_halt, screen_init
;     boot_rom_entry: HW init, screen up, copy RAM section, JMP $8000
;
;   RAM SECTION  — stored in ROM, copied to RAM_CODE_BASE ($20000) at boot
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
;   reads.  Code fetched from that same ROM puts its own instruction-fetch
;   addresses on the bus and corrupts the sequence the device sees, so it runs
;   from chip RAM.  Once command-response mode is established the device
;   filters on the command page and ROM reads elsewhere are harmless — the
;   screen routines read the font from ROM and may be called after entry, but
;   never between the knock and the response to ENTER_CMD_RESP.
;
;   The initial hardware setup runs from ROM because it must execute before
;   the RAM section is copied.  It performs no RBCP address sequences.
;
; Addressing note:
;   RAM-section code reaches ROM data through explicit absolute long
;   addressing — LEA (label).L,A0 — never PC-relative, because the code is
;   assembled at its ROM address but executes from $8000.  The .L suffix also
;   stops the assembler shortening high addresses to sign-extended absolute
;   short, which works on a 68000's 24-bit bus but not on a 32-bit one.

; Definitions first — the ORG below depends on CONFIG_ROM_BASE.  None of
; these emit any code or data.
        INCLUDE "rbcp_config.s"
        INCLUDE "../rbcp/rbcp_defs.s"
        INCLUDE "amiga_config.s"
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
        DC.L    boot_cold_start         ; initial PC

        DCB.B   $D0-(*-ROMStart),$00    ; pad to offset $D0

        RESET                           ; +$D0: soft-reset entry
boot_cold_start:                        ; +$D2: CPU jumps here on power-on
        JMP     boot_rom_entry

; ---------------------------------------------------------------------------
; ROM-section hardware routines: a500_hw_init, exc_halt, screen_init
; screen_init contains a forward BSR to screen_clear in the RAM section.  Both
; are in ROM at assembly time, so the PC-relative branch is correct there.
; ---------------------------------------------------------------------------
        INCLUDE "amiga_hw.s"

; ---------------------------------------------------------------------------
; boot_rom_entry — runs from ROM.  Clears OVL, sets the stack, brings the
; hardware and the display up, copies the RAM section to RAM_CODE_BASE and
; jumps to it.
;
; The screen is up before the RAM copy, so a machine that fails in the copy
; still shows the boot progress colour.
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
        JMP     (RAM_CODE_BASE).L

; ============================================================
; RAM SECTION
; Stored in the ROM image between ram_section_rom_start and
; ram_section_rom_end, copied word-by-word to RAM_CODE_BASE.
;
; boot_ram_entry is at offset 0 so JMP RAM_CODE_BASE enters it directly.
; BSR/BRA within this section are PC-relative and span the same distance in
; ROM and in the copy.  References out of it use absolute long addressing.
; ============================================================
ram_section_rom_start:

; ---------------------------------------------------------------------------
; boot_ram_entry — the bootloader proper, running from chip RAM.  The session
; with the device, then either the menu or a straight boot.
;
; A device with a single RAM slot (a 27C400, or a 27C200 on some boards)
; cannot stage a load in a spare slot, so it boots with LOAD_AND_EXIT into the
; active slot instead, and cannot remember a choice.
; ---------------------------------------------------------------------------
boot_ram_entry:
        MOVE.L  #BITPLANE_BASE,VAR_DRAW_BASE
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        MOVE.B  #MENU_COL,VAR_MENU_COL
        ; The beam line an animation step and the chime's wait both work from,
        ; which is the first line off the bottom of the display.
        MOVE.W  #FIELD_TICK_NTSC,VAR_TICK_LINE
        TST.B   VAR_IS_PAL
        BEQ.S   .bre_ntsc
        MOVE.W  #FIELD_TICK_PAL,VAR_TICK_LINE
.bre_ntsc:
        BSR     screen_clear
        BSR     banner_init             ; artwork into chip RAM, before any
                                        ; RBCP command is in flight
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
        ; Where the block of text beside the logo starts — see
        ; MENU_CENTRE_SUM.  The count is settled here and does not change
        ; while the menu is up.
        MOVEQ   #MENU_CENTRE_SUM,D1
        SUB.B   D0,D1
        LSR.B   #1,D1                   ; the title's row
        ADDQ.B  #MENU_TITLE_GAP,D1      ; the entries start below it
        MOVE.B  D1,VAR_MENU_ROW0

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
        ; Both mouse buttons held asks for the menu, the gesture the Amiga's
        ; own early-startup screen uses.
    ifne CONFIG_DEV_ALWAYS_MENU
        MOVEQ   #1,D0                   ; development build: always the menu
    else
        BSR     both_buttons_held
    endc
        TST.B   D0
        BNE.S   .want_menu
        LEA     (msg_autoboot).L,A0
        BSR     log_line
        MOVE.B  VAR_BOOT_FLASH,D0
        BRA     boot_slot
.want_menu:
    ifne CONFIG_BOOT_CHIME
        BSR     chime_start             ; only where the menu was asked for
    endc
        LEA     (msg_menu).L,A0
        BSR     log_line
        BSR     led_cycle
        ; The ball goes last, so nothing it has to pass behind is drawn after
        ; it starts moving.
        BSR     banner_show
        BSR     menu_draw_text
        BSR     draw_footer
        BSR     draw_device
        BSR     banner_start
        ; The buttons are still held, so the menu opens in the state that
        ; watches for them coming up.  The loop animates throughout.
        MOVE.L  #RELEASE_LIMIT,VAR_REL_CNT
        CLR.B   VAR_PEND_KEY
        MOVE.B  #ST_RELEASE,VAR_STATE
        ; fall through

; ---------------------------------------------------------------------------
; main_loop — the one loop the menu runs in, and the only place anything
; periodic happens.
;
; Nothing it calls waits.  A routine that cannot finish this pass records
; where it got to and returns, so every pass is short and every pass reaches
; tick_periodic.  Adding a state below cannot stop the ball, because keeping
; the ball moving is not that state's business.
; ---------------------------------------------------------------------------
main_loop:
        BSR     tick_periodic
        CMPI.B  #ST_RELEASE,VAR_STATE
        BNE.S   .ml_menu
        BSR     release_step
        BRA.S   main_loop
.ml_menu:
        BSR     state_menu
        BRA.S   main_loop

; ---------------------------------------------------------------------------
; tick_periodic — everything that has to keep happening, whatever state the
; loop is in.  Called once a pass from main_loop and from nowhere else.
;
; The hook itself is outside the art switches.  A build without a ball drops
; what is inside it, not the hook, so periodic work always has somewhere to go.
; ---------------------------------------------------------------------------
tick_periodic:
    ifne CONFIG_BOOT_CHIME
        BSR     chime_tick              ; silence it once it has played out
    endc
    ifne CONFIG_BANNER_BALL
        BSR     banner_tick             ; one step of the animation
    endc
        RTS

    ifne CONFIG_BOOT_CHIME
; ---------------------------------------------------------------------------
; chime_tick — start the chime when its wait is up, and switch the channel off
; one pass later.
;
; Paula has no way to play a sample once.  It repeats for as long as the
; channel is on, so a single chime means switching the channel off after one
; pass, and the length of a pass is known exactly from the sample and the
; period.  The counter is free running, so both moments are right however long
; the loop spent elsewhere.
; ---------------------------------------------------------------------------
chime_tick:
        TST.B   VAR_CHIME_ON
        BEQ     .cht_out
        MOVEM.L D0-D1,-(SP)
        BSR     tod_now
        SUB.L   VAR_CHIME_END,D0
        ANDI.L  #$00FFFFFF,D0
        CMPI.L  #$00800000,D0
        BCC     .cht_done               ; the moment has not come round yet
        CMPI.B  #1,VAR_CHIME_ON
        BNE     .cht_off

        ; --- time to play it ---
        MOVE.W  #INTF_AUD0,INTREQ
        MOVE.L  #CHIP_CHIME,AUD0LCH
        MOVE.W  #CHIME_LEN_WORDS,AUD0LEN
        MOVE.W  #CHIME_VOLUME,AUD0VOL
        MOVE.W  #CHIME_PERIOD_NTSC,AUD0PER
        TST.B   VAR_IS_PAL
        BEQ     .cht_on
        MOVE.W  #CHIME_PERIOD,AUD0PER
.cht_on:
        MOVE.W  #$8000+DMAF_AUD0,DMACON
        BSR     tod_now                 ; and off again one pass later
        ADDI.L  #CHIME_TICKS_NTSC,D0
        TST.B   VAR_IS_PAL
        BEQ     .cht_end
        SUBI.L  #CHIME_TICKS_NTSC-CHIME_TICKS_PAL,D0
.cht_end:
        ANDI.L  #$00FFFFFF,D0
        MOVE.L  D0,VAR_CHIME_END
        MOVE.B  #2,VAR_CHIME_ON
        BRA     .cht_done

        ; --- one pass done, switch it off ---
.cht_off:
        CLR.W   AUD0VOL
        MOVE.W  #DMAF_AUD0,DMACON
        CLR.B   VAR_CHIME_ON
.cht_done:
        MOVEM.L (SP)+,D0-D1
.cht_out:
        RTS
    endc

; ---------------------------------------------------------------------------
; release_step — one test of the mouse buttons the menu was asked for with.
; The menu takes no input until they are up, or until the count runs out.
; ---------------------------------------------------------------------------
release_step:
        MOVEM.L D1,-(SP)
        BTST    #CIAA_PRA_LMB,(CIAA_PRA).L
        BEQ.S   .rs_held                ; left still down
        MOVE.W  (POTGOR).L,D1
        BTST    #POTGOR_RMB,D1
        BNE.S   .rs_up                  ; both up
.rs_held:
        SUBQ.L  #1,VAR_REL_CNT
        BNE.S   .rs_out
.rs_up:
        BSR.S   release_settle
        CLR.B   VAR_LMB_HELD
        CLR.B   VAR_RMB_HELD
        CLR.W   VAR_LMB_UP_CNT
        MOVE.B  #ST_MENU,VAR_STATE
.rs_out:
        MOVEM.L (SP)+,D1
        RTS

; release_settle — the settle after the buttons read up.  It waits for
; nothing, it is the same length every time and it runs once.
release_settle:
        MOVEM.L D0,-(SP)
        MOVE.W  #RELEASE_SETTLE,D0
.rst_loop:
        SUBQ.W  #1,D0
        BNE.S   .rst_loop
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; state_menu — one poll of the keyboard and the mouse, and what it asks for.
; A left click or the arrows change the choice, a right click or RETURN boots
; it, and a digit picks one of the first nine.
;
; Acting on a key redraws, which needs the blitter, so a key that arrives
; mid-frame is held until the frame is on screen rather than waited out on
; BBUSY.  That is at most one frame's blits, and no key is lost: the keyboard
; is left un-acknowledged until the held one has been dealt with.
; ---------------------------------------------------------------------------
state_menu:
        TST.B   VAR_PEND_KEY
        BNE.S   .sm_ready
        BSR     amiga_getkey
        TST.B   D0
        BEQ.S   .sm_done
        MOVE.B  D0,VAR_PEND_KEY
.sm_ready:
    ifne CONFIG_BANNER_BALL
        TST.B   VAR_ANIM_STEP
        BNE.S   .sm_done                ; a frame is part way through
        BTST    #6,(DMACONR).L          ; BBUSY: its last blit is still running
        BNE.S   .sm_done
    endc
        MOVEQ   #0,D0
        MOVE.B  VAR_PEND_KEY,D0
        CLR.B   VAR_PEND_KEY
        CMPI.B  #KEY_RETURN,D0
        BEQ     do_boot
        CMPI.B  #KEY_RMB,D0
        BEQ     do_boot                 ; a right click boots the highlight
        CMPI.B  #KEY_UP,D0
        BEQ.S   .sm_up
        CMPI.B  #KEY_LMB,D0
        BEQ.S   .sm_click
        CMPI.B  #KEY_DOWN,D0
        BEQ.S   .sm_down
        CMPI.B  #'1',D0
        BCS.S   .sm_done
        CMPI.B  #'9'+1,D0
        BCC.S   .sm_done
        SUBI.B  #'1',D0                 ; the digit is the entry
        CMP.B   VAR_NUM_DISPLAY,D0
        BCC.S   .sm_done
        BRA     menu_select
.sm_up:
        TST.B   VAR_SELECTION
        BEQ.S   .sm_done
        MOVEQ   #0,D0
        MOVE.B  VAR_SELECTION,D0
        SUBQ.B  #1,D0
        BRA     menu_select
.sm_down:
        MOVEQ   #0,D0
        MOVE.B  VAR_SELECTION,D0
        ADDQ.B  #1,D0
        CMP.B   VAR_NUM_DISPLAY,D0
        BCC.S   .sm_done
        BRA     menu_select
.sm_click:
        BRA     sel_cycle_down
.sm_done:
        RTS

; sel_cycle_down — move the highlight down one, wrapping to the top, so
; mouse-only operation can reach every entry.
sel_cycle_down:
        MOVEM.L D0,-(SP)
        MOVEQ   #0,D0
        MOVE.B  VAR_SELECTION,D0
        ADDQ.B  #1,D0
        CMP.B   VAR_NUM_DISPLAY,D0
        BCS.S   .scd_ok
        MOVEQ   #0,D0                   ; past the end, wrap to the top
.scd_ok:
        BSR     menu_select
        MOVEM.L (SP)+,D0
        RTS

do_boot:
        BSR     banner_stop             ; nothing moving while RBCP is talking
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
    ifne CONFIG_BOOT_CHIME
        BSR     chime_stop
    endc
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

; ---------------------------------------------------------------------------
; draw_title — what this is, above the list and beside the top of the logo.
; It starts at the list's own column, so it lines up with the "1)" of the
; entry beneath it.
; ---------------------------------------------------------------------------
draw_title:
        MOVEM.L D0-D2/A0,-(SP)
        MOVE.B  #PEN_TEXT,VAR_PEN
        LEA     (str_title).L,A0
        MOVE.B  #MENU_COL,D1
        MOVE.B  VAR_MENU_ROW0,D2
        SUBQ.B  #MENU_TITLE_GAP,D2
        BSR     screen_print
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; draw_title_at — D2.B = row, centred across the screen.  The error screen
; clears everything away and needs a heading of its own.
; ---------------------------------------------------------------------------
draw_title_at:
        MOVE.B  #PEN_TEXT,VAR_PEN
        LEA     (str_title).L,A0
        BSR     screen_print_centred
        RTS

; ---------------------------------------------------------------------------
; draw_device — the device's own name and version along the bottom, with the
; author beside them.  A device that will not name itself gets the author line
; alone.
;
; Forty columns leave no room for a long device name beside "piers.rocks", so
; the print limit is pulled in and a name that would reach it is cut short.
; ---------------------------------------------------------------------------
draw_device:
        MOVE.B  #PEN_LIGHT,VAR_PEN
        MOVE.B  #ROCKS_COL-1,VAR_COL_MAX
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
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        MOVE.B  #PEN_GOLD,VAR_PEN
        LEA     (str_rocks).L,A0
        MOVE.B  #ROCKS_COL,D1
        MOVE.B  #DEVICE_ROW,D2
        BSR     screen_print
        MOVE.B  #PEN_TEXT,VAR_PEN
        RTS

; ---------------------------------------------------------------------------
; draw_list — the images down the right of the band, beside the logo.  Every
; entry starts at MENU_COL, and a name wider than the columns left is cut
; short by screen_print rather than wrapped.
;
; One command carries one name, so every name is read before any is drawn.
; D7 is the 0-based display index across both passes, which the command
; helpers preserve.
; ---------------------------------------------------------------------------
draw_list:
        MOVEM.L D3-D7/A0-A1,-(SP)

        ; --- pass one: read every name ---
        MOVEQ   #0,D7
.dl_fetch:
        MOVE.B  VAR_NUM_DISPLAY,D0
        CMP.B   D7,D0
        BLS     .dl_place               ; D7 >= num_display
        LEA     (NAME_LEN_TAB).W,A1
        CLR.B   (A1,D7.W)               ; no entry until the device names one
        MOVE.B  D7,D0
        ADDQ.B  #1,D0                   ; flash slot
        BSR     rbcp_cmd_get_flash_info
        TST.B   D0
        BNE.S   .dl_fnext               ; a slot that will not describe: skip
        MOVEQ   #32,D0
        BSR     rbcp_read_data

        LEA     (CONFIG_RBCP_DATA_BUF+RBCP_FLASH_NAME).W,A0
        BSR     name_slot_addr          ; A1 = this entry's room in NAME_BUF
        MOVEQ   #0,D5
.dl_copy:
        MOVE.B  (A0)+,D0
        MOVE.B  D0,(A1)+
        BEQ.S   .dl_copied
        ADDQ.W  #1,D5
        CMPI.W  #NAME_STRIDE-1,D5
        BCS.S   .dl_copy
        CLR.B   (A1)                    ; terminate a name that filled its room
.dl_copied:
        LEA     (NAME_LEN_TAB).W,A1
        MOVE.B  D5,(A1,D7.W)
        BSR     log_entry               ; name is still in the un-swap buffer
.dl_fnext:
        ADDQ.B  #1,D7
        BRA     .dl_fetch

        ; --- pass two: draw them all ---
.dl_place:
        MOVE.B  #MENU_COL,VAR_MENU_COL
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEQ   #0,D7
.dl_draw:
        MOVE.B  VAR_NUM_DISPLAY,D0
        CMP.B   D7,D0
        BLS.S   .dl_done
        BSR     draw_entry
        ADDQ.B  #1,D7
        BRA.S   .dl_draw
.dl_done:
        MOVEM.L (SP)+,D3-D7/A0-A1
        RTS

; ---------------------------------------------------------------------------
; draw_entry — D7.B = display index.  Draws "N) name" in the current pen, at
; the column draw_list settled on for every entry.  The number shown is the
; flash slot, one more than the list place because slot 0 is the bootloader,
; and it doubles as the digit key that picks the entry.  An entry the device
; would not name is left alone.
; ---------------------------------------------------------------------------
draw_entry:
        MOVEM.L D0-D3/A0-A1,-(SP)
        MOVEQ   #0,D3
        MOVE.B  D7,D3
        LEA     (NAME_LEN_TAB).W,A1
        TST.B   (A1,D3.W)
        BEQ.S   .de_done

        MOVE.B  D7,D2
        ADD.B   VAR_MENU_ROW0,D2
        MOVE.B  D7,D0
        ADDQ.B  #1,D0
        ADDI.B  #'0',D0                 ; '1'..'9'
        MOVE.B  VAR_MENU_COL,D1
        BSR     screen_putchar
        MOVEQ   #')',D0
        ADDQ.B  #1,D1
        BSR     screen_putchar
        MOVEQ   #' ',D0                 ; the gap the name is set back from,
        ADDQ.B  #1,D1                   ; drawn so the entry paints its whole
        BSR     screen_putchar          ; span whatever was under it

        BSR     name_slot_addr
        MOVEA.L A1,A0
        MOVE.B  VAR_MENU_COL,D1
        ADDQ.B  #MENU_PREFIX,D1
        BSR     screen_print
.de_done:
        MOVEM.L (SP)+,D0-D3/A0-A1
        RTS

; name_slot_addr — D7.B = display index, returns A1 = that entry's name in
; NAME_BUF.  Every data register is preserved.
name_slot_addr:
        MOVEM.L D0,-(SP)
        MOVEQ   #0,D0
        MOVE.B  D7,D0
        MULU    #NAME_STRIDE,D0
        LEA     (NAME_BUF).W,A1
        ADDA.W  D0,A1
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; The highlight is a solid gold bar across the list's columns with the entry
; re-drawn in black on it.  It stops where the list does, so it cannot run
; under the logo beside it.
; ---------------------------------------------------------------------------
highlight_selection:
        MOVEM.L D0,-(SP)
        MOVE.B  #PEN_GOLD,VAR_PEN
        BSR.S   sel_row
        BSR     screen_fill_row         ; the bar, right across the row
        MOVE.B  #PEN_BG,VAR_PEN         ; black glyphs
        MOVE.B  #PEN_GOLD,VAR_PEN_BG    ; on the gold behind them
        BSR.S   draw_sel_entry
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVEM.L (SP)+,D0
        RTS

unhighlight_selection:
        MOVEM.L D0,-(SP)
        MOVE.B  #PEN_BG,VAR_PEN
        BSR.S   sel_row
        BSR     screen_fill_row         ; the bar away again
        MOVE.B  #PEN_TEXT,VAR_PEN
        BSR.S   draw_sel_entry
        MOVEM.L (SP)+,D0
        RTS

; sel_row — D0.B = the text row the selected entry sits on.
sel_row:
        MOVEQ   #0,D0
        MOVE.B  VAR_SELECTION,D0
        ADD.B   VAR_MENU_ROW0,D0
        RTS

; draw_sel_entry — draw the selected entry.  draw_entry takes its index in D7,
; which the menu loops are using for their own count.
draw_sel_entry:
        MOVEM.L D7,-(SP)
        MOVEQ   #0,D7
        MOVE.B  VAR_SELECTION,D7
        BSR     draw_entry
        MOVEM.L (SP)+,D7
        RTS

; draw_footer — the controls line, centred.
draw_footer:
        MOVE.B  #PEN_LIGHT,VAR_PEN
        LEA     (str_footer).L,A0
        MOVE.B  #FOOTER_ROW,D2
        BSR     screen_print_centred
        MOVE.B  #PEN_TEXT,VAR_PEN
        RTS

; ---------------------------------------------------------------------------
; amiga_getkey — one poll of the keyboard and the mouse buttons.
; Returns D0.B: 0 none, KEY_UP/DOWN/RETURN, KEY_LMB, or '1'..'9' for a digit.
;
; The keyboard arrives over the CIA-A serial port.  A received byte is the
; keycode rotated and inverted, and bit 7 after decoding is the key-up flag.
; The host must acknowledge each byte by driving the serial line as an output
; for a short pulse, or the keyboard stops sending.
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
        BNE     .gk_none                ; a key release, ignore
        ANDI.B  #$7F,D0
        CMPI.B  #KBD_UP,D0
        BEQ.S   .gk_up
        CMPI.B  #KBD_DOWN,D0
        BEQ.S   .gk_down
        CMPI.B  #KBD_RETURN,D0
        BEQ.S   .gk_ret
        TST.B   D0                      ; digit scancodes are $01..$09
        BEQ     .gk_none
        CMPI.B  #$0A,D0
        BCC     .gk_none
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
        CLR.W   VAR_LMB_UP_CNT          ; down again: the settle count restarts
        TST.B   VAR_LMB_HELD
        BNE.S   .gk_rmb                 ; already reported this press
        MOVE.B  #1,VAR_LMB_HELD
        MOVEQ   #KEY_LMB,D0
        BRA.S   .gk_out
.gk_lmbup:
        ; Arm the next press once the button has read up long enough for the
        ; contact to have settled.  Bounce on either edge restarts the count.
        TST.B   VAR_LMB_HELD
        BEQ.S   .gk_rmb                 ; already armed
        ADDQ.W  #1,VAR_LMB_UP_CNT
        CMPI.W  #LMB_DEBOUNCE,VAR_LMB_UP_CNT
        BCS.S   .gk_rmb                 ; still settling
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
    ifne CONFIG_BOOT_CHIME
        BSR     chime_stop              ; nothing left running behind the error
    endc
        MOVE.L  #BITPLANE_BASE,VAR_DRAW_BASE    ; on screen, wherever we came
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX        ; from
        BSR     screen_clear
        ; The copper writes COLOR00 every frame, so the background changes by
        ; writing the copper list, not the register.
        MOVE.W  #COL_RED,(COPPER_BASE+COP_OFF_COLOR00).W
        MOVE.B  #ERR_TITLE_ROW,D2
        BSR     draw_title_at
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
; next field chains on.  Clobbers D1 deliberately, and saves the rest.
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


; ===========================================================================
; Banner — the tagline heading, the band, and the ball that bounces in it
;
; Everything here runs from the RAM section and touches only chip RAM and the
; custom chips, so it cannot put a byte on the ROM bus.  That matters: while
; an RBCP command is in flight a ROM read is taken by the device as the next
; byte of the command, and the session comes apart with neither end able to
; tell.  The animation is driven from the menu's own polling loop rather than
; from a vertical blank interrupt, so it only ever runs at a moment when the
; bootloader has nothing outstanding — the session's questions are all
; answered before the menu goes up, and banner_stop runs before the commands
; that boot a slot.
;
; Copper, blitter and audio DMA read chip RAM and never the ROM, so they are
; left running throughout.
;
; The ball has to pass behind the logo and behind the list.  The logo carries
; a mask of its own, but text carries none, and putting the intersecting rows
; of text back with the CPU costs more than a whole frame.  So the screen's
; whole contents are built once into an object laid out exactly as the bitmap
; is, with a mask beside it, and the frame puts back only the rectangle the
; ball covers.
; ===========================================================================

    ifne BANNER_FG
; The object covers the whole screen, so a row number lands at the same offset
; in either and the base is all that has to change.
FG_DRAW_BASE        EQU CHIP_FG
    endc

; ---------------------------------------------------------------------------
; banner_init — the artwork and the sample into chip RAM, where the blitter
; and Paula can reach them.  Called before the RBCP session starts.
; ---------------------------------------------------------------------------
banner_init:
        MOVEM.L D0-D2/A0-A1,-(SP)
    ifne CONFIG_BANNER_ART
        MOVEA.L #LogoData,A0
        MOVEA.L #CHIP_LOGO,A1
        MOVE.W  #LOGO_BYTES/2-1,D0
        BSR     copy_words
        MOVEA.L #LogoMask,A0
        MOVEA.L #CHIP_LOGO_MASK,A1
        MOVE.W  #LOGO_ROW_BYTES/2,D1
        MOVE.W  #LOGO_HEIGHT-1,D2
        BSR     spread_mask

        MOVEA.L #TaglineWideData,A0
        MOVEA.L #CHIP_TAGLINE,A1
        MOVE.W  #TAGLINE_WIDE_BYTES/2-1,D0
        BSR     copy_words
    endc
    ifne CONFIG_BANNER_BALL
        MOVEA.L #BallData,A0
        MOVEA.L #CHIP_BALL,A1
        MOVE.W  #BALL_BYTES/2-1,D0
        BSR     copy_words
        MOVEA.L #BallMask,A0
        MOVEA.L #CHIP_BALL_MASK,A1
        MOVE.W  #BALL_ROW_BYTES/2,D1
        MOVE.W  #BALL_HEIGHT-1,D2
        BSR     spread_mask
    endc
    ifne BANNER_SHADOW
        MOVEA.L #BallMask,A0
        MOVEA.L #CHIP_BALL_SHADOW,A1
        MOVE.W  #BALL_ROW_BYTES/2,D1
        MOVE.W  #BALL_HEIGHT-1,D2
        BSR     build_shadow
    endc
    ifne CONFIG_BOOT_CHIME
        MOVEA.L #ChimeData,A0
        MOVEA.L #CHIP_CHIME,A1
        MOVE.W  #CHIME_LEN_WORDS-1,D0
        BSR     copy_words
    endc
        MOVEM.L (SP)+,D0-D2/A0-A1
        RTS

    ifne CONFIG_BANNER_ART+CONFIG_BANNER_BALL+CONFIG_BOOT_CHIME
; copy_words — A0 to A1, D0.W = words less one.
copy_words:
        MOVEM.L D0/A0-A1,-(SP)
.cw_loop:
        MOVE.W  (A0)+,(A1)+
        DBF     D0,.cw_loop
        MOVEM.L (SP)+,D0/A0-A1
        RTS
    endc

    ifne CONFIG_BANNER_ART+CONFIG_BANNER_BALL
; ---------------------------------------------------------------------------
; spread_mask — A0 = a one-plane mask, A1 = where it goes, D1.W = words in a
; mask row, D2.W = rows less one.  Writes every row four times over, so the
; result lines up with the four-plane object beside it and one cookie-cut blit
; covers all four planes.
; ---------------------------------------------------------------------------
spread_mask:
        MOVEM.L D0-D3/A0-A2,-(SP)
.sm_row:
        MOVEQ   #SCREEN_PLANES-1,D3
.sm_plane:
        MOVEA.L A0,A2                   ; each plane takes the same mask row
        MOVE.W  D1,D0
        SUBQ.W  #1,D0
.sm_word:
        MOVE.W  (A2)+,(A1)+
        DBF     D0,.sm_word
        DBF     D3,.sm_plane
        MOVEA.L A2,A0                   ; on to the next mask row
        DBF     D2,.sm_row
        MOVEM.L (SP)+,D0-D3/A0-A2
        RTS

    endc

    ifne BANNER_SHADOW
; ---------------------------------------------------------------------------
; build_shadow — the same arguments as spread_mask, but plane 0 is left clear
; and the mask goes into planes 1, 2 and 3.  Pen 14 is %1110, so the result is
; a solid shadow-coloured copy of the ball's silhouette.
; ---------------------------------------------------------------------------
build_shadow:
        MOVEM.L D0-D3/A0-A2,-(SP)
.bs_row:
        MOVE.W  D1,D0
        SUBQ.W  #1,D0
.bs_clear:
        CLR.W   (A1)+                   ; plane 0
        DBF     D0,.bs_clear
        MOVEQ   #SCREEN_PLANES-2,D3
.bs_plane:
        MOVEA.L A0,A2
        MOVE.W  D1,D0
        SUBQ.W  #1,D0
.bs_word:
        MOVE.W  (A2)+,(A1)+
        DBF     D0,.bs_word
        DBF     D3,.bs_plane
        MOVEA.L A2,A0
        DBF     D2,.bs_row
        MOVEM.L (SP)+,D0-D3/A0-A2
        RTS
    endc

; ---------------------------------------------------------------------------
; banner_show — the heading and the logo into the foreground object where
; there is a ball to pass behind them, straight on screen where there is not.
; Only the base address differs.
; ---------------------------------------------------------------------------
banner_show:
        MOVEM.L D0-D7/A0-A3,-(SP)
    ifne BANNER_FG
        BSR     fg_clear
        MOVE.L  #FG_DRAW_BASE,VAR_DRAW_BASE
    endc
    ifne CONFIG_BANNER_ART
        MOVEA.L #CHIP_TAGLINE,A0        ; the heading, on ground still clear,
        MOVE.W  #TAGLINE_WIDE_WIDTH_W,D0        ; so it needs no mask of its own
        MOVE.W  #TAGLINE_WIDE_HEIGHT,D1
        MOVE.W  #TAGLINE_X,D6
        MOVE.W  #TAGLINE_Y,D7
        BSR     draw_object_solid

        MOVEA.L #CHIP_LOGO,A0
        MOVEA.L #CHIP_LOGO_MASK,A2
        MOVE.W  #LOGO_WIDTH_W,D0
        MOVE.W  #LOGO_HEIGHT,D1
        MOVE.W  #LOGO_X,D6
        MOVE.W  #LOGO_Y,D7
        BSR     draw_object
    endc
    ifne BANNER_FG
        MOVE.L  #BITPLANE_BASE,VAR_DRAW_BASE
    endc
        MOVEM.L (SP)+,D0-D7/A0-A3
        RTS

; ---------------------------------------------------------------------------
; menu_draw_text — everything else the menu says, and the screen put up.
; With a ball this goes into the foreground object, its mask is worked out
; from what was drawn, and the whole screen goes over in one blit.  Without a
; ball it is ordinary drawing.
; ---------------------------------------------------------------------------
menu_draw_text:
    ifne BANNER_FG
        MOVE.L  #FG_DRAW_BASE,VAR_DRAW_BASE
    endc
        BSR     draw_title
        BSR     draw_list
        BSR     highlight_selection
        BSR     draw_footer
        BSR     draw_device
    ifne BANNER_FG
        BSR     fg_mask_all
        MOVE.L  #BITPLANE_BASE,VAR_DRAW_BASE
        BSR     fg_show
    endc
        RTS

; ---------------------------------------------------------------------------
; menu_select — D0.B = the entry to highlight.  Moves the bar in the object
; and puts the screen back up.  The ball is left where it was and the next
; frame draws it again.
; ---------------------------------------------------------------------------
menu_select:
        MOVEM.L D0,-(SP)
    ifne BANNER_FG
        MOVE.L  #FG_DRAW_BASE,VAR_DRAW_BASE
    endc
        BSR     unhighlight_selection
        MOVE.L  (SP),D0
        MOVE.B  D0,VAR_SELECTION
        BSR     highlight_selection
    ifne BANNER_FG
        BSR     fg_mask_sel
        MOVE.L  #BITPLANE_BASE,VAR_DRAW_BASE
        BSR     fg_show
    endc
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; banner_start — set the ball going, once everything it passes behind is up.
; ---------------------------------------------------------------------------
banner_start:
    ifne CONFIG_BANNER_BALL
        MOVEM.L D0-D7/A0-A3,-(SP)
        MOVE.L  #BALL_START_X<<8,VAR_BALL_X
        MOVE.L  #BALL_START_Y<<8,VAR_BALL_Y
        MOVE.W  #BALL_VX,VAR_BALL_VX
        MOVE.W  #BALL_VY,VAR_BALL_VY
        MOVE.W  #BALL_START_X,VAR_BALL_PX
        MOVE.W  #BALL_START_Y,VAR_BALL_PY
        ; How far down the ball may go follows the Agnus: 200 lines are shown
        ; on an NTSC machine where a PAL one shows 256.
        MOVE.L  #BALL_Y_MAX_NTSC<<8,VAR_BALL_Y_MAX
        TST.B   VAR_IS_PAL
        BEQ.S   .bst_ntsc
        MOVE.L  #BALL_Y_MAX_PAL<<8,VAR_BALL_Y_MAX
.bst_ntsc:
        CLR.B   VAR_SPIN_STEP
        MOVE.B  #BANNER_SPIN_FRAMES,VAR_SPIN_TICK
        CLR.B   VAR_FRAME_SEEN
        MOVE.B  #AN_IDLE,VAR_ANIM_STEP
        CLR.B   VAR_ANIM_PLANE
        BSR     ball_colours
        BSR     ball_draw
        BSR     ball_cover_all
        MOVEM.L (SP)+,D0-D7/A0-A3
    endc
        RTS

; ---------------------------------------------------------------------------
; banner_stop — everything the banner set running, stopped.  Called before the
; commands that boot a slot, so nothing is stealing bus cycles while the
; device is being talked to.
; ---------------------------------------------------------------------------
banner_stop:
    ifne CONFIG_BANNER_BALL
        MOVE.B  #AN_IDLE,VAR_ANIM_STEP  ; no frame left half drawn
    endc
    ifne CONFIG_BANNER_ART+CONFIG_BANNER_BALL
        BRA     blit_wait
    else
        RTS
    endc

    ifne CONFIG_BANNER_BALL+CONFIG_BOOT_CHIME
; ---------------------------------------------------------------------------
; beam_line — D0.W = the beam's line, all nine bits of it.  VPOSR carries the
; top bit and VHPOSR the rest, and a long read takes both at once.
; ---------------------------------------------------------------------------
beam_line:
        MOVE.L  (VPOSR).L,D0
        LSR.L   #8,D0
        ANDI.W  #$01FF,D0
        RTS

; ---------------------------------------------------------------------------
; tod_now — D0.L = the CIA-B time of day counter, 24 bits.
;
; Reading the high byte latches all three so the value cannot tear, and
; reading the low byte lets it go again.
; ---------------------------------------------------------------------------
tod_now:
        MOVEM.L D1,-(SP)
        MOVEQ   #0,D0
        MOVE.B  (CIAB_TODHI).L,D0
        LSL.L   #8,D0
        MOVE.B  (CIAB_TODMID).L,D0
        LSL.L   #8,D0
        MOVE.B  (CIAB_TODLO).L,D0
        ANDI.L  #$00FFFFFF,D0
        MOVEM.L (SP)+,D1
        RTS

; ---------------------------------------------------------------------------
; tod_start — set the counter going from zero.
;
; Writing the low byte is what starts it, and the high byte must be written
; first.  CRB bit 7 clear means the writes go to the counter and not the alarm.
; ---------------------------------------------------------------------------
tod_start:
        MOVEM.L D0,-(SP)
        MOVE.B  (CIAB_CRB).L,D0
        ANDI.B  #$7F,D0
        MOVE.B  D0,(CIAB_CRB).L
        CLR.B   (CIAB_TODHI).L
        CLR.B   (CIAB_TODMID).L
        CLR.B   (CIAB_TODLO).L          ; this one starts it
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; wait_field — hold until the beam next leaves the display.  Chip registers
; only, so no ROM is read while it waits.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
wait_field:
        MOVEM.L D0,-(SP)
.wf_below:
        BSR     beam_line
        CMP.W   VAR_TICK_LINE,D0
        BCC.S   .wf_below               ; still past it from last time
.wf_reach:
        BSR     beam_line
        CMP.W   VAR_TICK_LINE,D0
        BCS.S   .wf_reach
        MOVEM.L (SP)+,D0
        RTS
    endc

    ifne CONFIG_BANNER_BALL
; ---------------------------------------------------------------------------
; banner_tick — one step of the animation, from tick_periodic.  It never
; waits: a step that needs the blitter and finds it busy leaves the state
; alone and returns, so the pass goes on to read the keyboard instead.
;
; A frame still starts when the beam leaves the display — see FIELD_TICK_NTSC
; — and its blits still run back to back.  The difference is where the CPU
; spends the gaps between them.
; ---------------------------------------------------------------------------
banner_tick:
        MOVEM.L D0,-(SP)
        TST.B   VAR_ANIM_STEP
        BNE.S   .bt_step
        ; --- between frames: the beam is the clock ---
        BSR     beam_line
        CMP.W   VAR_TICK_LINE,D0
        BCS.S   .bt_above
        TST.B   VAR_FRAME_SEEN
        BNE.S   .bt_done
        MOVE.B  #1,VAR_FRAME_SEEN
        MOVE.B  #AN_RESTORE,VAR_ANIM_STEP
        BRA.S   .bt_step
.bt_above:
        CLR.B   VAR_FRAME_SEEN          ; a new field has started
        BRA.S   .bt_done
.bt_step:
        BTST    #6,(DMACONR).L          ; BBUSY: the last blit is still running
        BNE.S   .bt_done
        BSR.S   banner_step
.bt_done:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; banner_step — the step the frame has reached, with the blitter known free.
; Each one sets up a single blit and returns.
;
; The band's object goes back over where the ball was, which both takes the
; ball away and restores whatever it was covering.  Then the shadow, the ball,
; and the object again over the ball's new place — this time cut out by its
; mask, so the logo's outlines and the list's letters cover the ball and the
; background between them does not.  That last one takes a blit per plane,
; because the mask has one plane where the object has four.
; ---------------------------------------------------------------------------
banner_step:
        MOVEM.L D0-D7/A0-A3,-(SP)
        MOVE.B  VAR_ANIM_STEP,D0
        CMPI.B  #AN_RESTORE,D0
        BEQ.S   .bs_restore
        CMPI.B  #AN_DRAW,D0
        BEQ.S   .bs_draw
    ifne BANNER_SHADOW
        CMPI.B  #AN_SHADOW,D0
        BEQ.S   .bs_shadow
    endc
        BRA.S   .bs_cover

.bs_restore:
        BSR     ball_restore
        BSR     ball_move
    ifne BANNER_SHADOW
        MOVE.B  #AN_SHADOW,VAR_ANIM_STEP
    else
        MOVE.B  #AN_DRAW,VAR_ANIM_STEP
    endc
        BRA.S   .bs_done

    ifne BANNER_SHADOW
.bs_shadow:
        BSR     ball_shadow_draw
        MOVE.B  #AN_DRAW,VAR_ANIM_STEP
        BRA.S   .bs_done
    endc

.bs_draw:
        BSR     ball_draw
        CLR.B   VAR_ANIM_PLANE
        MOVE.B  #AN_COVER,VAR_ANIM_STEP
        BRA.S   .bs_done

.bs_cover:
        MOVE.B  VAR_ANIM_PLANE,D0
        BSR     ball_cover
        ADDQ.B  #1,VAR_ANIM_PLANE
        CMPI.B  #SCREEN_PLANES,VAR_ANIM_PLANE
        BCS.S   .bs_done
        BSR     ball_spin               ; the frame is on screen
        MOVE.B  #AN_IDLE,VAR_ANIM_STEP
.bs_done:
        MOVEM.L (SP)+,D0-D7/A0-A3
        RTS

; ball_rect — the ball's rectangle in the band, from a position in D6 (pixel
; x) and D7 (line).  Returns D6 = first word, D7 = line, D0 = words,
; D1 = pixel rows, ready for the two fg_blit routines.
ball_rect:
        LSR.W   #4,D6                   ; the word the ball starts in
        MOVE.W  #BALL_CLR_W,D0
        MOVE.W  #BALL_CLR_H,D1
        RTS

; ball_restore — the band back over where the ball was drawn last.
ball_restore:
        MOVEM.L D0-D1/D6-D7,-(SP)
        MOVE.W  VAR_BALL_PX,D6
        MOVE.W  VAR_BALL_PY,D7
        BSR.S   ball_rect
        BSR     fg_blit_solid
        MOVEM.L (SP)+,D0-D1/D6-D7
        RTS

; ball_cover — D0.B = plane.  One plane of the band back over the ball,
; masked, so the ball is behind it.
ball_cover:
        MOVEM.L D0-D2/D6-D7,-(SP)
        MOVEQ   #0,D2
        MOVE.B  D0,D2
        MOVE.W  VAR_BALL_PX,D6
        MOVE.W  VAR_BALL_PY,D7
        BSR.S   ball_rect
        BSR     fg_blit_over
        MOVEM.L (SP)+,D0-D2/D6-D7
        RTS

; ball_cover_all — every plane of it, one blit after another.  For
; banner_start, which is not on the main loop and has no frame to fit into.
ball_cover_all:
        MOVEM.L D0,-(SP)
        MOVEQ   #0,D0
.bca_plane:
        BSR.S   ball_cover
        ADDQ.B  #1,D0
        CMPI.B  #SCREEN_PLANES,D0
        BCS.S   .bca_plane
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; ball_move — move the ball on by its velocity and turn it round at an edge.
;
; Position is 8.8 fixed point held in a long, so the ball can drift down the
; band slower than a pixel a field.  An edge reflects the overshoot back the
; way it came, so the ball never sticks to a limit.
; ---------------------------------------------------------------------------
ball_move:
        MOVEM.L D0-D2,-(SP)
        MOVE.L  VAR_BALL_X,D0
        MOVE.W  VAR_BALL_VX,D1
        EXT.L   D1
        ADD.L   D1,D0
        CMPI.L  #BALL_X_MIN<<8,D0
        BLT.S   .bm_xlow
        CMPI.L  #BALL_X_MAX<<8,D0
        BLE.S   .bm_xok
        MOVE.L  #2*(BALL_X_MAX<<8),D2
        BRA.S   .bm_xturn
.bm_xlow:
        MOVE.L  #2*(BALL_X_MIN<<8),D2
.bm_xturn:
        SUB.L   D0,D2
        MOVE.L  D2,D0                   ; reflected off the edge
        NEG.W   VAR_BALL_VX             ; and the spin turns with it
.bm_xok:
        MOVE.L  D0,VAR_BALL_X
        LSR.L   #8,D0
        MOVE.W  D0,VAR_BALL_PX

        MOVE.L  VAR_BALL_Y,D0
        MOVE.W  VAR_BALL_VY,D1
        EXT.L   D1
        ADD.L   D1,D0
        BMI.S   .bm_ylow
        MOVE.L  VAR_BALL_Y_MAX,D2
        CMP.L   D2,D0
        BLE.S   .bm_yok
        ADD.L   D2,D2
        BRA.S   .bm_yturn
.bm_ylow:
        MOVEQ   #0,D2
.bm_yturn:
        SUB.L   D0,D2
        MOVE.L  D2,D0
        NEG.W   VAR_BALL_VY
.bm_yok:
        MOVE.L  D0,VAR_BALL_Y
        LSR.L   #8,D0
        MOVE.W  D0,VAR_BALL_PY
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; ball_draw — the ball at its new place.  Without a shadow it goes down flat,
; because the foreground laid over it straight after puts back the black the
; ball writes around itself.  With a shadow the ball has to be cut out, or it
; would black the shadow out from under itself.
; ---------------------------------------------------------------------------
ball_draw:
        MOVEM.L D0-D7/A0-A3,-(SP)
        MOVEA.L #CHIP_BALL,A0
        MOVE.W  #BALL_WIDTH_W,D0
        MOVE.W  #BALL_HEIGHT,D1
        MOVE.W  VAR_BALL_PX,D6
        MOVE.W  VAR_BALL_PY,D7
    ifne BANNER_SHADOW
        MOVEA.L #CHIP_BALL_MASK,A2
        BSR     draw_object
    else
        BSR     draw_object_solid
    endc
        MOVEM.L (SP)+,D0-D7/A0-A3
        RTS

    ifne BANNER_SHADOW
; ball_shadow_draw — the silhouette in pen 14, down and right of the ball.  It
; lands on ground the restore has just cleared, so nothing needs masking out.
ball_shadow_draw:
        MOVEM.L D0-D7/A0-A3,-(SP)
        MOVEA.L #CHIP_BALL_SHADOW,A0
        MOVE.W  #BALL_WIDTH_W,D0
        MOVE.W  #BALL_HEIGHT,D1
        MOVE.W  VAR_BALL_PX,D6
        ADDI.W  #BALL_SHADOW_OFF,D6
        MOVE.W  VAR_BALL_PY,D7
        ADDI.W  #BALL_SHADOW_OFF,D7
        BSR     draw_object_solid
        MOVEM.L (SP)+,D0-D7/A0-A3
        RTS
    endc

; ---------------------------------------------------------------------------
; ball_spin — step BallCycle on every BANNER_SPIN_FRAMES fields.  The bitmap
; never changes: one row of the table written to COLOR06 upwards turns the
; ball an eighth of a quarter turn, because every band of longitude is drawn
; in its own pen and one step lands each band where its neighbour was.  The
; direction follows the way the ball is travelling, so it rolls rather than
; spinning on the spot.
; ---------------------------------------------------------------------------
ball_spin:
        MOVEM.L D0,-(SP)
        SUBQ.B  #1,VAR_SPIN_TICK
        BNE.S   .bsp_done
        MOVE.B  #BANNER_SPIN_FRAMES,VAR_SPIN_TICK
        MOVE.B  VAR_SPIN_STEP,D0
        TST.W   VAR_BALL_VX
        BMI.S   .bsp_back
        ADDQ.B  #1,D0
        BRA.S   .bsp_wrap
.bsp_back:
        SUBQ.B  #1,D0
.bsp_wrap:
        ANDI.B  #BALL_STEPS-1,D0
        MOVE.B  D0,VAR_SPIN_STEP
        BSR     ball_colours
.bsp_done:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; ball_colours — one row of BallCycle into the copper list.  The copper writes
; the whole palette every field, so the registers themselves cannot be written
; directly: the list is where a colour has to change.
; ---------------------------------------------------------------------------
ball_colours:
        MOVEM.L D0-D1/A0-A1,-(SP)
        MOVEQ   #0,D0
        MOVE.B  VAR_SPIN_STEP,D0
        MULU    #BALL_STEP_BYTES,D0
        MOVEA.L #BallCycle,A0
        ADDA.W  D0,A0
        LEA     (COPPER_BASE+COP_OFF_COLOR00+BALL_PEN_FIRST*4).W,A1
        MOVEQ   #BALL_PENS-1,D1
.bc_loop:
        MOVE.W  (A0)+,(A1)
        ADDA.W  #4,A1                   ; a register and its value, per entry
        DBF     D1,.bc_loop
        MOVEM.L (SP)+,D0-D1/A0-A1
        RTS
    endc

    ifne BANNER_FG
; ===========================================================================
; The foreground object — 20 words to a plane row, four planes interleaved,
; the same shape as the bitmap, so a rectangle of it goes back on screen
; without any shifting and the text routines draw into it by changing one
; base address.
; ===========================================================================

; fg_clear — the object and its mask, empty.  Both are contiguous and written
; whole, so 40 words to a row and a modulo of zero is a flat run through them.
fg_clear:
        MOVEM.L D0-D2/A1,-(SP)
        MOVEA.L #CHIP_FG,A1
        MOVE.W  #SCREEN_BPL_W,D0
        MOVE.W  #FG_BYTES/(SCREEN_BPL_W*2),D1
        MOVEQ   #0,D2
        BSR     blit_clear
        MOVEA.L #CHIP_FG_MASK,A1
        MOVE.W  #SCREEN_BPL_W,D0
        MOVE.W  #FG_MASK_BYTES/(SCREEN_BPL_W*2),D1
        MOVEQ   #0,D2
        BSR     blit_clear
        MOVEM.L (SP)+,D0-D2/A1
        RTS

    ifne CONFIG_BANNER_ART
; ---------------------------------------------------------------------------
; fg_logo_mask — the logo's own mask folded into the object's.
;
; Everywhere else the mask is worked out from what was drawn, but the logo has
; black pixels inside its outlines that are solid all the same, and only its
; own mask knows that.  It is stored four times over for the cookie-cut blits,
; so this takes one row in four by stepping the source on by the three it
; skips.
; ---------------------------------------------------------------------------
fg_logo_mask:
        MOVEM.L D0-D5/A0-A1,-(SP)
        MOVEA.L #CHIP_LOGO_MASK,A0
        MOVEA.L #CHIP_FG_MASK+LOGO_Y*SCREEN_BPL_W,A1
        MOVE.W  #LOGO_WIDTH_W,D0
        MOVE.W  #LOGO_HEIGHT,D1
        MOVE.W  #SCREEN_BPL_W-LOGO_WIDTH_W*2,D2
        MOVE.W  #LOGO_X&15,D3
        MOVE.W  #LOGO_WIDTH_W*2*(SCREEN_PLANES-1),D4
        BSR     blit_or
        MOVEM.L (SP)+,D0-D5/A0-A1
        RTS
    endc

; ---------------------------------------------------------------------------
; fg_mask_all — the mask for the whole object, from what was drawn into it.
;
; A pixel is solid where any plane has a bit, which for text on the background
; pen is exactly the glyph, so the ball shows between the letters rather than
; behind a black box.  The logo's own mask goes in afterwards, because its
; outlines enclose black that has to cover the ball too.
; ---------------------------------------------------------------------------
fg_mask_all:
        MOVEM.L D0-D4/A0-A1,-(SP)
        MOVEA.L #CHIP_FG,A0
        MOVEA.L #CHIP_FG_MASK,A1
        MOVE.W  #SCREEN_BPL_H-1,D4
.fma_row:
        MOVE.W  #SCREEN_BPL_W/2-1,D3
.fma_word:
        MOVE.W  (A0),D1
        OR.W    SCREEN_BPL_W(A0),D1
        OR.W    SCREEN_BPL_W*2(A0),D1
        OR.W    SCREEN_BPL_W*3(A0),D1
        MOVE.W  D1,(A1)+
        ADDQ.L  #2,A0
        DBF     D3,.fma_word
        ADDA.W  #SCREEN_ROW_BYTES-SCREEN_BPL_W,A0
        DBF     D4,.fma_row
    ifne CONFIG_BANNER_ART
        BSR     fg_logo_mask
    endc
        BSR     fg_mask_bar
        MOVEM.L (SP)+,D0-D4/A0-A1
        RTS

; ---------------------------------------------------------------------------
; fg_mask_sel — the same, over the list's rows and columns alone.  Moving the
; highlight changes nothing else, and going near the logo's columns would
; undo the mask fg_logo_mask folded in.
; ---------------------------------------------------------------------------
fg_mask_sel:
        MOVEM.L D0-D4/A0-A1,-(SP)
        MOVEQ   #0,D0
        MOVE.B  VAR_MENU_ROW0,D0
        MOVE.W  D0,D1
        MULU    #ROW_STRIDE,D0
        MOVEA.L #CHIP_FG+FG_LIST_W0*2,A0
        ADDA.L  D0,A0
        MULU    #8*SCREEN_BPL_W,D1
        MOVEA.L #CHIP_FG_MASK+FG_LIST_W0*2,A1
        ADDA.L  D1,A1
        MOVE.W  #MAX_DISPLAY*8-1,D4
.fms_row:
        MOVE.W  #FG_LIST_WORDS-1,D3
.fms_word:
        MOVE.W  (A0),D1
        OR.W    SCREEN_BPL_W(A0),D1
        OR.W    SCREEN_BPL_W*2(A0),D1
        OR.W    SCREEN_BPL_W*3(A0),D1
        MOVE.W  D1,(A1)+
        ADDQ.L  #2,A0
        DBF     D3,.fms_word
        ADDA.W  #SCREEN_ROW_BYTES-FG_LIST_WORDS*2,A0
        ADDA.W  #SCREEN_BPL_W-FG_LIST_WORDS*2,A1
        DBF     D4,.fms_row
        BSR     fg_mask_bar
        MOVEM.L (SP)+,D0-D4/A0-A1
        RTS

; ---------------------------------------------------------------------------
; fg_mask_bar — the highlighted row, solid right across the list.
;
; It is a gold bar with the entry knocked out of it in the background pen, so
; working the mask out from the planes would leave the letters transparent and
; the ball would show through the entry the user is about to boot.
; ---------------------------------------------------------------------------
fg_mask_bar:
        MOVEM.L D0-D1/D3-D4/A1,-(SP)
        MOVEQ   #0,D0
        MOVE.B  VAR_SELECTION,D0
        MOVEQ   #0,D1
        MOVE.B  VAR_MENU_ROW0,D1
        ADD.W   D1,D0
        MULU    #8*SCREEN_BPL_W,D0
        MOVEA.L #CHIP_FG_MASK+FG_LIST_W0*2,A1
        ADDA.L  D0,A1
        MOVEQ   #7,D4
.fmb_row:
        MOVE.W  #FG_LIST_WORDS-1,D3
.fmb_word:
        MOVE.W  #$FFFF,(A1)+
        DBF     D3,.fmb_word
        ADDA.W  #SCREEN_BPL_W-FG_LIST_WORDS*2,A1
        DBF     D4,.fmb_row
        MOVEM.L (SP)+,D0-D1/D3-D4/A1
        RTS

; fg_show — the whole object on screen.  Object and bitmap are the same shape
; and both contiguous, so this is a flat copy of every byte.
fg_show:
        MOVEM.L D0-D5/A0-A1,-(SP)
        MOVEA.L #CHIP_FG,A0
        MOVEA.L #BITPLANE_BASE,A1
        MOVE.W  #SCREEN_BPL_W,D0
        MOVE.W  #FG_BYTES/(SCREEN_BPL_W*2),D1
        MOVEQ   #0,D2
        MOVEQ   #0,D3
        MOVEQ   #0,D4
        BSR     blit_copy
        MOVEM.L (SP)+,D0-D5/A0-A1
        RTS

; ---------------------------------------------------------------------------
; fg_blit_solid — a rectangle of the band on screen outright, covering
; whatever was there.  One blit, no shift, no mask.
; D6.W = first word, D7.W = line, D0.W = words, D1.W = pixel rows
; ---------------------------------------------------------------------------
fg_blit_solid:
        MOVEM.L D0-D5/A0-A1,-(SP)
        BSR     fg_ptrs                 ; A0 = object, A1 = screen
        MOVE.W  #SCREEN_BPL_W,D2
        SUB.W   D0,D2
        SUB.W   D0,D2
        MOVE.W  D2,D4                   ; the object skips the same as the
        LSL.W   #2,D1                   ; bitmap does
        MOVEQ   #0,D3
        BSR     blit_copy
        MOVEM.L (SP)+,D0-D5/A0-A1
        RTS

; ---------------------------------------------------------------------------
; fg_blit_over — one plane of the same rectangle, cut out by the band's mask,
; so what is already on screen shows through where the band is transparent.
;
; The mask has a single plane where the object has four, and a blit steps its
; sources at one rate, so the planes cannot be done together the way a spread
; mask allows.  One call sets up one blit and the caller comes back for the
; next, which is what lets the main loop keep running between them.
; D6.W = first word, D7.W = line, D0.W = words, D1.W = pixel rows,
; D2.W = plane
; ---------------------------------------------------------------------------
fg_blit_over:
        MOVEM.L D0-D5/A0-A2,-(SP)
        BSR     fg_ptrs                 ; A0 = object, A1 = screen, A2 = mask
        MULU    #SCREEN_BPL_W,D2        ; MULU reads the low word, so a plane
        ADDA.L  D2,A0                   ; number in the low byte is enough
        ADDA.L  D2,A1
        MOVE.W  #SCREEN_BPL_W,D5
        SUB.W   D0,D5
        SUB.W   D0,D5                   ; the mask skips a plane row
        MOVE.W  #SCREEN_ROW_BYTES,D2
        SUB.W   D0,D2
        SUB.W   D0,D2                   ; object and bitmap skip a pixel row
        MOVE.W  D2,D4
        MOVEQ   #0,D3
        BSR     blit_cookie
        MOVEM.L (SP)+,D0-D5/A0-A2
        RTS

; ---------------------------------------------------------------------------
; fg_ptrs — D6.W = first word, D7.W = line.  Returns A0 into the foreground
; object, A2 into its mask and A1 into the bitmap, all at that corner.
; ---------------------------------------------------------------------------
fg_ptrs:
        MOVEM.L D0-D2,-(SP)
        MOVEQ   #0,D1
        MOVE.W  D6,D1
        ADD.W   D1,D1                   ; two bytes to the word
        MOVEQ   #0,D0
        MOVE.W  D7,D0
        MOVE.W  D0,D2
        MULU    #SCREEN_ROW_BYTES,D2
        ADD.L   D1,D2
        MOVEA.L #BITPLANE_BASE,A1
        ADDA.L  D2,A1
        MOVEA.L #CHIP_FG,A0
        ADDA.L  D2,A0                   ; same offset in both, same shape
        MOVE.W  D0,D2
        MULU    #SCREEN_BPL_W,D2
        ADD.L   D1,D2
        MOVEA.L #CHIP_FG_MASK,A2
        ADDA.L  D2,A2
        MOVEM.L (SP)+,D0-D2
        RTS
    endc

    ifne CONFIG_BOOT_CHIME
; ---------------------------------------------------------------------------
; chime_start — arm the chime as the menu comes up.  An autoboot is silent, so
; a machine nobody asked the menu for makes no sound.
;
; It only arms it.  A sample started here is not heard in full — the beginning
; is lost, and how much is lost depends on how long the machine has been on.
; What swallows it has not been identified and is not in the Amiga's own audio
; path, which settles in about a sixth of a second.  A second's wait is enough
; on this bench, so that is what is waited.
;
; The wait is measured on the CIA counter rather than on screen refreshes,
; because that counter runs whether or not anything is watching it, and the
; loop can be away for tens of milliseconds at a time.
; ---------------------------------------------------------------------------
chime_start:
        MOVEM.L D0-D1,-(SP)
        MOVE.W  #DMAF_AUD0,DMACON       ; off, in case anything left it on
        CLR.W   AUD0VOL
        BSR     tod_now                 ; note the moment it is due to start
        ADDI.L  #CHIME_WAIT_NTSC,D0
        TST.B   VAR_IS_PAL
        BEQ.S   .chs_due
        SUBI.L  #CHIME_WAIT_NTSC-CHIME_WAIT_PAL,D0
.chs_due:
        ANDI.L  #$00FFFFFF,D0
        MOVE.L  D0,VAR_CHIME_END
        MOVE.B  #1,VAR_CHIME_ON
.chs_out:
        MOVEM.L (SP)+,D0-D1
        RTS

; ---------------------------------------------------------------------------
; chime_stop — channel off and silent, before the machine is handed over.
; Usually chime_tick has already switched it off and this does nothing.  A
; boot that came round while the chime was still sounding cuts a bell off part
; way, which steps the output and clicks, so the volume is taken down over a
; few fields first.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; chime_stop — channel off and silent, before the machine is handed over.
; Usually chime_tick has already switched it off and this does nothing.  A
; boot that came round while the chime was still sounding cuts a bell off part
; way, which steps the output and clicks, so the volume is taken down over a
; few fields first.
; ---------------------------------------------------------------------------
chime_stop:
        MOVEM.L D0-D2,-(SP)
        TST.B   VAR_CHIME_ON
        BEQ.S   .chp_off                ; never started, nothing to fade
        MOVE.W  #CHIME_VOLUME,D1
        MOVEQ   #CHIME_RAMP_FIELDS,D2
.chp_fade:
        SUBI.W  #CHIME_VOLUME/CHIME_RAMP_FIELDS,D1
        BPL.S   .chp_set
        MOVEQ   #0,D1
.chp_set:
        MOVE.W  D1,AUD0VOL
        BSR     wait_field
        SUBQ.W  #1,D2
        BNE.S   .chp_fade
.chp_off:
        CLR.W   AUD0VOL
        MOVE.W  #DMAF_AUD0,DMACON
        MOVEM.L (SP)+,D0-D2
        RTS

    endc

    ifne CONFIG_BANNER_ART+CONFIG_BANNER_BALL
; ===========================================================================
; Blitter
;
; Every object is interleaved as the bitmap is, so the whole of it goes down
; in one blit of HEIGHT*PLANES rows.  Each row carries one blank word on the
; right, where the barrel shifter pushes the last pixels, which is what lets
; an object land on any pixel column rather than only a word boundary.
;
; The asset masks were spread to four planes at startup, so they step at the
; same rate as the object beside them and their modulo is zero too.
; ===========================================================================

; blit_wait — hold until the blitter has finished.
blit_wait:
        BTST    #6,(DMACONR).L          ; BBUSY, bit 14 of the word
        BNE.S   blit_wait
        RTS

; ---------------------------------------------------------------------------
; obj_dest — D6.W = x, D7.W = y.  Returns A1 = the word the object's top left
; corner lands in, and D3.W = how far into that word.  It follows
; VAR_DRAW_BASE, as the text routines do, so an object goes into the
; foreground object or straight on screen by the same means.
; ---------------------------------------------------------------------------
obj_dest:
        MOVEM.L D0-D1,-(SP)
        MOVE.W  D6,D3
        ANDI.W  #15,D3
        MOVEQ   #0,D0
        MOVE.W  D6,D0
        LSR.W   #4,D0
        ADD.W   D0,D0                   ; two bytes to the word
        MOVEQ   #0,D1
        MOVE.W  D7,D1
        MULU    #SCREEN_ROW_BYTES,D1
        ADD.L   D0,D1
        MOVEA.L VAR_DRAW_BASE,A1
        ADDA.L  D1,A1
        MOVEM.L (SP)+,D0-D1
        RTS

; ---------------------------------------------------------------------------
; draw_object — an object on the screen, cut out by its mask so what is behind
; shows through where the object is transparent.
; A0 = object, A2 = its spread mask, D0.W = words across, D1.W = pixel rows,
; D6.W = x, D7.W = y.
; ---------------------------------------------------------------------------
draw_object:
        MOVEM.L D1-D5/A1,-(SP)
        BSR     obj_dest
        MOVE.W  #SCREEN_BPL_W,D2
        SUB.W   D0,D2
        SUB.W   D0,D2                   ; the rest of the plane's row
        LSL.W   #2,D1                   ; four planes to every pixel row
        MOVEQ   #0,D4                   ; the object's rows are contiguous
        MOVEQ   #0,D5                   ; and so are the spread mask's
        BSR     blit_cookie
        MOVEM.L (SP)+,D1-D5/A1
        RTS

; ---------------------------------------------------------------------------
; draw_object_solid — the same, unmasked.  The object's own transparent pixels
; are written as background, so this is only for an object landing on ground
; that is already clear.
; A0 = object, D0.W = words across, D1.W = pixel rows, D6.W = x, D7.W = y.
; ---------------------------------------------------------------------------
draw_object_solid:
        MOVEM.L D1-D4/A1,-(SP)
        BSR     obj_dest
        MOVE.W  #SCREEN_BPL_W,D2
        SUB.W   D0,D2
        SUB.W   D0,D2
        LSL.W   #2,D1
        MOVEQ   #0,D4
        BSR     blit_copy
        MOVEM.L (SP)+,D1-D4/A1
        RTS

; ---------------------------------------------------------------------------
; blit_clear — zero a rectangle.  D alone, with a minterm of zero.
; A1 = first word, D0.W = words across, D1.W = blitter rows, D2.W = modulo.
; ---------------------------------------------------------------------------
blit_clear:
        MOVEM.L D0-D2,-(SP)
        BSR     blit_wait
        MOVE.W  #$0100,BLTCON0          ; D enabled, every minterm clear
        CLR.W   BLTCON1
        MOVE.W  D2,BLTDMOD
        MOVE.L  A1,BLTDPTH
        LSL.W   #6,D1
        OR.W    D0,D1
        MOVE.W  D1,BLTSIZE
        MOVEM.L (SP)+,D0-D2
        RTS

; ---------------------------------------------------------------------------
; blit_copy — A straight into D, shifted.
; A0 = source, A1 = destination, D0.W = words across, D1.W = blitter rows,
; D2.W = destination modulo, D3.W = shift 0 to 15, D4.W = source modulo.
; ---------------------------------------------------------------------------
blit_copy:
        MOVEM.L D0-D5,-(SP)
        BSR     blit_wait
        MOVE.W  D3,D5
        ROR.W   #4,D5                   ; the shift lives in bits 15 to 12
        ORI.W   #$09F0,D5               ; A and D enabled, D = A
        MOVE.W  D5,BLTCON0
        CLR.W   BLTCON1
        MOVE.W  #$FFFF,BLTAFWM
        MOVE.W  #$FFFF,BLTALWM
        MOVE.W  D4,BLTAMOD
        MOVE.W  D2,BLTDMOD
        MOVE.L  A0,BLTAPTH
        MOVE.L  A1,BLTDPTH
        LSL.W   #6,D1
        OR.W    D0,D1
        MOVE.W  D1,BLTSIZE
        MOVEM.L (SP)+,D0-D5
        RTS

; ---------------------------------------------------------------------------
; blit_or — A into D over what C already holds, shifted.  Used to fold one
; mask into another.
; A0 = source, A1 = destination, D0.W = words across, D1.W = blitter rows,
; D2.W = destination modulo, D3.W = shift, D4.W = source modulo.
; ---------------------------------------------------------------------------
blit_or:
        MOVEM.L D0-D5,-(SP)
        BSR     blit_wait
        MOVE.W  D3,D5
        ROR.W   #4,D5
        ORI.W   #$0BFA,D5               ; A, C and D enabled, D = A OR C
        MOVE.W  D5,BLTCON0
        CLR.W   BLTCON1
        MOVE.W  #$FFFF,BLTAFWM
        MOVE.W  #$FFFF,BLTALWM
        MOVE.W  D4,BLTAMOD
        MOVE.W  D2,BLTCMOD
        MOVE.W  D2,BLTDMOD
        MOVE.L  A0,BLTAPTH
        MOVE.L  A1,BLTCPTH
        MOVE.L  A1,BLTDPTH
        LSL.W   #6,D1
        OR.W    D0,D1
        MOVE.W  D1,BLTSIZE
        MOVEM.L (SP)+,D0-D5
        RTS

; ---------------------------------------------------------------------------
; blit_cookie — the mask decides, pixel by pixel, whether the object or what
; is already on screen comes out: D = A AND B, OR NOT A AND C, which is
; minterm $CA with A the mask, B the object and C the screen.  A and B shift
; together, A's amount from BLTCON0 and B's from BLTCON1.
; A0 = object, A2 = mask, A1 = destination, D0.W = words across,
; D1.W = blitter rows, D2.W = destination modulo, D3.W = shift,
; D4.W = object modulo, D5.W = mask modulo.
; ---------------------------------------------------------------------------
blit_cookie:
        MOVEM.L D0-D6,-(SP)
        BSR     blit_wait
        MOVE.W  D3,D6
        ROR.W   #4,D6
        MOVE.W  D6,BLTCON1              ; the mask shifts with the object
        ORI.W   #$0FCA,D6               ; A, B, C and D enabled
        MOVE.W  D6,BLTCON0
        MOVE.W  #$FFFF,BLTAFWM
        MOVE.W  #$FFFF,BLTALWM
        MOVE.W  D5,BLTAMOD
        MOVE.W  D4,BLTBMOD
        MOVE.W  D2,BLTCMOD
        MOVE.W  D2,BLTDMOD
        MOVE.L  A2,BLTAPTH
        MOVE.L  A0,BLTBPTH
        MOVE.L  A1,BLTCPTH
        MOVE.L  A1,BLTDPTH
        LSL.W   #6,D1
        OR.W    D0,D1
        MOVE.W  D1,BLTSIZE
        MOVEM.L (SP)+,D0-D6
        RTS
    endc

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
; The bitmap is interleaved, so one character row is 1280 contiguous bytes —
; eight pixel rows of plane 0, 1, 2, 3 in turn, 40 bytes each.  A character
; cell is a column within it, and stepping down one pixel row is +160.
;
; A character cell takes two pens: VAR_PEN for the glyph and VAR_PEN_BG for
; the rest of the cell.  Both are written, so a character covers whatever was
; there, and text on the highlight bar is black on gold rather than black on
; a hole punched through it.
;
; They are variables rather than arguments because screen_print, draw_entry,
; diag_field and print_hex_byte all sit between a caller and screen_putchar.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; screen_clear — zero every plane of the whole bitmap
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
; screen_fill_row — fill one character row with VAR_PEN, from VAR_MENU_COL to
; the right edge.  That is the list's span, which is what the highlight bar
; covers, and it stops the bar reaching the logo beside the list.
; Input : D0.B = row
; Clobbers (saved/restored): D0-D6/A0
; ---------------------------------------------------------------------------
screen_fill_row:
        MOVEM.L D0-D6/A0,-(SP)
        MOVEQ   #0,D1
        MOVE.B  D0,D1
        MULU    #ROW_STRIDE,D1
        MOVEA.L VAR_DRAW_BASE,A0
        ADDA.L  D1,A0
        MOVEQ   #0,D3
        MOVE.B  VAR_MENU_COL,D3
        ADDA.W  D3,A0                   ; the bar's first column
        NEG.W   D3
        ADDI.W  #SCREEN_COLS-1,D3       ; columns it covers, less one
        MOVEQ   #0,D1
        MOVE.B  VAR_PEN,D1
        MOVEQ   #7,D5                   ; eight pixel rows
.fr_line:
        MOVEQ   #0,D4                   ; plane number
.fr_plane:
        MOVEQ   #0,D2
        BTST    D4,D1
        BEQ.S   .fr_mask
        MOVEQ   #-1,D2                  ; this plane is set right across
.fr_mask:
        MOVE.W  D3,D6
.fr_byte:
        MOVE.B  D2,(A0)+
        DBF     D6,.fr_byte
        ADDA.W  #SCREEN_BPL_W-1,A0      ; the same column, one plane on
        SUBA.W  D3,A0
        ADDQ.B  #1,D4
        CMPI.B  #SCREEN_PLANES,D4
        BCS.S   .fr_plane
        DBF     D5,.fr_line
        MOVEM.L (SP)+,D0-D6/A0
        RTS

; ---------------------------------------------------------------------------
; screen_putchar — render one ASCII character into the bitmap
; Input : D0.B = character code, D1.B = column (0-39), D2.B = row (0-31)
;         VAR_PEN = glyph pen, VAR_PEN_BG = pen for the rest of the cell
;
; Within a plane the byte is the background mask with the glyph's bits
; switched to the foreground mask, which is what base EOR (sel AND glyph)
; comes to.
; Clobbers (saved/restored): D0-D7/A0-A2
; ---------------------------------------------------------------------------
screen_putchar:
        MOVEM.L D0-D7/A0-A2,-(SP)

        ; Cell address in plane 0 = VAR_DRAW_BASE + row*1280 + col.  The offset
        ; runs past $7FFF at the bottom of the screen, so it is kept long.
        MOVEQ   #0,D3
        MOVE.B  D2,D3
        MULU    #ROW_STRIDE,D3
        MOVEQ   #0,D7
        MOVE.B  D1,D7
        ADD.L   D7,D3
        MOVEA.L VAR_DRAW_BASE,A1
        ADDA.L  D3,A1

        ; Glyph address = font_data + char_code * 8
        MOVEQ   #0,D3
        MOVE.B  D0,D3
        ASL.W   #3,D3
        LEA     (font_data).L,A0
        ADDA.W  D3,A0

        MOVEQ   #0,D4
        MOVE.B  VAR_PEN,D4
        MOVEQ   #0,D5
        MOVE.B  VAR_PEN_BG,D5

        MOVEQ   #0,D6                   ; plane number
.pc_plane:
        MOVEQ   #0,D2                   ; D2 = this plane's background bits
        BTST    D6,D5
        BEQ.S   .pc_fg
        MOVEQ   #-1,D2
.pc_fg:
        MOVEQ   #0,D3                   ; D3 = this plane's foreground bits
        BTST    D6,D4
        BEQ.S   .pc_sel
        MOVEQ   #-1,D3
.pc_sel:
        EOR.B   D2,D3                   ; the bits the glyph switches
        MOVEA.L A0,A2                   ; the glyph, from its first line
        MOVEQ   #7,D7                   ; eight scan lines
.pc_line:
        MOVE.B  (A2)+,D0
        AND.B   D3,D0
        EOR.B   D2,D0
        MOVE.B  D0,(A1)
        ADDA.W  #SCREEN_ROW_BYTES,A1
        DBF     D7,.pc_line
        ; back up to line 0, one plane further in
        SUBA.W  #SCREEN_ROW_BYTES*8-SCREEN_BPL_W,A1
        ADDQ.B  #1,D6
        CMPI.B  #SCREEN_PLANES,D6
        BCS.S   .pc_plane

        MOVEM.L (SP)+,D0-D7/A0-A2
        RTS

; ---------------------------------------------------------------------------
; screen_print — print a null-terminated ASCII string in VAR_PEN
; Input : A0 = string pointer, D1.B = column, D2.B = row
; Characters at or beyond VAR_COL_MAX are dropped, so a name too wide for the
; space it has is cut short rather than running into what is beside it.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
screen_print:
        MOVEM.L D0-D2/A0,-(SP)
.sp_loop:
        MOVE.B  (A0)+,D0
        BEQ.S   .sp_done
        CMP.B   VAR_COL_MAX,D1
        BCC.S   .sp_done
        BSR     screen_putchar
        ADDQ.B  #1,D1
        BRA.S   .sp_loop
.sp_done:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; screen_print_centred — A0 = string, D2.B = row.  Centres the string across
; the screen.  A string wider than the screen starts at column 0.
screen_print_centred:
        MOVEM.L D0-D1/A0-A1,-(SP)
        MOVEA.L A0,A1                   ; keep the start
        MOVEQ   #0,D0
.spc_len:
        TST.B   (A0)+
        BEQ.S   .spc_got
        ADDQ.W  #1,D0
        BRA.S   .spc_len
.spc_got:
        MOVEQ   #SCREEN_COLS,D1
        SUB.W   D0,D1
        BPL.S   .spc_col
        MOVEQ   #0,D1
.spc_col:
        LSR.W   #1,D1
        MOVEA.L A1,A0
        BSR     screen_print
        MOVEM.L (SP)+,D0-D1/A0-A1
        RTS

        EVEN
ram_section_rom_end:

; ============================================================
; ROM DATA SECTION
; Copper template, font and strings.  Reached from RAM code by absolute long
; address, so correct from any PC.
; ============================================================

; ---------------------------------------------------------------------------
; Copper list template
;
; screen_init copies this to chip RAM and patches the four bitplane pointers,
; and DIWSTOP where the Agnus is PAL.  The offsets below are what it patches
; through, so the order here and those three equates go together.
; ---------------------------------------------------------------------------
        EVEN
copper_template:
cop_bplpt:
        DC.W    COP_BPL1PTH,$0000       ; the four pointers, patched by
        DC.W    COP_BPL1PTL,$0000       ; screen_init to plane 0..3 within
        DC.W    COP_BPL1PTH+4,$0000     ; the bitmap's first pixel row
        DC.W    COP_BPL1PTL+4,$0000
        DC.W    COP_BPL1PTH+8,$0000
        DC.W    COP_BPL1PTL+8,$0000
        DC.W    COP_BPL1PTH+12,$0000
        DC.W    COP_BPL1PTL+12,$0000
        DC.W    COP_BPLCON0,BPLCON0_4PL
        DC.W    COP_BPLCON1,$0000
        DC.W    COP_BPLCON2,$0024
        DC.W    COP_BPL1MOD,SCREEN_BPL_MOD
        DC.W    COP_BPL2MOD,SCREEN_BPL_MOD
        DC.W    COP_DDFSTRT,DDF_START
        DC.W    COP_DDFSTOP,DDF_STOP
        DC.W    COP_DIWSTRT,DIW_START
cop_diwstop:
        DC.W    COP_DIWSTOP,DIW_STOP_NTSC   ; PAL height patched in
cop_colours:
        DC.W    COP_COLOR00+0,PEN00_RGB
        DC.W    COP_COLOR00+2,PEN01_RGB
        DC.W    COP_COLOR00+4,PEN02_RGB
        DC.W    COP_COLOR00+6,PEN03_RGB
        DC.W    COP_COLOR00+8,PEN04_RGB
        DC.W    COP_COLOR00+10,PEN05_RGB
        DC.W    COP_COLOR00+12,PEN06_RGB
        DC.W    COP_COLOR00+14,PEN07_RGB
        DC.W    COP_COLOR00+16,PEN08_RGB
        DC.W    COP_COLOR00+18,PEN09_RGB
        DC.W    COP_COLOR00+20,PEN10_RGB
        DC.W    COP_COLOR00+22,PEN11_RGB
        DC.W    COP_COLOR00+24,PEN12_RGB
        DC.W    COP_COLOR00+26,PEN13_RGB
        DC.W    COP_COLOR00+28,PEN14_RGB
        DC.W    COP_COLOR00+30,PEN15_RGB
        DC.W    $FFFF,$FFFE             ; END
copper_template_end:

; Byte offsets into the copied list of the data words the code writes.
COP_OFF_BPL1PTH     EQU cop_bplpt-copper_template+2
COP_OFF_DIWSTOP     EQU cop_diwstop-copper_template+2
COP_OFF_COLOR00     EQU cop_colours-copper_template+2

; font_8x8.bin: 256 glyphs * 8 bytes = 2048 bytes, no header.
; One byte per scan line, MSB = leftmost pixel.
        EVEN
font_data:
        INCBIN  "font_8x8.bin"
font_data_end:

        EVEN
str_title:
        DC.B    "AMIGA BOOTLOADER "
        APP_VERSION
        DC.B    0
        EVEN
str_log_title:
        DC.B    "Amiga RBCP Bootloader "
        APP_VERSION
        DC.B    0
        EVEN
str_rocks:
        DC.B    "piers.rocks",0
        EVEN
; The controls, in the 40 columns there are.
str_footer:
        DC.B    "MOVE: ARROWS/CLICK  BOOT: RET/R-CLICK",0
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
; Banner artwork
;
; Generated by the tools under tools/ and checked in — see tools/README.md.
; banner_init copies each one to the chip RAM slot beside it here.
; ============================================================
        EVEN
    ifne CONFIG_BANNER_ART
        INCLUDE "assets/logo.s"
        INCLUDE "assets/tagline_wide.s"
    ifgt LOGO_BYTES-(CHIP_LOGO_MASK-CHIP_LOGO)
    fail "the logo has outgrown its chip RAM slot"
    endc
    ifgt TAGLINE_WIDE_BYTES-(CHIP_CHIME-CHIP_TAGLINE)
    fail "the tagline has outgrown its chip RAM slot"
    endc
; Pen 1 is spare and the palette shows it as background, so a regenerated
; asset that went back to pen 1 would come out black on black.
    ifeq PEN01_RGB
    ifd TAGLINE_WIDE_PEN1
    fail "the heading uses pen 1, which the palette has as background"
    endc
    ifd LOGO_PEN1
    fail "the logo uses pen 1, which the palette has as background"
    endc
    endc
    endc

    ifne CONFIG_BANNER_BALL
        INCLUDE "assets/ball.s"
    ifgt BALL_BYTES-(CHIP_BALL_MASK-CHIP_BALL)
    fail "the ball has outgrown its chip RAM slot"
    endc
    endc

    ifne CONFIG_BOOT_CHIME
        INCLUDE "assets/chime.s"
    ifgt CHIME_LEN_BYTES-(CHIP_FG-CHIP_CHIME)
    fail "the chime has outgrown its chip RAM slot"
    endc
    endc

; The foreground object and its mask are built at run time, so nothing above
; sizes them.  Check them against the room the layout gave them, and check
; that the RAM code above them still lands inside a base A500's chip RAM.
    ifgt FG_BYTES-(CHIP_FG_MASK-CHIP_FG)
    fail "the foreground object has outgrown its chip RAM slot"
    endc
    ifgt FG_MASK_BYTES-(RAM_CODE_BASE-CHIP_FG_MASK)
    fail "the foreground mask has outgrown its chip RAM slot"
    endc
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
