; amiga_defs.s — Amiga hardware constants and chip RAM layout
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

; ---------------------------------------------------------------------------
; Custom chip base and register offsets
; ---------------------------------------------------------------------------
CUSTOM              EQU $DFF000

INTENA              EQU CUSTOM+$09A
INTREQ              EQU CUSTOM+$09C
ADKCON              EQU CUSTOM+$09E
DMACON              EQU CUSTOM+$096
COLOR00             EQU CUSTOM+$180
COLOR01             EQU CUSTOM+$182
BPLCON0             EQU CUSTOM+$100
BPLCON1             EQU CUSTOM+$102
BPLCON2             EQU CUSTOM+$104
BPL1MOD             EQU CUSTOM+$108
BPL1PTH             EQU CUSTOM+$0E0
BPL1PTL             EQU CUSTOM+$0E2
DIWSTRT             EQU CUSTOM+$08E
DIWSTOP             EQU CUSTOM+$090
DDFSTRT             EQU CUSTOM+$092
DDFSTOP             EQU CUSTOM+$094
COP1LCH             EQU CUSTOM+$080
COPJMP1             EQU CUSTOM+$088
POTGO               EQU CUSTOM+$034     ; write: pot-pin direction and start
POTGOR              EQU CUSTOM+$016     ; read: pot-pin levels (POTINP)

; ---------------------------------------------------------------------------
; CIA-A registers
; Base $BFE001.  CIA registers use odd byte addresses with stride $100.
; ---------------------------------------------------------------------------
CIAA_BASE           EQU $BFE001
CIAA_PRA            EQU CIAA_BASE+$000      ; port A: OVL, LED, LMB
CIAA_DDRA           EQU CIAA_BASE+$200      ; port A direction register
CIAA_SDR            EQU CIAA_BASE+$C00      ; serial data register (keyboard)
CIAA_ICR            EQU CIAA_BASE+$D00      ; interrupt control / status
CIAA_CRA            EQU CIAA_BASE+$E00      ; control register A

; CIA-A PRA bit positions
CIAA_PRA_OVL        EQU 0                   ; overlay: 1=ROM at $0, 0=RAM at $0
CIAA_PRA_LED        EQU 1                   ; power LED: 0=on, 1=off
CIAA_PRA_LMB        EQU 6                   ; left mouse button: 0=pressed
POTGOR_RMB          EQU 10                  ; right mouse button in POTGOR: 0=pressed

; CIA-A ICR bit position
CIAA_ICR_SP         EQU 3                   ; serial port: 1=byte received

; CIA-A CRA bit position
CIAA_CRA_SPMODE     EQU 6                   ; 0=SP input (keyboard), 1=output

; ---------------------------------------------------------------------------
; Screen geometry
; 640x224 NTSC, 80x28 characters using an 8x8-pixel font.
; ---------------------------------------------------------------------------
SCREEN_COLS         EQU 80
SCREEN_ROWS         EQU 28
SCREEN_BPL_W        EQU 80                  ; bytes per bitplane row
SCREEN_BPL_H        EQU 224                 ; pixel rows
SCREEN_BPL_SZ       EQU SCREEN_BPL_W*SCREEN_BPL_H   ; 17920 = $4600 bytes
ROW_STRIDE          EQU SCREEN_BPL_W*8      ; bytes per character row = 640

; ---------------------------------------------------------------------------
; Colour constants (12-bit RGB, $0RGB format for COLOR00 etc.)
; ---------------------------------------------------------------------------
COL_BLACK           EQU $0000
COL_WHITE           EQU $0FFF
COL_RED             EQU $0F00
COL_GREEN           EQU $00F0
COL_BLUE            EQU $000F
COL_YELLOW          EQU $0FF0
COL_CYAN            EQU $00FF
COL_MAGENTA         EQU $0F0F
COL_ORANGE          EQU $0F80
COL_PURPLE          EQU $0808
COL_DARK_GREY       EQU $0444
COL_LIGHT_GREY      EQU $0AAA

; ---------------------------------------------------------------------------
; Chip RAM layout
;
;   $0000-$03FF  Exception vector table (256 vectors * 4 bytes)
;   $0400-$041F  Boot trampoline (reserved for the boot-switch milestone)
;   $1000-$101F  RBCP scratch RAM (32 bytes, CONFIG_RBCP_SCRATCH_BASE)
;   $1020-$109F  Copper list (128 bytes, copied from the ROM template)
;   $10A0-$569F  Mono bitplane (640*224 = 17920 bytes)
;   $56A0-$7EFF  Application buffers and variables
;   $7F00        Supervisor stack top (grows downward)
;   $8000+       RAM code section (copied from ROM by boot_rom_entry)
; ---------------------------------------------------------------------------
CHIP_TRAMPOLINE     EQU $00000400           ; boot trampoline destination
COPPER_BASE         EQU $00001020           ; copper list in chip RAM
BITPLANE_BASE       EQU $000010A0           ; mono bitplane

APP_BASE            EQU $000056A0           ; first byte after the bitplane

; Single-byte application variables.  Response records and strings are read
; through the RBCP library's own un-swap buffer (CONFIG_RBCP_DATA_BUF), so the
; application keeps only these few state bytes of its own.
VAR_BASE            EQU APP_BASE+$0000

VAR_TOTAL_RAM       EQU VAR_BASE+0          ; RAM slots the device has
VAR_ACTIVE_RAM      EQU VAR_BASE+1          ; the active RAM slot
VAR_TARGET_RAM      EQU VAR_BASE+2          ; RAM slot a load stages into
VAR_SINGLE_SLOT     EQU VAR_BASE+3          ; 1 = only one RAM slot, use LOAD_AND_EXIT
VAR_TOTAL_FLASH     EQU VAR_BASE+4          ; flash slots the device has
VAR_NUM_DISPLAY     EQU VAR_BASE+5          ; menu entries shown
VAR_SELECTION       EQU VAR_BASE+6          ; 0-based index into the shown list
VAR_LMB_HELD        EQU VAR_BASE+7          ; 1 while the left button stays down
VAR_RMB_HELD        EQU VAR_BASE+17         ; 1 while the right button stays down
VAR_NV_PRESENT      EQU VAR_BASE+8          ; 1 = the device can remember a choice
VAR_NV_STORED       EQU VAR_BASE+9          ; slot the device already had stored
VAR_PIPE_PRESENT    EQU VAR_BASE+10         ; 1 = pipe 0 is available for logging
VAR_BOOT_FLASH      EQU VAR_BASE+11         ; 1-based flash slot to boot
VAR_LED             EQU VAR_BASE+12         ; lowest RGB LED, or $FF if none
VAR_SAVED_KEY       EQU VAR_BASE+14         ; key held across a logging call
VAR_LOG_SLOT        EQU VAR_BASE+15         ; slot a log line is naming
VAR_ERR_NUM        EQU VAR_BASE+16         ; error number, for the diagnostics
VAR_LMB_UP_CNT      EQU VAR_BASE+18         ; polls the left button has read up

; Polls the left button must read up before another press is taken, so the
; bounce either side of a click reads as one press.  A loop count, like the
; RBCP timeouts, not a unit.
LMB_DEBOUNCE        EQU 1500

STACK_TOP           EQU $00007F00           ; supervisor stack, grows down

; RAM code section destination — all RBCP and application code runs here
RAM_CODE_BASE       EQU $00008000

; ---------------------------------------------------------------------------
; Menu screen layout (row indices, 0-based)
;
; The NTSC copper shows 200 lines, so everything sits within the first 24 rows
; of the 8x8 text grid.  The list runs from MENU_ROW0 to two rows above the
; footer, leaving a gap so the footer reads as separate.
; ---------------------------------------------------------------------------
TITLE_ROW           EQU 0
TITLE_COL           EQU 26
MENU_ROW0           EQU 3
MENU_COL            EQU 6                    ; where the name starts
MENU_NUM_COL        EQU 3                    ; where the "N)" starts
FOOTER_ROW          EQU 21
DEVICE_ROW          EQU 23
DEVICE_COL          EQU 2
ROCKS_COL           EQU 68                   ; "piers.rocks" is 11 chars

MAX_DISPLAY         EQU 14
MENU_PREFIX         EQU 3                    ; the "N) " in front of a name

; Menu name store — one slot name per entry, as read from the device.
NAME_STRIDE         EQU 32                   ; room per name, as read
NAME_LEN_TAB        EQU APP_BASE+$20         ; MAX_DISPLAY lengths, 0 = no entry
NAME_MAX            EQU APP_BASE+$30         ; the widest name found
NAME_BUF            EQU APP_BASE+$40         ; MAX_DISPLAY*NAME_STRIDE bytes


; Error numbers, indices into the error message table.
ERR_NO_CMD_RESP     EQU 0
ERR_VERSION         EQU 1
ERR_RAM_INFO        EQU 2
ERR_FLASH_INFO      EQU 3
ERR_NO_IMAGES       EQU 4
ERR_LOAD            EQU 5
ERROR_ROW           EQU 10
ERROR_COL           EQU 8

; ---------------------------------------------------------------------------
; Input token constants — reserved for the menu milestone
; ---------------------------------------------------------------------------
KEY_NONE            EQU 0
KEY_UP              EQU 1
KEY_DOWN            EQU 2
KEY_RETURN          EQU 3
KEY_ESC             EQU 4
KEY_LMB             EQU 5
KEY_RMB             EQU 6

; Amiga keyboard scancodes (key press, bit 7 clear)
KBD_RETURN          EQU $44
KBD_UP              EQU $4C
KBD_DOWN            EQU $4D
KBD_ESC             EQU $45

; ---------------------------------------------------------------------------
; Copper register offsets (within the custom chip $DFF000 address space)
; ---------------------------------------------------------------------------
COP_BPL1PTH         EQU $00E0
COP_BPL1PTL         EQU $00E2
COP_BPLCON0         EQU $0100
COP_BPLCON1         EQU $0102
COP_BPLCON2         EQU $0104
COP_BPL1MOD         EQU $0108
COP_DDFSTRT         EQU $0092
COP_DDFSTOP         EQU $0094
COP_DIWSTRT         EQU $008E
COP_DIWSTOP         EQU $0090
COP_COLOR00         EQU $0180
COP_COLOR01         EQU $0182
