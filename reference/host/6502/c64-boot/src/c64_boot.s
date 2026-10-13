; c64_boot.s — Reset entry, relocation, RBCP session, menu UX
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

.include "boot_defs.s"

; ---------------------------------------------------------------------------
; This bootloader's own version, shown in the header.  It is not the
; protocol's version and it is not the device's.  RELEASE.md says when it
; changes and how it is published.
; ---------------------------------------------------------------------------

.define APP_VERSION "0.1.5"

; ---------------------------------------------------------------------------
; Imports
; ---------------------------------------------------------------------------

.import c64_hw_init
.import c64_clear_screen
.import c64_print_at
.import c64_highlight_row
.import c64_unhighlight_row
.import c64_scan_key
.import c64_wait_den_line

.import rbcp_reset
.import rbcp_cmd_enter_cmd_resp
.import rbcp_cmd_get_ram_slot_info_all
.import rbcp_cmd_get_flash_slot_info_all
.import rbcp_cmd_get_flash_slot_info
.import rbcp_cmd_load_slot
.import rbcp_cmd_switch_and_exit
.import rbcp_cmd_get_device_type, rbcp_cmd_get_device_version
.import rbcp_check_protocol_version
.import rbcp_cmd_get_nv_capability
.import rbcp_cmd_nv_peek
.import rbcp_cmd_nv_poke_commit_byte
.import rbcp_cmd_get_pipe_capability
.import rbcp_cmd_pipe_write

.import diag_init
.import diag_begin
.import diag_end
.import diag_late
.import diag_screen
.import diag_send
.import diag_result
.import diag_ms

.export buf_putc
.export buf_puts
.export byte_to_hex
.export buf_dec16
.export pipe_log
.export str_app

.import row_off_lo
.import row_scr_hi

; Linker-generated symbols for the CODE segment (load/run split)
.import __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__

; ZP addresses are constants defined in c64_defs.s (via .include above).
; Do not import them — ca65 must see them as compile-time constants so it
; generates ZP indirect addressing mode for (ZP_PTR_LO),Y etc.

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------

RESET_VECTOR    = $FFFC
MENU_HEADER_ROW = 1
MENU_COPYRIGHT_ROW = 3
MENU_PROMPT_ROW = 5
MENU_ABOVE_ROW  = 6
MENU_ENTRY_ROW0 = 7
MENU_BELOW_ROW  = 21
MENU_FOOTER_ROW = 22
MENU_DEVICE_ROW = 24
MENU_NAME_COL   = 3
MENU_MORE_COL   = (SCREEN_COLS - 2) / 2
MAX_DISPLAY     = MENU_BELOW_ROW - MENU_ENTRY_ROW0
MAX_ENTRIES     = 254       ; every flash slot but 0
NAME_MAX        = 30        ; characters in a slot name

MORE_ABOVE      = SCREEN_BASE + MENU_ABOVE_ROW * SCREEN_COLS + MENU_MORE_COL
MORE_BELOW      = SCREEN_BASE + MENU_BELOW_ROW * SCREEN_COLS + MENU_MORE_COL

; ---------------------------------------------------------------------------
; BSS — RAM-resident variables
; ---------------------------------------------------------------------------

.bss

; One GET_FLASH_SLOT_INFO record per kernal.  Entry N is flash slot N+1.
slot_name_buf:  .res MAX_ENTRIES * 32
name_buf:       .res NAME_MAX + 1
status_line_buf: .res 48
device_type_buf:    .res 24
device_version_buf: .res 24
device_line_buf:    .res 50

var_total_ram:  .res 1
var_active_ram: .res 1
var_target_ram: .res 1
var_total_flash:.res 1
var_num_entries:.res 1      ; every flash slot but 0
var_num_rows:   .res 1      ; entries on screen at once
var_top:        .res 1      ; entry on the first row
var_selection:  .res 1      ; entry, not row
var_cbm_held:   .res 1      ; $00 = C= held; non-zero = not held
var_nv_present: .res 1      ; 0 = absent or not writable, 1 = writable
var_pipe_present: .res 1    ; 0 = device has no pipe, 1 = pipe 0 is available
var_boot_flash: .res 1      ; resolved flash slot to boot
var_nv_done:    .res 1      ; 1 once this boot has committed to NV storage
var_nv_ms:      .res 2      ; how long the commit took

dec_val:        .res 2      ; buf_dec16's state
dec_tmp:        .res 1
dec_lead:       .res 1

; ===========================================================================
; BOOT segment — runs from ROM, executes before relocation
; ===========================================================================

.segment "BOOT"

; ---------------------------------------------------------------------------
; boot_entry — RESET vector target
; Runs from ROM. Must not call into the CODE segment (not in RAM yet).
; Calls c64_hw_init (also in BOOT) and copies CODE to RAM, then jumps to
; boot_ram_entry.
; ---------------------------------------------------------------------------

.export boot_entry
boot_entry:
    sei
    cld
    ldx #$FF
    txs                     ; set up stack

    jsr c64_hw_init         ; hardware init (in BOOT segment, safe from ROM)

    ; Detect C= (Commodore) key: column 7 low, test row 5.
    ; Active-low matrix: bit clear = key pressed.
    ; Read after a debounce delay to avoid noisy power-on false positives.
    lda #KEY_CBM_COL
    sta CIA1_PRA
    ldx #DEBOUNCE_COUNT
@cbm_dly:
    dex
    bne @cbm_dly
    lda CIA1_PRB
    and #KEY_CBM_ROW_BIT
    sta var_cbm_held        ; $00 = held, non-zero = not held

    ; ------------------------------------------------------------------
    ; Relocate CODE segment from ROM to RAM.
    ;
    ; __CODE_LOAD__ = load address of CODE in ROM image
    ; __CODE_RUN__  = run address of CODE in RAM
    ; __CODE_SIZE__ = byte count of CODE segment
    ;
    ; ZP use: ZP_PTR_LO/hi = ROM source, ZP_TMP0/1 = RAM destination.
    ; ZP_TMP3/4
    ;
    ; Y is used as a byte index within each 256-byte page. When Y wraps
    ; from $FF to $00 we advance both pointers by 256 (one full page).
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
    ; Decrement 16-bit counter
    lda ZP_TMP3
    bne @copy_dec_lo
    dec ZP_TMP4
@copy_dec_lo:
    dec ZP_TMP3
    lda ZP_TMP3
    ora ZP_TMP4
    bne @copy_loop

    jmp boot_ram_entry      ; run (RAM) address of boot_ram_entry

; ===========================================================================
; CODE segment — runs from RAM after relocation
; ===========================================================================

.code

; ---------------------------------------------------------------------------
; boot_ram_entry — all subsequent execution runs from RAM
; ---------------------------------------------------------------------------

boot_ram_entry:
    ldy #COL_BLACK
    jsr c64_clear_screen
    jsr diag_init
    jsr boot_dark
    lda #0
    sta var_nv_done

    ; ------------------------------------------------------------------
    ; RBCP common setup
    ; ------------------------------------------------------------------

.if 0
    ; Wait for 256 x 256 cycles
    ldx #$00
    ldy #$00
@delay_loop:
    dex
    bne @delay_loop
    dey
    bne @delay_loop
.endif

    ; Spec defined reset sequence.
    jsr rbcp_reset

    ; Enter command-response mode using the settings in rbcp_config.s
    recorded rbcp_cmd_enter_cmd_resp
    bcc @ok_enter
    jmp err_no_cmd_resp

    ; Check device's RBCP protocol version 
@ok_enter:
    recorded rbcp_check_protocol_version
    bcc @ok_version
    jmp err_protocol_version

@ok_version:
    recorded rbcp_cmd_get_ram_slot_info_all
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

    lda #0
    cmp var_active_ram
    bne @target_set
    lda #1
@target_set:
    sta var_target_ram

    ; Flash slot info — needed by both paths and for NV validation
    lda #0
    sta var_total_flash
    recorded rbcp_cmd_get_flash_slot_info_all
    bcs @flash_info_done        ; on failure totals stay zero; menu path catches this, auto-boot falls back to slot 1
    lda RBCP_DATA_ADDR + 0
    sta var_total_flash
@flash_info_done:

    ; NV query — resolve boot slot; failures fall through to default
    lda #0
    sta var_nv_present
    lda #1
    sta var_boot_flash              ; default: flash slot 1

    recorded rbcp_cmd_get_nv_capability
    bcs @nv_skip                    ; command failed
    lda RBCP_DATA_ADDR + RBCP_NV_CAP_SIZE_LO
    ora RBCP_DATA_ADDR + RBCP_NV_CAP_SIZE_HI
    beq @nv_skip                    ; size == 0, no NV storage
    lda RBCP_DATA_ADDR + RBCP_NV_CAP_WRITABLE
    beq @nv_skip                    ; present but read-only
    lda #1
    sta var_nv_present

    lda #1
    sta rbcp_arg0                   ; count = 1
    lda #0
    sta rbcp_arg1                   ; location LSB = 0
    sta rbcp_arg2                   ; location MSB = 0
    recorded rbcp_cmd_nv_peek
    bcs @nv_skip                    ; peek failed

    lda RBCP_DATA_ADDR              ; the stored slot byte
    beq @nv_skip                    ; 0 = bootloader slot, invalid
    cmp var_total_flash             ; >= total slots, out of range
    bcs @nv_skip
    sta var_boot_flash              ; valid, use it
@nv_skip:

    ; Pipe query — is there anywhere to send a log line?
    ;
    ; GET_PIPE_CAPABILITY takes no argument bytes, so this doubles as the
    ; version check: a device whose protocol version predates the Pipes group
    ; consumes nothing, fails the command and stays in step.  Carry set and a
    ; count of zero lead to the same place, so neither is told from the other.
    lda #0
    sta var_pipe_present
    recorded rbcp_cmd_get_pipe_capability
    bcs @pipe_skip
    lda RBCP_DATA_ADDR + RBCP_PIPE_CAP_COUNT
    beq @pipe_skip                  ; count == 0, no pipes
    lda #1
    sta var_pipe_present
@pipe_skip:

    ; ------------------------------------------------------------------
    ; Branch on C= state
    ; ------------------------------------------------------------------

    lda var_cbm_held
    beq path_menu           ; $00 = C= was held

    ; ==================================================================
    ; AUTO-BOOT PATH — load flash slot 1, switch, and go
    ; ==================================================================

    ldx var_boot_flash
    lda var_target_ram
    recorded rbcp_cmd_load_slot
    bcc @ok_load_auto
    jmp err_load
@ok_load_auto:

    lda var_boot_flash
    jsr log_switch

    lda var_target_ram
    jsr rbcp_cmd_switch_and_exit

.if PAUSE_BEFORE_RESET
    jsr pause_before_reset
.endif

    jmp (RESET_VECTOR)

    ; ==================================================================
    ; MENU PATH
    ; ==================================================================

path_menu:
    ldy #COL_WHITE
    ;sty VIC_BORDER
    jsr c64_clear_screen

    recorded rbcp_cmd_get_device_type
    bcc @ok_devtype
    jmp err_device_type
@ok_devtype:
    lda #<RBCP_DATA_ADDR
    sta ZP_PTR_LO
    lda #>RBCP_DATA_ADDR
    sta ZP_PTR_HI
    lda #<device_type_buf
    sta ZP_TMP0
    lda #>device_type_buf
    sta ZP_TMP1
    jsr buf_puts
    lda #0
    jsr buf_putc

    ;ldy #COL_BLUE
    ;sty VIC_BORDER

    recorded rbcp_cmd_get_device_version
    bcc @ok_devver
    jmp err_device_version
@ok_devver:
    lda #<RBCP_DATA_ADDR
    sta ZP_PTR_LO
    lda #>RBCP_DATA_ADDR
    sta ZP_PTR_HI
    lda #<device_version_buf
    sta ZP_TMP0
    lda #>device_version_buf
    sta ZP_TMP1
    jsr buf_puts
    lda #0
    jsr buf_putc

    ;ldy #COL_ORANGE
    ;sty VIC_BORDER

    ; Build the device line
    lda #<device_type_buf
    sta ZP_PTR_LO
    lda #>device_type_buf
    sta ZP_PTR_HI
    lda #<device_line_buf
    sta ZP_TMP0
    lda #>device_line_buf
    sta ZP_TMP1
    jsr buf_puts
    lda #' '
    jsr buf_putc
    lda #<device_version_buf
    sta ZP_PTR_LO
    lda #>device_version_buf
    sta ZP_PTR_HI
    jsr buf_puts
    lda #0
    jsr buf_putc

    ;ldy #COL_BROWN
    ;sty VIC_BORDER

    lda var_total_flash
    bne @flash_ok
    jmp err_flash_info      ; query failed earlier, report the real error
@flash_ok:
    cmp #2
    bcs @ok_flashcount
    jmp err_no_kernals
@ok_flashcount:

    sec
    sbc #1                  ; subtract slot 0, the bootloader
    sta var_num_entries
    cmp #MAX_DISPLAY + 1
    bcc @rows_ok
    lda #MAX_DISPLAY
@rows_ok:
    sta var_num_rows

    ; Every name is read now, with the display off, so scrolling sends no
    ; commands.  Only a failed read is recorded, because an entry for every
    ; slot would fill the record.
    lda #0
    sta ZP_TMP2             ; entry
@name_loop:
    lda ZP_TMP2
    cmp var_num_entries
    beq @names_done
    jsr diag_begin
    clc
    adc #1                  ; flash slot
    jsr rbcp_cmd_get_flash_slot_info
    bcc @name_ok
    jsr diag_end
    jmp err_flash_info
@name_ok:
    lda ZP_TMP2
    jsr entry_ptr
    ldy #31
@name_copy:
    lda RBCP_DATA_ADDR, y
    sta (ZP_PTR_LO), y
    dey
    bpl @name_copy
    inc ZP_TMP2
    bne @name_loop          ; always
@names_done:

    ldy #COL_BLACK
    sty VIC_BORDER

    jsr draw_menu

    ; Start on the auto-booting slot, on the last row if it is below the
    ; first screenful.  var_boot_flash is always a valid kernal slot.
    ldx var_boot_flash
    dex
    stx var_selection
    lda #0
    sta var_top
    txa
    sec
    sbc #MAX_DISPLAY - 1
    bcc @top_ok
    sta var_top
@top_ok:
    jsr draw_list
    jsr highlight_selection
    jsr boot_light

    ; ------------------------------------------------------------------
    ; Keyboard polling loop
    ; ------------------------------------------------------------------

key_loop:
    jsr c64_scan_key
    cmp #KEY_NONE
    beq key_loop
    cmp #KEY_RETURN
    beq do_boot
    cmp #KEY_UP
    beq do_up
    cmp #KEY_DOWN
    beq do_down
    jmp key_loop

do_up:
    lda var_selection
    beq key_loop
    jsr unhighlight_selection
    dec var_selection
    lda var_selection
    cmp var_top
    bcs @shown
    sta var_top
    jsr draw_list
@shown:
    jsr highlight_selection
    jmp key_delay

do_down:
    ldx var_selection
    inx
    cpx var_num_entries
    bcs key_loop
    jsr unhighlight_selection
    inc var_selection
    lda var_selection
    sec
    sbc var_top
    cmp #MAX_DISPLAY
    bcc @shown
    inc var_top
    jsr draw_list
@shown:
    jsr highlight_selection
    ; fall through

key_delay:
    ldx #0
    ldy #0
@delay_loop:
    dex
    bne @delay_loop
    dey
    bne @delay_loop
    jmp key_loop

do_boot:
    jsr boot_dark
    inc var_selection       ; convert to 1-based flash slot index
    lda var_nv_present
    beq @nv_skip_write
    lda var_selection
    cmp var_boot_flash      ; already stored?
    beq @nv_skip_write      ; yes — skip the write
    sta rbcp_arg0           ; byte to store
    lda #0
    sta rbcp_arg1           ; location LSB
    sta rbcp_arg2           ; location MSB
    lda var_target_ram
    sta rbcp_arg3           ; RAM slot for staging
    recorded rbcp_cmd_nv_poke_commit_byte
    bcc @nv_committed
    jmp err_nv_commit
@nv_committed:
    lda diag_ms
    sta var_nv_ms
    lda diag_ms + 1
    sta var_nv_ms + 1
    lda #1
    sta var_nv_done

@nv_skip_write:
    ldx var_selection       ; X = flash slot
    lda var_target_ram      ; A = RAM slot
    recorded rbcp_cmd_load_slot
    bcc @ok_load_menu
    jmp err_load
@ok_load_menu:
    lda var_selection           ; 1-based flash slot, as passed to LOAD_SLOT
    jsr log_switch

    lda var_target_ram
    jsr rbcp_cmd_switch_and_exit

    ; No need to pause as we'll clear the screen before a reset.
    ldy #COL_BLACK
    jsr c64_clear_screen
    sty VIC_BORDER

.if PAUSE_BEFORE_RESET
    jsr pause_before_reset
.endif

    jmp (RESET_VECTOR)

; ===========================================================================
; Error handlers
; ===========================================================================

err_no_cmd_resp:
    lda #COL_RED
    sta VIC_BORDER
    lda #<msg_err_no_cmd_resp
    sta ZP_PTR_LO
    lda #>msg_err_no_cmd_resp
    sta ZP_PTR_HI
    jmp halt_with_msg

err_protocol_version:
    lda #COL_RED
    sta VIC_BORDER
    lda #<msg_err_protocol_version
    sta ZP_PTR_LO
    lda #>msg_err_protocol_version
    sta ZP_PTR_HI
    jmp halt_with_msg

err_ram_info:
    lda #COL_RED
    sta VIC_BORDER
    lda #<msg_err_ram_info
    sta ZP_PTR_LO
    lda #>msg_err_ram_info
    sta ZP_PTR_HI
    jmp halt_with_msg

err_insuff_ram:
    lda #COL_RED
    sta VIC_BORDER
    lda #<msg_err_insuff_ram
    sta ZP_PTR_LO
    lda #>msg_err_insuff_ram
    sta ZP_PTR_HI
    jmp halt_with_msg

err_flash_info:
    lda #COL_RED
    sta VIC_BORDER
    lda #<msg_err_flash_info
    sta ZP_PTR_LO
    lda #>msg_err_flash_info
    sta ZP_PTR_HI
    jmp halt_with_msg

err_no_kernals:
    lda #COL_RED
    sta VIC_BORDER
    lda #<msg_err_no_kernals
    sta ZP_PTR_LO
    lda #>msg_err_no_kernals
    sta ZP_PTR_HI
    jmp halt_with_msg

err_device_type:
    lda #COL_RED
    sta VIC_BORDER
    lda #<msg_err_device_type
    sta ZP_PTR_LO
    lda #>msg_err_device_type
    sta ZP_PTR_HI
    jmp halt_with_msg

err_device_version:
    lda #COL_RED
    sta VIC_BORDER
    lda #<msg_err_device_version
    sta ZP_PTR_LO
    lda #>msg_err_device_version
    sta ZP_PTR_HI
    jmp halt_with_msg

err_nv_commit:
    lda #COL_RED
    sta VIC_BORDER
    lda #<msg_err_nv_commit
    sta ZP_PTR_LO
    lda #>msg_err_nv_commit
    sta ZP_PTR_HI
    jmp halt_with_msg

err_load:
    lda #COL_RED
    sta VIC_BORDER
    lda #<msg_err_load
    sta ZP_PTR_LO
    lda #>msg_err_load
    sta ZP_PTR_HI
    ; fall through

; ---------------------------------------------------------------------------
; halt_with_msg — reports the failure and stops.  ZP_PTR is the message.
;
; The display is off on every path here.  It comes on for the prompt and goes
; off again for the reset and the pipe report, which are exchanges with the
; device.
;
; Nothing reads the ROM between the prompt and RETURN, so One ROM's ring of
; the last 64 ROM reads still holds the failure when the user captures it.
; ---------------------------------------------------------------------------
halt_with_msg:
    jsr diag_late
    lda #COL_RED
    sta VIC_BORDER
    jsr diag_screen
    jsr boot_light
    jsr wait_return
    jsr boot_dark
    jsr diag_send
    jsr diag_result
    jsr boot_light

@halt:
    jmp @halt

; ---------------------------------------------------------------------------
; boot_dark — turns the display off and returns once the VIC-II has stopped
; fetching characters.
;
; While the VIC-II fetches characters it holds the bus.  Around each handover
; the device can decode an access that wasn't one, decode one twice or miss
; one.
;
; Clobbers A.
; ---------------------------------------------------------------------------
boot_dark:
    lda VIC_CTRL1
    and #<(~VIC_CTRL1_DEN)
    sta VIC_CTRL1
    jmp c64_wait_den_line

; wait_return — returns once RETURN is pressed.  A key held on entry, for
; example the RETURN that chose the kernal, has to be released first.
; Clobbers A, X.
wait_return:
@release:
    jsr c64_scan_key
    cmp #KEY_NONE
    bne @release
@press:
    jsr c64_scan_key
    cmp #KEY_RETURN
    bne @press
    rts

; boot_light — turns the display back on.  Clobbers A.
boot_light:
    lda VIC_CTRL1
    ora #VIC_CTRL1_DEN
    sta VIC_CTRL1
    rts

.macro set_ptr addr
    lda #<addr
    sta ZP_PTR_LO
    lda #>addr
    sta ZP_PTR_HI
.endmacro

; ---------------------------------------------------------------------------
; log_switch — sends "SWITCHING TO SLOT $XX" out through the device, followed
; by " NV COMMIT nMS" when this boot stored the slot.
;
; The last thing the bootloader does before SWITCH_AND_EXIT, which is the last
; moment it can send anything: the switch ends the command-response session,
; and the newly served image need not have a back-channel at all.
;
; A = flash slot, the image the user is booting.  Each path holds that in a
; variable of its own, so the caller loads it rather than this routine picking
; between them.  It is the flash slot rather than the RAM slot because the
; flash slot is the thing a reader chose - the RAM slot is only where it was
; put.
;
; Clobbers A, X, Y, ZP_PTR_LO/HI, ZP_TMP0/1, ZP_TMP2 and the RBCP arguments.
; ---------------------------------------------------------------------------
log_switch:
    sta ZP_TMP2                 ; flash slot, wanted once the string is set up
    lda var_pipe_present
    beq @done

    lda #<status_line_buf       ; the menu is finished with this by now
    sta ZP_TMP0
    lda #>status_line_buf
    sta ZP_TMP1

    set_ptr msg_switching
    jsr buf_puts
    lda ZP_TMP2                 ; done with it before pipe_log wants it back
    jsr byte_to_hex
    lda var_nv_done
    beq @end
    set_ptr msg_nv_commit
    jsr buf_puts
    lda var_nv_ms
    ldx var_nv_ms + 1
    jsr buf_dec16
    set_ptr msg_ms
    jsr buf_puts
@end:
    lda #13                     ; the device's log is CRLF terminated
    jsr buf_putc
    lda #10
    jsr buf_putc
    lda #0
    jsr buf_putc                ; terminator, not sent

    set_ptr status_line_buf
    jmp pipe_log
@done:
    rts

; ---------------------------------------------------------------------------
; pipe_log — sends the null-terminated string at (ZP_PTR_LO/HI) to pipe 0.
;
; PIPE_WRITE carries at most four bytes, so the string goes out in chunks.  A
; chunk the device will not take ends the whole thing: waiting for room would
; mean a C64 that hangs because nothing on the other end is reading, and a log
; line is never worth not booting for.  The library reports the refusal and
; leaves that choice here, which is what this is.
;
; Carry clear if the whole string was sent, carry set if a chunk failed.
; Clobbers A, X, Y, ZP_PTR_LO/HI, ZP_TMP2 and the RBCP arguments.
; ---------------------------------------------------------------------------
pipe_log:
@chunk:
    ldy #0                      ; rbcp_cmd_pipe_write clobbers Y
    ldx #0                      ; bytes gathered so far
@gather:
    lda (ZP_PTR_LO), y
    beq @flush                  ; terminator, send what we have
    sta rbcp_arg0, x
    inc ZP_PTR_LO
    bne @next
    inc ZP_PTR_HI
@next:
    inx
    cpx #RBCP_PIPE_WRITE_MAX
    bne @gather
@flush:
    txa                         ; A = count, and sets Z when none
    beq @sent                   ; nothing gathered, the string is finished
    stx ZP_TMP2                 ; count, to tell a full chunk from a short one
    ldx #0                      ; pipe 0
    jsr rbcp_cmd_pipe_write
    bcs @done                   ; refused, or the device is gone — give up
    lda ZP_TMP2
    cmp #RBCP_PIPE_WRITE_MAX
    beq @chunk                  ; a full chunk, so there may be more
@sent:
    clc
@done:
    rts

; ---------------------------------------------------------------------------
; buf_putc — writes A to (ZP_TMP0/1), advances ZP_TMP0/1. Clobbers Y.
; ---------------------------------------------------------------------------
buf_putc:
    ldy #0
    sta (ZP_TMP0), y
    inc ZP_TMP0
    bne @ret
    inc ZP_TMP1
@ret:
    rts

; ---------------------------------------------------------------------------
; buf_puts — copies null-terminated string from (ZP_PTR_LO/HI) to (ZP_TMP0/1).
; Advances both pointers. Clobbers A, Y.
; ---------------------------------------------------------------------------
buf_puts:
@loop:
    ldy #0
    lda (ZP_PTR_LO), y
    beq @done
    jsr buf_putc
    inc ZP_PTR_LO
    bne @loop
    inc ZP_PTR_HI
    bne @loop           ; always
@done:
    rts

; ---------------------------------------------------------------------------
; byte_to_hex — writes A as two uppercase hex chars via buf_putc.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------
byte_to_hex:
    tax
    lsr a
    lsr a
    lsr a
    lsr a
    jsr @nibble
    txa
    and #$0F
@nibble:
    cmp #10
    bcc @digit
    adc #6
@digit:
    adc #'0'
    jmp buf_putc        ; tail call

; ---------------------------------------------------------------------------
; buf_dec16 — writes A (low) and X (high) in decimal via buf_putc, without
; leading zeros.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------
buf_dec16:
    sta dec_val
    stx dec_val + 1
    lda #0
    sta dec_lead
    ldx #0
@power:
    ldy #'0'
@subtract:
    lda dec_val
    sec
    sbc dec_power_lo, x
    sta dec_tmp
    lda dec_val + 1
    sbc dec_power_hi, x
    bcc @digit
    sta dec_val + 1
    lda dec_tmp
    sta dec_val
    iny
    bne @subtract               ; always
@digit:
    tya
    cmp #'0'
    bne @emit
    ldy dec_lead
    beq @next
@emit:
    sta dec_lead
    jsr buf_putc                ; keeps X
@next:
    inx
    cpx #4
    bne @power
    lda dec_val
    ora #'0'
    jmp buf_putc

dec_power_lo: .byte <10000, <1000, <100, <10
dec_power_hi: .byte >10000, >1000, >100, >10

; ===========================================================================
; draw_menu
; Draws header, copyright, prompt, footer and device line.
; ===========================================================================

draw_menu:
    lda #<str_header
    sta ZP_PTR_LO
    lda #>str_header
    sta ZP_PTR_HI
    lda #MENU_HEADER_ROW
    sta ZP_TMP0
    lda #1
    sta ZP_TMP1
    jsr c64_print_at

    lda #<str_copright
    sta ZP_PTR_LO
    lda #>str_copright
    sta ZP_PTR_HI
    lda #MENU_COPYRIGHT_ROW
    sta ZP_TMP0
    lda #1
    sta ZP_TMP1
    jsr c64_print_at

    lda #<str_prompt
    sta ZP_PTR_LO
    lda #>str_prompt
    sta ZP_PTR_HI
    lda #MENU_PROMPT_ROW
    sta ZP_TMP0
    lda #1
    sta ZP_TMP1
    jsr c64_print_at

    lda #<str_footer
    sta ZP_PTR_LO
    lda #>str_footer
    sta ZP_PTR_HI
    lda #MENU_FOOTER_ROW
    sta ZP_TMP0
    lda #1
    sta ZP_TMP1
    jsr c64_print_at

    ; Output the device info line right aligned
    lda #<device_line_buf
    sta ZP_PTR_LO
    lda #>device_line_buf
    sta ZP_PTR_HI
    ldy #0
@dlen:
    lda (ZP_PTR_LO), y
    beq @dlen_done
    iny
    bne @dlen
@dlen_done:
    tya
    eor #$FF
    clc
    adc #41             ; ~len + 41 = 40 - len
    sta ZP_TMP1
    lda #24
    sta ZP_TMP0
    jmp c64_print_at        ; tail call

; ===========================================================================
; draw_list
; Draws the entries from var_top, one per row, with a triangle above or below
; the list where entries are off screen.
; Relies on c64_print_at to not clobber ZP_TMP2+.
; Clobbers: A, X, Y, ZP_PTR_LO/HI, ZP_TMP0-2
; ===========================================================================

draw_list:
    lda #0
    sta ZP_TMP2             ; row
@row_loop:
    lda ZP_TMP2
    cmp var_num_rows
    beq @marks

    clc
    adc var_top
    jsr entry_ptr

    ; Spaces pad the name over the name drawn before.
    ldx #0
    ldy #1                  ; past the ROM type
@copy:
    lda (ZP_PTR_LO), y
    beq @pad
    sta name_buf, x
    iny
    inx
    cpx #NAME_MAX
    bne @copy
@pad:
    lda #' '
@pad_loop:
    cpx #NAME_MAX
    beq @print
    sta name_buf, x
    inx
    bne @pad_loop           ; always
@print:
    lda #0
    sta name_buf, x

    lda #<name_buf
    sta ZP_PTR_LO
    lda #>name_buf
    sta ZP_PTR_HI
    lda ZP_TMP2
    clc
    adc #MENU_ENTRY_ROW0
    sta ZP_TMP0
    lda #MENU_NAME_COL
    sta ZP_TMP1
    jsr c64_print_at

    inc ZP_TMP2
    bne @row_loop           ; always

@marks:
    ldx #CHAR_SPACE
    ldy #CHAR_SPACE
    lda var_top
    beq @put_above
    ldx #CHAR_TRI_UP_L
    ldy #CHAR_TRI_UP_R
@put_above:
    stx MORE_ABOVE
    sty MORE_ABOVE + 1

    ldx #CHAR_SPACE
    ldy #CHAR_SPACE
    lda var_top
    clc
    adc var_num_rows
    cmp var_num_entries
    bcs @put_below
    ldx #CHAR_TRI_DOWN_L
    ldy #CHAR_TRI_DOWN_R
@put_below:
    stx MORE_BELOW
    sty MORE_BELOW + 1
    rts

; entry_ptr: ZP_PTR = the record of entry A in slot_name_buf.  Clobbers A.
entry_ptr:
    pha
    lsr a
    lsr a
    lsr a
    sta ZP_PTR_HI           ; high byte of A * 32
    pla
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc #<slot_name_buf
    sta ZP_PTR_LO
    lda ZP_PTR_HI
    adc #>slot_name_buf
    sta ZP_PTR_HI
    rts

; ===========================================================================
; highlight_selection / unhighlight_selection
; ===========================================================================

highlight_selection:
    jsr selection_row
    jsr c64_highlight_row
    jsr set_arrow
    rts

unhighlight_selection:
    jsr selection_row
    jsr c64_unhighlight_row
    jsr clear_arrow
    rts

; selection_row: A = the screen row of the selected entry
selection_row:
    lda var_selection
    sec
    sbc var_top
    clc
    adc #MENU_ENTRY_ROW0
    rts

; set_arrow: write '>' at col 1 of the current selection row
set_arrow:
    jsr selection_row
    tax
    lda row_off_lo, x
    clc
    adc #1                  ; col 1
    sta ZP_PTR_LO
    lda row_scr_hi, x
    adc #0
    sta ZP_PTR_HI
    lda #CHAR_GT
    ldy #0
    sta (ZP_PTR_LO), y
    rts

; clear_arrow: write space at col 1 of the current selection row
clear_arrow:
    jsr selection_row
    tax
    lda row_off_lo, x
    clc
    adc #1
    sta ZP_PTR_LO
    lda row_scr_hi, x
    adc #0
    sta ZP_PTR_HI
    lda #CHAR_SPACE
    ldy #0
    sta (ZP_PTR_LO), y
    rts

.if PAUSE_BEFORE_RESET
pause_before_reset:
    ; Count to 65536 before resetting
    lda #0
    sta ZP_TMP0
    sta ZP_TMP1
@wait_for_reset:
    inc ZP_TMP0
    bne @wait_for_reset
    inc ZP_TMP1
    bne @wait_for_reset
    rts
.endif

; ===========================================================================
; String data (RODATA — accessed via RAM so in code)
; ===========================================================================

str_header:         .byte "   C64 RBCP KERNAL BOOTLOADER ", APP_VERSION, 0
str_copright:       .byte "         (C) 2026 PIERS.ROCKS", 0
str_prompt:         .byte "SELECT KERNAL:", 0
str_footer:         .byte "   UP/DOWN TO MOVE, RETURN TO BOOT", 0

msg_err_no_cmd_resp:    .byte "RBCP ERROR: FAILED TO ENTER CMD RESP", 0
msg_err_protocol_version: .byte "RBCP ERROR: INCOMPATIBLE VERSION", 0
msg_err_ram_info:       .byte "RBCP ERROR: RAM SLOT INFO FAILED", 0
msg_err_insuff_ram:     .byte "RBCP ERROR: INSUFFICIENT RAM SLOTS", 0
msg_err_flash_info:     .byte "RBCP ERROR: FLASH SLOT INFO FAILED", 0
msg_err_device_type:    .byte "RBCP ERROR: GET DEVICE TYPE FAILED", 0
msg_err_device_version: .byte "RBCP ERROR: GET DEVICE VERSION FAILED", 0
msg_err_nv_commit:      .byte "RBCP ERROR: NV COMMIT FAILED", 0
msg_err_no_kernals:     .byte "NO KERNALS FOUND TO BOOT", 0
msg_err_load:           .byte "RBCP ERROR: LOAD FAILED", 0
msg_halt:               .byte "HALTING", 0
msg_switching:          .byte "SWITCHING TO SLOT $", 0
msg_nv_commit:          .byte " NV COMMIT ", 0
msg_ms:                 .byte "MS", 0
str_app:                .byte "C64 BOOTLOADER ", APP_VERSION, 0
