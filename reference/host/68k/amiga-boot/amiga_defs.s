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

; Application buffer layout (all absolute chip RAM addresses).
; Reserved now, used from the slot-enumeration milestone onwards.
SLOT_NAME_BUF       EQU APP_BASE+$0000      ; 14 * 32 = 448 bytes ($1C0)
SLOT_NAME_MAX       EQU 14
SLOT_NAME_SZ        EQU 32

DEVICE_TYPE_BUF     EQU APP_BASE+$01C0      ; 24 bytes
DEVICE_VER_BUF      EQU APP_BASE+$01D8      ; 24 bytes

; Single-byte application variables
VAR_BASE            EQU APP_BASE+$01F0

; Milestone 1
VAR_ENTER_RESULT    EQU VAR_BASE+0          ; 0 = entered command-response
VAR_ENTER_STAGE     EQU VAR_BASE+1          ; RBCP_ERROR_CODE at failure
VAR_NOP_RESULT      EQU VAR_BASE+2
VAR_NOP_STAGE       EQU VAR_BASE+3

; Later milestones
VAR_TOTAL_RAM       EQU VAR_BASE+4
VAR_ACTIVE_RAM      EQU VAR_BASE+5
VAR_TARGET_RAM      EQU VAR_BASE+6
VAR_TOTAL_FLASH     EQU VAR_BASE+7
VAR_WHOLE_FLASH     EQU VAR_BASE+8
VAR_NUM_DISPLAY     EQU VAR_BASE+9
VAR_SELECTION       EQU VAR_BASE+10
VAR_LMB_HELD        EQU VAR_BASE+11         ; 0=held, non-zero=not held
VAR_NV_PRESENT      EQU VAR_BASE+12
VAR_BOOT_FLASH      EQU VAR_BASE+13         ; 1-based flash slot for auto-boot

STACK_TOP           EQU $00007F00           ; supervisor stack, grows down

; RAM code section destination — all RBCP and application code runs here
RAM_CODE_BASE       EQU $00008000

; ---------------------------------------------------------------------------
; Milestone 1 screen layout (row indices, 0-based)
; ---------------------------------------------------------------------------
ROW_CFG_A           EQU 2                   ; ROM geometry, device-side values
ROW_CFG_B           EQU 3                   ; mapped CPU addresses
ROW_BEFORE_LBL      EQU 5
ROW_BEFORE_HEX      EQU 6
ROW_AFTER_LBL       EQU 8
ROW_AFTER_HEX       EQU 9
ROW_HEADER          EQU 11                  ; decoded response header
ROW_RESULT          EQU 13                  ; ENTER_CMD_RESP outcome
ROW_NOP             EQU 16                  ; NOP outcome

STAGE_COL           EQU 46                  ; column for the stage digit

; ---------------------------------------------------------------------------
; Menu screen layout — reserved for the menu milestone
; ---------------------------------------------------------------------------
MENU_HEADER_ROW     EQU 1
MENU_COPY_ROW       EQU 3
MENU_PROMPT_ROW     EQU 5
MENU_ENTRY_ROW0     EQU 7                   ; first slot entry row
MENU_FOOTER_ROW     EQU 23
MENU_DEVICE_ROW     EQU 26

MAX_DISPLAY         EQU 14

; ---------------------------------------------------------------------------
; Input token constants — reserved for the menu milestone
; ---------------------------------------------------------------------------
KEY_NONE            EQU 0
KEY_UP              EQU 1
KEY_DOWN            EQU 2
KEY_RETURN          EQU 3
KEY_ESC             EQU 4
KEY_LMB             EQU 5

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
