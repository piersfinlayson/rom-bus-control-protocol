; vic20_boot.s — Reset entry, relocation, RBCP session, menu UX
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

.include "vic20_defs.s"

; ---------------------------------------------------------------------------
; Imports
; ---------------------------------------------------------------------------

.import vic20_hw_init
.import vic20_clear_screen
.import vic20_print_at
.import vic20_highlight_row
.import vic20_unhighlight_row
.import vic20_scan_key

.import rbcp_reset
.import rbcp_cmd_enter_cmd_resp
.import rbcp_cmd_get_ram_slot_info_all
.import rbcp_cmd_get_flash_slot_info_all
.import rbcp_cmd_load_slot
.import rbcp_cmd_switch_and_exit
.import rbcp_cmd_get_device_type, rbcp_cmd_get_device_version
.import rbcp_check_protocol_version
.import rbcp_cmd_get_nv_capability
.import rbcp_cmd_nv_peek
.import rbcp_cmd_nv_poke_commit_byte

.import row_off_lo
.import row_scr_hi

; Linker-generated symbols for the CODE segment (load/run split)
.import __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------

RESET_VECTOR        = $FFFC
MENU_HEADER_ROW     = 1
MENU_COPYRIGHT_ROW  = 3
MENU_PROMPT_ROW     = 5
MENU_ENTRY_ROW0     = 7
MENU_FOOTER_ROW     = 20
MENU_DEVICE_ROW     = 22
MAX_DISPLAY         = 13

; ---------------------------------------------------------------------------
; BSS — RAM-resident variables
; ---------------------------------------------------------------------------

.bss

; Slot name buffer: 13 entries * 32 bytes = 416 bytes.
; Entry 0 = flash slot 1, entry N = flash slot N+1.
slot_name_buf:      .res MAX_DISPLAY * 32
status_line_buf:    .res 32
device_type_buf:    .res 24
device_version_buf: .res 24
device_line_buf:    .res 32

var_total_ram:  .res 1
var_active_ram: .res 1
var_target_ram: .res 1
var_total_flash:.res 1
var_whole_flash:.res 1
var_num_display:.res 1
var_selection:  .res 1
var_cbm_held:   .res 1      ; $00 = C= held; non-zero = not held
var_nv_present: .res 1      ; 0 = absent or not writable, 1 = writable
var_boot_flash: .res 1      ; resolved flash slot to boot

; ===========================================================================
; BOOT segment — runs from ROM, executes before relocation
; ===========================================================================

.segment "BOOT"

; ---------------------------------------------------------------------------
; boot_entry — RESET vector target
; Runs from ROM.  Must not call into the CODE segment (not in RAM yet).
; Calls vic20_hw_init (also in BOOT) and copies CODE to RAM, then jumps to
; boot_ram_entry (CODE segment run address = $1000+).
; ---------------------------------------------------------------------------

.export boot_entry
boot_entry:
    sei
    cld
    ldx #$FF
    txs                     ; set up stack

    jsr vic20_hw_init       ; hardware init (in BOOT segment, safe from ROM)

    ; Detect C= (Commodore) key: column 5 low, test row 0.
    ; Active-low matrix: bit clear = key pressed.
    ; Read after a debounce delay to avoid noisy power-on false positives.
    lda #KEY_CBM_COL
    sta VIA2_PRB
    ldx #DEBOUNCE_COUNT
@cbm_dly:
    dex
    bne @cbm_dly
    lda VIA2_PRA
    and #KEY_CBM_ROW_BIT
    sta var_cbm_held        ; $00 = held, non-zero = not held

    ; ------------------------------------------------------------------
    ; Relocate CODE segment from ROM to RAM.
    ;
    ; __CODE_LOAD__ = load address of CODE in ROM image
    ; __CODE_RUN__  = run address of CODE in RAM ($1000)
    ; __CODE_SIZE__ = byte count of CODE segment
    ;
    ; ZP use: ZP_PTR_LO/hi = ROM source, ZP_TMP0/1 = RAM destination.
    ; ZP_TMP3/4
    ;
    ; Y is used as a byte index within each 256-byte page.  When Y wraps
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
; CODE segment — runs from RAM ($1000+) after relocation
; ===========================================================================

.code

; ---------------------------------------------------------------------------
; boot_ram_entry — all subsequent execution runs from RAM
; ---------------------------------------------------------------------------

boot_ram_entry:
    ldy #COL_BLACK
    jsr vic20_clear_screen

    ; ------------------------------------------------------------------
    ; RBCP common setup
    ; ------------------------------------------------------------------

    ; Spec defined reset sequence.
    jsr rbcp_reset

    ; Enter command-response mode using the settings in rbcp_config.s
    jsr rbcp_cmd_enter_cmd_resp
    bcc @ok_enter
    jmp err_no_cmd_resp

    ; Check device's RBCP protocol version
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

    ; Flash slot info — needed by both paths and for NV validation
    lda #0
    sta var_total_flash
    sta var_whole_flash
    jsr rbcp_cmd_get_flash_slot_info_all
    bcs @flash_info_done        ; on failure totals stay zero; menu path catches this, auto-boot falls back to slot 1
    lda RBCP_DATA_ADDR + 0
    sta var_total_flash
    lda RBCP_DATA_ADDR + 1
    sta var_whole_flash
@flash_info_done:

    ; NV query — resolve boot slot; failures fall through to default
    lda #0
    sta var_nv_present
    lda #1
    sta var_boot_flash              ; default: flash slot 1

    jsr rbcp_cmd_get_nv_capability
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
    jsr rbcp_cmd_nv_peek
    bcs @nv_skip                    ; peek failed

    lda RBCP_DATA_ADDR              ; the stored slot byte
    beq @nv_skip                    ; 0 = bootloader slot, invalid
    cmp var_total_flash             ; >= total slots, out of range
    bcs @nv_skip
    sta var_boot_flash              ; valid, use it
@nv_skip:

    ; ------------------------------------------------------------------
    ; Branch on C= state
    ; ------------------------------------------------------------------

    lda var_cbm_held
    beq path_menu           ; $00 = C= was held

    ; ==================================================================
    ; AUTO-BOOT PATH — load resolved flash slot, switch, and go
    ; ==================================================================

    ldx var_boot_flash
    lda var_target_ram
    jsr rbcp_cmd_load_slot
    bcc @ok_load_auto
    jmp err_load
@ok_load_auto:

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
    jsr vic20_clear_screen

    jsr rbcp_cmd_get_device_type
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

    jsr rbcp_cmd_get_device_version
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

    ; Build the device line: type + space + version
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

    lda var_total_flash
    bne @flash_ok
    jmp err_flash_info      ; query failed earlier, report the real error
@flash_ok:
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
    ; Data section layout (at RBCP_DATA_ADDR):
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
    ; lo byte = (n<<5) & $FF, hi byte = n>>3.
    ; ------------------------------------------------------------------

    lda var_num_display
    asl a
    asl a
    asl a
    asl a
    asl a                   ; lo byte of n*32
    sta ZP_TMP3
    lda var_num_display
    lsr a
    lsr a
    lsr a                   ; hi byte of n*32 (= n/8)
    sta ZP_TMP4

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
    lda ZP_TMP3
    bne @name_dec_lo
    dec ZP_TMP4
@name_dec_lo:
    dec ZP_TMP3
    lda ZP_TMP3
    ora ZP_TMP4
    bne @name_copy

    lda #VIC_COLOUR_VAL
    sta VIC_COLOUR

jsr draw_menu

    ; Highlight the auto-booting slot if configured
    lda var_boot_flash
    sec
    sbc #1                  ; convert 1-based flash slot to 0-based index
    cmp var_num_display     ; out of displayable range?
    bcc @sel_ok
    lda #0                  ; fall back to first entry
@sel_ok:
    sta var_selection
    jsr highlight_selection

    ; ------------------------------------------------------------------
    ; Keyboard polling loop
    ; ------------------------------------------------------------------

key_loop:
    jsr vic20_scan_key
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
    jmp key_delay

do_down:
    lda var_selection
    clc
    adc #1
    cmp var_num_display
    bcs key_loop
    jsr unhighlight_selection
    inc var_selection
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
    jsr rbcp_cmd_nv_poke_commit_byte
    bcc @nv_skip_write
    jmp err_nv_commit

@nv_skip_write:
    ldx var_selection       ; X = flash slot
    lda var_target_ram      ; A = RAM slot
    jsr rbcp_cmd_load_slot
    bcc @ok_load_menu
    jmp err_load
@ok_load_menu:
    lda var_target_ram
    jsr rbcp_cmd_switch_and_exit

    ; Clear screen before reset.
    ; Y = COL_BLACK = 0 = VIC_COLOUR_VAL, so sty VIC_COLOUR is correct.
    ldy #COL_BLACK
    jsr vic20_clear_screen
    sty VIC_COLOUR

.if PAUSE_BEFORE_RESET
    jsr pause_before_reset
.endif

    jmp (RESET_VECTOR)

; ===========================================================================
; Error handlers
; ===========================================================================

err_no_cmd_resp:
    lda #VIC_COLOUR_ERR
    sta VIC_COLOUR
    lda #<msg_err_no_cmd_resp
    sta ZP_PTR_LO
    lda #>msg_err_no_cmd_resp
    sta ZP_PTR_HI
    jmp halt_with_msg

err_protocol_version:
    lda #VIC_COLOUR_ERR
    sta VIC_COLOUR
    lda #<msg_err_protocol_version
    sta ZP_PTR_LO
    lda #>msg_err_protocol_version
    sta ZP_PTR_HI
    jmp halt_with_msg

err_ram_info:
    lda #VIC_COLOUR_ERR
    sta VIC_COLOUR
    lda #<msg_err_ram_info
    sta ZP_PTR_LO
    lda #>msg_err_ram_info
    sta ZP_PTR_HI
    jmp halt_with_msg

err_insuff_ram:
    lda #VIC_COLOUR_ERR
    sta VIC_COLOUR
    lda #<msg_err_insuff_ram
    sta ZP_PTR_LO
    lda #>msg_err_insuff_ram
    sta ZP_PTR_HI
    jmp halt_with_msg

err_flash_info:
    lda #VIC_COLOUR_ERR
    sta VIC_COLOUR
    lda #<msg_err_flash_info
    sta ZP_PTR_LO
    lda #>msg_err_flash_info
    sta ZP_PTR_HI
    jmp halt_with_msg

err_no_kernals:
    lda #VIC_COLOUR_ERR
    sta VIC_COLOUR
    lda #<msg_err_no_kernals
    sta ZP_PTR_LO
    lda #>msg_err_no_kernals
    sta ZP_PTR_HI
    jmp halt_with_msg

err_device_type:
    lda #VIC_COLOUR_ERR
    sta VIC_COLOUR
    lda #<msg_err_device_type
    sta ZP_PTR_LO
    lda #>msg_err_device_type
    sta ZP_PTR_HI
    jmp halt_with_msg

err_device_version:
    lda #VIC_COLOUR_ERR
    sta VIC_COLOUR
    lda #<msg_err_device_version
    sta ZP_PTR_LO
    lda #>msg_err_device_version
    sta ZP_PTR_HI
    jmp halt_with_msg

err_nv_commit:
    lda #VIC_COLOUR_ERR
    sta VIC_COLOUR
    lda #<msg_err_nv_commit
    sta ZP_PTR_LO
    lda #>msg_err_nv_commit
    sta ZP_PTR_HI
    jmp halt_with_msg

err_load:
    lda #VIC_COLOUR_ERR
    sta VIC_COLOUR
    lda #<msg_err_load
    sta ZP_PTR_LO
    lda #>msg_err_load
    sta ZP_PTR_HI
    ; fall through

halt_with_msg:
    ldy #COL_WHITE
    jsr vic20_clear_screen

    lda #10
    sta ZP_TMP0
    lda #0
    sta ZP_TMP1
    jsr vic20_print_at

    jsr build_status_line

    lda #<status_line_buf
    sta ZP_PTR_LO
    lda #>status_line_buf
    sta ZP_PTR_HI
    lda #11
    sta ZP_TMP0
    lda #0
    sta ZP_TMP1
    jsr vic20_print_at

@halt:
    jmp @halt

; ---------------------------------------------------------------------------
; buf_putc — writes A to (ZP_TMP0/1), advances ZP_TMP0/1.  Clobbers Y.
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
; Advances both pointers.  Clobbers A, Y.
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
; build_status_line
;
; Accesses RBCP library zero page addresses
; ---------------------------------------------------------------------------

.macro set_ptr addr
    lda #<addr
    sta ZP_PTR_LO
    lda #>addr
    sta ZP_PTR_HI
.endmacro

build_status_line:
    lda #<status_line_buf
    sta ZP_TMP0
    lda #>status_line_buf
    sta ZP_TMP1

    set_ptr str_sl_stg
    jsr buf_puts
    lda rbcp_zp_5
    clc
    adc #'0'
    jsr buf_putc

    set_ptr str_sl_grp
    jsr buf_puts
    lda rbcp_zp_0
    jsr byte_to_hex

    set_ptr str_sl_cmd
    jsr buf_puts
    lda rbcp_zp_1
    jsr byte_to_hex

    set_ptr str_sl_tok
    jsr buf_puts
    lda RBCP_TOKEN_LSB_ADDR
    jsr byte_to_hex

    set_ptr str_sl_prog
    jsr buf_puts
    lda RBCP_PROGRESS_ADDR
    jsr byte_to_hex

    set_ptr str_sl_resp
    jsr buf_puts
    lda RBCP_RESPONSE_ADDR
    jsr byte_to_hex

    set_ptr str_sl_dgrp
    jsr buf_puts
    lda CONFIG_RBCP_BCH_BASE + 0
    jsr byte_to_hex

    set_ptr str_sl_dcmd
    jsr buf_puts
    lda CONFIG_RBCP_BCH_BASE + 1
    jsr byte_to_hex

    lda #0
    jsr buf_putc
    rts

str_sl_stg:  .byte "STG:", 0
str_sl_grp:  .byte " GRP:", 0
str_sl_cmd:  .byte " CMD:", 0
str_sl_tok:  .byte " TOK:", 0
str_sl_prog: .byte " PRG:", 0
str_sl_resp: .byte " RSP:", 0
str_sl_dgrp: .byte "DGRP:", 0
str_sl_dcmd: .byte " DCMD:", 0

; ===========================================================================
; draw_menu
; Draws header, copyright, prompt, footer, device line, and all slot entries.
; Relies on vic20_print_at to not clobber ZP_TMP2+.
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
    jsr vic20_print_at

    lda #<str_copyright
    sta ZP_PTR_LO
    lda #>str_copyright
    sta ZP_PTR_HI
    lda #MENU_COPYRIGHT_ROW
    sta ZP_TMP0
    lda #1
    sta ZP_TMP1
    jsr vic20_print_at

    lda #<str_prompt
    sta ZP_PTR_LO
    lda #>str_prompt
    sta ZP_PTR_HI
    lda #MENU_PROMPT_ROW
    sta ZP_TMP0
    lda #1
    sta ZP_TMP1
    jsr vic20_print_at

    lda #<str_footer
    sta ZP_PTR_LO
    lda #>str_footer
    sta ZP_PTR_HI
    lda #MENU_FOOTER_ROW
    sta ZP_TMP0
    lda #1
    sta ZP_TMP1
    jsr vic20_print_at

    ; Output the device info line right-aligned on the last row.
    ; col = 22 - len: ~len + 23 = (255 - len) + 23 mod 256 = 22 - len.
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
    adc #23             ; ~len + 23 = 22 - len
    sta ZP_TMP1
    lda #MENU_DEVICE_ROW
    sta ZP_TMP0
    jsr vic20_print_at

    ; Draw slot names.
    ; For each entry i: source = slot_name_buf + i*32, row = MENU_ENTRY_ROW0+i.
    ; Loop counter in ZP_TMP2.

    lda #0
    sta ZP_TMP2             ; i = 0

@entry_loop:
    lda ZP_TMP2
    cmp var_num_display
    beq @entries_done

    ; Compute slot_name_buf + i*32
    asl a
    asl a
    asl a
    asl a
    asl a
    sta ZP_TMP3             ; offset lo
    lda ZP_TMP2
    lsr a
    lsr a
    lsr a
    sta ZP_TMP4             ; offset hi

    lda #<slot_name_buf
    clc
    adc ZP_TMP3
    sta ZP_PTR_LO
    lda #>slot_name_buf
    adc ZP_TMP4
    sta ZP_PTR_HI

    ; Skip byte 0 (ROM type field)
    inc ZP_PTR_LO
    bne @no_carry
    inc ZP_PTR_HI

@no_carry:
    lda ZP_TMP2
    clc
    adc #MENU_ENTRY_ROW0
    sta ZP_TMP0
    lda #3
    sta ZP_TMP1

    jsr vic20_print_at      ; does not clobber ZP_TMP2+

    inc ZP_TMP2
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
    jsr vic20_highlight_row
    jsr set_arrow
    rts

unhighlight_selection:
    lda var_selection
    clc
    adc #MENU_ENTRY_ROW0
    jsr vic20_unhighlight_row
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

str_header:     .byte "  VIC-20 RBCP BOOT", 0
str_copyright:  .byte "(C) 2026 PIERS.ROCKS", 0
str_prompt:     .byte "SELECT KERNAL:", 0
str_footer:     .byte "UP/DN=MOVE  RET=BOOT", 0

msg_err_no_cmd_resp:        .byte "RBCP: NO CMD RESP", 0
msg_err_protocol_version:   .byte "RBCP: PROTOCOL VER", 0
msg_err_ram_info:           .byte "RBCP: RAM INFO FAIL", 0
msg_err_insuff_ram:         .byte "RBCP: INSUFF RAM", 0
msg_err_flash_info:         .byte "RBCP: FLASH INFO FAIL", 0
msg_err_device_type:        .byte "RBCP: DEV TYPE FAIL", 0
msg_err_device_version:     .byte "RBCP: DEV VER FAIL", 0
msg_err_nv_commit:          .byte "RBCP: NV COMMIT FAIL", 0
msg_err_no_kernals:         .byte "NO KERNALS FOUND", 0
msg_err_load:               .byte "RBCP: LOAD FAILED", 0