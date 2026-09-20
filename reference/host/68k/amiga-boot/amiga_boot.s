; amiga_boot.s — Amiga RBCP Kickstart bootloader
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Lets an Amiga pick which Kickstart image it boots from those held on the
; RBCP device serving its ROM socket.  It enters command-response mode, reads
; what the device holds, and boots the remembered or default image at once.
; Holding both mouse buttons at boot brings up a menu instead.  See README.md
; for the controls and the display.
;
; ROM image layout, top-aligned — 256 KB from $FC0000 or 512 KB from $F80000:
;
;   ROM SECTION  — executed directly from ROM
;     ROM header, boot_cold_start, JMP boot_rom_entry
;     amiga_hw.s: a500_hw_init, exc_halt, kbd_init, screen_init
;     boot_rom_entry: HW init, screen up, copy RAM section, JMP $28000
;
;   RAM SECTION  — stored in ROM, copied to RAM_CODE_BASE ($28000) at boot
;     boot_ram_entry: the RBCP session
;     main_loop, do_boot and banner_*: the menu, the banner and booting
;     rbcp.s: RBCP protocol library
;     amiga-common: shared Amiga routines
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
;   assembled at its ROM address but executes from $28000.  The .L suffix also
;   stops the assembler shortening high addresses to sign-extended absolute
;   short, which works on a 68000's 24-bit bus but not on a 32-bit one.

; Definitions first — the ORG below depends on CONFIG_ROM_BASE.  None of
; these emit any code or data.
        INCLUDE "rbcp_config.s"
        INCLUDE "../rbcp/rbcp_defs.s"
        INCLUDE "amiga_config.s"
        INCLUDE "../amiga-common/amiga_defs.s"
        INCLUDE "amiga_defs.s"

; The version, shown on screen and in the log.  A macro rather than an EQU
; because it expands to text.
APP_VERSION MACRO
        DC.B    "0.1.2"
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
; ROM-section hardware routines: a500_hw_init, exc_halt, kbd_init, screen_init
; screen_init contains a forward BSR to screen_clear in the RAM section.  Both
; are in ROM at assembly time, so the PC-relative branch is correct there.
; ---------------------------------------------------------------------------
        INCLUDE "../amiga-common/amiga_hw.s"

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
; active slot instead.  It can still remember a choice, where it offers writes
; that need no slot provided — see nv_locate.
; ---------------------------------------------------------------------------
boot_ram_entry:
        MOVE.L  #BITPLANE_BASE,VAR_DRAW_BASE
        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        MOVE.B  #MENU_COL,VAR_MENU_COL
        ; The first line off the bottom of the display.  An animation step and
        ; the chime's fade both wait on the beam reaching it.
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
        MOVEQ   #0,D1
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
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        TST.B   (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_CAP_COUNT).W
        BEQ.S   .pipe_done
        MOVEQ   #0,D0                   ; the bootloader logs through pipe 0
        BSR     log_open
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
        MOVEQ   #0,D1
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
        MOVEQ   #0,D1
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
        MOVEQ   #0,D1
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
        BSR     nv_locate
        TST.B   D0
        BEQ.S   .nv_done
        MOVE.B  #1,VAR_NV_PRESENT
        MOVE.B  #1,RBCP_ARG0            ; count = 1
        MOVE.B  D1,RBCP_ARG1            ; location LSB
        LSR.W   #8,D1
        MOVE.B  D1,RBCP_ARG2            ; location MSB
        BSR     rbcp_cmd_nv_peek
        TST.B   D0
        BNE.S   .nv_done
        MOVEQ   #1,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF).W,D0
        MOVE.B  D0,VAR_NV_STORED
        BEQ.S   .nv_done                ; 0 = never stored
        CMP.B   VAR_TOTAL_FLASH,D0
        BCC.S   .nv_done                ; out of range
        MOVE.B  D0,VAR_BOOT_FLASH
.nv_done:
        BSR     log_stored

        ; selection follows the stored slot, or the first entry when that is
        ; not shown
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
; Nothing it calls blocks on a condition.  A routine that cannot finish this
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
; This routine is outside the art switches.  A build without a ball drops
; what is inside it, not the hook, so periodic work always has somewhere to go.
; ---------------------------------------------------------------------------
tick_periodic:
        BSR     key_poll                ; so a key appears as it is struck
    ifne CONFIG_BOOT_CHIME
        BSR     chime_tick              ; silence it once it has played out
    endc
    ifne CONFIG_BANNER_BALL
        BSR     banner_tick             ; one step of the animation
    endc
        RTS

; ---------------------------------------------------------------------------
; key_poll — one read of the keyboard, held until the menu can act on it.
;
; The keyboard holds a press until the host handshakes it, so one left unread
; arrives late.
; This runs every pass in either state, so a key struck while the mouse
; buttons are still coming up appears as the menu opens.
;
; In ST_RELEASE the buttons that asked for the menu are the ones still down,
; and letting go of them is not a click, so the mouse tokens are dropped.
; ---------------------------------------------------------------------------
key_poll:
        TST.B   VAR_PEND_KEY
        BNE.S   .kp_done                ; one still waiting to be acted on
        MOVEM.L D0,-(SP)
        BSR     amiga_getkey
        TST.B   D0
        BEQ.S   .kp_out
        CMPI.B  #ST_MENU,VAR_STATE
        BEQ.S   .kp_keep
        CMPI.B  #KEY_LMB,D0
        BEQ.S   .kp_out
        CMPI.B  #KEY_RMB,D0
        BEQ.S   .kp_out
.kp_keep:
        MOVE.B  D0,VAR_PEND_KEY
.kp_out:
        MOVEM.L (SP)+,D0
.kp_done:
        RTS

    ifne CONFIG_BOOT_CHIME
; ---------------------------------------------------------------------------
; chime_tick — start the chime when its wait is up, and switch the channel off
; once the sample has played through.
;
; Paula has no way to play a sample once.  It repeats for as long as the
; channel is on, so a single chime means switching the channel off after one
; play-through, and how long that takes is known exactly from the sample and
; the period.  The counter is free running, so both moments are right however long
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
        BSR     tod_now                 ; and off again when the sample has played
        ADDI.L  #CHIME_TICKS_NTSC,D0
        TST.B   VAR_IS_PAL
        BEQ     .cht_end
        SUBI.L  #CHIME_TICKS_NTSC-CHIME_TICKS_PAL,D0
.cht_end:
        ANDI.L  #$00FFFFFF,D0
        MOVE.L  D0,VAR_CHIME_END
        MOVE.B  #2,VAR_CHIME_ON
        BRA     .cht_done

        ; --- the sample has played through, switch it off ---
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
; nothing.  It is the same length every time and it runs once.
release_settle:
        MOVEM.L D0,-(SP)
        MOVE.W  #RELEASE_SETTLE,D0
.rst_loop:
        SUBQ.W  #1,D0
        BNE.S   .rst_loop
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; state_menu — acts on the key key_poll is holding.  A left click or the
; arrows change the choice, a right click or RETURN boots it, and a digit
; picks one of the first nine.
;
; Acting on a key redraws, which needs the blitter, so a key that arrives
; mid-frame is held until the frame is on screen rather than waited out on
; BBUSY.  That is at most one frame's blits, and no key is lost: key_poll
; reads no further while one is still waiting here.
; ---------------------------------------------------------------------------
state_menu:
        TST.B   VAR_PEND_KEY
        BEQ.S   .sm_done
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
        BSR     nv_locate               ; where it goes, and what to name
        TST.B   D0
        BEQ.S   boot_slot_entry
        MOVE.B  VAR_BOOT_FLASH,RBCP_ARG0 ; byte to store
        MOVE.B  D1,RBCP_ARG1            ; location LSB
        LSR.W   #8,D1
        MOVE.B  D1,RBCP_ARG2            ; location MSB
        MOVE.B  D2,RBCP_ARG3            ; staging slot, or none
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
        BSR     led_set_colour          ; the image's own colour, left set after the handover
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
    ifne CONFIG_BANNER_ART+CONFIG_BANNER_BALL
        BSR     blit_wait               ; let the last blit finish before DMA goes
    endc
        ORI.W   #$0700,SR               ; interrupts off
        MOVE.W  #$7FFF,INTENA
        MOVE.W  #$7FFF,INTREQ
        MOVE.W  #$03FF,DMACON           ; all DMA off, display included
        MOVEA.L (CONFIG_ROM_BASE).L,SP        ; SSP from the new ROM
        MOVEA.L (CONFIG_ROM_BASE+4).L,A0      ; initial PC from the new ROM
        JMP     (A0)

; boot_settle — a delay long enough for the device to finish a LOAD_AND_EXIT
; copy before the machine reads the new ROM.  Roughly 650ms at 7MHz.
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
; nv_locate — where a remembered byte lives, and what to name as staging.
;
; Returns D0 = 0 when the device cannot hold one, 1 when it can.  On success
; D1 is the location, a word, and D2 the RAM slot argument to pass.
;
; A device writes NV storage one of two ways.  Given a spare RAM slot it stages
; the whole region there, so any location can be written and byte 0 is used.
; With no spare slot to provide it stages within itself instead, and only a few
; bytes of NV storage survive.  GET_NV_CAPABILITY says how many and which end
; of NV storage they sit at, the byte goes at the start of them, and
; RBCP_NV_SLOT_NONE is named in place of a slot.  A write of that kind loses
; the rest of NV storage, which costs this bootloader nothing — one byte is all
; it keeps.
; ---------------------------------------------------------------------------
nv_locate:
        MOVEM.L D3-D4,-(SP)
        BSR     rbcp_cmd_get_nv_cap
        TST.B   D0
        BNE.S   .nl_fail
        MOVEQ   #4,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data

        MOVEQ   #0,D3
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_NV_CAP_SIZE_HI).W,D3
        LSL.W   #8,D3
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_NV_CAP_SIZE_LO).W,D3
        TST.W   D3
        BEQ.S   .nl_fail                ; no storage
        TST.B   (CONFIG_RBCP_DATA_BUF+RBCP_NV_CAP_WRITABLE).W
        BEQ.S   .nl_fail                ; read only

        TST.B   VAR_SINGLE_SLOT
        BNE.S   .nl_no_slot
        MOVEQ   #0,D1                   ; a spare slot stages the whole region
        MOVE.B  VAR_TARGET_RAM,D2
        BRA.S   .nl_ok
.nl_no_slot:
        MOVEQ   #0,D0
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_NV_CAP_NOSLOT).W,D0
        MOVE.W  D0,D4
        ANDI.W  #$000F,D4               ; N
        BEQ.S   .nl_fail                ; needs a slot, and there is none
        MOVEQ   #1,D1
        LSL.W   D4,D1                   ; 2^N bytes stay unchanged
        BTST    #7,D0                   ; which end of NV storage they sit at
        BEQ.S   .nl_at_start
        SUB.W   D1,D3
        MOVE.W  D3,D1                   ; they end it
        BRA.S   .nl_named
.nl_at_start:
        MOVEQ   #0,D1                   ; they start it
.nl_named:
        MOVE.B  #RBCP_NV_SLOT_NONE,D2
.nl_ok:
        MOVEQ   #1,D0
        MOVEM.L (SP)+,D3-D4
        RTS
.nl_fail:
        MOVEQ   #0,D0
        MOVEM.L (SP)+,D3-D4
        RTS

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

        INCLUDE "../amiga-common/amiga_device.s"

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
        MOVEQ   #0,D1
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
        MOVEQ   #' ',D0                 ; the gap before the name, drawn so the
        ADDQ.B  #1,D1                   ; entry paints its whole span over
        BSR     screen_putchar          ; whatever was under it

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

; draw_sel_entry — draw the selected entry.  draw_entry takes its index in D7
; and the menu loops are using D7 for their own count.
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

        INCLUDE "../amiga-common/amiga_input.s"

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

        INCLUDE "../amiga-common/amiga_log.s"

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
        MOVEQ   #0,D1
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

        INCLUDE "../amiga-common/amiga_error.s"

; ===========================================================================
; Banner — the tagline heading, the band, and the ball that bounces in it
;
; Everything here runs from the RAM section and touches only chip RAM and the
; custom chips, so it cannot put a byte on the ROM bus.  Two moments need
; that.  Between the knock and the response to ENTER_CMD_RESP, and after a
; command the device never answered until rbcp_reset has re-opened the
; session, a ROM read is taken as the next byte of a command.  Everywhere else
; the device filters on the command page and a ROM read elsewhere is harmless,
; so nothing here has to be stopped around a command.
;
; The animation is driven from the menu's polling loop rather than from a
; vertical blank interrupt.  The loop never waits, so a step takes the blitter
; at the first pass that finds it free.  Choosing a slot leaves that loop for
; good, so the ball stands still from there to the handover.
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

        INCLUDE "../amiga-common/amiga_time.s"

    ifne CONFIG_BANNER_BALL
; ---------------------------------------------------------------------------
; banner_tick — one step of the animation, from tick_periodic.  It never
; waits: a step that needs the blitter and finds it busy leaves the state
; alone and returns, so the pass goes on to read the keyboard instead.
;
; A frame starts when the beam leaves the display — see FIELD_TICK_NTSC — and
; its blits run back to back, with the CPU reading the keyboard in the gaps
; between them.
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

; ball_cover_all — every plane of it, one blit after another.  banner_start is
; off the main loop and has no frame to fit into, so it takes them all at once.
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
        INCLUDE "../amiga-common/amiga_blit.s"
    endc

; ============================================================
; RBCP library (runs from RAM)
; ============================================================
        INCLUDE "../rbcp/rbcp.s"

        INCLUDE "../amiga-common/amiga_screen.s"

        EVEN
ram_section_rom_end:

; ============================================================
; ROM DATA SECTION
; Copper template, font and strings.  Reached from RAM code by absolute long
; address, so correct from any PC.
; ============================================================

        INCLUDE "../amiga-common/amiga_screen_data.s"

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

        INCLUDE "../amiga-common/amiga_device_data.s"
        INCLUDE "../amiga-common/amiga_input_data.s"

        EVEN
; The controls line, fitted to the screen's 40 columns.
str_footer:
        DC.B    "MOVE: ARROWS/CLICK  BOOT: RET/R-CLICK",0

        INCLUDE "../amiga-common/amiga_error_data.s"

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

        INCLUDE "../amiga-common/amiga_log_data.s"

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
        DC.B    "DEVICE REPORTS INCOMPATIBLE VERSION",0
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

        INCLUDE "../amiga-common/amiga_diag_data.s"

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
