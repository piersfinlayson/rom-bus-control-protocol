; apple2_boot.s — Reset entry, relocation, RBCP session, boot menu
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

.include "apple2_defs.s"

; ---------------------------------------------------------------------------
; Imports
; ---------------------------------------------------------------------------

.import a2_hw_init
.import a2_clear_screen
.import a2_print_at
.import a2_invert_row
.import a2_normal_row
.import a2_getkey

.import rbcp_reset
.import rbcp_cmd_enter_cmd_resp
.import rbcp_check_protocol_version
.import rbcp_cmd_get_ram_slot_info_all
.import rbcp_cmd_get_flash_slot_count
.import rbcp_cmd_get_flash_slot_info
.import rbcp_cmd_load_slot
.import rbcp_cmd_switch_and_exit
.import rbcp_cmd_get_nv_capability
.import rbcp_cmd_nv_peek
.import rbcp_cmd_nv_poke_commit_byte
.import rbcp_cmd_get_pipe_capability
.import rbcp_cmd_pipe_write
.if CONFIG_ROM_SIZE > $0800
.import rbcp_cmd_get_led_capability
.import rbcp_cmd_get_led_info
.import rbcp_cmd_set_led
.endif

; Linker-generated symbols for the CODE segment (load/run split)
.import __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------

; Nine images, because the menu numbers them 1 to 9 and a single digit picks
; one.  Flash slot 0 is this bootloader and is never listed.
MAX_DISPLAY      = 9

TITLE_ROW        = 0
TITLE_COL        = 8
MENU_ENTRY_ROW0  = 3
MENU_ENTRY_COL   = 6

; The countdown and the footer share a row and a column, and the footer is the
; longer of the two, so drawing the footer is what rubs the countdown out.
FOOTER_ROW       = 20
FOOTER_COL       = 4
COUNT_DIGIT      = 11               ; where the 0 sits in str_counting

ERROR_ROW        = 12
ERROR_COL        = 8

COUNTDOWN_SECS   = 3

; ---------------------------------------------------------------------------
; BSS — RAM-resident variables
; ---------------------------------------------------------------------------

.bss

var_total_ram:    .res 1
var_active_ram:   .res 1
var_target_ram:   .res 1
var_total_flash:  .res 1
var_num_display:  .res 1
var_selection:    .res 1    ; 0-based index into the displayed list
var_nv_present:   .res 1    ; 0 = absent or read only, 1 = writable
var_nv_stored:    .res 1    ; slot the device already has stored
var_pipe_present: .res 1    ; 0 = device has no pipe, 1 = pipe 0 is available
var_boot_flash:   .res 1    ; flash slot the countdown will boot
var_count:        .res 1
.if CONFIG_ROM_SIZE > $0800
var_led:          .res 1    ; lowest RGB LED, or $FF where the device has none
.endif

; ===========================================================================
; BOOT segment — runs from ROM, executes before relocation
; ===========================================================================

.segment "BOOT"

; ---------------------------------------------------------------------------
; boot_entry — RESET vector target
;
; Runs from ROM.  Must not call into the CODE segment, which is not in RAM
; yet.  Every instruction fetched here is an address read the device can see,
; which is why the session only starts once execution has moved to RAM.
; ---------------------------------------------------------------------------

.export boot_entry
boot_entry:
    sei
    cld
    ldx #$FF
    txs                     ; set up stack

    jsr a2_hw_init          ; in BOOT, safe to call from ROM

    ; ------------------------------------------------------------------
    ; Relocate the CODE segment from ROM to RAM.
    ;
    ; ZP use: ZP_PTR_LO/HI = ROM source, ZP_TMP0/1 = RAM destination,
    ; ZP_TMP3/4 = 16-bit byte count.
    ; ------------------------------------------------------------------

    lda #<__CODE_LOAD__
    sta ZP_PTR_LO
    lda #>__CODE_LOAD__
    sta ZP_PTR_HI

    lda #<__CODE_RUN__
    sta ZP_TMP0
    lda #>__CODE_RUN__
    sta ZP_TMP1

    lda #<__CODE_SIZE__
    sta ZP_TMP3
    lda #>__CODE_SIZE__
    sta ZP_TMP4

    ldy #0
@copy_loop:
    lda (ZP_PTR_LO), y
    sta (ZP_TMP0), y
    iny
    bne @copy_no_page
    inc ZP_PTR_HI
    inc ZP_TMP1
@copy_no_page:
    lda ZP_TMP3
    bne @copy_dec_lo
    dec ZP_TMP4
@copy_dec_lo:
    dec ZP_TMP3
    lda ZP_TMP3
    ora ZP_TMP4
    bne @copy_loop

    jmp boot_ram_entry      ; run (RAM) address

; ===========================================================================
; CODE segment — runs from RAM after relocation
; ===========================================================================

.code

.macro set_ptr addr
    lda #<(addr)
    sta ZP_PTR_LO
    lda #>(addr)
    sta ZP_PTR_HI
.endmacro

.macro print_at addr, row, col
    set_ptr addr
    lda #row
    ldx #col
    jsr print_str
.endmacro

; ---------------------------------------------------------------------------
; boot_ram_entry — all subsequent execution runs from RAM
; ---------------------------------------------------------------------------

boot_ram_entry:
    jsr a2_clear_screen

    ; Spec defined reset sequence, then the session.
    jsr rbcp_reset

    jsr rbcp_cmd_enter_cmd_resp
    bcc @ok_enter
    jmp err_no_cmd_resp
@ok_enter:

    jsr rbcp_check_protocol_version
    bcc @ok_version
    jmp err_protocol_version
@ok_version:

    jsr rbcp_cmd_get_ram_slot_info_all
    bcc @ok_ram
    jmp err_ram_info
@ok_ram:
    lda RBCP_DATA_ADDR + 0
    sta var_total_ram
    lda RBCP_DATA_ADDR + 1
    sta var_active_ram

    lda var_total_ram
    cmp #2
    bcs @ok_ramcount
    jmp err_insuff_ram
@ok_ramcount:
    lda var_active_ram
    eor #1
    sta var_target_ram

    ; ------------------------------------------------------------------
    ; Is there a pipe to log through?
    ;
    ; GET_PIPE_CAPABILITY takes no argument bytes, so a device whose protocol
    ; version predates the Pipes group consumes nothing, fails the command and
    ; stays in step.  Carry set and a count of zero lead to the same place.
    ; ------------------------------------------------------------------

    lda #0
    sta var_pipe_present
    jsr rbcp_cmd_get_pipe_capability
    bcs @pipe_done
    lda RBCP_DATA_ADDR + RBCP_PIPE_CAP_COUNT
    beq @pipe_done
    lda #1
    sta var_pipe_present
    set_ptr str_header
    jsr log_line
@pipe_done:

.if CONFIG_ROM_SIZE > $0800
    ; ------------------------------------------------------------------
    ; Which LED can show a colour?
    ;
    ; LEDs are numbered per device, so the lowest-numbered RGB one is found
    ; rather than assumed.  As with the pipe, a device whose protocol version
    ; predates the LEDs group consumes nothing and fails the capability
    ; command, which lands in the same place as a device with no LEDs.
    ; ------------------------------------------------------------------

    lda #$FF
    sta var_led
    jsr rbcp_cmd_get_led_capability
    bcs @led_done
    lda RBCP_DATA_ADDR + RBCP_LED_CAP_COUNT
    beq @led_done
    sta ZP_TMP3                     ; count
    lda #0
@led_scan:
    pha
    jsr rbcp_cmd_get_led_info
    bcs @led_next
    lda RBCP_DATA_ADDR + RBCP_LED_INFO_TYPE
    cmp #RBCP_LED_TYPE_RGB
    bne @led_next
    pla
    sta var_led
    jmp @led_done
@led_next:
    pla
    clc
    adc #1
    cmp ZP_TMP3
    bcc @led_scan
@led_done:
    jsr led_cycle
.endif

    ; ------------------------------------------------------------------
    ; How many images are there to choose between?
    ; ------------------------------------------------------------------

    jsr rbcp_cmd_get_flash_slot_count
    bcc @ok_flash
    jmp err_flash_info
@ok_flash:
    lda RBCP_DATA_ADDR + 0
    sta var_total_flash
    cmp #2                  ; slot 0 is this bootloader
    bcs @ok_flashcount
    jmp err_no_images
@ok_flashcount:
    sec
    sbc #1                  ; drop slot 0 from the count
    cmp #MAX_DISPLAY + 1
    bcc @disp_ok
    lda #MAX_DISPLAY
@disp_ok:
    sta var_num_display

    ; ------------------------------------------------------------------
    ; Which image does the device already have stored as the choice?
    ; A failure anywhere here leaves the default of flash slot 1.
    ; ------------------------------------------------------------------

    lda #0
    sta var_nv_present
    sta var_nv_stored
    lda #1
    sta var_boot_flash

    jsr rbcp_cmd_get_nv_capability
    bcs @nv_done
    lda RBCP_DATA_ADDR + RBCP_NV_CAP_SIZE_LO
    ora RBCP_DATA_ADDR + RBCP_NV_CAP_SIZE_HI
    beq @nv_done                    ; no NV storage
    lda RBCP_DATA_ADDR + RBCP_NV_CAP_WRITABLE
    beq @nv_done                    ; present but read only
    lda #1
    sta var_nv_present

    lda #1
    sta rbcp_arg0                   ; count = 1
    lda #0
    sta rbcp_arg1                   ; location LSB
    sta rbcp_arg2                   ; location MSB
    jsr rbcp_cmd_nv_peek
    bcs @nv_done

    lda RBCP_DATA_ADDR              ; the stored slot byte
    sta var_nv_stored
    beq @nv_done                    ; 0 = this bootloader, so never stored
    cmp var_total_flash
    bcs @nv_done                    ; out of range
    sta var_boot_flash
@nv_done:

    ; Selection follows the stored slot, clamped to what is on screen.
    lda var_boot_flash
    sec
    sbc #1
    cmp var_num_display
    bcc @sel_ok
    lda #0
@sel_ok:
    sta var_selection

; ---------------------------------------------------------------------------
; The menu is drawn either way.  A countdown runs under it naming how long is
; left, and any key stops it — at which point the user is already looking at
; the list they wanted.
; ---------------------------------------------------------------------------

    jsr draw_title
    jsr draw_list
    jsr highlight_selection
    lda #COUNTDOWN_SECS
    sta var_count
@tick:
    lda var_count
    clc
    adc #'0'
    sta str_counting + COUNT_DIGIT   ; the strings are in RAM, so this sticks
    print_at str_counting, FOOTER_ROW, FOOTER_COL

    jsr wait_a_second
    cmp #KEY_NONE
    bne path_menu                   ; any key stops the countdown
    dec var_count
    bne @tick

    ; The countdown ran out.  Boot what the device had stored, which is the
    ; highlighted line unless the stored slot is past the end of the list.
    lda var_boot_flash
    jmp boot_slot

; ---------------------------------------------------------------------------
; Menu
; ---------------------------------------------------------------------------

path_menu:
    print_at str_footer, FOOTER_ROW, FOOTER_COL

key_loop:
    jsr a2_getkey
    cmp #KEY_NONE
    beq key_loop
    cmp #KEY_RETURN
    beq do_boot
    cmp #KEY_UP
    beq do_up
    cmp #KEY_LEFT
    beq do_up
    cmp #KEY_DOWN
    beq do_down
    cmp #KEY_RIGHT
    beq do_down
    cmp #KEY_SPACE
    beq do_down
    cmp #KEY_1
    bcc key_loop
    cmp #KEY_9 + 1
    bcs key_loop
    sec
    sbc #KEY_1              ; 0-based index
    cmp var_num_display
    bcs key_loop
    pha
    jsr unhighlight_selection
    pla
    sta var_selection
    jsr highlight_selection
    jmp key_loop

do_up:
    lda var_selection
    beq key_loop
    jsr unhighlight_selection
    dec var_selection
    jsr highlight_selection
    jmp key_loop

do_down:
    lda var_selection
    clc
    adc #1
    cmp var_num_display
    bcs key_loop
    jsr unhighlight_selection
    inc var_selection
    jsr highlight_selection
    jmp key_loop

do_boot:
    lda var_selection
    clc
    adc #1                  ; 1-based flash slot
    sta var_boot_flash

    ; Remember the choice, where the device can hold one and it has changed.
    lda var_nv_present
    beq boot_slot_entry
    lda var_boot_flash
    cmp var_nv_stored
    beq boot_slot_entry
    sta rbcp_arg0           ; byte to store
    lda #0
    sta rbcp_arg1           ; location LSB
    sta rbcp_arg2           ; location MSB
    lda var_target_ram
    sta rbcp_arg3           ; RAM slot used for staging
    jsr rbcp_cmd_nv_poke_commit_byte
    bcc boot_slot_entry
    jmp err_nv_commit

boot_slot_entry:
    lda var_boot_flash
    ; fall through

; ---------------------------------------------------------------------------
; boot_slot — A = flash slot.  Loads it into the spare RAM slot, switches to
; it, and resets through the new image's reset vector.
; ---------------------------------------------------------------------------

boot_slot:
    sta ZP_TMP2             ; flash slot, wanted again after the load
    ldx ZP_TMP2
    lda var_target_ram
    jsr rbcp_cmd_load_slot
    bcc @loaded
    jmp err_load
@loaded:
    lda ZP_TMP2
    jsr led_set_colour
    lda ZP_TMP2
    jsr log_switch

    lda var_target_ram
    jsr rbcp_cmd_switch_and_exit

    ; The image now being served is the one the user picked.  Make the
    ; autostart ROM cold start rather than warm start into whatever it finds.
    lda #0
    sta PWRUP_VECT_CK
    sta PWRUP_BYTE

    jmp (RESET_VECTOR)

;  --------------------------------------------------------------------------
; led_set_colour — A = the flash slot being booted.
;
; Sets the device's RGB LED breathing a colour of its own per image, so the
; machine says which one it is running without anything on screen.  An LED's state outlives
; the session, which is what makes this worth doing here: the colour is still
; showing long after the bootloader has handed over.
;
; The 2KB build leaves this out.  There is no room in an F8 ROM for the
; capability query, the search for an RGB LED and a table of colours.
; ---------------------------------------------------------------------------

; led_cycle — puts the LED through the hues for as long as the bootloader is
; up.  Booting an image replaces it with that image's colour, and a device
; whose LED is still cycling is one that never got that far.
.if CONFIG_ROM_SIZE > $0800
led_cycle:
    ldx var_led
    bmi @none
    lda #RBCP_LED_CYCLE
    sta rbcp_arg0
    lda #0
    sta rbcp_arg1
    sta rbcp_arg2
    sta rbcp_arg3           ; colour, which Cycle does not take
    sta rbcp_arg4           ; brightness, the device's to choose
    sta rbcp_arg5           ; period, so the mode runs at its own rate
    sta rbcp_arg6           ; hold, so it cycles until something stops it
    txa
    jmp rbcp_cmd_set_led
@none:
    rts
.endif

led_set_colour:
.if CONFIG_ROM_SIZE > $0800
    ldx var_led
    bmi @done               ; $FF, no RGB LED on this device
    and #$07
    sta ZP_TMP3
    asl a
    clc
    adc ZP_TMP3             ; three bytes to a colour
    tay
    lda led_colours, y
    sta rbcp_arg1           ; red
    lda led_colours + 1, y
    sta rbcp_arg2           ; green
    lda led_colours + 2, y
    sta rbcp_arg3           ; blue
    lda #RBCP_LED_BREATHE
    sta rbcp_arg0
    lda #0
    sta rbcp_arg4           ; brightness, the device's to choose
    sta rbcp_arg5           ; period, so the mode breathes at its own rate
    sta rbcp_arg6           ; hold, so the colour stays until something changes it
    lda var_led
    jmp rbcp_cmd_set_led
@done:
.endif
    rts

.if CONFIG_ROM_SIZE > $0800
; A colour per flash slot, three bytes each, the slot number taken modulo eight.
; Slot 0 is the bootloader and never boots, so its entry is the one a slot
; number past the end of the table lands on.
led_colours:
    .byte $40, $40, $40     ; 0 — white, and what slot 8 gets
    .byte $00, $FF, $00     ; 1 — green
    .byte $00, $40, $FF     ; 2 — blue
    .byte $FF, $00, $00     ; 3 — red
    .byte $FF, $80, $00     ; 4 — orange
    .byte $FF, $00, $FF     ; 5 — magenta
    .byte $00, $FF, $FF     ; 6 — cyan
    .byte $FF, $FF, $00     ; 7 — yellow
.endif

; ===========================================================================
; Screen
; ===========================================================================

; print_str — A = row, X = column, ZP_PTR_LO/HI = string.
print_str:
    sta ZP_TMP0
    stx ZP_TMP1
    jmp a2_print_at

draw_title:
    print_at str_header, TITLE_ROW, TITLE_COL
    lda #TITLE_ROW
    jmp a2_invert_row

; ---------------------------------------------------------------------------
; draw_list — one line per image, each asked for as it is drawn.
;
; The back-channel is 64 bytes, which holds one slot record and no more, so
; the names arrive one command at a time and go straight to the screen.  A
; slot the device will not describe is left blank rather than stopping the
; menu.
; ---------------------------------------------------------------------------

draw_list:
    lda #0
    sta ZP_TMP2             ; 0-based display index
@loop:
    lda ZP_TMP2
    cmp var_num_display
    beq @done

    clc
    adc #1                  ; flash slot
    jsr rbcp_cmd_get_flash_slot_info
    bcs @next

    lda ZP_TMP2
    clc
    adc #'1'
    sta str_entry           ; 1 upwards, in front of the name
    set_ptr str_entry
    lda ZP_TMP2
    clc
    adc #MENU_ENTRY_ROW0
    ldx #MENU_ENTRY_COL - 3
    jsr print_str           ; leaves ZP_TMP2 alone

    set_ptr RBCP_DATA_ADDR + 1      ; the name, past the ROM type byte
    lda ZP_TMP2
    clc
    adc #MENU_ENTRY_ROW0
    ldx #MENU_ENTRY_COL
    jsr print_str

@next:
    inc ZP_TMP2
    jmp @loop
@done:
    rts

highlight_selection:
    lda var_selection
    clc
    adc #MENU_ENTRY_ROW0
    jmp a2_invert_row

unhighlight_selection:
    lda var_selection
    clc
    adc #MENU_ENTRY_ROW0
    jmp a2_normal_row

; ---------------------------------------------------------------------------
; wait_a_second — waits about a second, or until a key is pressed.
;
; Returns the key in A, or KEY_NONE if the second ran out.  There is no timer
; to read on an Apple II, so this counts.  256 turns of the inner loop is
; about 1300 cycles, and 768 of those is a little over a second at 1.023MHz.
; Clobbers: A, X, Y, ZP_TMP3
; ---------------------------------------------------------------------------

wait_a_second:
    lda #3
    sta ZP_TMP3
@third:
    ldy #0
@outer:
    ldx #0
@inner:
    dex
    bne @inner
    jsr a2_getkey
    cmp #KEY_NONE
    bne @done
    dey
    bne @outer
    dec ZP_TMP3
    bne @third
    lda #KEY_NONE
@done:
    rts

; ===========================================================================
; Logging, through pipe 0 where the device has one
; ===========================================================================

; ---------------------------------------------------------------------------
; log_switch — sends "SWITCHING TO SLOT $XX" with A holding the slot.
;
; The last thing sent before SWITCH_AND_EXIT, which is the last moment
; anything can be sent: the switch ends the session, and the image that
; follows need not have a back-channel at all.
; ---------------------------------------------------------------------------

log_switch:
    pha
    lda var_pipe_present
    beq @done
    set_ptr msg_switching
    jsr pipe_puts
    pla
    jsr hex_to_args
    lda #13
    sta rbcp_arg2
    lda #10
    sta rbcp_arg3
    lda #4
    ldx #0                  ; pipe 0
    jsr rbcp_cmd_pipe_write
    rts
@done:
    pla
    rts

; ---------------------------------------------------------------------------
; log_line — sends the string at (ZP_PTR_LO/HI) and a CRLF.
; ---------------------------------------------------------------------------

log_line:
    lda var_pipe_present
    beq @done
    jsr pipe_puts
    lda #13
    sta rbcp_arg0
    lda #10
    sta rbcp_arg1
    lda #2
    ldx #0
    jsr rbcp_cmd_pipe_write
@done:
    rts

; ---------------------------------------------------------------------------
; pipe_puts — sends the null-terminated string at (ZP_PTR_LO/HI) to pipe 0.
;
; PIPE_WRITE carries at most four bytes, so the string goes out in chunks.  A
; chunk the device will not take ends the whole thing: waiting for room would
; mean an Apple II that hangs because nothing at the far end is reading, and a
; log line is never worth not booting for.
;
; Clobbers: A, X, Y, ZP_PTR_LO/HI, ZP_TMP4 and the RBCP arguments.
; ---------------------------------------------------------------------------

pipe_puts:
@chunk:
    ldy #0                  ; rbcp_cmd_pipe_write clobbers Y
    ldx #0                  ; bytes gathered so far
@gather:
    lda (ZP_PTR_LO), y
    beq @flush              ; terminator, send what we have
    sta rbcp_arg0, x
    inc ZP_PTR_LO
    bne @next
    inc ZP_PTR_HI
@next:
    inx
    cpx #RBCP_PIPE_WRITE_MAX
    bne @gather
@flush:
    txa                     ; A = count, and sets Z when none
    beq @done
    stx ZP_TMP4             ; count, to tell a full chunk from a short one
    ldx #0                  ; pipe 0
    jsr rbcp_cmd_pipe_write
    bcs @done               ; refused, or the device is gone — give up
    lda ZP_TMP4
    cmp #RBCP_PIPE_WRITE_MAX
    beq @chunk              ; a full chunk, so there may be more
@done:
    rts

; ---------------------------------------------------------------------------
; hex_to_args — A as two upper case hex characters in rbcp_arg0 and arg1.
; Clobbers: A, X, Y
; ---------------------------------------------------------------------------

hex_to_args:
    tay
    lsr a
    lsr a
    lsr a
    lsr a
    jsr @nibble
    sta rbcp_arg0
    tya
    and #$0F
    jsr @nibble
    sta rbcp_arg1
    rts
@nibble:
    cmp #10
    bcc @digit
    adc #6                  ; carry is set, so this adds 7
@digit:
    adc #'0'
    rts

; ===========================================================================
; Error handlers
; ===========================================================================

; Each of these names a line in the error table below.
err_no_cmd_resp:      ldx #0
                      jmp err_halt
err_protocol_version: ldx #1
                      jmp err_halt
err_ram_info:         ldx #2
                      jmp err_halt
err_insuff_ram:       ldx #3
                      jmp err_halt
err_flash_info:       ldx #4
                      jmp err_halt
err_no_images:        ldx #5
                      jmp err_halt
err_nv_commit:        ldx #6
                      jmp err_halt
err_load:             ldx #7
                      ; fall through

; err_halt — X = error number.  Says what went wrong and stops.  There is no
; way back from here: the session is in an unknown state, and the image this
; would have booted has not been loaded.  Power cycling starts again.
err_halt:
    stx ZP_TMP3             ; a2_print_at leaves ZP_TMP2 and above alone
    jsr a2_clear_screen
    jsr draw_title
    print_at str_err, ERROR_ROW, ERROR_COL
    ldx ZP_TMP3
    lda err_lo, x
    sta ZP_PTR_LO
    lda err_hi, x
    sta ZP_PTR_HI
    lda #ERROR_ROW + 2
    ldx #ERROR_COL
    jsr print_str
@halt:
    jmp @halt

err_lo:
    .byte <msg_err_cmd_resp, <msg_err_version, <msg_err_ram_info
    .byte <msg_err_ram_count, <msg_err_flash_info, <msg_err_no_images
    .byte <msg_err_nv, <msg_err_load
err_hi:
    .byte >msg_err_cmd_resp, >msg_err_version, >msg_err_ram_info
    .byte >msg_err_ram_count, >msg_err_flash_info, >msg_err_no_images
    .byte >msg_err_nv, >msg_err_load

; ===========================================================================
; Strings.  These live in the CODE segment, so they are read from RAM once
; the session is open.
; ===========================================================================

str_header:     .byte "APPLE II RBCP BOOTLOADER", 0
str_counting:   .byte "BOOTING IN 0 - ANY KEY FOR MENU", 0
str_entry:      .byte "0) ", 0
str_footer:     .byte "RETURN BOOTS, ARROWS OR 1-9 PICK", 0

msg_switching:  .byte "SWITCHING TO SLOT $", 0

str_err:            .byte "RBCP ERROR", 0
msg_err_cmd_resp:   .byte "NO REPLY", 0
msg_err_version:    .byte "PROTOCOL VERSION", 0
msg_err_ram_info:   .byte "NO RAM INFO", 0
msg_err_ram_count:  .byte "NEED 2 RAM SLOTS", 0
msg_err_flash_info: .byte "NO SLOT COUNT", 0
msg_err_no_images:  .byte "NO IMAGES", 0
msg_err_nv:         .byte "NV WRITE FAILED", 0
msg_err_load:       .byte "LOAD FAILED", 0
