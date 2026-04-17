; c64_boot.s — Reset entry, relocation, RBCP session, menu UX
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

    .include "../rbcp/rbcp_defs.s"
    .include "c64_defs.s"

; ---------------------------------------------------------------------------
; Imports
; ---------------------------------------------------------------------------

.import c64_hw_init
.import c64_clear_screen
.import c64_print_at
.import c64_highlight_row
.import c64_unhighlight_row
.import c64_scan_key

.import rbcp_knock
.import rbcp_cmd_enter_cmd_resp
.import rbcp_cmd_get_ram_slot_info
.import rbcp_cmd_get_flash_slot_info
.import rbcp_cmd_load_slot
.import rbcp_cmd_switch_and_exit

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
MENU_PROMPT_ROW = 3
MENU_ENTRY_ROW0 = 5
MENU_FOOTER_ROW = 23
MAX_DISPLAY     = 15

; ---------------------------------------------------------------------------
; BSS — RAM-resident variables
; ---------------------------------------------------------------------------

.bss

; Slot name buffer: 15 entries * 32 bytes = 480 bytes.
; Entry 0 = flash slot 1, entry N = flash slot N+1.
slot_name_buf:  .res MAX_DISPLAY * 32

var_total_ram:  .res 1
var_active_ram: .res 1
var_target_ram: .res 1
var_total_flash:.res 1
var_whole_flash:.res 1
var_num_display:.res 1
var_selection:  .res 1
var_cbm_held:   .res 1      ; $00 = C= held; non-zero = not held

; ===========================================================================
; BOOT segment — runs from ROM, executes before relocation
; ===========================================================================

.segment "BOOT"

; ---------------------------------------------------------------------------
; boot_entry — RESET vector target
; Runs from ROM. Must not call into the CODE segment (not in RAM yet).
; Calls c64_hw_init (also in BOOT) and copies CODE to RAM, then jumps to
; boot_ram_entry (CODE segment run address = $C000+).
; ---------------------------------------------------------------------------

.export boot_entry
boot_entry:
    sei
    cld

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
    ; __CODE_RUN__  = run address of CODE in RAM ($C000)
    ; __CODE_SIZE__ = byte count of CODE segment
    ;
    ; ZP use: ZP_PTR_LO/hi = ROM source, ZP_TMP0/1 = RAM destination.
    ; rbcp_zp_3/4 = 16-bit byte counter (RBCP lib not yet called).
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
    sta rbcp_zp_3
    lda #>__CODE_SIZE__
    sta rbcp_zp_4

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
    lda rbcp_zp_3
    bne @copy_dec_lo
    dec rbcp_zp_4
@copy_dec_lo:
    dec rbcp_zp_3
    lda rbcp_zp_3
    ora rbcp_zp_4
    bne @copy_loop

    jmp boot_ram_entry      ; run (RAM) address of boot_ram_entry

; ===========================================================================
; CODE segment — runs from RAM ($C000+) after relocation
; ===========================================================================

.code

; ---------------------------------------------------------------------------
; boot_ram_entry — all subsequent execution runs from RAM
; ---------------------------------------------------------------------------

boot_ram_entry:
    jsr c64_clear_screen

    ; ------------------------------------------------------------------
    ; RBCP common setup
    ; ------------------------------------------------------------------

    jsr rbcp_knock

    jsr rbcp_cmd_enter_cmd_resp
    bcc @ok_enter
    jmp err_generic
@ok_enter:

    jsr rbcp_cmd_get_ram_slot_info
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
    ; Branch on C= state
    ; ------------------------------------------------------------------

    lda var_cbm_held
    beq path_menu           ; $00 = C= was held

    ; ==================================================================
    ; AUTO-BOOT PATH — load flash slot 1, switch, and go
    ; ==================================================================

    lda var_target_ram
    ldx #1
    jsr rbcp_cmd_load_slot
    bcc @ok_load_auto
    jmp err_load
@ok_load_auto:

    lda var_target_ram
    jsr rbcp_cmd_switch_and_exit
    jmp (RESET_VECTOR)

    ; ==================================================================
    ; MENU PATH
    ; ==================================================================

path_menu:
    jsr rbcp_cmd_get_flash_slot_info
    bcc @ok_flash
    jmp err_flash_info
@ok_flash:

    lda RBCP_DATA_ADDR + 0
    sta var_total_flash
    lda RBCP_DATA_ADDR + 1
    sta var_whole_flash

    lda var_total_flash
    cmp #2
    bcs @ok_flashcount
    jmp err_no_kernals
@ok_flashcount:

    lda var_whole_flash
    bne @ok_whole
    jmp err_no_kernals
@ok_whole:
    sec
    sbc #1                  ; subtract slot 0 (bootloader record)
    bne @ok_after_sub
    jmp err_no_kernals
@ok_after_sub:
    cmp #MAX_DISPLAY + 1
    bcc @disp_ok
    lda #MAX_DISPLAY
@disp_ok:
    sta var_num_display

    ; ------------------------------------------------------------------
    ; Copy slot name records from data section to RAM buffer.
    ;
    ; Data section layout (at RBCP_DATA_ADDR = $E008):
    ;   +0  total_count   (1 byte)
    ;   +1  whole_count   (1 byte)
    ;   +2  partial_flag  (1 byte)
    ;   +3  reserved      (1 byte)
    ;   +4  record 0      (32 bytes, flash slot 0 = bootloader, not shown)
    ;   +36 record 1      (32 bytes, flash slot 1 = first display entry)
    ;   ...
    ;
    ; Source: RBCP_DATA_ADDR + 36 (skip preamble + slot 0 record)
    ; Dest:   slot_name_buf
    ; Count:  var_num_display * 32
    ;
    ; Multiply by 32: n*32 = n<<5.
    ; Result is at most 15*32 = 480, fitting in 9 bits.
    ; lo byte = (n<<5) & $FF, hi byte = n>>3.
    ; ------------------------------------------------------------------

    lda var_num_display
    asl a
    asl a
    asl a
    asl a
    asl a                   ; lo byte of n*32
    sta rbcp_zp_3
    lda var_num_display
    lsr a
    lsr a
    lsr a                   ; hi byte of n*32 (= n/8)
    sta rbcp_zp_4

    lda #<(RBCP_DATA_ADDR + 36)
    sta ZP_PTR_LO
    lda #>(RBCP_DATA_ADDR + 36)
    sta ZP_PTR_HI
    lda #<slot_name_buf
    sta ZP_TMP0
    lda #>slot_name_buf
    sta ZP_TMP1

    ldy #0
@name_copy:
    lda (ZP_PTR_LO), y
    sta (ZP_TMP0), y
    iny
    bne @name_no_page
    inc ZP_PTR_HI
    inc ZP_TMP1
@name_no_page:
    lda rbcp_zp_3
    bne @name_dec_lo
    dec rbcp_zp_4
@name_dec_lo:
    dec rbcp_zp_3
    lda rbcp_zp_3
    ora rbcp_zp_4
    bne @name_copy

    jsr draw_menu

    lda #0
    sta var_selection
    jsr highlight_selection

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
    ; Flash slot = selection + 1 (slot 0 is bootloader, not displayed)
    lda var_selection
    clc
    adc #1
    tax                     ; X = flash slot
    lda var_target_ram      ; A = RAM slot
    jsr rbcp_cmd_load_slot
    bcc @ok_load_menu
    jmp err_load
@ok_load_menu:
    lda var_target_ram
    jsr rbcp_cmd_switch_and_exit
    jmp (RESET_VECTOR)

; ===========================================================================
; Error handlers
; ===========================================================================

err_generic:
    lda #<msg_err_generic
    sta ZP_PTR_LO
    lda #>msg_err_generic
    sta ZP_PTR_HI
    jmp halt_with_msg

err_ram_info:
    lda #<msg_err_ram_info
    sta ZP_PTR_LO
    lda #>msg_err_ram_info
    sta ZP_PTR_HI
    jmp halt_with_msg

err_insuff_ram:
    lda #<msg_err_insuff_ram
    sta ZP_PTR_LO
    lda #>msg_err_insuff_ram
    sta ZP_PTR_HI
    jmp halt_with_msg

err_flash_info:
    lda #<msg_err_flash_info
    sta ZP_PTR_LO
    lda #>msg_err_flash_info
    sta ZP_PTR_HI
    jmp halt_with_msg

err_no_kernals:
    lda #<msg_err_no_kernals
    sta ZP_PTR_LO
    lda #>msg_err_no_kernals
    sta ZP_PTR_HI
    jmp halt_with_msg

err_load:
    lda #<msg_err_load
    sta ZP_PTR_LO
    lda #>msg_err_load
    sta ZP_PTR_HI
    ; fall through

halt_with_msg:
    lda #12
    sta ZP_TMP0
    lda #1
    sta ZP_TMP1
    jsr c64_print_at
@halt:
    jmp @halt

; ===========================================================================
; draw_menu
; Draws header, prompt, footer, and all slot name entries.
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

    ; Draw slot names
    ; For each entry i: source = slot_name_buf + i*32, row = MENU_ENTRY_ROW0+i
    ; i*32: lo = (i<<5)&$FF, hi = i>>3
    ; Loop counter in rbcp_zp_0

    lda #0
    sta rbcp_zp_0           ; i = 0

@entry_loop:
    lda rbcp_zp_0
    cmp var_num_display
    beq @entries_done

    ; Compute slot_name_buf + i*32
    asl a
    asl a
    asl a
    asl a
    asl a
    sta rbcp_zp_3           ; offset lo
    lda rbcp_zp_0
    lsr a
    lsr a
    lsr a
    sta rbcp_zp_4           ; offset hi

    lda #<slot_name_buf
    clc
    adc rbcp_zp_3
    sta ZP_PTR_LO
    lda #>slot_name_buf
    adc rbcp_zp_4
    sta ZP_PTR_HI

    lda rbcp_zp_0
    clc
    adc #MENU_ENTRY_ROW0
    sta ZP_TMP0
    lda #3
    sta ZP_TMP1

    jsr c64_print_at        ; does not clobber rbcp_zp_0..4

    inc rbcp_zp_0
    jmp @entry_loop

@entries_done:
    rts

; ===========================================================================
; highlight_selection / unhighlight_selection
; ===========================================================================

highlight_selection:
    lda var_selection
    clc
    adc #MENU_ENTRY_ROW0
    jsr c64_highlight_row
    jsr set_arrow
    rts

unhighlight_selection:
    lda var_selection
    clc
    adc #MENU_ENTRY_ROW0
    jsr c64_unhighlight_row
    jsr clear_arrow
    rts

; set_arrow: write '>' at col 1 of the current selection row
set_arrow:
    lda var_selection
    clc
    adc #MENU_ENTRY_ROW0
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
    lda var_selection
    clc
    adc #MENU_ENTRY_ROW0
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

; ===========================================================================
; String data (RODATA — accessed via ROM addresses)
; ===========================================================================

.rodata

str_header:         .byte "RBCP KERNAL BOOTLOADER", 0
str_prompt:         .byte "SELECT KERNAL:", 0
str_footer:         .byte "UP/DOWN TO MOVE, RETURN TO BOOT", 0

msg_err_generic:    .byte "RBCP ERROR: COMMAND FAILED", 0
msg_err_ram_info:   .byte "RBCP ERROR: RAM SLOT INFO FAILED", 0
msg_err_insuff_ram: .byte "RBCP ERROR: INSUFFICIENT RAM SLOTS", 0
msg_err_flash_info: .byte "RBCP ERROR: FLASH SLOT INFO FAILED", 0
msg_err_no_kernals: .byte "NO KERNALS FOUND TO BOOT", 0
msg_err_load:       .byte "RBCP ERROR: LOAD FAILED", 0